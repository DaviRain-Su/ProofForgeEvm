#!/usr/bin/env python3
"""Fail when product docs still list ERC-1155 TransferBatch or duplicate ids as an open gap.

Phase 2 shipped bounded `TransferBatch` / `balanceOfBatch` / `safeBatchTransferFrom` on
`MultiToken`. `DuplicateId()` is the shipped fail-closed bound versus OpenZeppelin in-order
application. `Sdk.OzAudit.temporaryGapCount` stays 0 for that bound. A doc
that says TransferBatch is still remaining S4, or that the duplicate-id gap is still open,
is a lying inventory.

Usage:
    python3 scripts/check_product_honesty.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs" / "product"

STALE_PHRASES = (
    "Open: duplicate ids",
    "no duplicate ids in one batch",
    "remaining gap the receiving side, duplicate ids",
    "remaining gap (receiving side, duplicate ids",
    "Remaining S4 (ERC-1155 `TransferBatch`",
    "`TransferBatch` only with a separately approved bounded dynamic-event plan",
    "not `TransferBatch`, safe callbacks, metadata URI, or",
    "No SDK implementation found",
    "Constructor Ownable logs remain unlowered",
    "Remaining S4 (not a “full ERC” claim): constructor `OwnershipTransferred`, `RoleAdminChanged`",
    "Remaining S4 is `RoleAdminChanged`",
    "Remaining S4 is\n> `RoleAdminChanged`",
    "Remaining S4 (not a “full ERC” claim): `RoleAdminChanged`",
)

REQUIRED = (
    (ROOT / "Examples" / "Evm" / "MultiToken.lean", ".error .DuplicateId"),
    (ROOT / "Examples" / "Evm" / "MultiToken.lean", "def safeBatchTransferFrom"),
    (ROOT / "Examples" / "Evm" / "MultiToken.lean", "def balanceOfBatch"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc1155.lean", "def distinctIds"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (ROOT / "runtime-tests" / "evm" / "anvil_multitoken.sh", "shl(224, 0xb1fb6bd0)"),
    (ROOT / "runtime-tests" / "evm" / "anvil_multitoken.sh", "DuplicateId mutation still reverted"),
    (ROOT / "runtime-tests" / "evm" / "anvil_multitoken.sh", "ABI TransferBatch signature"),
    (
        ROOT / "docs" / "product" / "sdk-foundations-design.md",
        "Phase 2 shipped bounded ERC-1155",
    ),
    (
        ROOT / "docs" / "product" / "sdk-foundations-design.md",
        "ERC-1155 `TransferBatch` rides on two tails",
    ),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "bounded `TransferBatch` event are in",
    ),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "S4 TransferBatch / constructor-log honesty",
    ),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "S4 RoleAdminChanged named restriction",
    ),
)


def main() -> int:
    failures: list[str] = []
    for path in sorted(DOCS.rglob("*")):
        if not path.is_file():
            continue
        if path.suffix not in {".md", ".txt"}:
            continue
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
            print(f"check_product_honesty: {item}", file=sys.stderr)
        print(f"check_product_honesty: FAIL ({len(failures)} issue(s))", file=sys.stderr)
        return 1
    print("check_product_honesty: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
