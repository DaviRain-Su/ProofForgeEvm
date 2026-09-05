#!/usr/bin/env python3
"""Fail when product docs still list Erc20Meta issuer permit as unshipped.

Erc20Meta.permit / DOMAIN_SEPARATOR / nonces use the closed Token/1 path.
Rows 8 and 19 stay PARTIAL. Sdk.OzAudit.temporaryGapCount stays 0.
A doc that still says permit is closed call/internal as the current gap is a lying inventory.

Usage:
    python3 scripts/check_erc20_permit_honesty.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = (
    ROOT / "docs" / "product",
    ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
    ROOT / "Examples" / "Evm" / "Erc20Meta.lean",
)

STALE_PHRASES = (
    "permit is closed call/internal",
    "no pause / permit /",
    "extensions/permit-votes remain PARTIAL).",
)

ABSENT = (
    (ROOT / "Examples" / "Evm" / "Erc20Meta.lean", "def nonceOf"),
    (ROOT / "runtime-tests" / "evm" / "anvil_erc20meta.sh", "nonceOf(address)"),
)

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "Erc20Meta.lean", "def permit"),
    (ROOT / "Examples" / "Evm" / "Erc20Meta.lean", "def DOMAIN_SEPARATOR"),
    (ROOT / "Examples" / "Evm" / "Erc20Meta.lean", "def nonces"),
    (ROOT / "Examples" / "Evm" / "Erc20Meta.lean", "Permit.authorize"),
    (ROOT / "Examples" / "Evm" / "Erc20Meta.lean", "def nonceStore"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
        "Remaining named restriction on those rows is extensions/permit-votes.",
    ),
    (ROOT / "Tests" / "Erc20MetaSpec.lean", '"permit"'),
    (ROOT / "Tests" / "Erc20MetaSpec.lean", '"DOMAIN_SEPARATOR"'),
    (ROOT / "Tests" / "Erc20MetaSpec.lean", '"nonces"'),
    (ROOT / "Tests" / "EvmOzAuditSpec.lean", "OzAudit.pathTagOf 8 == OzAudit.tagIface20"),
    (ROOT / "Tests" / "EvmOzAuditSpec.lean", "OzAudit.pathTagOf 19 == OzAudit.tagToken20"),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "3dfa816778bd3ef6"'),
    (ROOT / "Tests" / "Erc20MetaSpec.lean", 'digest == "3dfa816778bd3ef6"'),
    (ROOT / "Tests" / "EvmOzAuditSpec.lean", "!OzAudit.isTemporaryGap 8"),
    (ROOT / "runtime-tests" / "evm" / "anvil_erc20meta.sh", "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"),
    (ROOT / "runtime-tests" / "evm" / "anvil_erc20meta.sh", "DOMAIN_SEPARATOR()(bytes32)"),
    (ROOT / "runtime-tests" / "evm" / "anvil_erc20meta.sh", "nonces(address)(uint256)"),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "this expansion shipped issuer permit on `Erc20Meta`",
    ),
    (
        ROOT / "docs" / "product" / "support-matrix.md",
        "issuer EIP-2612 `permit` / `DOMAIN_SEPARATOR` / `nonces`",
    ),
    (
        ROOT / "docs" / "product" / "writing-contracts.md",
        "issuer EIP-2612 `permit` / `DOMAIN_SEPARATOR` / `nonces`",
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
            print(f"check_erc20_permit_honesty: {item}", file=sys.stderr)
        print(f"check_erc20_permit_honesty: FAIL ({len(failures)} issue(s))", file=sys.stderr)
        return 1
    print("check_erc20_permit_honesty: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
