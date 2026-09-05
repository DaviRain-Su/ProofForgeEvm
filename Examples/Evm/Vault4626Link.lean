import ProofForge.Evm.Sdk

/-!
Bounded ERC-4626 vault consumer: compile-time fixed underlying asset, floor
`assets * totalSupply / totalAssets` share ledger, ceiling `previewMint`, closed ERC-20
asset movement, and ordered reentrancy lock around external calls. Empty supply is 1:1.
-/

namespace Examples.Evm.Vault4626Link
open ProofForge.Evm.Sdk

structure State where
  totalShares : UInt256
  guard : UInt64
  dummy : UInt64
  deriving Repr, DecidableEq, Inhabited

structure Handles where
  guard : Storage.Static.Handle UInt64

@[pf_inline] def declared : Storage.Static.Allocated Handles :=
  let totalShares := Storage.Static.Layout.root.uint256 "totalShares"
  let guard := totalShares.next.uint64 "guard"
  { handle := { guard := guard.handle }, next := guard.next }

inductive Error where
  | overflow
  | reentrantCall
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_inline] def shares : Fungible.Balances :=
  Storage.Layout.root.addressMap256.handle

@[pf_inline] private def hold (s : State) : State :=
  { totalShares := s.totalShares, guard := s.guard, dummy := s.dummy }

@[pf_entry]
def init (_asset : Address) : State :=
  { totalShares := UInt256.zero, guard := Reentrancy.notEntered, dummy := 0 }

@[pf_entry]
def asset (_s : State) : Address :=
  if Erc4626.canVault Immutable.address then Immutable.address else Address.zero

@[pf_entry]
def totalAssets (_s : State) : UInt256 :=
  if Erc4626.canVault Immutable.address then
    ERC20.balanceOfSelf Immutable.address
  else
    UInt256.zero

@[pf_inline]
def convertShares (s : State) (assets : UInt256) : UInt256 :=
  Erc4626.convertToShares Immutable.address assets s.totalShares
    (ERC20.balanceOfSelf Immutable.address)

@[pf_inline]
def convertAssets (s : State) (sharesAmt : UInt256) : UInt256 :=
  Erc4626.convertToAssets Immutable.address sharesAmt s.totalShares
    (ERC20.balanceOfSelf Immutable.address)

@[pf_entry]
def convertToShares (s : State) (assets : UInt256) : UInt256 :=
  convertShares s assets

@[pf_entry]
def convertToAssets (s : State) (sharesAmt : UInt256) : UInt256 :=
  convertAssets s sharesAmt

@[pf_entry]
def previewDeposit (s : State) (assets : UInt256) : UInt256 :=
  Erc4626.previewDeposit Immutable.address assets s.totalShares
    (ERC20.balanceOfSelf Immutable.address)

@[pf_entry]
def previewMint (s : State) (sharesAmt : UInt256) : UInt256 :=
  Erc4626.previewMint Immutable.address sharesAmt s.totalShares
    (ERC20.balanceOfSelf Immutable.address)

@[pf_entry]
def previewRedeem (s : State) (sharesAmt : UInt256) : UInt256 :=
  Erc4626.previewRedeem Immutable.address sharesAmt s.totalShares
    (ERC20.balanceOfSelf Immutable.address)

@[pf_entry]
def totalSupply (s : State) : UInt256 :=
  if Erc4626.canVault Immutable.address then s.totalShares else UInt256.zero

@[pf_entry]
def balanceOf (_s : State) (owner : Address) : UInt256 :=
  if Erc4626.canVault Immutable.address then
    Fungible.Balances.balanceOf shares owner
  else
    UInt256.zero

@[pf_entry]
def deposit (s : State) (assets : UInt256) (receiver : Address) :
    Except Error (State × UInt64) :=
  if Erc4626.canVault Immutable.address then
    if Reentrancy.canEnter s.guard then
      let base := hold s
      let totalAssets := ERC20.balanceOfSelf Immutable.address
      let sharesAmt := Erc4626.sharesForDeposit assets base.totalShares totalAssets
      if !Address.isZero receiver &&
          Fungible.Balances.canCredit shares receiver sharesAmt then
        let _ := Reentrancy.enter declared.handle.guard
        let _ := ERC20.transferFrom Immutable.address Context.caller Context.self assets
        let _ := Reentrancy.leave declared.handle.guard
        .ok ({ totalShares := UInt256.add s.totalShares sharesAmt,
               guard := Reentrancy.notEntered,
               dummy := Fungible.Balances.credit shares receiver sharesAmt },
          Erc4626.Log.deposit Context.caller receiver assets sharesAmt)
      else if Address.isZero receiver then
        .ok (s, Revert.zeroAddress)
      else
        .error .overflow
    else
      .error .reentrantCall
  else
    .ok (s, 0)

@[pf_entry]
def redeem (s : State) (sharesAmt : UInt256) (receiver : Address) (owner : Address) :
    Except Error (State × UInt64) :=
  if Erc4626.canVault Immutable.address then
    if Reentrancy.canEnter s.guard then
      if Address.eq Context.caller owner then
        if !Address.isZero receiver &&
            Fungible.Balances.canDebit shares owner sharesAmt then
          let totalAssets := ERC20.balanceOfSelf Immutable.address
          let assets := Erc4626.assetsForRedeem sharesAmt s.totalShares totalAssets
          let _ := Reentrancy.enter declared.handle.guard
          let _ := Fungible.Balances.debit shares owner sharesAmt
          let _ := ERC20.transfer Immutable.address receiver assets
          let _ := Reentrancy.leave declared.handle.guard
          .ok ({ totalShares := UInt256.sub s.totalShares sharesAmt,
                 guard := Reentrancy.notEntered,
                 dummy := 0 },
            Erc4626.Log.withdraw Context.caller receiver owner assets sharesAmt)
        else if Address.isZero receiver then
          .ok (s, Revert.zeroAddress)
        else
          .ok (s, Fungible.Balances.insufficient shares owner sharesAmt)
      else
        .ok (s, Revert.unauthorized Context.caller)
    else
      .error .reentrantCall
  else
    .ok (s, 0)

end Examples.Evm.Vault4626Link
