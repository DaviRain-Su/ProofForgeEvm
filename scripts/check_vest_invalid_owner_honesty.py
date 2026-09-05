#!/usr/bin/env python3
"""Fail when product docs still list Vest CREATE OwnableInvalidOwner as missing.

VestLink and Vest20Link revert OwnableInvalidOwner(address) on CREATE of
address(0) and on transferOwnership(address(0)). Sdk.OzAudit.temporaryGapCount
stays 0. A doc that still lists that selector as the VestingWallet gap is a
lying inventory. Remaining remainder is Unauthorized vs OwnableUnauthorizedAccount.

Usage:
    python3 scripts/check_vest_invalid_owner_honesty.py
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
    "CREATE reverts `ZeroAddress()` rather than OZ `OwnableInvalidOwner(address)`",
    "The selector is `ZeroAddress()`, not OZ `OwnableInvalidOwner(address)`.",
    "Drop-in OpenZeppelin VestingWallet `OwnableInvalidOwner`",
    "OZ OwnableInvalidOwner remains the named remainder",
    "OwnableInvalidOwner remains the named remainder",
)

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "Revert.ownableInvalidOwner beneficiary"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "Revert.ownableInvalidOwner beneficiary"),
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "Revert.ownableInvalidOwner newOwner"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "Revert.ownableInvalidOwner newOwner"),
    (ROOT / "ProofForge" / "Evm" / "NativeFx.lean", "revertOwnableInvalidOwner"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "Base.lean", "def ownableInvalidOwner"),
    (ROOT / "ProofForge" / "Extract" / "Decode.lean", "evmRevertOwnableInvalidOwner"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "OwnableUnauthorizedAccount(address)"),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "b9471739ac722d35"'),
    (ROOT / "Tests" / "EvmVestingSpec.lean", 'IR.digestHex program == "b9471739ac722d35"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "194894e2bbdb47e0"'),
    (ROOT / "Tests" / "EvmVest20Spec.lean", 'IR.digestHex program == "194894e2bbdb47e0"'),
    (ROOT / "runtime-tests" / "evm" / "lib.sh", "pf_evm_require_create_ownable_invalid_owner"),
    (ROOT / "runtime-tests" / "evm" / "lib.sh", "pf_evm_strip_ctor_invalid_owner_guard"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "zero new owner"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "zero new owner"),
    (ROOT / "docs" / "product" / "oz-sdk-backlog.md", "CREATE and `transferOwnership` `OwnableInvalidOwner(address)`"),
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
            print(f"check_vest_invalid_owner_honesty: {item}", file=sys.stderr)
        print(f"check_vest_invalid_owner_honesty: FAIL ({len(failures)} issue(s))", file=sys.stderr)
        return 1
    print("check_vest_invalid_owner_honesty: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
