#!/usr/bin/env python3
"""Fail when product docs still list the VestingWallet cliff as missing.

VestLink and Vest20Link store cliffDuration and expose cliff(). Before the
cliff, vestedAmount is 0. After the cliff the linear formula still uses
timestamp - start. Sdk.OzAudit.temporaryGapCount stays 0. A doc that still
lists the cliff as the VestingWallet gap is a lying inventory.

Usage:
    python3 scripts/check_vest_cliff_honesty.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = (
    ROOT / "docs" / "product",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "Vesting.lean",
    ROOT / "Examples" / "Evm" / "VestLink.lean",
    ROOT / "Examples" / "Evm" / "Vest20Link.lean",
)

STALE_PHRASES = (
    "Cliff schedule; constructor zero-owner revert not lowered",
    "There is no cliff or arbitrary schedule mutation",
    "There is no cliff or schedule mutation",
    "Drop-in OpenZeppelin VestingWalletCliff / constructor zero-owner revert",
    "Remaining named gaps on that row are the cliff schedule and the",
    "Row 5 stays PARTIAL (cliff, constructor zero-owner revert)",
)

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "def cliff"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "def cliff"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "Vesting.lean", "def wellFormedCliff"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "Vesting.lean", "def cliffAt"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "OZ jump at the cliff is half the allocation"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "OZ jump at the cliff is half the ERC-20 allocation"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "constructor(address,uint64,uint64,uint64)"),
    (ROOT / "docs" / "product" / "oz-sdk-backlog.md", "constructor-stored OZ cliff"),
    (ROOT / "docs" / "product" / "support-matrix.md", "cliffDuration"),
    (ROOT / "docs" / "product" / "writing-contracts.md", "cliffDuration"),
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
            print(f"check_vest_cliff_honesty: {item}", file=sys.stderr)
        print(f"check_vest_cliff_honesty: FAIL ({len(failures)} issue(s))", file=sys.stderr)
        return 1
    print("check_vest_cliff_honesty: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
