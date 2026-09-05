#!/usr/bin/env python3
"""Fail when product docs still list Ownable2Step nominate-zero as ZeroAddress.

TwoStepCounter, Credits, VestLink, and Vest20Link transferOwnership of address(0)
revert OwnableInvalidOwner(address). Credits grant to zero and Vest20Link
release(address(0)) still revert ZeroAddress(). Sdk.OzAudit.temporaryGapCount stays 0.
A doc that still names nominate-zero ZeroAddress as the current remainder is a lying inventory.

Usage:
    python3 scripts/check_nominate_invalid_owner_honesty.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = (
    ROOT / "docs" / "product",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "Ownable.lean",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "Vesting.lean",
    ROOT / "Examples" / "Evm" / "TwoStepCounter.lean",
    ROOT / "Examples" / "Evm" / "Credits.lean",
    ROOT / "Examples" / "Evm" / "VestLink.lean",
    ROOT / "Examples" / "Evm" / "Vest20Link.lean",
)

STALE_PHRASES = (
    "nominate-zero still `ZeroAddress()`",
    "Nominate-zero on `transferOwnership` still reverts `ZeroAddress()`",
    "`transferOwnership` of a zero nominee still reverts `ZeroAddress()`",
    "Nominate-zero still reverts `ZeroAddress()`",
    "Nominate-zero reverts `ZeroAddress()`",
    "Zero `newOwner` reverts `ZeroAddress()`",
    "`transferOwnership(address(0))` reverts `ZeroAddress()`",
)

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "TwoStepCounter.lean", "Revert.ownableInvalidOwner candidate"),
    (ROOT / "Examples" / "Evm" / "Credits.lean", "Revert.ownableInvalidOwner candidate"),
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "Revert.ownableInvalidOwner newOwner"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "Revert.ownableInvalidOwner newOwner"),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "f53ac3264ec9cf51"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "9bbe0424c5bc56d0"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "86c8363611ee3cc7"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "9a9cce6e0d2a58a2"'),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
        "Nominate-zero reverts `OwnableInvalidOwner(address)`.",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
        "Remaining named restriction on that row is the bounded two-step profile.",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Ownable.lean",
        "`transferOwnership` of a zero nominee reverts",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Vesting.lean",
        "Nominate-zero on",
    ),
    (ROOT / "Tests" / "TwoStepCounterSpec.lean", "TwoStepCounter must not advertise ZeroAddress"),
    (ROOT / "Tests" / "EvmVestingSpec.lean", "VestLink must not advertise ZeroAddress"),
    (ROOT / "Tests" / "EvmOzAuditSpec.lean", "Row 1 nominate-zero reverts"),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_twostep_counter.sh",
        "zero-address transferOwnership",
    ),
    (ROOT / "runtime-tests" / "evm" / "anvil_credits.sh", "zero-address transferOwnership"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "zero new owner"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "zero new owner"),
    (ROOT / "runtime-tests" / "evm" / "anvil_twostep_counter.sh", "pf_evm_require_ownable_invalid_owner"),
    (ROOT / "runtime-tests" / "evm" / "anvil_credits.sh", "pf_evm_require_ownable_invalid_owner"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "pf_evm_require_ownable_invalid_owner"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "pf_evm_require_ownable_invalid_owner"),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "Ownable2Step nominate-zero `OwnableInvalidOwner`",
    ),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "No remaining implementable slice. CREATE and nominate-zero revert",
    ),
    (
        ROOT / "docs" / "product" / "support-matrix.md",
        "Nominate-zero reverts `OwnableInvalidOwner(address)`",
    ),
    (
        ROOT / "docs" / "product" / "writing-contracts.md",
        "Nominate-zero reverts `OwnableInvalidOwner(address)`",
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
                failures.append(f"{rel}: stale phrase {phrase!r}")
    for path, needle in REQUIRED:
        rel = path.relative_to(ROOT)
        if not path.is_file():
            failures.append(f"{rel}: missing required file")
            continue
        if needle not in path.read_text(encoding="utf-8"):
            failures.append(f"{rel}: missing {needle!r}")
    if failures:
        print("check_nominate_invalid_owner_honesty: FAIL", file=sys.stderr)
        for item in failures:
            print(f"  {item}", file=sys.stderr)
        return 1
    print("check_nominate_invalid_owner_honesty: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
