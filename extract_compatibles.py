#!/usr/bin/env python3
from __future__ import annotations

import sys
from typing import Any, Set

import yaml

YamlNode = Any


def collect_strings(node: YamlNode, out: Set[str]) -> None:
    if isinstance(node, str):
        out.add(node)
    elif isinstance(node, list):
        for item in node:
            collect_strings(item, out)
    elif isinstance(node, dict):
        for value in node.values():
            collect_strings(value, out)


def find_compatible_nodes(node: YamlNode, out: Set[str]) -> None:
    if isinstance(node, dict):
        for key, value in node.items():
            if key == 'compatible':
                collect_strings(value, out)
            else:
                find_compatible_nodes(value, out)
    elif isinstance(node, list):
        for item in node:
            find_compatible_nodes(item, out)


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(1)

    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f)

    results: Set[str] = set()
    find_compatible_nodes(data, results)

    for s in sorted(results):
        print(s)


if __name__ == '__main__':
    main()
