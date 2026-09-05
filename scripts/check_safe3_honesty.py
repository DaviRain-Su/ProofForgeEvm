#!/usr/bin/env python3
"""Fail when product docs still list the ERC-721 3-arg safeTransferFrom as missing.

Collectible ships both ABI overloads. Lean names the 3-arg root `safeTransferFrom__id`.
`Sdk.OzAudit.temporaryGapCount` stays 0. A doc that says there is no three-argument
overload is a lying inventory.

Usage:
    python3 scripts/check_safe3_honesty.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = (
    ROOT / "docs" / "product",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc721.lean",
    ROOT / "Examples" / "Evm" / "Collectible.lean",
)

STALE_PHRASES = (
    "no three-argument overload",
    "there is no three-argument overload",
    "one Lean name is one ABI name; callers pass `0x`",
)

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "Collectible.lean", "def safeTransferFrom__id"),
    (ROOT / "ProofForge" / "Extract.lean", "def abiNameOfLean"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (ROOT / "Tests" / "EvmErc721Spec.lean", "42842e0e"),
    (ROOT / "runtime-tests" / "evm" / "anvil_collectible.sh", "case 0x42842e0e"),
    (ROOT / "runtime-tests" / "evm" / "anvil_collectible.sh", "rewrote 3-arg selector left the owner in place"),
    (ROOT / "docs" / "product" / "oz-sdk-backlog.md", "safeTransferFrom__id"),
    (ROOT / "docs" / "product" / "support-matrix.md", "safeTransferFrom__id"),
    (ROOT / "docs" / "product" / "writing-contracts.md", "safeTransferFrom__id"),
)


def iter_scan_files() -> list[Path]:
    files: list[Path] = []
    for root in SCAN_ROOTS:
        if root.is_file():
            files.append(root)
            continue
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*")):
            if path.is_file() and path.suffix in {".md", ".txt", ".lean"}:
                files.append(path)
    return files


def main() -> int:
    failures: list[str] = []
    for path in iter_scan_files():
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)
        for phrase in STALE_PHRASES:
            if phrase in text:
                failures.append(f"{rel}: stale phrase {phrase!r}")
    for path, needle in REQUIRED:
        rel = path.relative_to(ROOT)
        if not path.is_file():
            failures.append(f"{rel}: missing required file")
            continue
        if needle not in path.read_text(encoding="utf-8"):
            failures.append(f"{rel}: missing {needle!r}")
    if failures:
        for item in failures:
            print(f"check_safe3_honesty: {item}", file=sys.stderr)
        print(f"check_safe3_honesty: FAIL ({len(failures)} issue(s))", file=sys.stderr)
        return 1
    print("check_safe3_honesty: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
