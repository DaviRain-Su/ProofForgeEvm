#!/usr/bin/env python3
"""Fail when product docs still list ERC-3009 cancel as unshipped.

Auth3009Link.cancelAuthorization uses a distinct CancelAuthorization typehash
and marks the same auth-used slot as transfer/receive. Row 16 stays PARTIAL.
Sdk.OzAudit.temporaryGapCount stays 0.
A doc that still says cancellation is the current gap is a lying inventory.

Usage:
    python3 scripts/check_erc3009_cancel_honesty.py
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
    "cancellation and the remaining draft interfaces",
    "Cancellation is out",
    "Cancellation stays out",
    "no cancellation or cross-chain/account protocols",
    "There is no cancellation",
)

ABSENT = ()

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "Auth3009Link.lean", "def cancelAuthorization"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc3009.lean", "def cancel"),
    (ROOT / "ProofForge" / "Evm" / "Runtime.lean", "def evmCancelAuthorization"),
    (
        ROOT / "ProofForge" / "Evm" / "ClosedCall.lean",
        "cancelAuthorization",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "ClosedCall/Emit.lean",
        "CancelAuthorization(address authorizer,bytes32 nonce)",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "ClosedCall/Emit.lean",
        "AuthorizationCanceled(address,bytes32)",
    ),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
        "Remaining named restriction on that row is the remaining draft interfaces.",
    ),
    (ROOT / "Tests" / "EvmOzAuditSpec.lean", "OzAudit.pathTagOf 16 == OzAudit.tagIfaceDraft"),
    (ROOT / "Tests" / "EvmOzAuditSpec.lean", "!OzAudit.isTemporaryGap 16"),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_auth3009link.sh",
        "cancelAuthorization(address,bytes32,uint8,bytes32,bytes32)",
    ),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_auth3009link.sh",
        "CancelAuthorization",
    ),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_auth3009link.sh",
        "AuthorizationCanceled",
    ),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "this expansion shipped `cancelAuthorization`",
    ),
    (
        ROOT / "docs" / "product" / "support-matrix.md",
        "Bounded ERC-3009 `transferWithAuthorization`, `receiveWithAuthorization`, and `cancelAuthorization`",
    ),
    (
        ROOT / "docs" / "product" / "writing-contracts.md",
        "bounded ERC-3009 `transferWithAuthorization`, `receiveWithAuthorization`, and `cancelAuthorization`",
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
            print(f"check_erc3009_cancel_honesty: {item}", file=sys.stderr)
        print(f"check_erc3009_cancel_honesty: FAIL ({len(failures)} issue(s))", file=sys.stderr)
        return 1
    print("check_erc3009_cancel_honesty: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
