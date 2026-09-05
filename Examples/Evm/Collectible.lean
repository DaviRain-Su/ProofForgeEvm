import ProofForge.Evm.Sdk

/-!
Owner-minted ERC-721 consumer. The SDK owns token-id encoding, ownership/approval maps,
checked mint/transfer movement, and the receiver hook (`Erc721.checkOnReceived`). This contract
owns the immutable minter gate, zero-address policy, and canonical ERC-721 `Transfer` /
`Approval` logs (`Erc721.Log`). Operator `ApprovalForAll` is not part of this method surface.
-/

namespace Examples.Evm.Collectible
open ProofForge.Evm.Sdk
open ProofForge.Core.Value (BoundedBytes)

structure State where
  dummy : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_inline] def owners : Erc721.Owners :=
  Storage.Layout.root.addressMap256.handle

@[pf_inline] def approvals : Erc721.TokenApprovals :=
  Storage.Layout.root.addressMap256.next.addressMap256.handle

@[pf_inline] def operators : Erc721.Operators :=
  Storage.Layout.root.addressMap256.next.addressMap256.next.addressPairMap.handle

@[pf_inline] def balances : Erc721.Balances :=
  Storage.Layout.root.addressMap256.next.addressMap256.next.addressPairMap.next
    |>.addressMap.handle

@[pf_entry]
def init (_owner : Address) : State :=
  { dummy := 0 }

@[pf_entry]
def mint (s : State) (to : Address) (tokenId : UInt256) : Except Error (State × UInt64) :=
  if Address.eqImmutable Context.caller then
    if Erc721.canMint owners balances to tokenId then
      .ok ({ dummy := Erc721.mint owners balances to tokenId },
        Erc721.Log.transfer Address.zero to tokenId)
    else if Address.isZero to then
      .ok (s, Revert.zeroAddress)
    else
      .ok (s, Revert.unauthorized Context.caller)
  else
    .ok (s, Revert.unauthorized Context.caller)

@[pf_entry]
def approve (s : State) (spender : Address) (tokenId : UInt256) :
    Except Error (State × UInt64) :=
  if !Erc721.canEncode tokenId then
    .ok (s, Revert.unauthorized Context.caller)
  else if Address.eq (Erc721.Owners.ownerOf owners tokenId) Context.caller then
    .ok ({ dummy := Erc721.TokenApprovals.approve approvals tokenId spender },
      Erc721.Log.approval Context.caller spender tokenId)
  else
    .ok (s, Revert.unauthorized Context.caller)

@[pf_entry]
def transferFrom (s : State) (source to : Address) (tokenId : UInt256) :
    Except Error (State × UInt64) :=
  if !Erc721.isApprovedOrOwner owners approvals operators Context.caller tokenId then
    .ok (s, Revert.unauthorized Context.caller)
  else if Address.isZero to then
    .ok (s, Revert.zeroAddress)
  else if Erc721.canTransfer owners balances source to tokenId then
    .ok ({ dummy := Erc721.transfer owners approvals balances source to tokenId },
      Erc721.Log.transfer source to tokenId)
  else
    .ok (s, Revert.unauthorized Context.caller)

/-- Empty hook payload for the three-argument `safeTransferFrom` overload. -/
@[pf_inline]
def noData : BoundedBytes 32 :=
  { length := 0, values := Vector.replicate 32 0 }

/-- Shared body of both `safeTransferFrom` ABI overloads. -/
@[pf_inline]
def runSafeTransfer (s : State) (source to : Address) (tokenId : UInt256)
    (data : BoundedBytes 32) : Except Error (State × Bool) :=
  if !Erc721.isApprovedOrOwner owners approvals operators Context.caller tokenId then
    Effect.abort s (Revert.unauthorized Context.caller)
  else if Address.isZero to then
    Effect.abort s Revert.zeroAddress
  else if Erc721.canTransfer owners balances source to tokenId then
    .ok ({ dummy := Erc721.transfer owners approvals balances source to tokenId |||
        Erc721.Log.transfer source to tokenId },
      Effect.thenTrue (Erc721.checkOnReceived to Context.caller source tokenId data))
  else
    Effect.abort s (Revert.unauthorized Context.caller)

/-- `safeTransferFrom(address,address,uint256,bytes)`: `transferFrom` followed by OZ's receiver
check. The ledger move and the `Transfer` log land before the hook runs, so a receiver that
reads `ownerOf` inside `onERC721Received` sees itself; a recipient without code is not called;
a hook answer other than its own selector reverts the whole transaction. `data` is bounded to
32 bytes. The three-argument overload is `safeTransferFrom__id`. -/
@[pf_entry]
def safeTransferFrom (s : State) (source to : Address) (tokenId : UInt256)
    (data : BoundedBytes 32) : Except Error (State × Bool) :=
  runSafeTransfer s source to tokenId data

/-- `safeTransferFrom(address,address,uint256)`: same move with empty `data`. -/
@[pf_entry]
def safeTransferFrom__id (s : State) (source to : Address) (tokenId : UInt256) :
    Except Error (State × Bool) :=
  runSafeTransfer s source to tokenId noData

/-- Packed owner (`⟨w0,w1,w2,0⟩`). Address-typed returns from map reads still expand to four
UInt256 limbs under Extract, so consumers expose the packed word until Emit grows a 3-limb
Address path for hashed-map loads. Unencodable ids return zero (no `tokenKey` alias). -/
@[pf_entry]
def ownerOf (_s : State) (tokenId : UInt256) : UInt256 :=
  if !Erc721.canEncode tokenId then UInt256.zero
  else owners.get (Erc721.tokenKey tokenId)

/-- Packed per-token approval; same Extract limitation as `ownerOf`. -/
@[pf_entry]
def getApproved (_s : State) (tokenId : UInt256) : UInt256 :=
  if !Erc721.canEncode tokenId then UInt256.zero
  else approvals.get (Erc721.tokenKey tokenId)

@[pf_entry]
def balanceOf (_s : State) (owner : Address) : UInt256 :=
  Erc721.Balances.balanceOf256 balances owner

/-- This partial ERC-721-shaped profile implements only IERC165. It deliberately does not
advertise the IERC721 identifier until every required ERC-721 method is implemented. -/
@[pf_entry]
def supportsInterface (_s : State) (interfaceId : Bytes4) : Bool :=
  Erc165.supports interfaceId Erc165.erc165

end Examples.Evm.Collectible