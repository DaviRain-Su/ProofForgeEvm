#!/usr/bin/env python3
"""Fail when product docs still list IERC1271 false vs revert as the remainder.

Ierc1271.validNow / validSignature answer Bool over OpenCall.staticTryMagic.
checkSignature / checkNow stay fail-closed CALL carriers. Row 12 stays PARTIAL.
Sdk.OzAudit.temporaryGapCount stays 0.
A doc that still names false vs revert as the current gap is a lying inventory.

Usage:
    python3 scripts/check_ierc1271_bool_honesty.py
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
    "Remaining: receiving side, wider payloads, `false` vs revert",
    "Both helpers revert, where OZ answers `false`",
    "revert instead of `false`",
    "Drop-in OpenZeppelin SignatureChecker (`false` instead of revert",
)

REQUIRED = (
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "Ierc1271.lean", "def validNow"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "Ierc1271.lean", "def validSignature"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "Base.lean", "def staticTryMagic"),
    (ROOT / "ProofForge" / "Evm" / "Runtime.lean", "def evmOpenStaticTryMagic"),
    (ROOT / "ProofForge" / "Evm" / "CallResult.lean", "tryMagicBytes4"),
    (ROOT / "Examples" / "Evm" / "SignerLink.lean", "def tryNow"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "Remaining: receiving side, wider payloads",
    ),
    (ROOT / "docs" / "product" / "support-matrix.md", "Ierc1271.validNow"),
    (ROOT / "runtime-tests" / "evm" / "anvil_signerlink.sh", "tryNow(address,bytes32,bytes)"),
    (ROOT / "runtime-tests" / "evm" / "Erc1271ViewWalletMock.sol", "external view returns (bytes4)"),
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
            print(f"check_ierc1271_bool_honesty: {item}", file=sys.stderr)
        print(f"check_ierc1271_bool_honesty: FAIL ({len(failures)} issue(s))", file=sys.stderr)
        return 1
    print("check_ierc1271_bool_honesty: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
