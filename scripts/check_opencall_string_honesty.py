#!/usr/bin/env python3
"""Fail when OpenCall docs still refuse BoundedString or treat string as bytes.

ArgType.string is ABI string. The packed limb frame is shared with bytes.
A second packed field stays refused.
A source-built malformed UTF-8 string reverts at emit before CALL.
Sdk.OzAudit.temporaryGapCount stays 0.

Usage:
    python3 scripts/check_opencall_string_honesty.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

STALE_PHRASES = (
    "BoundedString and a second `bytes` field are refused",
    "`string` and a second `bytes` field are refused",
    "expectUnsupported env ``Unsupported.stringArg \"closed EVM scalar\"",
    "`{ v with length }` stays fail closed",
)

REQUIRED = (
    (ROOT / "ProofForge" / "Evm" / "OpenCall.lean", "| string (capacity : Nat)"),
    (ROOT / "ProofForge" / "Evm" / "OpenCall.lean", '| .string _ => pure "string"'),
    (ROOT / "ProofForge" / "Evm" / "OpenCall.lean", "def ArgType.isPacked : ArgType → Bool"),
    (ROOT / "ProofForge" / "Evm" / "OpenCall.lean", "def ArgType.validateUtf8 : ArgType → Bool"),
    (ROOT / "ProofForge" / "Evm" / "OpenCall" / "Emit.lean", 'Codec.Emit.renderUtf8Guard "oc_utf8_"'),
    (
        ROOT / "ProofForge" / "Extract" / "Decode.lean",
        "let argType := Evm.OpenCall.ArgType.string capacity",
    ),
    (ROOT / "Examples" / "Evm" / "EvmOpenCall.lean", "| label (text : BoundedString 8)"),
    (ROOT / "Examples" / "Evm" / "EvmOpenCall.lean", "def sinkString"),
    (ROOT / "Examples" / "Evm" / "EvmOpenCall.lean", "def hashString"),
    (ROOT / "Examples" / "Evm" / "EvmOpenCall.lean", "def sinkBadUtf8"),
    (ROOT / "Tests" / "EvmOpenCallSpec.lean", "(OpenCall.ArgType.string 8).abiType matches .ok \"string\""),
    (ROOT / "Tests" / "EvmOpenCallSpec.lean", "sel != Keccak.selector \"label\" #[\"bytes\"]"),
    (ROOT / "Tests" / "EvmOpenCallSpec.lean", "labelPlans[0]!.args[0]!.type == .string 8"),
    (ROOT / "Tests" / "EvmOpenCallSpec.lean", 'yul.contains "let oc_utf8_need0 := 0"'),
    (ROOT / "Tests" / "EvmOpenCallSpec.lean", "source.methods.find? (·.ixName == \"sinkBadUtf8\")"),
    (ROOT / "runtime-tests" / "evm" / "OpenCallTarget.sol", "function label(string calldata text) external"),
    (ROOT / "runtime-tests" / "evm" / "OpenCallTarget.sol", "function stringHash(string calldata) external pure returns (bytes32)"),
    (ROOT / "runtime-tests" / "evm" / "anvil_opencall.sh", "sinkString(address,string)"),
    (ROOT / "runtime-tests" / "evm" / "anvil_opencall.sh", "hashString(address,string)(bytes32)"),
    (ROOT / "runtime-tests" / "evm" / "anvil_opencall.sh", "sinkBadUtf8(address)"),
    (ROOT / "docs" / "product" / "oz-sdk-backlog.md", "BoundedString OpenCall args as ABI `string`"),
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
        print("check_opencall_string_honesty: FAIL", file=sys.stderr)
        for item in failures:
            print(f"  {item}", file=sys.stderr)
        return 1
    print("check_opencall_string_honesty: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
