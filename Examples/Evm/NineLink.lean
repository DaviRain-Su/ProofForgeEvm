import ProofForge.Evm.Sdk

/-!
Owner-minted bounded ERC-6909 fixed-id consumer using existing map primitives.
-/

namespace Examples.Evm.NineLink
open ProofForge.Evm.Sdk

structure State where
  dummy : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_inline] def fixedId : UInt256 :=
  ⟨Immutable.u64, 0, 0, 0⟩

@[pf_inline] def balances : Erc6909.Balances :=
  Storage.Layout.root.addressMap256.handle

@[pf_inline] def allowances : Erc6909.Allowances :=
  Storage.Layout.root.addressMap256.next.addressPairMap256.handle

@[pf_inline] def operators : Erc6909.Operators :=
  Storage.Layout.root.addressMap256.next.addressPairMap256.next.addressPairMap.handle

@[pf_entry]
def init (_owner : Address) (_tokenId : UInt64) : State :=
  { dummy := 0 }

@[pf_entry]
def tokenId (_s : State) : UInt256 :=
  if Erc6909.matchesId fixedId fixedId then fixedId else UInt256.zero

@[pf_entry]
def balanceOf (_s : State) (owner : Address) (id : UInt256) : UInt256 :=
  if Erc6909.matchesId id fixedId then
    Erc6909.Balances.balanceOf balances owner
  else
    UInt256.zero

@[pf_entry]
def allowance (_s : State) (owner spender : Address) (id : UInt256) : UInt256 :=
  if Erc6909.matchesId id fixedId then
    Erc6909.Allowances.allowanceOf allowances owner spender
  else
    UInt256.zero

@[pf_entry]
def isOperator (_s : State) (owner operator : Address) : Bool :=
  Erc6909.Operators.isOperator operators owner operator

@[pf_entry]
def mint (s : State) (to : Address) (id : UInt256) (amount : UInt256) :
    Except Error (State × UInt64) :=
  if Address.eqImmutable Context.caller then
    if Erc6909.canMint balances to id fixedId amount then
      .ok ({ dummy := Erc6909.mint balances to amount },
        Erc6909.Log.transfer Context.caller Address.zero to id amount)
    else if !Erc6909.matchesId id fixedId then
      .ok (s, Revert.unauthorized Context.caller)
    else if Address.isZero to then
      .ok (s, Revert.zeroAddress)
    else
      .error .overflow
  else
    .ok (s, Revert.unauthorized Context.caller)

@[pf_entry]
def approve (s : State) (spender : Address) (id : UInt256) (amount : UInt256) :
    Except Error (State × UInt64) :=
  if Erc6909.matchesId id fixedId then
    if Address.isZero spender then
      .ok (s, Revert.zeroAddress)
    else
      .ok ({ dummy := Erc6909.Allowances.approve allowances Context.caller spender amount },
        Erc6909.Log.approval Context.caller spender id amount)
  else
    .ok (s, Revert.unauthorized Context.caller)

@[pf_entry]
def setOperator (s : State) (operator : Address) (approved : Bool) :
    Except Error (State × UInt64) :=
  if Address.isZero operator then
    .ok (s, Revert.zeroAddress)
  else if Address.eq operator Context.caller then
    .ok (s, Revert.unauthorized Context.caller)
  else
    .ok ({ dummy := Erc6909.Operators.setOperator operators Context.caller operator approved },
      Erc6909.Log.operatorSet Context.caller operator approved)

@[pf_entry]
def transfer (s : State) (receiver : Address) (id : UInt256) (amount : UInt256) :
    Except Error (State × UInt64) :=
  if !Erc6909.matchesId id fixedId then
    .ok (s, Revert.unauthorized Context.caller)
  else if Address.isZero receiver then
    .ok (s, Revert.zeroAddress)
  else if Erc6909.Balances.canTransfer balances Context.caller receiver amount then
    .ok ({ dummy := Erc6909.Balances.transfer balances Context.caller receiver amount },
      Erc6909.Log.transfer Context.caller Context.caller receiver id amount)
  else
    .ok (s, Erc6909.Balances.insufficient balances Context.caller amount)

@[pf_entry]
def transferFrom (s : State) (sender receiver : Address) (id : UInt256) (amount : UInt256) :
    Except Error (State × UInt64) :=
  if !Erc6909.matchesId id fixedId then
    .ok (s, Revert.unauthorized Context.caller)
  else if Address.isZero receiver then
    .ok (s, Revert.zeroAddress)
  else if Address.eq Context.caller sender then
    if Erc6909.Balances.canTransfer balances sender receiver amount then
      .ok ({ dummy := Erc6909.Balances.transfer balances sender receiver amount },
        Erc6909.Log.transfer Context.caller sender receiver id amount)
    else
      .ok (s, Erc6909.Balances.insufficient balances sender amount)
  else if (Erc6909.isOperatorOrOwner operators Context.caller sender id fixedId ||
      Erc6909.Allowances.canSpend allowances sender Context.caller amount) &&
      Erc6909.Balances.canTransfer balances sender receiver amount then
    let spend :=
      if Address.eq Context.caller sender then 0
      else if Erc6909.Allowances.canSpend allowances sender Context.caller amount then
        Erc6909.Allowances.spend allowances sender Context.caller amount
      else 0
    .ok ({ dummy := (Erc6909.Balances.transfer balances sender receiver amount) ||| spend },
      Erc6909.Log.transfer Context.caller sender receiver id amount)
  else if !Erc6909.isOperatorOrOwner operators Context.caller sender id fixedId &&
      !Erc6909.Allowances.canSpend allowances sender Context.caller amount then
    .ok (s, Erc6909.Allowances.insufficient allowances sender Context.caller amount)
  else
    .ok (s, Erc6909.Balances.insufficient balances sender amount)

@[pf_entry]
def supportsInterface (_s : State) (interfaceId : Bytes4) : Bool :=
  Erc165.supports interfaceId Erc165.erc165

end Examples.Evm.NineLink
