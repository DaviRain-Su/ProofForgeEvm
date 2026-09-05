#!/usr/bin/env python3
"""Fail when product docs still list ERC-3009 receive as unshipped.

Auth3009Link.receiveWithAuthorization uses a distinct ReceiveWithAuthorization typehash
and requires caller == to. Row 16 stays PARTIAL. Sdk.OzAudit.temporaryGapCount stays 0.
A doc that still says no receive-with-authorization as the current gap is a lying inventory.

Usage:
    python3 scripts/check_erc3009_receive_honesty.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = (
    ROOT / "docs" / "product",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc3009.lean",
    ROOT / "Examples" / "Evm" / "Auth3009Link.lean",
)

STALE_PHRASES = (
    "no receive-with-authorization, cancellation",
    "Bounded `transferWithAuthorization` only; no receive-with-authorization",
    "There is no receive-with-\nauthorization",
    "There is no receive-with-authorization",
)

ABSENT = ()

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "Auth3009Link.lean", "def receiveWithAuthorization"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc3009.lean", "def receive"),
    (ROOT / "ProofForge" / "Evm" / "Runtime.lean", "def evmReceiveWithAuthorization"),
    (
        ROOT / "ProofForge" / "Evm" / "ClosedCall.lean",
        "receiveWithAuthorization",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "ClosedCall/Emit.lean",
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)",
    ),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
        "Remaining named restriction on that row is cancellation and the remaining draft interfaces.",
    ),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "3f8b259e6f5b6c23"'),
    (ROOT / "Tests" / "EvmErc3009Spec.lean", '"3f8b259e6f5b6c23"'),
    (ROOT / "Tests" / "EvmOzAuditSpec.lean", "OzAudit.pathTagOf 16 == OzAudit.tagIfaceDraft"),
    (ROOT / "Tests" / "EvmOzAuditSpec.lean", "!OzAudit.isTemporaryGap 16"),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_auth3009link.sh",
        "receiveWithAuthorization(address,address,uint256,uint256,uint256,bytes32,uint8,bytes32,bytes32)",
    ),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_auth3009link.sh",
        "ReceiveWithAuthorization",
    ),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "this expansion shipped `receiveWithAuthorization`",
    ),
    (
        ROOT / "docs" / "product" / "support-matrix.md",
        "Bounded ERC-3009 `transferWithAuthorization` and `receiveWithAuthorization`",
    ),
    (
        ROOT / "docs" / "product" / "writing-contracts.md",
        "bounded ERC-3009 `transferWithAuthorization` and `receiveWithAuthorization`",
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
        for item in failures:
            print(f"check_erc3009_receive_honesty: {item}", file=sys.stderr)
        print(f"check_erc3009_receive_honesty: FAIL ({len(failures)} issue(s))", file=sys.stderr)
        return 1
    print("check_erc3009_receive_honesty: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
