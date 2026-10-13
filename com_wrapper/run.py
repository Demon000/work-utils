#!/usr/bin/env python3

import ctypes
import fcntl
import logging
import os
import pty
import re
import select
import struct
import subprocess
import sys
import termios
import time
import traceback
import tty
from argparse import ArgumentParser
from functools import partial
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Event, Thread
from typing import Any, BinaryIO, Callable, Iterable, Optional, TypeVar

import json5
from config import (
    ActionConfig,
    Config,
    MuxConfig,
    RunWriteConfig,
    RunWriteFromFileConfig,
)
from utils import delay_us
from vterm import (
    get_vterm_row_data,
    get_vterm_screen_data,
    get_vterm_stripped_row,
)
from vterm_bindings import (
    SBPushLineCB,
    VTerm,
    VTermScreen,
    VTermScreenCallbacks,
    vterm_lib,
)

MAX_BUF_LEN = 4096
CHUNK_LEN = 1024

# tftpy's TftpServer.listen() blocks in select() with this as the timeout
# and only checks the stop flag once that select() call returns, so a
# larger value here directly delays shutdown by up to that many seconds.
TFTP_SHUTDOWN_POLL_INTERVAL_S = 0.5

# get_vterm_screen_data() does a full rows*cols cell-by-cell FFI scan
# (measured ~2ms for 80x24, ~11ms for 200x50) and runs synchronously inside
# vterm_input_write()'s sb_pushline callback, once per scrolled line. During
# a chatty burst (e.g. a fast boot log) that stalls the read loop for one
# scan per line before it can go back to reading the next chunk. The
# permanent scrollback history is still appended on every line regardless;
# only this speculative "current screen" tail is rate-limited.
SCREEN_SNAPSHOT_MIN_INTERVAL_S = 0.1

logging.getLogger('tftpy').setLevel(logging.WARNING)


class Context:
    def __init__(self, config_path: Path):
        self.config_path = config_path
        self.args: dict[str, str] = {}

        self.oneshot_actions_matched: set[ActionConfig] = set()
        self.actions_buf_position_map: dict[ActionConfig, int] = {}

        self.log_files: dict[str, BinaryIO] = {}
        self.log = bytearray()
        self.log_history_pos = 0

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

    def write_log_history(
        self,
        data: bytes,
        current_data: bytes | None = None,
    ):
        for log_file in self.log_files.values():
            log_file.seek(self.log_history_pos, os.SEEK_SET)
            log_file.truncate()
            log_file.write(data)
            if current_data is not None:
                log_file.write(current_data)
            log_file.flush()

        del self.log[self.log_history_pos :]
        self.log += data
        if current_data is not None:
            self.log += current_data
        self.log_history_pos += len(data)

    def reset_logs(self):
        logging.info('Reset logs')
        for log_file in self.log_files.values():
            log_file.close()

        self.log_files = {}
        self.log.clear()
        self.log_history_pos = 0


def get_terminal_size(fd: int) -> tuple[int, int, int, int]:
    data = fcntl.ioctl(fd, termios.TIOCGWINSZ, b'\0' * 8)
    return struct.unpack('HHHH', data)


T = TypeVar('T', str, bytes)


def _replace_text(
    args: dict[str, str],
    data: T,
    needed_args: Optional[Iterable[str]],
    make_replacee: Callable[[str], T],
    make_replacement: Callable[[str], T],
) -> T:
    logging.debug(f'Replacing args in: {data!r}')

    if needed_args is None:
        needed_args = args

    for arg in needed_args:
        if arg not in args:
            logging.warning(f'Arg {arg} not in context')
            return type(data)()  # '' or b''

        replacee = make_replacee(arg)
        replacement = make_replacement(args[arg])

        if replacee not in data:
            continue

        logging.debug(f'Replacing `{str(replacee)}` with `{str(replacement)}`')
        data = data.replace(replacee, replacement)

    return data


def replace_str_args(
    context: Context,
    data: str,
    needed_args: Optional[Iterable[str]] = None,
):
    return _replace_text(
        context.args,
        data,
        needed_args,
        make_replacee=lambda a: f'${{{a}}}',
        make_replacement=lambda v: v,
    )


def replace_bytes_args(
    context: Context,
    data: bytes,
    needed_args: Optional[Iterable[str]] = None,
):
    return _replace_text(
        context.args,
        data,
        needed_args,
        make_replacee=lambda a: f'${{{a}}}'.encode(),
        make_replacement=lambda v: v.encode(),
    )


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
            name = replace_str_args(context, name, run.needed_args)
        if not name:
            return
        file_path = Path(context.config_path.parent, name)
        data = file_path.read_bytes()

    if run.needed_args:
        data = replace_bytes_args(context, data, run.needed_args)
    if not data:
        return

    logging.debug(f'Writing: `{data.decode()}`')
    if config.write_char_delay_us:
        for c in data:
            delay_us(config.write_char_delay_us)
            os.write(master_fd, bytes((c,)))
    else:
        written = 0
        while written < len(data):
            written += os.write(master_fd, data[written:])


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
                name = replace_str_args(context, name, run.needed_args)
            if not name:
                continue
            context.add_log(name)
        elif run.type == 'set_arg':
            context.set_arg(run.name, run.value)


def compile_action_matchers(
    config: Config,
) -> dict[ActionConfig, bytes | re.Pattern]:
    matchers: dict[ActionConfig, bytes | re.Pattern] = {}
    for action in config.actions:
        if action.type == 'match':
            matchers[action] = action.value.encode()
        elif action.type == 'match_regex':
            matchers[action] = re.compile(action.value.encode())
    return matchers


def match_buffer_actions(
    config: Config,
    context: Context,
    matchers: dict[ActionConfig, bytes | re.Pattern],
    buf: bytearray,
    buf_total_length: int,
    master_fd: int,
):
    for action in config.actions:
        if action in context.oneshot_actions_matched:
            continue

        if action.type == 'match' or action.type == 'match_regex':
            matcher = matchers[action]
            if action.type == 'match':
                found_index = buf.find(matcher)
            elif action.type == 'match_regex':
                m = matcher.search(buf)
                found_index = m.start() if m else -1
            else:
                assert False

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
    vterm: VTerm,
    vterm_screen: VTermScreen,
):
    buf = bytearray()
    buf_total_length = 0
    matchers = compile_action_matchers(config)

    last_screen_snapshot_time = 0.0

    @SBPushLineCB
    def on_sb_pushline(cols: int, cells: Any, _user: ctypes.c_void_p):
        nonlocal last_screen_snapshot_time
        row_data = get_vterm_row_data(cols, cells)
        stripped_row_data = get_vterm_stripped_row(row_data)

        now = time.monotonic()
        screen_data = None
        if now - last_screen_snapshot_time >= SCREEN_SNAPSHOT_MIN_INTERVAL_S:
            screen_data = get_vterm_screen_data(vterm, vterm_screen)
            last_screen_snapshot_time = now

        context.write_log_history(stripped_row_data, screen_data)
        return 1

    cb = VTermScreenCallbacks()
    cb.sb_pushline = on_sb_pushline
    vterm_lib.vterm_screen_set_callbacks(vterm_screen, ctypes.byref(cb), None)

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
                del buf[:-MAX_BUF_LEN]

            match_buffer_actions(
                config,
                context,
                matchers,
                buf,
                buf_total_length,
                master_fd,
            )

            logging.debug(f'Received {data!r}')

            os.write(stdout_fd, data)
            vterm_lib.vterm_input_write(vterm, data, len(data))

    screen_data = get_vterm_screen_data(vterm, vterm_screen)
    context.write_log_history(screen_data)

    vterm_lib.vterm_free(vterm)


def dyn_file_func(
    config: Config,
    context: Context,
    file_path: str,
    raddress: str,
    rport: int,
):
    logging.debug(f'TFTP requested path {file_path}')
    if file_path[0] == '/':
        file_path = file_path[1:]

    fp = Path(file_path)
    for (
        dst_file_path,
        src_file_path,
    ) in config.tftp.mounts:
        dst_file_path = replace_str_args(context, dst_file_path)
        src_file_path = replace_str_args(context, src_file_path)

        logging.debug(f'TFTP trying {src_file_path} -> {dst_file_path}')

        if src_file_path[0] == '/':
            src_file_path = src_file_path[1:]

        dp = Path(dst_file_path).resolve()
        sp = Path(src_file_path)

        if fp == sp:
            real = dp
        elif fp.is_relative_to(sp):
            rp = fp.relative_to(sp)
            real = dp.joinpath(rp)
        else:
            continue

        logging.debug(f'TFTP resolved: {real}')

        real = real.resolve()
        if not real.is_relative_to(dp):
            logging.debug(f'TFTP path outside of destination: {real}')
            continue

        if not real.exists():
            logging.debug(f'TFTP path does not exist: {real}')
            return None

        return real.open('rb')

    return None


def tftp_thread_fn(config: Config, context: Context, stop_event: Event):
    import tftpy  # type: ignore

    with TemporaryDirectory(prefix='tftp-') as tmp_root:
        dyn_file_func_fn = partial(dyn_file_func, config, context)
        server = tftpy.TftpServer(tmp_root, dyn_file_func=dyn_file_func_fn)
        server_ip = replace_str_args(context, config.tftp.server_ip)
        server_port = replace_str_args(context, config.tftp.server_port)

        listen_t = Thread(
            target=server.listen,
            args=(server_ip, int(server_port)),
            kwargs={'timeout': TFTP_SHUTDOWN_POLL_INTERVAL_S},
            name='tftp-listen',
        )
        listen_t.start()

        stop_event.wait()
        try:
            server.stop(now=True)
        finally:
            listen_t.join()


def setup_tftp(config: Config, context: Context, stop_event: Event):
    t = Thread(
        target=tftp_thread_fn,
        args=(config, context, stop_event),
        name='tftp-server',
    )
    t.start()

    return t


MUX_POLL_INTERVAL_S = 0.2


def open_mux_device(mux: MuxConfig) -> int:
    fd = os.open(mux.device, os.O_RDWR | os.O_NOCTTY)
    attrs = termios.tcgetattr(fd)
    speed = getattr(termios, f'B{mux.baud}')
    tty.cfmakeraw(attrs)
    attrs[4] = speed
    attrs[5] = speed
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIOFLUSH)
    return fd


def open_mux_port(link: str) -> tuple[int, int]:
    master_fd, slave_fd = pty.openpty()
    attrs = termios.tcgetattr(slave_fd)
    tty.cfmakeraw(attrs)
    termios.tcsetattr(slave_fd, termios.TCSANOW, attrs)

    if os.path.islink(link) or os.path.exists(link):
        os.unlink(link)
    os.symlink(os.ttyname(slave_fd), link)

    return master_fd, slave_fd


def mux_thread_fn(
    mux: MuxConfig,
    device_fd: int,
    ports: dict[str, tuple[int, int]],
    stop_event: Event,
):
    masters = [master_fd for master_fd, _ in ports.values()]

    try:
        while not stop_event.is_set():
            rlist, _, _ = select.select(
                [device_fd] + masters, [], [], MUX_POLL_INTERVAL_S
            )

            if device_fd in rlist:
                data = os.read(device_fd, CHUNK_LEN)
                for master_fd in masters:
                    os.write(master_fd, data)

            for master_fd in masters:
                if master_fd not in rlist:
                    continue

                data = os.read(master_fd, CHUNK_LEN)
                os.write(device_fd, data)
    finally:
        for name, (master_fd, slave_fd) in ports.items():
            os.close(master_fd)
            os.close(slave_fd)
            os.unlink(mux.ports[name])
        os.close(device_fd)


def setup_mux(config: Config, context: Context, stop_event: Event):
    if config.mux is None:
        return None

    device_fd = open_mux_device(config.mux)
    ports = {}

    for name, link in config.mux.ports.items():
        ports[name] = open_mux_port(link)
        context.set_arg(f'mux_{name}', link)
        logging.info(f'Mux port {name} at {link}')

    t = Thread(
        target=mux_thread_fn,
        args=(config.mux, device_fd, ports, stop_event),
        name='mux',
    )
    t.start()

    return t


def nfs_thread_fn(config: Config, context: Context, stop_event: Event):
    from nfs3py.server import NfsServer

    server = NfsServer(config.nfs, lambda s: replace_str_args(context, s))
    server.start()
    stop_event.wait()
    server.stop()


def setup_nfs(config: Config, context: Context, stop_event: Event):
    if config.nfs is None:
        return None

    t = Thread(
        target=nfs_thread_fn,
        args=(config, context, stop_event),
        name='nfs-server',
    )
    t.start()

    return t


def run_wrapper(config: Config, context: Context):
    master_fd, slave_fd = pty.openpty()
    stdin_fd = sys.stdin.fileno()
    stdout_fd = sys.stdout.fileno()

    rows, cols, xpix, ypix = get_terminal_size(stdin_fd)
    vterm = vterm_lib.vterm_new(rows, cols)
    vterm_screen = vterm_lib.vterm_obtain_screen(vterm)
    vterm_lib.vterm_screen_reset(vterm_screen, 0)

    try:
        attrs = termios.tcgetattr(stdin_fd)
        termios.tcsetattr(slave_fd, termios.TCSANOW, attrs)
    except Exception as e:
        logging.error(e)

    try:
        winsz = struct.pack('HHHH', rows, cols, xpix, ypix)
        fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, winsz)
    except Exception as e:
        logging.error(e)

    program = tuple(replace_str_args(context, a) for a in config.program)
    proc = subprocess.Popen(
        program,
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=subprocess.STDOUT,
        close_fds=True,
    )
    os.close(slave_fd)
    old_tty = termios.tcgetattr(stdin_fd)
    tty.setraw(stdin_fd)

    try:
        process_input_output(
            config,
            context,
            stdin_fd,
            stdout_fd,
            master_fd,
            vterm,
            vterm_screen,
        )
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
        required=True,
        help='Path to config.json5',
    )
    parser.add_argument(
        '-a',
        '--arg',
        metavar='KEY=VALUE',
        help='Add argument with KEY and VALUE',
        action='append',
        default=[],
    )
    parser.add_argument(
        '--debug',
        action='store_true',
        help='Enable debug logging',
    )
    args = parser.parse_args()

    config_path = Path(args.config)
    config_data = config_path.read_text()
    config_json5 = json5.loads(config_data)  # type: ignore
    config = Config.model_validate(config_json5)  # type: ignore
    context = Context(config_path)

    logging.basicConfig(
        filename='log.txt',
        filemode='w',
        level=logging.DEBUG if args.debug else logging.INFO,
        format='%(asctime)s [%(levelname)s] %(message)s',
    )

    logging.info(f'Config: {config.model_dump_json(indent=4)}')

    for k, v in config.args.items():
        context.set_arg(k, v)

    for kv in args.arg:
        assert isinstance(kv, str)
        k, v = kv.split('=', 1)
        context.set_arg(k, v)

    stop_event = Event()

    mux_thread = setup_mux(config, context, stop_event)
    tftp_thread = setup_tftp(config, context, stop_event)
    nfs_thread = setup_nfs(config, context, stop_event)

    run_wrapper(config, context)

    stop_event.set()
    tftp_thread.join()
    if nfs_thread is not None:
        nfs_thread.join()
    if mux_thread is not None:
        mux_thread.join()


if __name__ == '__main__':
    main()
