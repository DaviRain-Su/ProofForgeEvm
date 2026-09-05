#!/usr/bin/env python3
"""Fail when product docs still list constructor zero-owner CREATE as missing.

VestLink and Vest20Link revert OwnableInvalidOwner(address) when CREATE gets
address(0). That guard is a dropped-let in init plus an Emit revert-only
constructor prefix. Sdk.OzAudit.temporaryGapCount stays 0. A doc that still
lists the CREATE guard as missing is a lying inventory.

Usage:
    python3 scripts/check_vest_zero_owner_honesty.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = (
    ROOT / "docs" / "product",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "Vesting.lean",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "Ownable.lean",
    ROOT / "Examples" / "Evm" / "VestLink.lean",
    ROOT / "Examples" / "Evm" / "Vest20Link.lean",
)

STALE_PHRASES = (
    "Constructor zero-owner revert not lowered",
    "Constructor zero-owner revert is still not lowered",
    "Drop-in OpenZeppelin constructor zero-owner revert",
    "Remaining named gap on that row is the constructor zero-owner revert",
)

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "if Address.isZero beneficiary then"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "if Address.isZero beneficiary then"),
    (ROOT / "ProofForge" / "Evm" / "Emit.lean", "ctorOpIsRevertGuard"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "OwnershipTransferred(address(0), owner)"),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "339e0387add0c97e"'),
    (ROOT / "Tests" / "EvmVestingSpec.lean", 'IR.digestHex program == "339e0387add0c97e"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "d105175ac1ff37bd"'),
    (ROOT / "Tests" / "EvmVest20Spec.lean", 'IR.digestHex program == "d105175ac1ff37bd"'),
    (ROOT / "runtime-tests" / "evm" / "lib.sh", "pf_evm_strip_ctor_invalid_owner_guard"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "zero beneficiary CREATE"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "zero beneficiary CREATE"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "mutation unexpectedly still reverted"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "mutation unexpectedly still reverted"),
    (ROOT / "docs" / "product" / "oz-sdk-backlog.md", "Constructor CREATE ZeroAddress revert"),
    (ROOT / "docs" / "product" / "support-matrix.md", "OwnableInvalidOwner(address)"),
    (ROOT / "docs" / "product" / "writing-contracts.md", "Revert.ownableInvalidOwner"),
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
            print(f"check_vest_zero_owner_honesty: {item}", file=sys.stderr)
        print(f"check_vest_zero_owner_honesty: FAIL ({len(failures)} issue(s))", file=sys.stderr)
        return 1
    print("check_vest_zero_owner_honesty: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
