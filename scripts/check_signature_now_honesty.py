#!/usr/bin/env python3
"""Fail when product docs still claim isValidSignatureNow cannot ship.

`Ierc1271.checkNow` is the combined OZ gate. A doc that says the extractor
cannot split a 65-byte signature, or that combined `isValidSignatureNow` is
still open, is a lying inventory. `Sdk.OzAudit.temporaryGapCount` stays 0.

Usage:
    python3 scripts/check_signature_now_honesty.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = (
    ROOT / "docs" / "product",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
    ROOT / "ProofForge" / "Evm" / "Sdk.lean",
    ROOT / "Tests" / "EvmOzAuditSpec.lean",
)

STALE_PHRASES = (
    "extractor does not split",
    "extractor does not lower",
    "no combined `isValidSignatureNow` because",
    "Open: a combined `isValidSignatureNow`",
    "Open for 3b: a combined `isValidSignatureNow`",
    "which the extractor does not lower",
)

REQUIRED = (
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "Ierc1271.lean", "def checkNow"),
    (ROOT / "Examples" / "Evm" / "SignerLink.lean", "Ierc1271.checkNow"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "e3d539121ce1e0d8"'),
    (ROOT / "Tests" / "EvmIerc1271Spec.lean", 'IR.digestHex evm == "e3d539121ce1e0d8"'),
    (ROOT / "runtime-tests" / "evm" / "anvil_signerlink.sh", "extcodesize forced to 0"),
    (ROOT / "docs" / "product" / "support-matrix.md", "Ierc1271.checkNow"),
    (ROOT / "docs" / "product" / "oz-sdk-backlog.md", "Sdk.Ierc1271.checkNow"),
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
            print(f"check_signature_now_honesty: {item}", file=sys.stderr)
        print(f"check_signature_now_honesty: FAIL ({len(failures)} issue(s))", file=sys.stderr)
        return 1
    print("check_signature_now_honesty: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
