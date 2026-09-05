#!/usr/bin/env python3
"""Fail when product docs still omit VestLink/Vest20Link renounceOwnership.

VestLink and Vest20Link renounceOwnership clears owner and pending and emits
OwnershipTransferred(previous, address(0)). After that, canSchedule fails closed.
There is still no cancelOwnership. Sdk.OzAudit.temporaryGapCount stays 0.

Usage:
    python3 scripts/check_vest_renounce_honesty.py
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
    "There is no `cancelOwnership` or `renounceOwnership`.",
    "`transferOwnership(address(0))` reverts `OwnableInvalidOwner(address(0))`.",
    "This phase left no renounceOwnership.",
)

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "def renounceOwnership"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "def renounceOwnership"),
    (
        ROOT / "Examples" / "Evm" / "VestLink.lean",
        "Access.Ownership.cancel s.ownership",
    ),
    (
        ROOT / "Examples" / "Evm" / "Vest20Link.lean",
        "Access.Ownership.cancel s.ownership",
    ),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "4d4f50a585db704d"'),
    (ROOT / "Tests" / "EvmVestingSpec.lean", 'IR.digestHex program == "4d4f50a585db704d"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "daab53b9a3e785ac"'),
    (ROOT / "Tests" / "EvmVest20Spec.lean", 'IR.digestHex program == "daab53b9a3e785ac"'),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
        "and Ownable2Step `transferOwnership` / `acceptOwnership` / `pendingOwner` /",
    ),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "`renounceOwnership`."),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Vesting.lean",
        "`renounceOwnership` clears owner and pending",
    ),
    (ROOT / "Tests" / "EvmVestingSpec.lean", r'"\"name\":\"renounceOwnership\""'),
    (ROOT / "Tests" / "EvmVest20Spec.lean", r'"\"name\":\"renounceOwnership\""'),
    (ROOT / "Tests" / "EvmOzAuditSpec.lean", "VestLink and Vest20Link ship `renounceOwnership`."),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "renounceOwnership()"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "renounceOwnership()"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "beneficiary fails closed after renounce"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "beneficiary fails closed after renounce"),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "Vest `renounceOwnership`.",
    ),
    (
        ROOT / "docs" / "product" / "support-matrix.md",
        "`renounceOwnership` clears owner and pending.",
    ),
    (
        ROOT / "docs" / "product" / "writing-contracts.md",
        "plus `renounceOwnership`",
    ),
    (
        ROOT / ".github" / "workflows" / "ci.yml",
        "scripts/check_vest_renounce_honesty.py",
    ),
    (ROOT / "scripts" / "ci_local.sh", "scripts/check_vest_renounce_honesty.py"),
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
        print("check_vest_renounce_honesty: FAIL", file=sys.stderr)
        for item in failures:
            print(f"  {item}", file=sys.stderr)
        return 1
    print("check_vest_renounce_honesty: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
