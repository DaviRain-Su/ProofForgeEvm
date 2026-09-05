#!/usr/bin/env python3
"""Fail when product docs still list vesting rotation or release() as missing.

VestLink.release() pays releasable() native ETH. transferOwnership rotates the
stored beneficiary on VestLink and Vest20Link. Sdk.OzAudit.temporaryGapCount
stays 0. A doc that still lists those as the VestingWallet gap is a lying
inventory.

Usage:
    python3 scripts/check_vest_rotate_honesty.py
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
    "Beneficiary rotation; parameterless native-ETH `release()` (ETH still takes an explicit payout)",
    "There is no beneficiary rotation",
    "ETH still takes an explicit payout",
    "Drop-in OpenZeppelin VestingWallet (beneficiary rotation, parameterless ETH `release()`)",
    "There is no beneficiary rotation or schedule mutation",
    "There is no beneficiary rotation or arbitrary schedule mutation",
)

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "def release__all"),
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "def transferOwnership"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "def transferOwnership"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "98d9e9f0644d9029"'),
    (ROOT / "Tests" / "EvmVestingSpec.lean", 'IR.digestHex program == "98d9e9f0644d9029"'),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "release()"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "transferOwnership(address)"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "ERC-20 beneficiary rotated"),
    (ROOT / "docs" / "product" / "oz-sdk-backlog.md", "VestLink.release()"),
    (ROOT / "docs" / "product" / "support-matrix.md", "transferOwnership"),
    (ROOT / "docs" / "product" / "writing-contracts.md", "VestLink.release()"),
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
            print(f"check_vest_rotate_honesty: {item}", file=sys.stderr)
        print(f"check_vest_rotate_honesty: FAIL ({len(failures)} issue(s))", file=sys.stderr)
        return 1
    print("check_vest_rotate_honesty: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
