import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.Erc6909

/-!
# EVM SDK bounded fixed-id ERC-6909 profile

Reusable O(1) single-id balance, per-id allowance, and operator core over existing typed hashed-map
namespaces. A fixed compile-time token id selects one `AddressMap256` balance namespace and one
`AddressPairMap256` allowance namespace; operator approval lives in one `AddressPairMap` flag map.

## Honest bound

Only the configured `fixedId` is live. Every view and mutation predicate gates on `matchesId`
before touching storage; other ids read zero and fail authorization without aliasing the fixed id.
Dynamic multi-id registration stays out.
-/

/-- True when `tokenId` equals the configured fixed id. -/
@[pf_inline] def matchesId (tokenId fixedId : UInt256) : Bool :=
  UInt256.eq tokenId fixedId

abbrev Balances := Storage.AddressMap256
abbrev Allowances := Storage.AddressPairMap256
abbrev Operators := Storage.AddressPairMap

namespace Balances

@[pf_inline] def balanceOf (balances : Balances) (owner : Address) : UInt256 :=
  balances.get owner

@[pf_inline] def canCredit (balances : Balances) (owner : Address) (amount : UInt256) : Bool :=
  UInt256.ge (balances.nextAdd owner amount) (balances.balanceOf owner)

@[pf_inline] def credit (balances : Balances) (owner : Address) (amount : UInt256) : UInt64 :=
  balances.put owner (balances.nextAdd owner amount)

@[pf_inline] def canDebit (balances : Balances) (owner : Address) (amount : UInt256) : Bool :=
  balances.containsAtLeast owner amount

@[pf_inline] def debit (balances : Balances) (owner : Address) (amount : UInt256) : UInt64 :=
  balances.put owner (balances.nextSub owner amount)

@[pf_inline] def canTransfer (balances : Balances) (source receiver : Address)
    (amount : UInt256) : Bool :=
  !Address.isZero receiver &&
    balances.containsAtLeast source amount &&
    (Address.eq source receiver || balances.canCredit receiver amount)

@[pf_inline] def transfer (balances : Balances) (source receiver : Address)
    (amount : UInt256) : UInt64 :=
  if Address.eq source receiver then
    0
  else
    debit balances source amount ||| credit balances receiver amount

@[pf_inline] def insufficient (balances : Balances) (owner : Address) (amount : UInt256) : UInt64 :=
  balances.revertInsufficient owner amount

end Balances

namespace Allowances

@[pf_inline] def allowanceOf (allowances : Allowances) (owner spender : Address) : UInt256 :=
  allowances.get owner spender

@[pf_inline] def approve (allowances : Allowances) (owner spender : Address)
    (amount : UInt256) : UInt64 :=
  allowances.put owner spender amount

@[pf_inline] def canSpend (allowances : Allowances) (owner spender : Address)
    (amount : UInt256) : Bool :=
  allowances.containsAtLeast owner spender amount

@[pf_inline] def spend (allowances : Allowances) (owner spender : Address)
    (amount : UInt256) : UInt64 :=
  allowances.put owner spender (allowances.nextSub owner spender amount)

@[pf_inline] def insufficient (allowances : Allowances) (owner spender : Address)
    (amount : UInt256) : UInt64 :=
  allowances.revertInsufficient owner spender amount

end Allowances

namespace Operators

@[pf_inline] def isOperator (operators : Operators) (owner operator : Address) : Bool :=
  operators.get owner operator != 0

@[pf_inline] def setOperator (operators : Operators) (owner operator : Address)
    (approved : Bool) : UInt64 :=
  operators.put owner operator (if approved then (1 : UInt64) else 0)

end Operators

@[pf_inline] def isOperatorOrOwner (operators : Operators) (spender owner : Address)
    (tokenId fixedId : UInt256) : Bool :=
  matchesId tokenId fixedId &&
    (Address.eq spender owner || operators.isOperator owner spender)

@[pf_inline] def canMint (balances : Balances) (to : Address) (tokenId fixedId amount : UInt256) :
    Bool :=
  matchesId tokenId fixedId && !Address.isZero to && balances.canCredit to amount

@[pf_inline] def mint (balances : Balances) (to : Address) (amount : UInt256) : UInt64 :=
  balances.credit to amount

@[pf_inline] def canBurn (balances : Balances) (source : Address) (tokenId fixedId amount : UInt256) :
    Bool :=
  matchesId tokenId fixedId && balances.canDebit source amount

@[pf_inline] def burn (balances : Balances) (source : Address) (amount : UInt256) : UInt64 :=
  balances.debit source amount

inductive Notice where
  | Transfer (caller : Event.Indexed Address) (sender : Event.Indexed Address)
      (receiver : Event.Indexed Address) (id : UInt256) (amount : UInt256)
  | Approval (owner : Event.Indexed Address) (spender : Event.Indexed Address)
      (id : UInt256) (amount : UInt256)
  | OperatorSet (owner : Event.Indexed Address) (operator : Event.Indexed Address)
      (approved : Bool)
  deriving Repr, DecidableEq, Inhabited

namespace Log

@[pf_inline] def transfer (caller sender receiver : Address) (tokenId amount : UInt256) : UInt64 :=
  Event.emit (Notice.Transfer (Event.indexed caller) (Event.indexed sender)
    (Event.indexed receiver) tokenId amount)

@[pf_inline] def approval (owner spender : Address) (tokenId amount : UInt256) : UInt64 :=
  Event.emit (Notice.Approval (Event.indexed owner) (Event.indexed spender) tokenId amount)

@[pf_inline] def operatorSet (owner operator : Address) (approved : Bool) : UInt64 :=
  Event.emit (Notice.OperatorSet (Event.indexed owner) (Event.indexed operator) approved)

end Log

end ProofForge.Evm.Sdk.Erc6909
