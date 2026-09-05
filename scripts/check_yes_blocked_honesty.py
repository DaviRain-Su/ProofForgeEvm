#!/usr/bin/env python3
"""Fail when a PARTIAL coverage row still lists Implementable as Yes.

A shipped bounded profile leaves blocked remainders, not a Yes cell.
Coverage table rows 3, 16, and 22 (OzAudit 2, 16, 22) were the liars that
closed blocked work. Row 13 names flash/777/1363 as remainders rather
than starting with Yes. DONE rows may
still say Yes.
Sdk.OzAudit.temporaryGapCount stays 0.

Usage:
    python3 scripts/check_yes_blocked_honesty.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKLOG = ROOT / "docs" / "product" / "oz-sdk-backlog.md"

STALE_PHRASES = (
    "Yes — W5 slice e shipped bounded delayed default-admin profile",
    "Yes — W5 slice 7 shipped bounded 1:1 ERC-4626 vault profile",
    "Yes — this expansion shipped `authorizationState`",
    "Yes — W5 slice 8 shipped bounded fixed-id ERC-6909 using existing map primitives",
    "There is no exchange-rate math, fee accrual, flash-loan callback",
    "1:1 `Vault4626Link` stays the shipped profile",
)

REQUIRED = (
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
        "Remaining named restriction on that row is enumeration/manager.",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
        "Remaining named restriction on that row is flash/777/1363.",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
        "Remaining named restriction on that row is the remaining draft interfaces.",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean",
        "Remaining named restriction on that row is dynamic multi-id registration.",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "DefaultAdminDelay.lean",
        "is no role hierarchy, enumeration, or delay-increase scheduling API.",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc4626.lean",
        "There is no fee accrual, flash-loan",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc6909.lean",
        "Dynamic multi-id registration stays out.",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc3009.lean",
        "Sibling draft interfaces stay out.",
    ),
    (ROOT / "ProofForge" / "Evm" / "Registry.lean", 'digest := "ad40c48e855ad5ef"'),
    (ROOT / "Tests" / "EvmOzAuditSpec.lean", "!OzAudit.isTemporaryGap 2"),
    (ROOT / "Tests" / "EvmOzAuditSpec.lean", "!OzAudit.isTemporaryGap 13"),
    (ROOT / "Tests" / "EvmOzAuditSpec.lean", "!OzAudit.isTemporaryGap 16"),
    (ROOT / "Tests" / "EvmOzAuditSpec.lean", "!OzAudit.isTemporaryGap 22"),
    (
        ROOT / "Tests" / "EvmOzAuditSpec.lean",
        "Row 2 remaining named restriction is enumeration/manager.",
    ),
    (
        ROOT / "Tests" / "EvmOzAuditSpec.lean",
        "Row 13 remaining named restriction is flash/777/1363.",
    ),
    (
        ROOT / "Tests" / "EvmOzAuditSpec.lean",
        "Row 16 remaining named restriction is the remaining draft interfaces.",
    ),
    (
        ROOT / "Tests" / "EvmOzAuditSpec.lean",
        "Row 22 remaining named restriction is dynamic multi-id registration.",
    ),
    (
        BACKLOG,
        "No remaining implementable slice. W5 slice e shipped bounded delayed default-admin profile",
    ),
    (
        BACKLOG,
        "Named remainder: flash/777/1363. This expansion shipped floor",
    ),
    (
        BACKLOG,
        "No remaining implementable slice (this expansion shipped `authorizationState`",
    ),
    (
        BACKLOG,
        "No remaining implementable slice. W5 slice 8 shipped bounded fixed-id ERC-6909 using existing map primitives. Dynamic multi-id registration remains blocked.",
    ),
    (
        BACKLOG,
        "PARTIAL Implementable cells that still started with Yes",
    ),
)


def coverage_rows(text: str) -> list[tuple[str, str, str]]:
    rows: list[tuple[str, str, str]] = []
    in_table = False
    for line in text.splitlines():
        if line.startswith("| OZ path |"):
            in_table = True
            continue
        if not in_table:
            continue
        if line.startswith("|---"):
            continue
        if not line.startswith("|"):
            break
        parts = [part.strip() for part in line.split("|")]
        if len(parts) < 6:
            continue
        path, status, _module, _gap, implementable = parts[1:6]
        if path == "OZ path" or not path:
            continue
        rows.append((path, status, implementable))
    return rows


def main() -> int:
    failures: list[str] = []
    if not BACKLOG.is_file():
        print("check_yes_blocked_honesty: missing docs/product/oz-sdk-backlog.md", file=sys.stderr)
        return 1
    backlog = BACKLOG.read_text(encoding="utf-8")
    rows = coverage_rows(backlog)
    if len(rows) != 32:
        failures.append(f"docs/product/oz-sdk-backlog.md: expected 32 coverage rows, got {len(rows)}")
    for path, status, implementable in rows:
        if status == "PARTIAL" and implementable.startswith("Yes"):
            failures.append(
                f"docs/product/oz-sdk-backlog.md: PARTIAL {path} Implementable still starts with Yes"
            )
    docs = ROOT / "docs" / "product"
    for path in sorted(docs.rglob("*")):
        if not path.is_file() or path.suffix not in {".md", ".txt"}:
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
        print("check_yes_blocked_honesty: FAIL", file=sys.stderr)
        for item in failures:
            print(f"  {item}", file=sys.stderr)
        return 1
    print("check_yes_blocked_honesty: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
