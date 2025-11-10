import time


def delay_us(us: int):
    end = time.perf_counter() + us / 1_000_000
    while time.perf_counter() < end:
        pass
