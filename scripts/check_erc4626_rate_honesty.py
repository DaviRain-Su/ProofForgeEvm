#!/usr/bin/env python3
"""Fail when ERC-4626 docs still claim 1:1 conversion or lose floor/ceiling math.

Erc4626.convertToShares is floor assets * totalSupply / totalAssets via mulDiv.
Erc4626.previewMint is ceiling shares * totalAssets / totalSupply.
Erc4626.previewWithdraw is ceiling assets * totalSupply / totalAssets.
Empty supply is 1:1. Virtual-offset inflation defense stays out.
Sdk.OzAudit.temporaryGapCount stays 0.

Usage:
    python3 scripts/check_erc4626_rate_honesty.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

STALE_PHRASES = (
    "There is no exchange-rate math, fee accrual, flash-loan callback",
    "1:1 `convertToShares`: assets equal shares when the asset gate passes",
    "1:1 `Vault4626Link` stays the shipped profile",
    "Ceiling `previewMint` stays out",
    "Ceiling previewMint stays out",
    "Ceiling `previewWithdraw` stays out",
    "Ceiling previewWithdraw stays out",
    "Full-precision mulDiv stays out",
    "`mulDiv` stays out",
)

REQUIRED = (
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc4626.lean",
        "if UInt256.eq totalSupply UInt256.zero then assets",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc4626.lean",
        "else if UInt256.eq totalAssets UInt256.zero then UInt256.zero",
    ),
    (
        ROOT / "ProofForge" / "Extract" / "Decode.lean",
        "bargs.size ≥ 5 && isUInt256Type bargs[0]!",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc4626.lean",
        "def mulDiv (left right denom : UInt256) : UInt256 :=",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc4626.lean",
        "mulDiv assets totalSupply totalAssets",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc4626.lean",
        "mulDiv shares totalAssets totalSupply",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Runtime.lean",
        "def evmMulDiv256 (a b denom : UInt256) : UInt256 :=",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "WideWord.lean",
        "| mulDiv256 (limb : Nat)",
    ),
    (
        ROOT / "ProofForge" / "Extract" / "Decode.lean",
        "endsWith baseE \".evmMulDiv256\" then some (.mulDiv256 limb.toNat)",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc4626.lean",
        "There is no virtual-offset inflation defense, fee accrual, flash-loan",
    ),
    (
        ROOT / "Examples" / "Evm" / "Vault4626Link.lean",
        "let base := hold s",
    ),
    (
        ROOT / "Examples" / "Evm" / "Vault4626Link.lean",
        "let totalAssets := ERC20.balanceOfSelf Immutable.address",
    ),
    (
        ROOT / "Examples" / "Evm" / "Vault4626Link.lean",
        "let sharesAmt := Erc4626.sharesForDeposit assets base.totalShares totalAssets",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc4626.lean",
        "def sharesForDeposit (assets totalSupply totalAssets : UInt256) : UInt256 :=",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc4626.lean",
        "def assetsForMint (shares totalSupply totalAssets : UInt256) : UInt256 :=",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc4626.lean",
        "if UInt256.eq (UInt256.mod prod totalSupply) UInt256.zero then q",
    ),
    (
        ROOT / "Examples" / "Evm" / "Vault4626Link.lean",
        "def previewMint (s : State) (sharesAmt : UInt256) : UInt256 :=",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc4626.lean",
        "def sharesForWithdraw (assets totalSupply totalAssets : UInt256) : UInt256 :=",
    ),
    (
        ROOT / "ProofForge" / "Evm" / "Sdk" / "Erc4626.lean",
        "if UInt256.eq (UInt256.mod prod totalAssets) UInt256.zero then q",
    ),
    (
        ROOT / "Examples" / "Evm" / "Vault4626Link.lean",
        "def previewWithdraw (s : State) (assets : UInt256) : UInt256 :=",
    ),
    (
        ROOT / "Tests" / "EvmErc4626Spec.lean",
        '"totalSupply", "convertToShares", "convertToAssets", "previewMint",',
    ),
    (
        ROOT / "Tests" / "EvmErc4626Spec.lean",
        '"previewWithdraw"] do',
    ),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_vault4626link.sh",
        'mint(address,uint256)\' "$addr" 100',
    ),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_vault4626link.sh",
        '"donated convertToShares is 50"',
    ),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_vault4626link.sh",
        '"second deposit mints 50"',
    ),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_vault4626link.sh",
        '"ceiling previewMint(1) is 3"',
    ),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_vault4626link.sh",
        '"floor convertToAssets(1) is 2"',
    ),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_vault4626link.sh",
        '"zero totalAssets convertToShares is 0"',
    ),
    (
        ROOT / "runtime-tests" / "evm" / "ERC20Mock.sol",
        "function burn(address from, uint256 amt) external {",
    ),
    (
        ROOT / "Tests" / "EvmErc4626Spec.lean",
        "unless names.any (· == \"totalShares_w0\") do",
    ),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_vault4626link.sh",
        '"ceiling previewWithdraw(1) is 1"',
    ),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_vault4626link.sh",
        '"floor convertToShares(1) is 0"',
    ),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_vault4626link.sh",
        "two128=340282366920938463463374607431768211456",
    ),
    (
        ROOT / "runtime-tests" / "evm" / "anvil_vault4626link.sh",
        '"full-precision convertToShares(2^128) is 2^128"',
    ),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "ERC-4626 ceiling `previewMint`",
    ),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "ERC-4626 ceiling `previewWithdraw`",
    ),
    (
        ROOT / "docs" / "product" / "oz-sdk-backlog.md",
        "ERC-4626 floor `mulDiv`",
    ),
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
    for path, needle in REQUIRED:
        rel = path.relative_to(ROOT)
        if not path.is_file():
            failures.append(f"{rel}: missing required file")
            continue
        if needle not in path.read_text(encoding="utf-8"):
            failures.append(f"{rel}: missing {needle!r}")
    if failures:
        print("check_erc4626_rate_honesty: FAIL", file=sys.stderr)
        for item in failures:
            print(f"  {item}", file=sys.stderr)
        return 1
    print("check_erc4626_rate_honesty: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
