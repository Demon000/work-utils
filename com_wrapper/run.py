#!/usr/bin/env python3

import fcntl
import logging
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import traceback
import tty
from argparse import ArgumentParser
from pathlib import Path
from types import FrameType
from typing import BinaryIO, Iterable

import json5
from config import (
    ActionConfig,
    Config,
    RunWriteConfig,
    RunWriteFromFileConfig,
)
from utils import delay_us

MAX_BUF_LEN = 4096
CHUNK_LEN = 1024

logging.basicConfig(
    filename='log.txt',
    filemode='w',
    level=logging.DEBUG,
    format='%(asctime)s [%(levelname)s] %(message)s',
)


class Context:
    def __init__(self, config_path: Path):
        self.config_path = config_path
        self.args: dict[str, str] = {}

        self.oneshot_actions_matched: set[ActionConfig] = set()
        self.actions_buf_position_map: dict[ActionConfig, int] = {}

        self.log_files: dict[str, BinaryIO] = {}
        self.log = bytearray()

    def set_arg(self, name: str, value: str):
        logging.info(f'Set arg {name}={value}')
        self.args[name] = value

    def reset_oneshots(self):
        logging.info('Reset oneshots')
        self.oneshot_actions_matched.clear()

    def add_oneshot(self, action: ActionConfig):
        logging.info(f'Add oneshot: {action.model_dump_json(indent=4)}')
        self.oneshot_actions_matched.add(action)

    def add_log(self, name: str):
        logging.info(f'Add log {name}')
        if name in self.log_files:
            logging.info(f'Log {name} already added')
            return

        log_file = open(name, 'wb')
        log_file.write(self.log)
        self.log_files[name] = log_file

    def write_log(self, data: bytes):
        for log_file in self.log_files.values():
            log_file.write(data)
            log_file.flush()

        self.log.extend(data)

    def reset_logs(self):
        logging.info('Reset logs')
        for log_file in self.log_files.values():
            log_file.close()

        self.log_files = {}
        self.log.clear()


def copy_tty_state(src_fd: int, dst_fd: int):
    try:
        attrs = termios.tcgetattr(src_fd)
        termios.tcsetattr(dst_fd, termios.TCSANOW, attrs)
    except Exception:
        pass

    try:
        winsz = fcntl.ioctl(src_fd, termios.TIOCGWINSZ, b'\0' * 8)
        fcntl.ioctl(dst_fd, termios.TIOCSWINSZ, winsz)
    except Exception:
        pass


def replace_bytes_str(
    context: Context,
    data: str,
    needed_args: Iterable[str],
):
    logging.debug(f'Replacing args in: {data}')
    for arg in needed_args:
        if arg not in context.args:
            logging.warning(f'Arg {arg} not in context')
            return ''

        replacee = f'{{{arg}}}'
        replacement = context.args[arg]
        logging.debug(f'Replacing `{replacee}` with `{replacement}`')
        data = data.replace(replacee, replacement)

    return data


def replace_bytes_args(
    context: Context,
    data: bytes,
    needed_args: Iterable[str],
):
    logging.debug(f'Replacing args in: {data.decode()}')
    for arg in needed_args:
        if arg not in context.args:
            logging.warning(f'Arg {arg} not in context')
            return b''

        replacee = f'{{{arg}}}'
        replacement = context.args[arg]
        logging.debug(f'Replacing `{replacee}` with `{replacement}`')
        data = data.replace(replacee.encode(), replacement.encode())

    return data


def run_write_action(
    config: Config,
    context: Context,
    master_fd: int,
    run: RunWriteConfig | RunWriteFromFileConfig,
):
    logging.debug(f'Running write: {run.model_dump_json(indent=4)}')
    data: bytes = bytes()
    if run.type == 'write':
        data = run.value.encode('utf-8')
    elif run.type == 'write_from_file':
        name = run.value
        if run.needed_args:
            name = replace_bytes_str(context, name, run.needed_args)
        if not name:
            return
        file_path = Path(context.config_path.parent, name)
        data = file_path.read_bytes()

    if run.needed_args:
        data = replace_bytes_args(context, data, run.needed_args)
        if not data:
            return

    logging.debug(f'Writing: `{data.decode()}`')
    for c in data:
        if config.write_char_delay_us:
            delay_us(config.write_char_delay_us)
        os.write(master_fd, bytes((c,)))


def run_action(
    config: Config,
    context: Context,
    master_fd: int,
    action: ActionConfig,
):
    logging.debug(f'Running action: {action.model_dump_json(indent=4)}')
    if action.reset_logs:
        context.reset_logs()
    if action.reset_oneshots:
        context.reset_oneshots()
    if action.oneshot:
        context.add_oneshot(action)

    if not action.run:
        return

    for run in action.run:
        if run.type == 'write' or run.type == 'write_from_file':
            run_write_action(config, context, master_fd, run)
        elif run.type == 'add_log_file':
            name = run.name
            if run.needed_args:
                name = replace_bytes_str(context, name, run.needed_args)
            if not name:
                return
            context.add_log(name)
        elif run.type == 'set_arg':
            context.set_arg(run.name, run.value)


def match_buffer_actions(
    config: Config,
    context: Context,
    buf: bytearray,
    buf_total_length: int,
    master_fd: int,
):
    for action in config.actions:
        if action in context.oneshot_actions_matched:
            continue

        if action.type == 'match':
            encoded_value = action.value.encode()
            found_index = buf.find(encoded_value)
            if found_index == -1:
                continue

            # Store the position of the find relative to the absolute length of
            # the buffer, and ignore the match if we matched it before
            found_index_total = buf_total_length - len(buf) + found_index

            if action in context.actions_buf_position_map:
                old_found_index_total = context.actions_buf_position_map[action]
                if old_found_index_total == found_index_total:
                    continue

            context.actions_buf_position_map[action] = found_index_total
            run_action(config, context, master_fd, action)


def process_input_output(
    config: Config,
    context: Context,
    stdin_fd: int,
    stdout_fd: int,
    master_fd: int,
):
    buf = bytearray()
    buf_total_length = 0

    while True:
        rlist, _, _ = select.select([stdin_fd, master_fd], [], [])

        if stdin_fd in rlist:
            try:
                data = os.read(stdin_fd, CHUNK_LEN)
            except OSError:
                break
            if not data:
                break

            os.write(master_fd, data)

        if master_fd in rlist:
            try:
                data = os.read(master_fd, CHUNK_LEN)
            except OSError:
                break
            if not data:
                break

            buf.extend(data)
            buf_total_length += len(data)

            if len(buf) > MAX_BUF_LEN:
                buf = buf[-MAX_BUF_LEN:]

            match_buffer_actions(
                config,
                context,
                buf,
                buf_total_length,
                master_fd,
            )

            os.write(stdout_fd, data)
            context.write_log(data)


def get_terminal_size(fd: int):
    data = fcntl.ioctl(fd, termios.TIOCGWINSZ, b'\0' * 8)
    return struct.unpack('hhhh', data)[0:2]


def run_wrapper(config: Config, context: Context):
    master_fd, slave_fd = pty.openpty()
    stdin_fd = sys.stdin.fileno()
    stdout_fd = sys.stdout.fileno()

    def handle_winch(_signum: int, _frame: FrameType | None):
        try:
            copy_tty_state(stdin_fd, master_fd)
        except Exception:
            pass

    copy_tty_state(stdin_fd, slave_fd)
    signal.signal(signal.SIGWINCH, handle_winch)

    proc = subprocess.Popen(
        config.program,
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=subprocess.STDOUT,
        close_fds=True,
    )
    os.close(slave_fd)
    old_tty = termios.tcgetattr(stdin_fd)
    tty.setraw(stdin_fd)

    try:
        process_input_output(config, context, stdin_fd, stdout_fd, master_fd)
    except KeyboardInterrupt:
        pass
    except Exception:
        traceback.print_exc()
    finally:
        termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old_tty)
        os.close(master_fd)
        proc.terminate()
        proc.wait()


def main():
    parser = ArgumentParser(
        description='Wrap an interactive TTY program and inject responses automatically'
    )
    parser.add_argument(
        '-c',
        '--config',
        help='Path to config.json5',
    )
    parser.add_argument(
        '-a',
        '--arg',
        metavar='KEY=VALUE',
        help='Add argument with KEY and VALUE',
        nargs='*',
        default=[],
    )
    args = parser.parse_args()

    config_path = Path(args.config)
    config_data = config_path.read_text()
    config_json5 = json5.loads(config_data)  # type: ignore
    config = Config.model_validate(config_json5)  # type: ignore
    context = Context(config_path)

    logging.info(f'Config: {config.model_dump_json(indent=4)}')

    for kv in args.arg:
        assert isinstance(kv, str)
        k, v = kv.split('=', 1)
        context.set_arg(k, v)

    run_wrapper(config, context)


if __name__ == '__main__':
    main()
