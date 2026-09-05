#!/usr/bin/env python3
"""Fail when product docs still list ERC-20 vesting as an open gap.

`Vest20Link.release(address)` is the shipped map-backed OZ `release(address token)`
profile. `Sdk.OzAudit.temporaryGapCount` stays 0. A doc that says the ERC-20
vesting map is still missing is a lying inventory.

Usage:
    python3 scripts/check_vest20_honesty.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = (
    ROOT / "docs" / "product",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
    ROOT / "ProofForge" / "Evm" / "Sdk.lean",
    ROOT / "Tests" / "EvmOzAuditSpec.lean",
)

STALE_PHRASES = (
    "ERC-20 vesting map, beneficiary rotation, parameterless release mutation",
    "There is no ERC-20 token map, beneficiary rotation, or arbitrary schedule mutation",
)

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "SafeErc20.transfer"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "Vesting.lean", "def erc20Released"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "daab53b9a3e785ac"'),
    (ROOT / "Tests" / "EvmVest20Spec.lean", 'IR.digestHex program == "daab53b9a3e785ac"'),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "rewrote"),
    (ROOT / "docs" / "product" / "oz-sdk-backlog.md", "Vest20Link"),
    (ROOT / "docs" / "product" / "support-matrix.md", "Vest20Link"),
    (ROOT / "docs" / "product" / "writing-contracts.md", "Vest20Link.release"),
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
            print(f"check_vest20_honesty: {item}", file=sys.stderr)
        print(f"check_vest20_honesty: FAIL ({len(failures)} issue(s))", file=sys.stderr)
        return 1
    print("check_vest20_honesty: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
