#!/usr/bin/env python3

import sys
from collections import OrderedDict

text = sys.stdin.read().splitlines()
versions: OrderedDict[str, list[str]] = OrderedDict()
current = None
buffer: list[str] = []


def flush_buffer():
    if buffer and current:
        item = '\n'.join(buffer).rstrip()

        if item.strip().lower() in ('* no changes'):
            buffer.clear()
            return

        if item not in versions[current]:
            versions[current].append(item)
        buffer.clear()


for line in text:
    line = line.rstrip()
    if not line.strip():
        continue

    if line.endswith(':'):  # version header
        flush_buffer()
        current = line[:-1].strip()
        versions.setdefault(current, [])
        continue

    if current is None:
        continue

    if line.lstrip().startswith('*'):  # start of new bullet
        flush_buffer()
    buffer.append(line)

flush_buffer()

for i, (version, items) in enumerate(versions.items()):
    print(f'{version}:')
    for item in items:
        print(item)
    if i < len(versions) - 1:
        print()
