#!/usr/bin/env python3
"""Fail when UInt64.ofNat of mixed runtime Nat add is still refused.

asVal of UInt64.ofNat folds staticNat? (OfNat and HAdd) through Lean UInt64.ofNat.
A mixed HAdd wraps the static side and addU64s a runtime side.
Lang.wrap64 publishes (2^64 + 3) as ABI 3.
Lang.wrap64mix publishes cells[0] + 2^64 as ABI cells[0].
Nested or non-add mixed runtime Nat then ofNat stays out.
Sdk.OzAudit.temporaryGapCount stays 0.

Usage:
    python3 scripts/check_uint64_ofnat_honesty.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

STALE_PHRASES = (
    "UInt64.ofNat wrap stays out",
    "UInt64.ofNat wrap of a wider Nat stays a named remainder",
    "Computed Nat overflow then ofNat stays out",
    "Computed Nat overflow then `ofNat` stays out",
    "Mixed runtime Nat add then ofNat stays out",
    "Mixed runtime Nat add then `ofNat` stays out",
)

REQUIRED = (
    (ROOT / "ProofForge" / "Extract" / "Lexical.lean", "def foldStaticNat?"),
    (ROOT / "ProofForge" / "Extract" / "Decode.lean", "isConstNamed e ``UInt64.ofNat"),
    (ROOT / "ProofForge" / "Extract" / "Decode.lean", "match foldStaticNat? env fuel arg with"),
    (ROOT / "ProofForge" / "Extract" / "Decode.lean", "if n ≥ UInt64.size then some (.lit (UInt64.ofNat n))"),
    (ROOT / "ProofForge" / "Extract" / "Decode.lean", "let addends := strip arg"),
    (ROOT / "Examples" / "Lang.lean", "def wrap64"),
    (ROOT / "Examples" / "Lang.lean", "UInt64.ofNat (18446744073709551616 + 3)"),
    (ROOT / "Examples" / "Lang.lean", "def wrap64mix"),
    (ROOT / "Examples" / "Lang.lean", "UInt64.ofNat (s.cells[0]!.toNat + 18446744073709551616)"),
    (ROOT / "Tests" / "LangSpec.lean", "#guard wrap64 (init 0) == 3"),
    (ROOT / "Tests" / "LangSpec.lean", "#guard wrap64mix (init 3) == 3"),
    (ROOT / "Tests" / "LangSpec.lean", 'source.methods.find? (·.ixName == "wrap64")'),
    (ROOT / "Tests" / "LangSpec.lean", 'source.methods.find? (·.ixName == "wrap64mix")'),
    (ROOT / "Tests" / "LangSpec.lean", ".returnU64 (.lit 3) => true"),
    (ROOT / "runtime-tests" / "evm" / "anvil_lang.sh", 'wrap64()(uint64)'),
    (ROOT / "runtime-tests" / "evm" / "anvil_lang.sh", '"wrapped ofNat ABI word is 3"'),
    (ROOT / "runtime-tests" / "evm" / "anvil_lang.sh", 'wrap64mix()(uint64)'),
    (ROOT / "runtime-tests" / "evm" / "anvil_lang.sh", '"mixed runtime ofNat follows a written cells_0"'),
    (ROOT / "docs" / "product" / "oz-sdk-backlog.md", "`UInt64.ofNat` wrap of mixed runtime Nat"),
    (ROOT / "ProofForge" / "Evm" / "Sdk" / "OzAudit.lean", "def temporaryGapCount : UInt64 := 0"),
)


def main() -> int:
    failures: list[str] = []
    docs = ROOT / "docs" / "product"
    for path in sorted(docs.rglob("*")):
        if not path.is_file() or path.suffix not in {".md", ".txt"}:
            continue
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)
        for phrase in STALE_PHRASES:
            if phrase in text:
                failures.append(f"{rel}: stale phrase {phrase!r}")
    spec = ROOT / "Tests" / "LangSpec.lean"
    spec_text = spec.read_text(encoding="utf-8") if spec.is_file() else ""
    for phrase in STALE_PHRASES:
        if phrase in spec_text:
            failures.append(f"Tests/LangSpec.lean: stale phrase {phrase!r}")
    for path, needle in REQUIRED:
        rel = path.relative_to(ROOT)
        if not path.is_file():
            failures.append(f"{rel}: missing required file")
            continue
        if needle not in path.read_text(encoding="utf-8"):
            failures.append(f"{rel}: missing {needle!r}")
    if failures:
        print("check_uint64_ofnat_honesty: FAIL", file=sys.stderr)
        for item in failures:
            print(f"  {item}", file=sys.stderr)
        return 1
    print("check_uint64_ofnat_honesty: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
