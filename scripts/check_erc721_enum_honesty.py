#!/usr/bin/env python3
"""Fail when product docs still list IERC721 enumeration as missing.

Gallery ships bounded IERC721Enumerable: totalSupply, tokenByIndex, and
tokenOfOwnerByIndex over UInt64 ids with compile-time capacity 4.
Sdk.OzAudit.temporaryGapCount stays 0. A doc that says there is no enumeration
is a lying inventory.

Usage:
    python3 scripts/check_erc721_enum_honesty.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = (
    ROOT / "docs" / "product",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc721.lean",
    ROOT / "Examples" / "Evm" / "Gallery.lean",
)

STALE_PHRASES = (
    "no enumeration or consecutive mint",
    "no enumeration",
    "Enumeration and the rest of IERC721 stay out",
)

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "Gallery.lean", "def tokenByIndex"),
    (ROOT / "Examples" / "Evm" / "Gallery.lean", "def tokenOfOwnerByIndex"),
    (ROOT / "Examples" / "Evm" / "Gallery.lean", "def totalSupply"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc721.lean", "namespace Enum"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (ROOT / "Tests" / "EvmErc721EnumSpec.lean", "9fdfc61d00414718"),
    (ROOT / "runtime-tests" / "evm" / "anvil_gallery.sh", "case 0x4f6ccce7"),
    (ROOT / "runtime-tests" / "evm" / "anvil_gallery.sh", "swap-remove moved id 2 into the hole"),
    (ROOT / "docs" / "product" / "oz-sdk-backlog.md", "Gallery"),
    (ROOT / "docs" / "product" / "support-matrix.md", "Gallery"),
    (ROOT / "docs" / "product" / "writing-contracts.md", "Gallery"),
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
            print(f"check_erc721_enum_honesty: {item}", file=sys.stderr)
        print(f"check_erc721_enum_honesty: FAIL ({len(failures)} issue(s))", file=sys.stderr)
        return 1
    print("check_erc721_enum_honesty: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
