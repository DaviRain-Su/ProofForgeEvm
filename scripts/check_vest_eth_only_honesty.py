#!/usr/bin/env python3
"""Fail when product docs still list VestLink ETH-only as an implementable gap.

Vest20Link is the dual-asset wallet. VestLink stays the smaller ETH-only profile.
Sdk.OzAudit.temporaryGapCount stays 0. A doc that still lists VestLink remains
ETH-only as the current named gap is a lying inventory.

Usage:
    python3 scripts/check_vest_eth_only_honesty.py
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
    "Remaining named gap on that row is VestLink remains ETH-only.",
    "The remaining named gap on this row is VestLink remains ETH-only.",
    "The remaining named gap is VestLink remains ETH-only.",
    "| VestLink remains ETH-only |",
    "Row 5 stays PARTIAL (VestLink remains ETH-only)",
)

ABSENT = (
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "SafeErc20.transfer"),
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "def released__token"),
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "ERC20Released"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "released(address)"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "release(address)"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "ERC20Released"),
)

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "VestLink.lean", "ETH-only smaller profile"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "Dual-asset vesting consumer"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "def release__all"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "SafeErc20.transfer"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
        "Remaining named restriction on that row is VestLink is the ETH-only smaller profile (Vest20Link is dual-asset).",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Vesting.lean",
        "Dual-asset release lives on Vest20Link",
    ),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "897a7934eb6291be"'),
    (ROOT / "Tests" / "EvmVestingSpec.lean", 'IR.digestHex program == "897a7934eb6291be"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "226bbefeac922a65"'),
    (ROOT / "Tests" / "EvmVest20Spec.lean", 'IR.digestHex program == "226bbefeac922a65"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "ad40c48e855ad5ef"'),
    (ROOT / "Tests" / "EvmVestingSpec.lean", "VestLink must not advertise release(address)"),
    (ROOT / "Tests" / "EvmVestingSpec.lean", "VestLink must not advertise released(address)"),
    (ROOT / "Tests" / "EvmVestingSpec.lean", "VestLink must not advertise ERC20Released"),
    (ROOT / "Tests" / "EvmOzAuditSpec.lean", "OzAudit.pathTagOf 5 == OzAudit.tagFinanceVesting"),
    (ROOT / "Tests" / "EvmOzAuditSpec.lean", "!OzAudit.isTemporaryGap 5"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vestlink.sh", "released()(uint256)"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "released(address)(uint256)"),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "No remaining implementable slice. Dual-asset already lives on Vest20Link.",
    ),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "VestLink ETH-only named profile",
    ),
    (
        ROOT / "docs" / "product" / "support-matrix.md",
        "Named restricted profile. VestLink is ETH-only.",
    ),
    (
        ROOT / "docs" / "product" / "writing-contracts.md",
        "VestLink.release()` is the ETH-only smaller profile",
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
    for path, needle in ABSENT:
        if not path.is_file():
            failures.append(f"{path.relative_to(ROOT)}: missing file")
            continue
        if needle in path.read_text(encoding="utf-8"):
            failures.append(f"{path.relative_to(ROOT)}: unexpected {needle!r}")
    for path, needle in REQUIRED:
        if not path.is_file():
            failures.append(f"{path.relative_to(ROOT)}: missing file")
            continue
        if needle not in path.read_text(encoding="utf-8"):
            failures.append(f"{path.relative_to(ROOT)}: missing {needle!r}")
    if failures:
        print("check_vest_eth_only_honesty: FAIL", file=sys.stderr)
        for item in failures:
            print(f"  {item}", file=sys.stderr)
        return 1
    print("check_vest_eth_only_honesty: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
