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
(`Log.transferSingle` / `Log.transferBatch` / `Log.approvalForAll`): LOG4 `TransferSingle` with
two data words (`id`, `value`), LOG4 `TransferBatch` with two bounded `uint256[]` tails, and LOG3
`ApprovalForAll` with a bool data word.

## Bounded batch transfer

A batch is two `Batch UInt256` arguments (`ids`, `amounts`) paired by position over one
`(source, to)`; slot `i` is active when `i < length` and inactive slots hold the decoder's zero
id and zero amount. The batch rules are pure predicates the consumer orders as it likes:
`isApprovedOrOwnerBatch` (operator check plus the key envelope over every id), equal lengths
(`lengthWord` spells a length as the `uint256` an OZ `ERC1155InvalidArrayLength` carries),
`distinctIds`, and `Balances.canTransferSlot` per slot. `distinctIds` is the honest bound that
makes per-slot pre-write checks exact: with pairwise distinct ids no two slots read or write the
same `(owner, id)` key, so checking every slot before the first write equals OZ's sequential
checks. OZ accepts duplicate ids by applying slots in order; here a duplicate fails closed and the
caller splits the batch. `Balances.batchTransfer` persists the active slots in array order and
`Log.transferBatch` emits the one `TransferBatch` EIP-1155 asks for, whose `ids` and `values`
arrays carry exactly the active slots in the same order. The event is a typed frame with two
bounded dynamic-array tails; the EVM emitter writes the ABI head (one offset word per array),
then each array's length and its first `length` slots.

## Explicitly unsupported

`safeBatchTransferFrom` with its `bytes data` and `onERC1155BatchReceived` callback (the bounded
`batchTransferFrom` consumers ship instead has no receiver hook), mint/burn batches,
ERC1155Receiver callbacks (`onERC1155Received`), metadata URI, duplicate ids inside one batch,
and unbounded inputs.
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

/-- Slot `i` carries a submitted element when `i < length`. Inactive slots hold the decoder's
zero id and zero amount. -/
@[pf_inline] def slotActive {α : Type} (batch : Batch α) (i : UInt64) : Bool :=
  i < batch.length.toUInt64

/-- A batch length as the `uint256` word an OZ `ERC1155InvalidArrayLength` revert carries. -/
@[pf_inline] def lengthWord {α : Type} (batch : Batch α) : UInt256 :=
  ⟨batch.length.toUInt64, 0, 0, 0⟩

/-- Limb-wise id equality. Kernel-checkable on the host, unlike `UInt256.eq`, whose Runtime leaf
is an extraction contract, so the spec pins `distinctIds` with real ids. -/
@[pf_inline] def idEq (left right : UInt256) : Bool :=
  left.w0 == right.w0 && left.w1 == right.w1 && left.w2 == right.w2 && left.w3 == right.w3

/-- No two active slots name the same id. An active slot `j` implies every earlier slot is
active, so each pair is gated by its later slot. See the module doc for why this bound keeps
`Balances.canTransferSlot` exact. -/
@[pf_inline] def distinctIds (ids : Batch UInt256) : Bool :=
  (!slotActive ids 1 || !idEq ids.values[0] ids.values[1]) &&
    (!slotActive ids 2 ||
      (!idEq ids.values[0] ids.values[2] && !idEq ids.values[1] ids.values[2])) &&
    (!slotActive ids 3 ||
      (!idEq ids.values[0] ids.values[3] && !idEq ids.values[1] ids.values[3] &&
        !idEq ids.values[2] ids.values[3]))

/-- Every id of the batch fits the key envelope. Inactive zero slots encode trivially. -/
@[pf_inline] def allEncodable (ids : Batch UInt256) : Bool :=
  canEncode ids.values[0] && canEncode ids.values[1] && canEncode ids.values[2] &&
    canEncode ids.values[3]

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

/-- One batch slot is movable when it is inactive or a checked single transfer. The `active`
gate skips the map reads of inactive slots. Exact only under `distinctIds`. -/
@[pf_inline] def canTransferSlot (balances : Balances) (source to : Address) (active : Bool)
    (tokenId amount : UInt256) : Bool :=
  !active || canTransfer balances source to tokenId amount

/-- Every slot of the batch is movable. Precondition for exactness: `distinctIds ids`. -/
@[pf_inline] def canBatchTransfer (balances : Balances) (source to : Address)
    (ids amounts : Batch UInt256) : Bool :=
  canTransferSlot balances source to (slotActive ids 0) ids.values[0] amounts.values[0] &&
    canTransferSlot balances source to (slotActive ids 1) ids.values[1] amounts.values[1] &&
    canTransferSlot balances source to (slotActive ids 2) ids.values[2] amounts.values[2] &&
    canTransferSlot balances source to (slotActive ids 3) ids.values[3] amounts.values[3]

/-- Persist one slot: inactive slots write nothing. Precondition: `canTransferSlot`. -/
@[pf_inline] def transferSlot (balances : Balances) (source to : Address) (active : Bool)
    (tokenId amount : UInt256) : UInt64 :=
  if active then transfer balances source to tokenId amount else 0

/-- Persist every active slot in array order (EIP-1155 orders balance changes by the arrays).
Precondition: `canBatchTransfer balances source to ids amounts` and `distinctIds ids`. -/
@[pf_inline] def batchTransfer (balances : Balances) (source to : Address)
    (ids amounts : Batch UInt256) : UInt64 :=
  transferSlot balances source to (slotActive ids 0) ids.values[0] amounts.values[0] |||
    transferSlot balances source to (slotActive ids 1) ids.values[1] amounts.values[1] |||
    transferSlot balances source to (slotActive ids 2) ids.values[2] amounts.values[2] |||
    transferSlot balances source to (slotActive ids 3) ids.values[3] amounts.values[3]

end Balances

namespace Operators

@[pf_inline] def isApprovedForAll (operators : Operators)
    (owner operator : Address) : Bool :=
  operators.get owner operator != 0

@[pf_inline] def setApprovalForAll (operators : Operators)
    (owner operator : Address) (approved : Bool) : UInt64 :=
  operators.put owner operator (if approved then (1 : UInt64) else 0)

end Operators

/-- True when `spender` is `source` or an approved operator of `source`. -/
@[pf_inline] def isOwnerOrOperator (operators : Operators) (spender source : Address) : Bool :=
  Address.eq spender source || operators.isApprovedForAll source spender

/-- True when `spender` is `source` or an approved operator of `source`. Unencodable token ids
are never authorized (pre-authorization gate, same envelope as the mutation predicates). -/
@[pf_inline] def isApprovedOrOwner (operators : Operators)
    (spender source : Address) (tokenId : UInt256) : Bool :=
  canEncode tokenId && isOwnerOrOperator operators spender source

/-- `isApprovedOrOwner` over every id of a batch: the key envelope covers all four slots, then
the same operator check. -/
@[pf_inline] def isApprovedOrOwnerBatch (operators : Operators)
    (spender source : Address) (ids : Batch UInt256) : Bool :=
  allEncodable ids && isOwnerOrOperator operators spender source

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

-- `Notice` derives `Repr`/`DecidableEq` like every SDK event, and Common's `BoundedVec` ships
-- neither; these stay here until ProofForgeCommon derives them at the type.
deriving instance Repr, DecidableEq for ProofForge.Core.Value.BoundedVec

/-- Canonical ERC-1155 events. Constructor names and field names are the ABI surface
(`TransferSingle` / `TransferBatch` / `ApprovalForAll`). Indexed flags produce LOG4 (two data
words) for TransferSingle, LOG4 (two `uint256[]` tails, no static word) for TransferBatch, and
LOG3 (bool data word) for ApprovalForAll. The batch fields spell `BoundedVec UInt256 4` rather
than `Batch UInt256` because the event decoder, like the entry-type profile, accepts only a
literal capacity; `Log.transferBatch` takes `Batch` and the two are the same type. -/
inductive Notice where
  | TransferSingle (operator : Event.Indexed Address) («from» : Event.Indexed Address)
      (to : Event.Indexed Address) (id : UInt256) (value : UInt256)
  | TransferBatch (operator : Event.Indexed Address) («from» : Event.Indexed Address)
      (to : Event.Indexed Address) (ids : ProofForge.Core.Value.BoundedVec UInt256 4)
      (values : ProofForge.Core.Value.BoundedVec UInt256 4)
  | ApprovalForAll (account : Event.Indexed Address) (operator : Event.Indexed Address)
      (approved : Bool)
  deriving Repr, DecidableEq, Inhabited

namespace Log

/-- LOG4 `TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value)`. -/
@[pf_inline] def transferSingle (operator source destination : Address)
    (tokenId amount : UInt256) : UInt64 :=
  Event.emit (Notice.TransferSingle (Event.indexed operator) (Event.indexed source)
    (Event.indexed destination) tokenId amount)

/-- LOG4 `TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values)`.
Both arrays publish exactly `ids.length` / `amounts.length` elements; the emitter reverts if a
length ever exceeds the capacity, which the ABI decoder already rules out for entry arguments. -/
@[pf_inline] def transferBatch (operator source destination : Address)
    (ids amounts : Batch UInt256) : UInt64 :=
  Event.emit (Notice.TransferBatch (Event.indexed operator) (Event.indexed source)
    (Event.indexed destination) ids amounts)

/-- OZ's `_update` log rule: a one-element batch logs `TransferSingle` for its only slot, any
other length logs `TransferBatch`. Indexers built against OZ ledgers see the same receipts. -/
@[pf_inline] def transferBatchOrSingle (operator source destination : Address)
    (ids amounts : Batch UInt256) : UInt64 :=
  if ids.length == 1 then
    transferSingle operator source destination ids.values[0] amounts.values[0]
  else transferBatch operator source destination ids amounts

/-- LOG3 `ApprovalForAll(address indexed account, address indexed operator, bool approved)`. -/
@[pf_inline] def approvalForAll (account operator : Address) (approved : Bool) : UInt64 :=
  Event.emit (Notice.ApprovalForAll (Event.indexed account) (Event.indexed operator) approved)

end Log

end ProofForge.Evm.Sdk.Erc1155
