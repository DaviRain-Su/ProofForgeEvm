#!/usr/bin/env python3
"""Fail when product docs still list Ownable2Step nominate-zero as a revert.

TwoStepCounter, Credits, VestLink, and Vest20Link transferOwnership of address(0)
nominate the zero address (OZ cancel) and emit OwnershipTransferStarted.
CREATE of address(0) still reverts OwnableInvalidOwner(address). Credits grant
to zero and Vest20Link release(address(0)) still revert ZeroAddress().
Sdk.OzAudit.temporaryGapCount stays 0. A doc that still names nominate-zero
OwnableInvalidOwner as the current remainder is a lying inventory.

Usage:
    python3 scripts/check_ownable2step_cancel_honesty.py
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
    "Nominate-zero reverts `OwnableInvalidOwner(address)`.",
    "Nominate-zero reverts `OwnableInvalidOwner(address)`",
    "Zero `newOwner` reverts `OwnableInvalidOwner(address)`.",
    "zero candidate → `OwnableInvalidOwner(address)`",
    "No remaining implementable slice. CREATE and nominate-zero revert",
    "`transferOwnership` of a zero nominee reverts",
    "`transferOwnership` of a zero nominee still reverts",
    "nominate-zero also reverts `OwnableInvalidOwner(address)`",
)

FORBIDDEN_ARMS = (
    (ROOT / "Examples" / "Evm" / "TwoStepCounter.lean", "if Address.isZero candidate then"),
    (ROOT / "Examples" / "Evm" / "Credits.lean", "if Address.isZero candidate then"),
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "if Address.isZero newOwner then"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "if Address.isZero newOwner then"),
)

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "TwoStepCounter.lean", "Access.Ownership.nominate s.ownership candidate"),
    (ROOT / "Examples" / "Evm" / "Credits.lean", "Access.Ownership.nominate s.ownership candidate"),
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "Access.Ownership.nominate s.ownership newOwner"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "Access.Ownership.nominate s.ownership newOwner"),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "af949b4ad7572721"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "38e5e3c91cadf3e6"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "4d4f50a585db704d"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "daab53b9a3e785ac"'),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
        "Nominate-zero nominates the zero address (OZ cancel).",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
        "Remaining named restriction on that row is the bounded two-step profile.",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Ownable.lean",
        "`transferOwnership(0)` nominates the zero",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Vesting.lean",
        "nominates zero (OZ cancel)",
    ),
    (ROOT / "Tests" / "TwoStepCounterSpec.lean", "TwoStepCounter must not advertise ZeroAddress"),
    (ROOT / "Tests" / "EvmVestingSpec.lean", "VestLink must not advertise ZeroAddress"),
    (ROOT / "Tests" / "EvmOzAuditSpec.lean", "Row 1 nominate-zero nominates"),
    (
        ROOT / "runtime-tests" / "evm" / "lib.sh",
        "pf_evm_require_ownable2step_cancel_via_zero",
    ),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_twostep_counter.sh",
        "zero-address transferOwnership",
    ),
    (ROOT / "runtime-tests" / "evm" / "anvil_credits.sh", "zero-address transferOwnership"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "zero new owner"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "zero new owner"),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_twostep_counter.sh",
        "pf_evm_require_ownable2step_cancel_via_zero",
    ),
    (ROOT / "runtime-tests" / "evm" / "anvil_credits.sh", "pf_evm_require_ownable2step_cancel_via_zero"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "pf_evm_require_ownable2step_cancel_via_zero"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "pf_evm_require_ownable2step_cancel_via_zero"),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "Ownable2Step cancel via `transferOwnership(0)`",
    ),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "No remaining implementable slice. CREATE reverts",
    ),
    (
        ROOT / "docs" / "product" / "support-matrix.md",
        "`transferOwnership(0)` nominates the zero address (OZ cancel)",
    ),
    (
        ROOT / "docs" / "product" / "writing-contracts.md",
        "`transferOwnership(0)` nominates the zero address (OZ cancel)",
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
    for path, needle in FORBIDDEN_ARMS:
        rel = path.relative_to(ROOT)
        if not path.is_file():
            failures.append(f"{rel}: missing required file")
            continue
        if needle in path.read_text(encoding="utf-8"):
            failures.append(f"{rel}: forbidden {needle!r}")
    for path, needle in REQUIRED:
        rel = path.relative_to(ROOT)
        if not path.is_file():
            failures.append(f"{rel}: missing required file")
            continue
        if needle not in path.read_text(encoding="utf-8"):
            failures.append(f"{rel}: missing {needle!r}")
    if failures:
        print("check_ownable2step_cancel_honesty: FAIL", file=sys.stderr)
        for item in failures:
            print(f"  {item}", file=sys.stderr)
        return 1
    print("check_ownable2step_cancel_honesty: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
