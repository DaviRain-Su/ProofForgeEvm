#!/usr/bin/env python3
"""Fail when product docs still list IERC1271 receiving as an implementable gap.

SignerLink calls isValidSignature on another contract. A pf_entry that answers
isValidSignature is the wallet. That receiving side stays a permanent non-goal.
Wider payloads stay the 65-byte bound. Row 12 stays PARTIAL.
Sdk.OzAudit.temporaryGapCount stays 0.
A doc that still names receiving as the current implementable remainder is a lying inventory.

Usage:
    python3 scripts/check_ierc1271_receiving_honesty.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = (
    ROOT / "docs" / "product",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "Ierc1271.lean",
    ROOT / "Examples" / "Evm" / "SignerLink.lean",
)

STALE_PHRASES = (
    "Remaining: receiving side, wider payloads",
    "Remaining: receiving side, wider payloads, `false` vs revert",
    "the receiving side is still implementable",
    "implementable remainder is the receiving side",
)

REQUIRED = (
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Ierc1271.lean",
        "Implementing the receiving side (`isValidSignature` on this contract) stays a non-goal.",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
        "Remaining named restriction is the receiving side (a permanent non-goal) and wider payloads.",
    ),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "e3d539121ce1e0d8"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "ad40c48e855ad5ef"'),
    (ROOT / "Tests" / "EvmIerc1271Spec.lean", 'IR.digestHex evm == "e3d539121ce1e0d8"'),
    (ROOT / "Tests" / "EvmOzAuditSpec.lean", "!OzAudit.isTemporaryGap 12"),
    (
        ROOT / "Tests" / "EvmOzAuditSpec.lean",
        "receiving side stays a permanent non-goal",
    ),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "No remaining implementable slice. Phase 3 shipped `checkSignature`",
    ),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "The receiving side stays a permanent non-goal. Wider payloads stay the 65-byte bound.",
    ),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "An ERC-1271 wallet (`isValidSignature` on a `pf` contract) stays out.",
    ),
    (
        ROOT / "docs" / "product" / "support-matrix.md",
        "an ERC-1271 wallet (the receiving side is a non-goal)",
    ),
    (
        ROOT / "docs" / "product" / "writing-contracts.md",
        "An ERC-1271 wallet stays out.",
    ),
    (
        ROOT / "Examples" / "Evm" / "SignerLink.lean",
        "This contract does not implement `isValidSignature`.",
    ),
    (ROOT / "runtime-tests" / "evm" / "anvil_signerlink.sh", "tryNow(address,bytes32,bytes)"),
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
    for path in sorted((ROOT / "Examples" / "Evm").rglob("*.lean")):
        text = path.read_text(encoding="utf-8")
        if "def isValidSignature" in text:
            failures.append(
                f"{path.relative_to(ROOT)}: unexpected `def isValidSignature` (receiving side)"
            )
    for path, needle in REQUIRED:
        rel = path.relative_to(ROOT)
        if not path.is_file():
            failures.append(f"{rel}: missing required file")
            continue
        if needle not in path.read_text(encoding="utf-8"):
            failures.append(f"{rel}: missing {needle!r}")
    if failures:
        print("check_ierc1271_receiving_honesty: FAIL", file=sys.stderr)
        for item in failures:
            print(f"  {item}", file=sys.stderr)
        return 1
    print("check_ierc1271_receiving_honesty: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
