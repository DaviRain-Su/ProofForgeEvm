#!/usr/bin/env python3
"""Compare two pf-build directories of hex .bin files.

Prints runtime byte size (hex length / 2) before, after, and delta, plus
whether the files are byte-identical. A reviewer reruns this against two
`lake exe pf -- build --out` directories. EIP-170 is 24576 runtime bytes.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

EIP170 = 24576


def runtime_bytes(path: Path) -> int:
    text = path.read_text(encoding="ascii").strip()
    if text.startswith("0x"):
        text = text[2:]
    if len(text) % 2 != 0 or any(c not in "0123456789abcdefABCDEF" for c in text):
        raise ValueError(f"not hex bytecode: {path}")
    return len(text) // 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    args = parser.parse_args()
    before_dir = args.before
    after_dir = args.after
    befores = sorted(before_dir.glob("*.bin"))
    if not befores:
        print(f"no .bin files in {before_dir}", file=sys.stderr)
        return 1
    identical = 0
    moved = 0
    over = 0
    print(f"{'program':<24} {'before':>8} {'after':>8} {'delta':>8}  status")
    names: set[str] = set()
    for path in befores:
        name = path.name.removesuffix(".bin")
        names.add(name)
        other = after_dir / path.name
        bsz = runtime_bytes(path)
        if not other.is_file():
            print(f"{name:<24} {bsz:8d} {'-':>8} {'-':>8}  MISSING")
            moved += 1
            continue
        asz = runtime_bytes(other)
        same = path.read_bytes() == other.read_bytes()
        tag = "identical" if same else "MOVED"
        if same:
            identical += 1
        else:
            moved += 1
        if asz > EIP170:
            tag += f" OVER-{asz - EIP170}"
            over += 1
        print(f"{name:<24} {bsz:8d} {asz:8d} {asz - bsz:8d}  {tag}")
    for path in sorted(after_dir.glob("*.bin")):
        name = path.name.removesuffix(".bin")
        if name in names:
            continue
        asz = runtime_bytes(path)
        tag = "NEW"
        if asz > EIP170:
            tag += f" OVER-{asz - EIP170}"
            over += 1
        print(f"{name:<24} {'-':>8} {asz:8d} {'-':>8}  {tag}")
    print(f"identical={identical} moved={moved} over_eip170={over}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
