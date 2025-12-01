#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path
from typing import Dict, List, Set


def find_all_dts_files(root: Path) -> List[Path]:
    exts = {'.dts', '.dtsi', '.dtso'}
    out: List[Path] = []
    arch = root / 'arch'
    for a in arch.iterdir():
        d = a / 'boot' / 'dts'
        if d.is_dir():
            for f in d.rglob('*'):
                if f.suffix in exts and f.is_file():
                    out.append(f.resolve())
    return out


def find_matching_files(files: List[Path], compatibles: List[str]) -> Set[Path]:
    quoted = [f'"{c}"' for c in compatibles]
    out: Set[Path] = set()
    for path in files:
        try:
            text = path.read_text(encoding='utf-8', errors='ignore')
        except Exception:
            continue
        if any(q in text for q in quoted):
            out.add(path)
    return out


def collect_includes(files: List[Path]) -> Dict[Path, Set[Path]]:
    m: Dict[Path, Set[Path]] = {}
    for path in files:
        try:
            text = path.read_text(encoding='utf-8', errors='ignore')
        except Exception:
            m[path] = set()
            continue
        incs: Set[Path] = set()
        for line in text.splitlines():
            s = line.strip()
            if s.startswith('#include'):
                parts = s.split('"')
                if len(parts) >= 2:
                    inc = (path.parent / parts[1]).resolve()
                    incs.add(inc)
        m[path] = incs
    return m


def find_roots(incmap: Dict[Path, Set[Path]]) -> Set[Path]:
    included = {x for s in incmap.values() for x in s}
    return {p for p in incmap if p.suffix == '.dts' and p not in included}


def reverse_graph(incmap: Dict[Path, Set[Path]]) -> Dict[Path, Set[Path]]:
    rev: Dict[Path, Set[Path]] = {p: set() for p in incmap}
    for src, incs in incmap.items():
        for inc in incs:
            if inc in rev:
                rev[inc].add(src)
    return rev


def reachable(
    starts: Set[Path], rev: Dict[Path, Set[Path]], roots: Set[Path]
) -> Set[Path]:
    out: Set[Path] = set()
    for t in starts:
        stack = [t]
        seen: Set[Path] = set()
        while stack:
            n = stack.pop()
            if n in seen:
                continue
            seen.add(n)
            if n in roots:
                out.add(n)
            for parent in rev.get(n, set()):
                stack.append(parent)
    return out


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(1)

    kernel = Path(sys.argv[1]).resolve()
    compatibles = sys.argv[2:]

    files = find_all_dts_files(kernel)
    matches = find_matching_files(files, compatibles)
    incmap = collect_includes(files)
    roots = find_roots(incmap)
    rev = reverse_graph(incmap)
    tops = reachable(matches, rev, roots)

    for p in sorted(tops):
        print(p)


if __name__ == '__main__':
    main()
