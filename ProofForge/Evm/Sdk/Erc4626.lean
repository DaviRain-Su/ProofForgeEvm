import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.Erc4626

/-!
# EVM SDK bounded ERC-4626 vault profile

Compile-time fixed underlying asset, 1:1 share/asset conversion, and closed ERC-20 call policy
helpers. There is no exchange-rate math, fee accrual, flash-loan callback, or dynamic asset
rotation. Consumers pair this module with `Fungible.Balances` for share ledger storage,
`Sdk.Reentrancy` around external asset movement, and closed `ERC20` / `SafeErc20` facades.

Fail-closed gates:
- Zero asset address yields zero views and no deposit/withdraw paths.
- Conversion helpers are identity only when `canVault asset`; otherwise zero.
- Share credit/debit and asset movement remain application-owned with explicit ordering.
-/

/-- True when the vault may advertise schedule views or run deposit/withdraw paths. -/
@[pf_inline] def wellFormedAsset (asset : Address) : Bool :=
  !Address.isZero asset

@[pf_inline] def canVault (asset : Address) : Bool :=
  wellFormedAsset asset

/-- 1:1 `convertToShares`: assets equal shares when the asset gate passes. -/
@[pf_inline] def convertToShares (asset : Address) (assets : UInt256) : UInt256 :=
  if canVault asset then assets else UInt256.zero

/-- 1:1 `convertToAssets`: shares equal assets when the asset gate passes. -/
@[pf_inline] def convertToAssets (asset : Address) (shares : UInt256) : UInt256 :=
  if canVault asset then shares else UInt256.zero

@[pf_inline] def previewDeposit (asset : Address) (assets : UInt256) : UInt256 :=
  convertToShares asset assets

@[pf_inline] def previewMint (asset : Address) (shares : UInt256) : UInt256 :=
  convertToAssets asset shares

@[pf_inline] def previewWithdraw (asset : Address) (assets : UInt256) : UInt256 :=
  convertToShares asset assets

@[pf_inline] def previewRedeem (asset : Address) (shares : UInt256) : UInt256 :=
  convertToAssets asset shares

/-- Canonical ERC-4626 typed events. Indexed flags follow the standard ABI layout. -/
inductive Notice where
  | Deposit (sender : Event.Indexed Address) (owner : Event.Indexed Address)
      (assets : UInt256) (shares : UInt256)
  | Withdraw (sender : Event.Indexed Address) (receiver : Event.Indexed Address)
      (owner : Event.Indexed Address) (assets : UInt256) (shares : UInt256)
  deriving Repr, DecidableEq, Inhabited

namespace Log

/-- LOG4 `Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares)`. -/
@[pf_inline] def deposit (sender owner : Address) (assets shares : UInt256) : UInt64 :=
  Event.emit (Notice.Deposit (Event.indexed sender) (Event.indexed owner) assets shares)

/-- LOG5 `Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares)`. -/
@[pf_inline] def withdraw (sender receiver owner : Address) (assets shares : UInt256) : UInt64 :=
  Event.emit (Notice.Withdraw (Event.indexed sender) (Event.indexed receiver)
    (Event.indexed owner) assets shares)

end Log

end ProofForge.Evm.Sdk.Erc4626
