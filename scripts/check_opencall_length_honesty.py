#!/usr/bin/env python3
"""Fail when OpenCall docs still refuse `{ v with length }` packed tails.

decodePackedByteArgParts mixedParts? reads length from the constructor's
length argument and GetElem from its values argument.
sinkKeep publishes a UInt32 parameter as that length.
asVal of UInt32.ofNat masks a non-literal with 0xffffffff.
sinkWrap publishes that wrapped length.
Emit reverts gt(len, capacity).
A second packed field stays refused.
Sdk.OzAudit.temporaryGapCount stays 0.

Usage:
    python3 scripts/check_opencall_length_honesty.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

STALE_PHRASES = (
    "`{ v with length }` stays fail closed",
    "the structure-update base resolution is a decoder follow-up",
    "A source-built `{ data with length := k }` argument stays fail closed",
    "A parameter `{ v with length := keep }` stays out unless emit reverts",
    "UInt32.ofNat wrap of a wider Nat stays a named remainder",
)

REQUIRED = (
    (ROOT / "ProofForge" / "Extract" / "Decode.lean", "let mixedParts? : Option (Array Ops.Val) := do"),
    (ROOT / "ProofForge" / "Extract" / "Decode.lean", "isConstNamed e ``UInt32.ofNat"),
    (ROOT / "Examples" / "Evm" / "EvmOpenCall.lean", "def sinkTrunc"),
    (ROOT / "Examples" / "Evm" / "EvmOpenCall.lean", "{ data with length := 3 }"),
    (ROOT / "Tests" / "EvmOpenCallSpec.lean", "source.methods.find? (·.ixName == \"sinkTrunc\")"),
    (ROOT / "Tests" / "EvmOpenCallSpec.lean", "truncPlans[0]!.args[1]!.parts[0]! == .lit 3"),
    (ROOT / "Tests" / "EvmOpenCallSpec.lean", 'truncPlans[0]!.args[1]!.parts[1]! matches .field _ "values_0"'),
    (ROOT / "runtime-tests" / "evm" / "anvil_opencall.sh", "sinkTrunc(address,uint256,bytes)"),
    (ROOT / "Examples" / "Evm" / "EvmOpenCall.lean", "def sinkKeep"),
    (ROOT / "Examples" / "Evm" / "EvmOpenCall.lean", "{ data with length := keep }"),
    (ROOT / "Tests" / "EvmOpenCallSpec.lean", "source.methods.find? (·.ixName == \"sinkKeep\")"),
    (ROOT / "Tests" / "EvmOpenCallSpec.lean", "keepPlans[0]!.args[1]!.parts[0]! == .arg 3"),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_opencall.sh",
        "sinkKeep(address,uint256,bytes,uint32)",
    ),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_opencall.sh",
        '"keep longer than capacity reverts empty"',
    ),
    (ROOT / "ProofForge" / "Extract" / "Decode.lean", "some (.bitAnd v (.lit (0xffffffff : UInt64)))"),
    (ROOT / "Examples" / "Evm" / "EvmOpenCall.lean", "def sinkWrap"),
    (ROOT / "Examples" / "Evm" / "EvmOpenCall.lean", "{ data with length := UInt32.ofNat wide.toNat }"),
    (ROOT / "Tests" / "EvmOpenCallSpec.lean", "source.methods.find? (·.ixName == \"sinkWrap\")"),
    (
        ROOT / "Tests" / "EvmOpenCallSpec.lean",
        "wrapPlans[0]!.args[1]!.parts[0]! == .bitAnd (.arg 3) (.lit 0xffffffff)",
    ),
    (ROOT / "Tests" / "EvmOpenCallSpec.lean", 'yul.contains ", 0xffffffff)"'),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_opencall.sh",
        "sinkWrap(address,uint256,bytes,uint64)",
    ),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_opencall.sh",
        '"wrapped ofNat ABI length is 3"',
    ),
    (ROOT / "docs" / "product" / "oz-sdk-backlog.md", "OpenCall `UInt32.ofNat` wrap"),
    (ROOT / "docs" / "product" / "oz-sdk-backlog.md", "OpenCall `{ v with length }` packed-tail decoder"),
    (ROOT / "docs" / "product" / "oz-sdk-backlog.md", "OpenCall parameter `{ v with length := keep }`"),
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
    spec = ROOT / "Tests" / "EvmOpenCallSpec.lean"
    spec_text = spec.read_text(encoding="utf-8") if spec.is_file() else ""
    for phrase in STALE_PHRASES:
        if phrase in spec_text:
            failures.append(f"Tests/EvmOpenCallSpec.lean: stale phrase {phrase!r}")
    for path, needle in REQUIRED:
        rel = path.relative_to(ROOT)
        if not path.is_file():
            failures.append(f"{rel}: missing required file")
            continue
        if needle not in path.read_text(encoding="utf-8"):
            failures.append(f"{rel}: missing {needle!r}")
    if failures:
        print("check_opencall_length_honesty: FAIL", file=sys.stderr)
        for item in failures:
            print(f"  {item}", file=sys.stderr)
        return 1
    print("check_opencall_length_honesty: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
