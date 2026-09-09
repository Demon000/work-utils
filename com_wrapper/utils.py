import time


def delay_us(us: int):
    time.sleep(us / 1_000_000)
