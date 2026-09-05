#!/usr/bin/env python3
"""Fail when product docs still list Vest Ownable2Step as the VestingWallet gap.

VestLink and Vest20Link transferOwnership nominates and logs OwnershipTransferStarted.
acceptOwnership rotates the stored beneficiary. Nominate-zero reverts ZeroAddress().
Sdk.OzAudit.temporaryGapCount stays 0. A doc that still lists no Ownable2Step as the
current remainder is a lying inventory. Remaining named restriction is VestLink is the
ETH-only smaller profile (Vest20Link is dual-asset).

Usage:
    python3 scripts/check_vest_ownable2step_honesty.py
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
    "Remaining named gap on that row is no Ownable2Step.",
    "no Ownable2Step; VestLink remains ETH-only",
    "is one-step Ownable rotation",
)

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "def acceptOwnership"),
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "def pendingOwner"),
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "Revert.zeroAddress"),
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "Ownable.Log.ownershipTransferStarted"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "def acceptOwnership"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "def pendingOwner"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "Revert.zeroAddress"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "Ownable.Log.ownershipTransferStarted"),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "897a7934eb6291be"'),
    (ROOT / "Tests" / "EvmVestingSpec.lean", 'IR.digestHex program == "897a7934eb6291be"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "226bbefeac922a65"'),
    (ROOT / "Tests" / "EvmVest20Spec.lean", 'IR.digestHex program == "226bbefeac922a65"'),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
        "Remaining named restriction on that row is VestLink is the ETH-only smaller profile (Vest20Link is dual-asset).",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Vesting.lean",
        "Nominate-zero on",
    ),
    (ROOT / "Tests" / "EvmVestingSpec.lean", '"acceptOwnership", "pendingOwner"'),
    (ROOT / "Tests" / "EvmVestingSpec.lean", "OwnershipTransferStarted"),
    (ROOT / "Tests" / "EvmVest20Spec.lean", '"acceptOwnership", "pendingOwner"'),
    (ROOT / "Tests" / "EvmVest20Spec.lean", "OwnershipTransferStarted"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "acceptOwnership()"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "OwnershipTransferStarted"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", 'VestLink.yul" 0'),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "acceptOwnership()"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "OwnershipTransferStarted"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", 'Vest20Link.yul" 0'),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "Vest Ownable2Step nominate plus accept",
    ),
    (
        ROOT / "docs" / "product" / "support-matrix.md",
        "acceptOwnership",
    ),
    (
        ROOT / "docs" / "product" / "writing-contracts.md",
        "Ownable2Step `transferOwnership` plus `acceptOwnership`",
    ),
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
                failures.append(f"{rel}: stale {phrase!r}")
    for path, needle in REQUIRED:
        if not path.is_file():
            failures.append(f"{path.relative_to(ROOT)}: missing file")
            continue
        if needle not in path.read_text(encoding="utf-8"):
            failures.append(f"{path.relative_to(ROOT)}: missing {needle!r}")
    if failures:
        print("check_vest_ownable2step_honesty: FAIL", file=sys.stderr)
        for item in failures:
            print(f"  {item}", file=sys.stderr)
        return 1
    print("check_vest_ownable2step_honesty: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
