import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.Erc4626

/-!
# EVM SDK bounded ERC-4626 vault profile

Compile-time fixed underlying asset, floor `assets * (totalSupply + 1) / (totalAssets + 1)` and floor
`shares * (totalAssets + 1) / (totalSupply + 1)` conversion via `mulDivOffset`, ceiling
`previewMint`, ceiling `previewWithdraw`, and closed ERC-20 call policy helpers. Empty
supply is 1:1 so the first depositor is not divided by zero. Floor conversions add a virtual
+1 share and +1 asset when supply is nonzero (OZ `_decimalsOffset() == 0`), folded into one
WideWord query. There is no fee accrual, flash-loan
callback, or dynamic asset rotation. Ceiling conversions still use checked 256-bit
mul and omit the virtual offset. Nonzero `_decimalsOffset` stays out. Consumers pair this module with `Fungible.Balances`
for share ledger storage, `Sdk.Reentrancy` around external asset movement, and closed
`ERC20` / `SafeErc20` facades.

Fail-closed gates:
- Zero asset address yields zero views and no deposit/withdraw paths.
- Conversion helpers run only when `canVault asset`; otherwise zero.
- Share credit/debit and asset movement remain application-owned with explicit ordering.
-/

/-- True when the vault may advertise schedule views or run deposit/withdraw paths. -/
@[pf_inline] def wellFormedAsset (asset : Address) : Bool :=
  !Address.isZero asset

@[pf_inline] def canVault (asset : Address) : Bool :=
  wellFormedAsset asset

/-- Floor `(left * right) / denom` with a 512-bit intermediate (OZ `Math.mulDiv`).
Zero `denom` reverts. A quotient that does not fit in 256 bits reverts. Ceiling
rounding stays out. -/
@[pf_inline] def mulDiv (left right denom : UInt256) : UInt256 :=
  UInt256.mulDiv left right denom

/-- Floor `(left * (right + 1)) / (denom + 1)` (OZ `_decimalsOffset() == 0`).
Checked `+ 1` reverts on overflow. -/
@[pf_inline] def mulDivOffset (left right denom : UInt256) : UInt256 :=
  UInt256.mulDivOffset left right denom

/-- Virtual +1 share and +1 asset (OZ `_decimalsOffset() == 0`). -/
@[pf_inline] def virtualOne : UInt256 := ⟨1, 0, 0, 0⟩

/-- Floor `assets * (totalSupply + 1) / (totalAssets + 1)` when the vault already has shares.
Empty supply answers `assets` (1:1). Zero `totalAssets` with outstanding shares answers 0.
The virtual +1 is folded into `mulDivOffset` so the vault stays under EIP-170. Callers that
already passed `canVault` use this so a stored mint amount does not mention `Immutable.address`. -/
@[pf_inline] def sharesForDeposit (assets totalSupply totalAssets : UInt256) : UInt256 :=
  if UInt256.eq totalSupply UInt256.zero then assets
  else if UInt256.eq totalAssets UInt256.zero then UInt256.zero
  else mulDivOffset assets totalSupply totalAssets

/-- Floor `shares * (totalAssets + 1) / (totalSupply + 1)` when the vault already has shares. Empty
supply answers `shares` (1:1). -/
@[pf_inline] def assetsForRedeem (shares totalSupply totalAssets : UInt256) : UInt256 :=
  if UInt256.eq totalSupply UInt256.zero then shares
  else mulDivOffset shares totalAssets totalSupply

/-- Ceiling `shares * totalAssets / totalSupply` when the vault already has shares.
Empty supply answers `shares` (1:1). A nonzero remainder adds one asset.
Checked 256-bit mul still reverts if the product overflows. Ceiling conversions omit the virtual offset. -/
@[pf_inline] def assetsForMint (shares totalSupply totalAssets : UInt256) : UInt256 :=
  if UInt256.eq totalSupply UInt256.zero then shares
  else
    let prod := UInt256.mul shares totalAssets
    let q := UInt256.div prod totalSupply
    if UInt256.eq (UInt256.mod prod totalSupply) UInt256.zero then q
    else UInt256.add q ⟨1, 0, 0, 0⟩

/-- Ceiling `assets * totalSupply / totalAssets` when the vault already has shares.
Empty supply answers `assets` (1:1). Zero `totalAssets` with outstanding shares answers 0,
because checked `UInt256.div` reverts on a zero divisor. A nonzero remainder adds one share.
Checked 256-bit mul still reverts if the product overflows. Ceiling conversions omit the virtual offset. -/
@[pf_inline] def sharesForWithdraw (assets totalSupply totalAssets : UInt256) : UInt256 :=
  if UInt256.eq totalSupply UInt256.zero then assets
  else if UInt256.eq totalAssets UInt256.zero then UInt256.zero
  else
    let prod := UInt256.mul assets totalSupply
    let q := UInt256.div prod totalAssets
    if UInt256.eq (UInt256.mod prod totalAssets) UInt256.zero then q
    else UInt256.add q ⟨1, 0, 0, 0⟩

/-- Floor `assets * (totalSupply + 1) / (totalAssets + 1)` when the vault already has shares. Empty
supply answers `assets` (1:1). Zero `totalAssets` with outstanding shares answers 0. -/
@[pf_inline] def convertToShares (asset : Address)
    (assets totalSupply totalAssets : UInt256) : UInt256 :=
  if canVault asset then sharesForDeposit assets totalSupply totalAssets else UInt256.zero

/-- Floor `shares * (totalAssets + 1) / (totalSupply + 1)` when the vault already has shares. Empty
supply answers `shares` (1:1). -/
@[pf_inline] def convertToAssets (asset : Address)
    (shares totalSupply totalAssets : UInt256) : UInt256 :=
  if canVault asset then assetsForRedeem shares totalSupply totalAssets else UInt256.zero

@[pf_inline] def previewDeposit (asset : Address)
    (assets totalSupply totalAssets : UInt256) : UInt256 :=
  convertToShares asset assets totalSupply totalAssets

@[pf_inline] def previewMint (asset : Address)
    (shares totalSupply totalAssets : UInt256) : UInt256 :=
  if canVault asset then assetsForMint shares totalSupply totalAssets else UInt256.zero

@[pf_inline] def previewWithdraw (asset : Address)
    (assets totalSupply totalAssets : UInt256) : UInt256 :=
  if canVault asset then sharesForWithdraw assets totalSupply totalAssets else UInt256.zero

@[pf_inline] def previewRedeem (asset : Address)
    (shares totalSupply totalAssets : UInt256) : UInt256 :=
  convertToAssets asset shares totalSupply totalAssets

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
