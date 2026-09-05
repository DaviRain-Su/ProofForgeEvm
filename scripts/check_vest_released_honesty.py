#!/usr/bin/env python3
"""Fail when product docs still list ABI releasedOf as the VestingWallet gap.

VestLink and Vest20Link publish OZ released() / released(address). Sdk.OzAudit.temporaryGapCount
stays 0. A doc that still lists releasedOf as the current remainder is a lying inventory.
Remaining remainder is no Ownable2Step.

Usage:
    python3 scripts/check_vest_released_honesty.py
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
    "no Ownable2Step and ABI `releasedOf`",
    "Remaining named gap on that row is no Ownable2Step and ABI `releasedOf`",
)

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "def released (s : State) : UInt256"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "def released__eth"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "def released__token"),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "339e0387add0c97e"'),
    (ROOT / "Tests" / "EvmVestingSpec.lean", 'IR.digestHex program == "339e0387add0c97e"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "d105175ac1ff37bd"'),
    (ROOT / "Tests" / "EvmVest20Spec.lean", 'IR.digestHex program == "d105175ac1ff37bd"'),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
        "Remaining named gap on that row is no Ownable2Step.",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Vesting.lean",
        "ABI `released()` / `released(address)` match OZ",
    ),
    (ROOT / "Tests" / "EvmVest20Spec.lean", "Vest20Link lost released()"),
    (ROOT / "Tests" / "EvmVest20Spec.lean", "Vest20Link lost released(address)"),
    (ROOT / "Tests" / "EvmVest20Spec.lean", "Vest20Link must not advertise releasedOf"),
    (ROOT / "Tests" / "EvmVestingSpec.lean", "VestLink must not advertise releasedOf"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "released()(uint256)"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "released()(uint256)"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "released(address)(uint256)"),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "ABI `released()` / `released(address)`",
    ),
    (
        ROOT / "docs" / "product" / "writing-contracts.md",
        "`released()` and `released(address)` are the OZ view names",
    ),
    (
        ROOT / "docs" / "product" / "support-matrix.md",
        "`released()` / `released(address)` are the OZ view names",
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
        print("check_vest_released_honesty: FAIL", file=sys.stderr)
        for item in failures:
            print(f"  {item}", file=sys.stderr)
        return 1
    print("check_vest_released_honesty: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
