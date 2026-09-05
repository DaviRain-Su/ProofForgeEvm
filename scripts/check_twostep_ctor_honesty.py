#!/usr/bin/env python3
"""Fail when TwoStepCounter/Credits CREATE no longer matches OwnableInvalidOwner plus OwnershipTransferred.

TwoStepCounter and Credits CREATE of address(0) revert OwnableInvalidOwner(address).
CREATE of a nonzero owner logs OwnershipTransferred(address(0), owner). Nominate-zero
on transferOwnership still reverts ZeroAddress(). Sdk.OzAudit.temporaryGapCount stays 0.

Usage:
    python3 scripts/check_twostep_ctor_honesty.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = (
    ROOT / "docs" / "product",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "Ownable.lean",
    ROOT / "Examples" / "Evm" / "TwoStepCounter.lean",
    ROOT / "Examples" / "Evm" / "Credits.lean",
)

STALE_PHRASES = (
    "Constructor init does not log",
    "TwoStepCounter/Credits constructor init does not log",
    "init must not log",
    "TwoStepCounter and Credits CREATE still store a zero owner",
)

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "TwoStepCounter.lean", "Revert.ownableInvalidOwner owner"),
    (ROOT / "Examples" / "Evm" / "Credits.lean", "Revert.ownableInvalidOwner owner"),
    (ROOT / "Examples" / "Evm" / "TwoStepCounter.lean", "Ownable.Log.constructorTransferred owner"),
    (ROOT / "Examples" / "Evm" / "Credits.lean", "Ownable.Log.constructorTransferred owner"),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "5c233c3f25cd6488"'),
    (ROOT / "Tests" / "EvmOzPolicyEventSpec.lean", 'expectDigest `Examples.Evm.TwoStepCounter "5c233c3f25cd6488"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "cd76930e05d07045"'),
    (ROOT / "Tests" / "EvmOzPolicyEventSpec.lean", 'expectDigest `Examples.Evm.Credits "cd76930e05d07045"'),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
        "TwoStepCounter/Credits CREATE",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
        "nominate-zero still `ZeroAddress()`",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Ownable.lean",
        "TwoStepCounter, and Credits CREATE of `address(0)` revert",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Ownable.lean",
        "`transferOwnership` of a zero nominee still reverts `ZeroAddress()`",
    ),
    (ROOT / "Tests" / "EvmOzPolicyEventSpec.lean", "ctorHasOwnableInvalidOwner"),
    (ROOT / "Tests" / "EvmOzPolicyEventSpec.lean", "ctorHasConstructorTransferred"),
    (ROOT / "Tests" / "EvmOzPolicyEventSpec.lean", "init lost constructor OwnershipTransferred"),
    (ROOT / "Tests" / "TwoStepCounterSpec.lean", '\\"name\\":\\"OwnableInvalidOwner\\"'),
    (ROOT / "Tests" / "CreditsSpec.lean", '\\"name\\":\\"OwnableInvalidOwner\\"'),
    (ROOT / "runtime-tests" / "evm" / "lib.sh", "pf_evm_strip_ctor_invalid_owner_guard"),
    (ROOT / "runtime-tests" / "evm" / "anvil_twostep_counter.sh", "CREATE OwnershipTransferred LOG3"),
    (ROOT / "runtime-tests" / "evm" / "anvil_credits.sh", "CREATE OwnershipTransferred LOG3"),
    (ROOT / "runtime-tests" / "evm" / "anvil_twostep_counter.sh", "zero-owner constructor CREATE"),
    (ROOT / "runtime-tests" / "evm" / "anvil_credits.sh", "zero-owner constructor CREATE"),
    (ROOT / "runtime-tests" / "evm" / "anvil_twostep_counter.sh", 'TwoStepCounter.yul" 0'),
    (ROOT / "runtime-tests" / "evm" / "anvil_credits.sh", 'Credits.yul" 0'),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "TwoStepCounter/Credits CREATE OwnableInvalidOwner plus OwnershipTransferred",
    ),
    (
        ROOT / "docs" / "product" / "support-matrix.md",
        "CREATE of `address(0)` reverts `OwnableInvalidOwner(address)`",
    ),
    (
        ROOT / "docs" / "product" / "writing-contracts.md",
        "TwoStepCounter, and Credits CREATE of `address(0)` revert `OwnableInvalidOwner(address)`",
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
        print("check_twostep_ctor_honesty: FAIL", file=sys.stderr)
        for item in failures:
            print(f"  {item}", file=sys.stderr)
        return 1
    print("check_twostep_ctor_honesty: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
