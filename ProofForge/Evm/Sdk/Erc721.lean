import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.Erc721

/-!
# EVM SDK ERC-721 core (EVM-SDK-7a)

Reusable O(1) ownership, per-token approval, operator approval, and balance movement over the
existing hashed-map namespaces. Token ids are `UInt256` values whose top limb is zero so the id
fits an `Address` map key (`tokenKey`). Owner and approved addresses are packed into `UInt256`
values with a zero top limb. Per-owner balances use a UInt64 address map (NFT counts stay far
below 2^64). Authorization against `Context.caller`, pause/zero-address policy, mint caps,
receiver hooks, and events remain application-owned.

Static ERC-165 declarations are supplied separately by `Sdk.Erc165`; this ledger never infers
interface support from its methods.

There is no new Runtime leaf, hashed-map kind, or Op/IR/Emit recipe. Canonical ERC-721 logs are
reusable `Event.emit` wrappers (`Log.transfer` / `Log.approval` / `Log.approvalForAll`): LOG4
`Transfer`/`Approval` with empty data, and LOG3 `ApprovalForAll` with a bool data word. Pause,
zero-address policy, mint caps, ERC-165, and metadata remain application-owned.

## Receiver hook

`checkOnReceived` is OZ's `ERC721Utils.checkOnERC721Received` over `OpenCall.callMagic`: a
recipient with code must answer `onERC721Received(address,address,uint256,bytes)` with exactly
one word equal to that selector, left-aligned, or the transaction reverts (`revert(0, 0)`, so no
partial state remains and the callee's reason is not bubbled); a recipient without code is not
called. The result is a CALL carrier, so it stands only as the entry's result word under
`Effect.thenTrue`, with the ledger movement and `Log.transfer` in the state word. The extractor
orders the hashed-map stores, then the log, then the hook, so a receiver that reads `ownerOf`
inside the hook sees itself as the owner, as under OZ `_safeTransfer`. `data` carries at most 32
bytes (`Hook` spells the literal because the open-call decoder wants one). The three-argument
`safeTransferFrom(address,address,uint256)` overload is the same move with empty `data`; Lean
names it `safeTransferFrom__id` so the ABI name stays `safeTransferFrom`. A `pf` contract
answers the hook by returning `onReceivedSelector` as `Bytes4`; `Examples.Evm.ReceiverLink` is
that shape. Bounded IERC721Enumerable (`totalSupply` / `tokenByIndex` /
`tokenOfOwnerByIndex`, UInt64 ids, compile-time capacity 4) lives in `Enum` and
`Examples.Evm.Gallery`. Unbounded enumeration and the rest of IERC721 stay out.
-/

/-- UInt256 unit used only for application event amount limbs. -/
@[pf_inline] def one : UInt256 := ⟨1, 0, 0, 0⟩

/-- True when `tokenId` fits the three-limb `Address` map key (top UInt256 limb is zero). -/
@[pf_inline] def canEncode (tokenId : UInt256) : Bool :=
  tokenId.w3 == 0

/-- Map key for one token id. Precondition: `canEncode tokenId`. -/
@[pf_inline] def tokenKey (tokenId : UInt256) : Address :=
  ⟨tokenId.w0, tokenId.w1, tokenId.w2⟩

@[pf_inline] def packAddress (address : Address) : UInt256 :=
  ⟨address.w0, address.w1, address.w2, 0⟩

@[pf_inline] def unpackAddress (value : UInt256) : Address :=
  ⟨value.w0, value.w1, value.w2⟩

/-- Compile-time handle to tokenId → owner storage. -/
abbrev Owners := Storage.AddressMap256

/-- Compile-time handle to tokenId → approved spender storage. -/
abbrev TokenApprovals := Storage.AddressMap256

/-- Compile-time handle to (owner, operator) → UInt64 approval flag storage. -/
abbrev Operators := Storage.AddressPairMap

/-- Per-owner token counts as UInt64 (hashed address map). -/
abbrev Balances := Storage.AddressMap

namespace Owners

/-- Owner of `tokenId`. Precondition for a meaningful result: `canEncode tokenId`
(otherwise `tokenKey` truncates and may alias another id). -/
@[pf_inline] def ownerOf (owners : Owners) (tokenId : UInt256) : Address :=
  unpackAddress (owners.get (tokenKey tokenId))

@[pf_inline] def isMinted (owners : Owners) (tokenId : UInt256) : Bool :=
  !Address.isZero (owners.ownerOf tokenId)

@[pf_inline] def putOwner (owners : Owners) (tokenId : UInt256) (owner : Address) : UInt64 :=
  owners.put (tokenKey tokenId) (packAddress owner)

@[pf_inline] def clear (owners : Owners) (tokenId : UInt256) : UInt64 :=
  owners.put (tokenKey tokenId) UInt256.zero

end Owners

namespace TokenApprovals

/-- Approved spender for `tokenId`. Precondition for a meaningful result: `canEncode tokenId`. -/
@[pf_inline] def getApproved (approvals : TokenApprovals) (tokenId : UInt256) : Address :=
  unpackAddress (approvals.get (tokenKey tokenId))

@[pf_inline] def approve (approvals : TokenApprovals) (tokenId : UInt256)
    (spender : Address) : UInt64 :=
  approvals.put (tokenKey tokenId) (packAddress spender)

@[pf_inline] def clear (approvals : TokenApprovals) (tokenId : UInt256) : UInt64 :=
  approvals.put (tokenKey tokenId) UInt256.zero

end TokenApprovals

namespace Operators

@[pf_inline] def isApprovedForAll (operators : Operators)
    (owner operator : Address) : Bool :=
  operators.get owner operator != 0

@[pf_inline] def setApprovalForAll (operators : Operators)
    (owner operator : Address) (approved : Bool) : UInt64 :=
  operators.put owner operator (if approved then (1 : UInt64) else 0)

end Operators

namespace Balances

@[pf_inline] def balanceOf (balances : Balances) (owner : Address) : UInt64 :=
  balances.get owner

/-- ABI-facing UInt256 view of the UInt64 count. -/
@[pf_inline] def balanceOf256 (balances : Balances) (owner : Address) : UInt256 :=
  ⟨balances.get owner, 0, 0, 0⟩

@[pf_inline] def canCredit (balances : Balances) (owner : Address) : Bool :=
  balances.get owner != ~~~(0 : UInt64)

@[pf_inline] def credit (balances : Balances) (owner : Address) : UInt64 :=
  balances.put owner (balances.get owner + 1)

@[pf_inline] def canDebit (balances : Balances) (owner : Address) : Bool :=
  balances.get owner != 0

@[pf_inline] def debit (balances : Balances) (owner : Address) : UInt64 :=
  balances.put owner (balances.get owner - 1)

end Balances

/-- True when `spender` is the owner, the per-token approved address, or an approved operator.
Unencodable token ids are never authorized (same gate as mutation predicates). -/
@[pf_inline] def isApprovedOrOwner (owners : Owners) (approvals : TokenApprovals)
    (operators : Operators) (spender : Address) (tokenId : UInt256) : Bool :=
  canEncode tokenId &&
    (let owner := owners.ownerOf tokenId
     Address.eq spender owner ||
       Address.eq spender (approvals.getApproved tokenId) ||
       operators.isApprovedForAll owner spender)

/-- Mint is valid when the id encodes, the token is absent, the recipient is nonzero, and the
recipient balance can accept one more token. -/
@[pf_inline] def canMint (owners : Owners) (balances : Balances)
    (to : Address) (tokenId : UInt256) : Bool :=
  canEncode tokenId &&
    !owners.isMinted tokenId &&
    !Address.isZero to &&
    balances.canCredit to

/-- Persist ownership and credit the recipient balance by one. Precondition:
`canMint owners balances to tokenId`. -/
@[pf_inline] def mint (owners : Owners) (balances : Balances)
    (to : Address) (tokenId : UInt256) : UInt64 :=
  owners.putOwner tokenId to ||| balances.credit to

/-- Burn is valid when the id encodes and is owned by `source`. -/
@[pf_inline] def canBurn (owners : Owners) (balances : Balances)
    (source : Address) (tokenId : UInt256) : Bool :=
  canEncode tokenId &&
    Address.eq (owners.ownerOf tokenId) source &&
    balances.canDebit source

/-- Clear approval and ownership after debiting the owner balance. Precondition:
`canBurn owners balances source tokenId`. Debit runs first so the owner address is still
readable if Extract re-inlines `owners.ownerOf` into the balance key. -/
@[pf_inline] def burn (owners : Owners) (approvals : TokenApprovals) (balances : Balances)
    (source : Address) (tokenId : UInt256) : UInt64 :=
  balances.debit source |||
    approvals.clear tokenId |||
    owners.clear tokenId

/-- Transfer is valid when the id encodes, `source` owns it, `to` is nonzero, and balances cover a
one-token move (same-address transfers only need the ownership gate). -/
@[pf_inline] def canTransfer (owners : Owners) (balances : Balances)
    (source to : Address) (tokenId : UInt256) : Bool :=
  canEncode tokenId &&
    Address.eq (owners.ownerOf tokenId) source &&
    !Address.isZero to &&
    (Address.eq source to ||
      (balances.canDebit source && balances.canCredit to))

/-- Move ownership, clear the per-token approval, and adjust balances. Equal `source`/`to` only
clears approval. Precondition: `canTransfer owners balances source to tokenId`. -/
@[pf_inline] def transfer (owners : Owners) (approvals : TokenApprovals) (balances : Balances)
    (source to : Address) (tokenId : UInt256) : UInt64 :=
  if Address.eq source to then
    approvals.clear tokenId
  else
    approvals.clear tokenId |||
      owners.putOwner tokenId to |||
      balances.debit source |||
      balances.credit to

/-- `onERC721Received` selector `0x150b7a02`, packed in the source fixed-bytes limb order.
A receiving entry returns this as `Bytes4`. Same packing as `Erc165.erc721Receiver`. -/
@[pf_inline] def onReceivedSelector : Bytes4 :=
  ⟨0x027a0b15, 0, 0, 0⟩

/-- The receiver hook a contract recipient must answer. Constructor and field names are the ABI
surface: `onERC721Received(address operator, address from, uint256 tokenId, bytes data)`, magic
`0x150b7a02`. `data` is bounded to 32 bytes. -/
inductive Hook where
  | onERC721Received (operator «from» : Address) (tokenId : UInt256)
      (data : ProofForge.Core.Value.BoundedBytes 32)

/-- OZ `checkOnERC721Received`: call the hook on a recipient with code and require its own
selector back; skip a recipient without code. A CALL carrier for the entry's result word under
`Effect.thenTrue`; see the module doc. -/
@[pf_inline] def checkOnReceived (to operator source : Address) (tokenId : UInt256)
    (data : ProofForge.Core.Value.BoundedBytes 32) : UInt64 :=
  if Address.hasCode to then
    OpenCall.callMagic to (Hook.onERC721Received operator source tokenId data)
  else 0

/-- Canonical ERC-721 events. Constructor names and field names are the ABI surface
(`Transfer` / `Approval` / `ApprovalForAll`). Indexed flags produce LOG4 (empty data) for
Transfer/Approval and LOG3 (bool data word) for ApprovalForAll. -/
inductive Notice where
  | Transfer («from» : Event.Indexed Address) (to : Event.Indexed Address)
      (tokenId : Event.Indexed UInt256)
  | Approval (owner : Event.Indexed Address) (approved : Event.Indexed Address)
      (tokenId : Event.Indexed UInt256)
  | ApprovalForAll (owner : Event.Indexed Address) (operator : Event.Indexed Address)
      (approved : Bool)
  deriving Repr, DecidableEq, Inhabited

namespace Log

/-- LOG4 `Transfer(address indexed from, address indexed to, uint256 indexed tokenId)`. -/
@[pf_inline] def transfer (source destination : Address) (tokenId : UInt256) : UInt64 :=
  Event.emit (Notice.Transfer (Event.indexed source) (Event.indexed destination)
    (Event.indexed tokenId))

/-- LOG4 `Approval(address indexed owner, address indexed approved, uint256 indexed tokenId)`. -/
@[pf_inline] def approval (owner approved : Address) (tokenId : UInt256) : UInt64 :=
  Event.emit (Notice.Approval (Event.indexed owner) (Event.indexed approved)
    (Event.indexed tokenId))

/-- LOG3 `ApprovalForAll(address indexed owner, address indexed operator, bool approved)`. -/
@[pf_inline] def approvalForAll (owner operator : Address) (approved : Bool) : UInt64 :=
  Event.emit (Notice.ApprovalForAll (Event.indexed owner) (Event.indexed operator) approved)

end Log

/-!
Bounded IERC721Enumerable packing. Token ids that use more than the low UInt64 limb cannot
enter the global `U64Map` index, so `canEnumerate` is the consumer gate. `indexKey` packs a
0-based owner-list slot into the pair-map's second address; slot 0 is the zero address as a
key, not as an account. `StorageEnumerableSet` owns the live-prefix arithmetic. Applications
own the `Vector` writes and the owner-list pair-map puts, the same split as `EvmAllowlist`.
-/
namespace Enum

/-- Compile-time live-token ceiling shared with `Examples.Evm.Gallery`. -/
@[pf_inline] def capU64 : UInt64 := 4

/-- True when `tokenId` fits the global `U64Map` key (limbs `w1..w3` are zero). -/
@[pf_inline] def canEnumerate (tokenId : UInt256) : Bool :=
  tokenId.w1 == 0 && tokenId.w2 == 0 && tokenId.w3 == 0

/-- ABI `uint256` view of a stored UInt64 id. -/
@[pf_inline] def wideId (id : UInt64) : UInt256 :=
  ⟨id, 0, 0, 0⟩

/-- Low limb of an enumerable id. Precondition: `canEnumerate tokenId`. -/
@[pf_inline] def narrowId (tokenId : UInt256) : UInt64 :=
  tokenId.w0

/-- Address key for a UInt64 token id. Same packing as `tokenKey (wideId id)`. -/
@[pf_inline] def idAddr (id : UInt64) : Address :=
  ⟨id, 0, 0⟩

/-- Pair-map slot key for a 0-based owner-list index. Index 0 packs to the zero address. -/
@[pf_inline] def indexKey (index : UInt64) : Address :=
  ⟨index, 0, 0⟩

end Enum

end ProofForge.Evm.Sdk.Erc721
