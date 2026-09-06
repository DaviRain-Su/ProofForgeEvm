#!/usr/bin/env python3
"""Fail when product docs still list RoleAdminChanged as remaining S4 work.

Set2/Set4 have no admin-role rotation API. RoleGranted/RoleRevoked are shipped.
RoleAdminChanged stays a named restriction, not an implementable remainder.
Sdk.OzAudit.temporaryGapCount stays 0 for that bound. A doc that still lists
RoleAdminChanged as remaining S4 is a lying inventory.

Usage:
    python3 scripts/check_role_admin_honesty.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs" / "product"

STALE_PHRASES = (
    "Remaining S4 is `RoleAdminChanged`",
    "Remaining S4 is\n> `RoleAdminChanged`",
    "Remaining S4 (not a “full ERC” claim): `RoleAdminChanged`",
    "Remaining S4 (not a “full ERC” claim): constructor `OwnershipTransferred`, `RoleAdminChanged`",
)

REQUIRED = (
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Roles.lean",
        "There is no\n`RoleAdminChanged` helper: these sets have no admin-role rotation API.",
    ),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "ad40c48e855ad5ef"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "6225c3939859e297"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "13617c85ae8d2231"'),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "223f5a54a8d54ae4"'),
    (
        ROOT / "Tests" / "EvmOzRolesEventSpec.lean",
        "ABI unexpectedly contains RoleAdminChanged",
    ),
    (
        ROOT / "Tests" / "EvmOzCrewEventSpec.lean",
        "ABI unexpectedly contains RoleAdminChanged",
    ),
    (
        ROOT / "runtime-tests" / "evm" / "lib.sh",
        "pf_evm_typed_event_undeclared()",
    ),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_static_counter.sh",
        'pf_evm_typed_event_undeclared "$abi" RoleAdminChanged',
    ),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_static_roster.sh",
        'pf_evm_typed_event_undeclared "$abi" RoleAdminChanged',
    ),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_evmcrew.sh",
        'pf_evm_typed_event_undeclared "$abi" RoleAdminChanged',
    ),
    (
        ROOT / "docs" / "product" / "sdk-foundations-design.md",
        "`RoleAdminChanged` stays out as a named restriction",
    ),
    (
        ROOT / "docs" / "product" / "roadmap.md",
        "Named S4 restriction: `RoleAdminChanged`",
    ),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "`RoleAdminChanged`: no (no role-admin state/API)",
    ),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "S4 RoleAdminChanged named restriction",
    ),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "No remaining implementable slice. `RoleAdminChanged`: no",
    ),
    (
        ROOT / "docs" / "product" / "support-matrix.md",
        "No `RoleAdminChanged`",
    ),
    (
        ROOT / "docs" / "product" / "writing-contracts.md",
        "no `RoleAdminChanged`",
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
            print(f"check_role_admin_honesty: {item}", file=sys.stderr)
        print(f"check_role_admin_honesty: FAIL ({len(failures)} issue(s))", file=sys.stderr)
        return 1
    print("check_role_admin_honesty: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
