#!/usr/bin/env python3
"""Fail when product docs still list split native-ETH / ERC-20 wallets as the gap.

Vest20Link is the dual-asset wallet: receive plus release() for native ETH, and
release(address) for ERC-20. Sdk.OzAudit.temporaryGapCount stays 0. A doc that
still lists the split wallets as the VestingWallet remainder is a lying
inventory. Remaining remainder is no Ownable2Step and ABI releasedOf rather
than OZ released.

Usage:
    python3 scripts/check_vest_dual_honesty.py
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
    ROOT / "Tests" / "EvmVest20Spec.lean",
)

STALE_PHRASES = (
    "Remaining named gap on that row is the split native-ETH / ERC-20 wallets",
    "remaining named gap on this row is the split native-ETH / ERC-20 wallets",
    "Split native-ETH / ERC-20 wallets (OZ is one contract)",
    "Split native-ETH / ERC-20 wallets (OZ VestingWallet is one contract)",
    "Row 5 stays PARTIAL (split native-ETH / ERC-20 wallets)",
    "Native-ETH `release()` stays on `VestLink`. `temporaryGapCount` stays 0.",
    "Vest20Link must not grow a native receive path",
    "Vest20Link must not grow an EtherReleased surface",
)

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "def release__all"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "def receive"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "nativeReleased"),
    (ROOT / "Examples" / "Evm" / "Vest20Link.lean", "Vesting.Log.etherReleased"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "no Ownable2Step and ABI `releasedOf`"),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "ac851caa6b77b626"'),
    (ROOT / "Tests" / "EvmVest20Spec.lean", 'IR.digestHex program == "ac851caa6b77b626"'),
    (ROOT / "Tests" / "EvmVest20Spec.lean", "Vest20Link lost release()"),
    (ROOT / "Tests" / "EvmVest20Spec.lean", "ABI lost dual-asset vesting surface"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "releasable()(uint256)"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "releasedOf()(uint256)"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh", "EtherReleased"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh",
     "native released stays zero after ERC-20 quarter"),
    (ROOT / "runtime-tests" / "evm" / "anvil_vest20link.sh",
     "rotated beneficiary ETH delta"),
    (ROOT / "docs" / "product" / "oz-sdk-backlog.md", "Dual-asset `Vest20Link`"),
    (ROOT / "docs" / "product" / "support-matrix.md", "dual-asset wallet"),
    (ROOT / "docs" / "product" / "writing-contracts.md", "Vest20Link.release()"),
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
            print(f"check_vest_dual_honesty: {item}", file=sys.stderr)
        print(f"check_vest_dual_honesty: FAIL ({len(failures)} issue(s))", file=sys.stderr)
        return 1
    print("check_vest_dual_honesty: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
