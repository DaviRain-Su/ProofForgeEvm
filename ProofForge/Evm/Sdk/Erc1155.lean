import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.Erc1155

/-!
# EVM SDK bounded ERC-1155 core (EVM-SDK-8)

Reusable O(1) single-id balance and operator core over the existing typed hashed-map namespaces.
A `(owner, tokenId)` balance lives in one `Storage.AddressPairMap256` keyed by the owner address
and the three-limb `tokenKey`; operator approval lives in one `Storage.AddressPairMap` UInt64
flag map. Both handles are compile-time `Storage.Layout` allocations; no runtime layout object,
heap allocation, or host Map/Array ever reaches contract state.

## Key envelope (honest bound)

`AddressPairMap256` keys are `Address` pairs, so a token id is accepted only when its top UInt256
limb is zero (`canEncode`): the supported id space is 192-bit. Every authorization and mutation
predicate gates on `canEncode` *before* `tokenKey` truncation, and consumers gate every view the
same way through the checked `balanceOf` helper. `id + 2^192` can never alias a live `(owner, id)`
balance through a view, authorization, or write.

## Owned surface

Single-id checked balance reads, a bounded `balanceOfBatch` over at most `batchCapacity` pairs
(one checked read per slot; unequal lengths answer an empty array because a view cannot revert),
`setApprovalForAll`/`isApprovedForAll`, checked mint/credit, checked burn/debit, and alias-safe
`transfer` decisions/effects (equal source/destination is a successful no-op after the debit gate
instead of two writes through the same hashed key). Credit rejects UInt256 wraparound; debit
rejects underflow. Canonical ERC-1155 logs are reusable `Event.emit` wrappers
(`Log.transferSingle` / `Log.approvalForAll`): LOG4 `TransferSingle` with two data words (`id`,
`value`), and LOG3 `ApprovalForAll` with a bool data word.

## Explicitly unsupported

Batch mutations (`safeBatchTransferFrom`, mint/burn batches), ERC1155Receiver callbacks
(`onERC1155Received`), metadata URI, `TransferBatch`, and unbounded inputs.
Static ERC-165 declarations are supplied separately by `Sdk.Erc165`; this ledger never infers
interface support from its methods.
There is no new Runtime leaf, hashed-map kind, Op/IR/Component/Emit recipe, protocol opcode,
selector/topic/offset magic, or hidden storage write: every state write is an existing explicit
hashed-map effect. Authorization against `Context.caller`, event/error ordering, pause, and
supply policy remain application-owned.
-/

/-- True when `tokenId` fits the three-limb `Address` map key (top UInt256 limb is zero). This is
the honest key envelope: the bounded core supports 192-bit token ids. -/
@[pf_inline] def canEncode (tokenId : UInt256) : Bool :=
  tokenId.w3 == 0

/-- Map key for one token id. Precondition: `canEncode tokenId`. -/
@[pf_inline] def tokenKey (tokenId : UInt256) : Address :=
  ⟨tokenId.w0, tokenId.w1, tokenId.w2⟩

/-- Compile-time handle to (owner, tokenId) → UInt256 balance storage. -/
abbrev Balances := Storage.AddressPairMap256

/-- Compile-time handle to (owner, operator) → UInt64 approval flag storage. -/
abbrev Operators := Storage.AddressPairMap

/-- Compile-time capacity of one batch: the most (owner, id) pairs a batch entry accepts. -/
abbrev batchCapacity : Nat := 4

/-- A bounded batch argument or result. The ABI decoder rejects `length > batchCapacity` before
source execution and zero-fills the inactive slots. -/
abbrev Batch (α : Type) := ProofForge.Core.Value.BoundedVec α batchCapacity

/-- Active length of a batch answer. Equal lengths answer `owners.length`; unequal lengths answer
zero, so the view publishes an empty array rather than pairing an owner with a stranger's id.
A view has no revert channel today (`Except` on a view is refused as a mutating boundary), which
is why this is a length rule and not an `ERC1155InvalidArrayLength` revert. -/
@[pf_inline] def batchLength (owners : Batch Address) (ids : Batch UInt256) : UInt32 :=
  if owners.length == ids.length then owners.length else 0

namespace Balances

/-- O(1) single-id balance read after an explicit key-envelope check. The `Encoded` suffix records
the precondition `canEncode tokenId`; without it `tokenKey` would truncate and could alias another
id. Prefer the checked `balanceOf` facade at application boundaries. -/
@[pf_inline] def balanceOfEncoded (balances : Balances) (owner : Address) (tokenId : UInt256) :
    UInt256 :=
  balances.get owner (tokenKey tokenId)

/-- O(1) single-id balance read with the key-envelope gate inside the reusable SDK helper.
Unencodable ids return zero and never reach the truncated map key. -/
@[pf_inline] def balanceOf (balances : Balances) (owner : Address) (tokenId : UInt256) :
    UInt256 :=
  if canEncode tokenId then balanceOfEncoded balances owner tokenId else UInt256.zero

/-- Bounded `balanceOfBatch`: one checked single-id read per slot, `batchLength` active slots.
Inactive slots hold the decoder's zero owner and zero id and read the unused `(0x0, 0)` key. -/
@[pf_inline] def balanceOfBatch (balances : Balances) (owners : Batch Address)
    (ids : Batch UInt256) : Batch UInt256 :=
  { length := batchLength owners ids
    values := #v[balanceOf balances owners.values[0] ids.values[0],
      balanceOf balances owners.values[1] ids.values[1],
      balanceOf balances owners.values[2] ids.values[2],
      balanceOf balances owners.values[3] ids.values[3]] }

/-- Credit is valid when the id encodes and the addition cannot wrap UInt256. -/
@[pf_inline] def canCredit (balances : Balances) (owner : Address)
    (tokenId amount : UInt256) : Bool :=
  canEncode tokenId &&
    UInt256.ge (balances.nextAdd owner (tokenKey tokenId) amount)
      (balances.get owner (tokenKey tokenId))

/-- Add and persist `amount` without UInt256 wraparound. Precondition:
`canCredit balances owner tokenId amount` (the pre-write gate). -/
@[pf_inline] def credit (balances : Balances) (owner : Address)
    (tokenId amount : UInt256) : UInt64 :=
  balances.put owner (tokenKey tokenId) (balances.nextAdd owner (tokenKey tokenId) amount)

/-- Debit is valid when the id encodes and the balance covers `amount`. -/
@[pf_inline] def canDebit (balances : Balances) (owner : Address)
    (tokenId amount : UInt256) : Bool :=
  canEncode tokenId && balances.containsAtLeast owner (tokenKey tokenId) amount

/-- Subtract and persist `amount`. Precondition:
`canDebit balances owner tokenId amount` (the pre-write gate). -/
@[pf_inline] def debit (balances : Balances) (owner : Address)
    (tokenId amount : UInt256) : UInt64 :=
  balances.put owner (tokenKey tokenId) (balances.nextSub owner (tokenKey tokenId) amount)

/-- A transfer is valid when the id encodes, `to` is nonzero, the source covers the debit, and
either both handles alias (same-address move keeps the balance) or the destination addition
cannot wrap. -/
@[pf_inline] def canTransfer (balances : Balances) (source to : Address)
    (tokenId amount : UInt256) : Bool :=
  canEncode tokenId &&
    !Address.isZero to &&
    balances.containsAtLeast source (tokenKey tokenId) amount &&
    (Address.eq source to ||
      UInt256.ge (balances.nextAdd to (tokenKey tokenId) amount)
        (balances.get to (tokenKey tokenId)))

/-- Persist one checked movement. Equal source/destination is a no-op, avoiding two writes through
the same hashed key. Precondition: `canTransfer balances source to tokenId amount`. -/
@[pf_inline] def transfer (balances : Balances) (source to : Address)
    (tokenId amount : UInt256) : UInt64 :=
  if Address.eq source to then
    0
  else
    debit balances source tokenId amount ||| credit balances to tokenId amount

/-- ABI-facing insufficient-balance revert for one (owner, id) balance.
Precondition: `canEncode tokenId`. -/
@[pf_inline] def insufficient (balances : Balances) (owner : Address)
    (tokenId amount : UInt256) : UInt64 :=
  balances.revertInsufficient owner (tokenKey tokenId) amount

end Balances

namespace Operators

@[pf_inline] def isApprovedForAll (operators : Operators)
    (owner operator : Address) : Bool :=
  operators.get owner operator != 0

@[pf_inline] def setApprovalForAll (operators : Operators)
    (owner operator : Address) (approved : Bool) : UInt64 :=
  operators.put owner operator (if approved then (1 : UInt64) else 0)

end Operators

/-- True when `spender` is `source` or an approved operator of `source`. Unencodable token ids
are never authorized (pre-authorization gate, same envelope as the mutation predicates). -/
@[pf_inline] def isApprovedOrOwner (operators : Operators)
    (spender source : Address) (tokenId : UInt256) : Bool :=
  canEncode tokenId &&
    (Address.eq spender source || operators.isApprovedForAll source spender)

/-- Mint is valid when the recipient is nonzero and the credit is checked-valid (which embeds
the id-encoding gate). -/
@[pf_inline] def canMint (balances : Balances) (to : Address)
    (tokenId amount : UInt256) : Bool :=
  !Address.isZero to && balances.canCredit to tokenId amount

/-- Persist one checked credit to `to`. Precondition: `canMint balances to tokenId amount`. -/
@[pf_inline] def mint (balances : Balances) (to : Address)
    (tokenId amount : UInt256) : UInt64 :=
  balances.credit to tokenId amount

/-- Burn is valid when the id encodes and `source` covers the debit. -/
@[pf_inline] def canBurn (balances : Balances) (source : Address)
    (tokenId amount : UInt256) : Bool :=
  balances.canDebit source tokenId amount

/-- Persist one checked debit from `source`. Precondition:
`canBurn balances source tokenId amount`. -/
@[pf_inline] def burn (balances : Balances) (source : Address)
    (tokenId amount : UInt256) : UInt64 :=
  balances.debit source tokenId amount

/-- Canonical ERC-1155 events. Constructor names and field names are the ABI surface
(`TransferSingle` / `ApprovalForAll`). Indexed flags produce LOG4 (two data words) for
TransferSingle and LOG3 (bool data word) for ApprovalForAll. -/
inductive Notice where
  | TransferSingle (operator : Event.Indexed Address) («from» : Event.Indexed Address)
      (to : Event.Indexed Address) (id : UInt256) (value : UInt256)
  | ApprovalForAll (account : Event.Indexed Address) (operator : Event.Indexed Address)
      (approved : Bool)
  deriving Repr, DecidableEq, Inhabited

namespace Log

/-- LOG4 `TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value)`. -/
@[pf_inline] def transferSingle (operator source destination : Address)
    (tokenId amount : UInt256) : UInt64 :=
  Event.emit (Notice.TransferSingle (Event.indexed operator) (Event.indexed source)
    (Event.indexed destination) tokenId amount)

/-- LOG3 `ApprovalForAll(address indexed account, address indexed operator, bool approved)`. -/
@[pf_inline] def approvalForAll (account operator : Address) (approved : Bool) : UInt64 :=
  Event.emit (Notice.ApprovalForAll (Event.indexed account) (Event.indexed operator) approved)

end Log

end ProofForge.Evm.Sdk.Erc1155
