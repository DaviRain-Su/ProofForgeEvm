#!/usr/bin/env python3
"""Fail when product docs still list constructor OwnershipTransferred as missing.

VestLink and Vest20Link emit OwnershipTransferred(address(0), owner) at CREATE.
That log is the else-arm of the OwnableInvalidOwner dropped-let plus Emit
ctorOpIsAllowedPrelude. Sdk.OzAudit.temporaryGapCount stays 0. A doc that still
lists the constructor log as the VestingWallet gap is a lying inventory.
The remaining named gap is the split native-ETH / ERC-20 wallets.
Only-owner reverts are OwnableUnauthorizedAccount(address).

Usage:
    python3 scripts/check_vest_ctor_log_honesty.py
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
    "Constructor `OwnershipTransferred(address(0), owner)` is still not lowered",
    "The constructor `OwnershipTransferred` log still does not lower",
    "Constructor `OwnershipTransferred(address(0), owner)` does not lower",
    "Constructor logs stay refused. Row 5 stays PARTIAL",
    "Remaining named gap on that row is the constructor",
    "Drop-in OpenZeppelin VestingWallet constructor `OwnershipTransferred` log and `OwnableInvalidOwner`",
)

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "Ownable.Log.constructorTransferred"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "Ownable.Log.constructorTransferred"),
    (ROOT / "ProofForge" / "Evm" / "Emit.lean", "ctorOpIsAllowedPrelude"),
    (ROOT / "ProofForge" / "Evm" / "NativeFx.lean", "isConstructorTransferred"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "OwnableInvalidOwner(address)"),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "fac351201b2369ba"'),
    (ROOT / "Tests" / "EvmVestingSpec.lean", 'IR.digestHex program == "fac351201b2369ba"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "6f387586e59335d5"'),
    (ROOT / "Tests" / "EvmVest20Spec.lean", 'IR.digestHex program == "6f387586e59335d5"'),
    (ROOT / "runtime-tests" / "evm" / "lib.sh", "pf_evm_strip_ctor_ownership_log"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "CREATE OwnershipTransferred LOG3"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "CREATE OwnershipTransferred LOG3"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "constructor-log mutation CREATE"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "constructor-log mutation CREATE"),
    (ROOT / "docs" / "product" / "oz-sdk-backlog.md", "Constructor `OwnershipTransferred(address(0), owner)` log"),
    (ROOT / "docs" / "product" / "support-matrix.md", "CREATE of a nonzero owner logs"),
    (ROOT / "docs" / "product" / "writing-contracts.md", "Ownable.Log.constructorTransferred"),
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
            print(f"check_vest_ctor_log_honesty: {item}", file=sys.stderr)
        print(f"check_vest_ctor_log_honesty: FAIL ({len(failures)} issue(s))", file=sys.stderr)
        return 1
    print("check_vest_ctor_log_honesty: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
