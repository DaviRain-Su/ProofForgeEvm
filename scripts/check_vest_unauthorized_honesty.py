#!/usr/bin/env python3
"""Fail when product docs still list only-owner Unauthorized as the VestingWallet gap.

Access.ownerViolation and VestLink/Vest20 transferOwnership revert
OwnableUnauthorizedAccount(address). Sdk.OzAudit.temporaryGapCount stays 0.
A doc that still lists Unauthorized versus OwnableUnauthorizedAccount as the
VestingWallet remainder is a lying inventory. Remaining remainder is no Ownable2Step.

Usage:
    python3 scripts/check_vest_unauthorized_honesty.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = (
    ROOT / "docs" / "product",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "Vesting.lean",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "Access.lean",
    ROOT / "Examples" / "Evm" / "VestLink.lean",
    ROOT / "Examples" / "Evm" / "Vest20Link.lean",
    ROOT / "runtime-tests" / "evm" / "anvil_bitmap_flags.sh",
)

STALE_PHRASES = (
    "`Unauthorized(address)` rather than OZ `OwnableUnauthorizedAccount(address)`",
    "Drop-in OpenZeppelin VestingWallet `OwnableUnauthorizedAccount`",
    "remaining named gap on this row is `Unauthorized(address)`",
    "Remaining named gap on that row is `Unauthorized(address)`",
)

REQUIRED = (
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "Access.lean", "Revert.ownableUnauthorizedAccount Context.caller"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "Base.lean", "def ownableUnauthorizedAccount"),
    (ROOT / "ProofForge" / "Evm" / "NativeFx.lean", "revertOwnableUnauthorizedAccount"),
    (ROOT / "ProofForge" / "Extract" / "Decode.lean", "evmRevertOwnableUnauthorizedAccount"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "Remaining named gap on that row is no Ownable2Step."),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "339e0387add0c97e"'),
    (ROOT / "Tests" / "EvmVestingSpec.lean", 'IR.digestHex program == "339e0387add0c97e"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "d105175ac1ff37bd"'),
    (ROOT / "Tests" / "EvmVest20Spec.lean", 'IR.digestHex program == "d105175ac1ff37bd"'),
    (ROOT / "Tests" / "EvmVestingSpec.lean", "VestLink ABI lost OwnableUnauthorizedAccount"),
    (ROOT / "Tests" / "EvmVest20Spec.lean", "Vest20Link ABI lost OwnableUnauthorizedAccount"),
    (ROOT / "runtime-tests" / "evm" / "lib.sh", "pf_evm_require_ownable_unauthorized_account"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "pf_evm_require_ownable_unauthorized_account"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "pf_evm_require_ownable_unauthorized_account"),
    (ROOT / "runtime-tests" / "evm" / "anvil_bitmap_flags.sh",
     "non-owner OOB toggle hits the owner gate first"),
    (ROOT / "runtime-tests" / "evm" / "anvil_bitmap_flags.sh",
     "pf_evm_require_ownable_unauthorized_account"),
    (ROOT / "docs" / "product" / "oz-sdk-backlog.md", "Only-owner `OwnableUnauthorizedAccount(address)`"),
    (ROOT / "docs" / "product" / "support-matrix.md", "OwnableUnauthorizedAccount(caller)"),
    (ROOT / "docs" / "product" / "writing-contracts.md", "OwnableUnauthorizedAccount(caller)"),
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
    bitmap_flags = ROOT / "runtime-tests" / "evm" / "anvil_bitmap_flags.sh"
    if bitmap_flags.is_file() and "'Unauthorized(address)'" in bitmap_flags.read_text(
        encoding="utf-8"
    ):
        failures.append(
            "runtime-tests/evm/anvil_bitmap_flags.sh: leftover Unauthorized(address) owner-gate check"
        )
    if failures:
        for item in failures:
            print(f"check_vest_unauthorized_honesty: {item}", file=sys.stderr)
        print(f"check_vest_unauthorized_honesty: FAIL ({len(failures)} issue(s))", file=sys.stderr)
        return 1
    print("check_vest_unauthorized_honesty: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
