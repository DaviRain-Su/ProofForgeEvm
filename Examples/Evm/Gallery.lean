import ProofForge.Evm.Sdk
import ProofForge.Evm.Sdk.StorageEnumerableSet

/-!
Owner-minted ERC-721 consumer with a capacity-4 IERC721Enumerable profile. Token ids are the
UInt64 `Erc721.Enum` bound. The SDK owns ownership/balance movement, the global live-prefix
arithmetic (`StorageEnumerableSet`), and the owner-list packing (`Enum.indexKey`). This
contract owns the `Vector` writes, the owner-list pair-map puts, the immutable minter gate, and
canonical `Transfer` logs. Approval, operators, and receiver hooks are out of this method
surface. The profile advertises IERC165 only.
-/

namespace Examples.Evm.Gallery
open ProofForge.Evm.Sdk

structure State where
  tokens : Vector UInt64 4
  count : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | malformed
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_inline] def owners : Erc721.Owners :=
  Storage.Layout.root.addressMap256.handle

@[pf_inline] def approvals : Erc721.TokenApprovals :=
  Storage.Layout.root.addressMap256.next.addressMap256.handle

@[pf_inline] def balances : Erc721.Balances :=
  Storage.Layout.root.addressMap256.next.addressMap256.next.addressMap.handle

@[pf_inline] def allIndex : Storage.U64Map :=
  Storage.Layout.root.addressMap256.next.addressMap256.next.addressMap.next.u64Map.handle

@[pf_inline] def ownedAt : Storage.AddressPairMap :=
  Storage.Layout.root.addressMap256.next.addressMap256.next.addressMap.next.u64Map.next
    |>.addressPairMap.handle

@[pf_inline] def ownedIndex : Storage.AddressMap :=
  Storage.Layout.root.addressMap256.next.addressMap256.next.addressMap.next.u64Map.next
    |>.addressPairMap.next.addressMap.handle

structure Handles where
  set : StorageEnumerableSet.Descriptor 4

@[pf_inline] def declared : Storage.Static.Allocated Handles :=
  let set := StorageEnumerableSet.declare Storage.Static.Layout.root "tokens" "count"
    allIndex 4
  { handle := { set := set.handle }, next := set.next }

@[pf_inline] def layout : Storage.Static.Layout := declared.next

/-- Append `id` at the owner's current live count. Call before `Erc721.mint` / `transfer`
so the map read still sees the pre-movement balance. -/
@[pf_inline] def appendOwned (to : Address) (id : UInt64) : UInt64 :=
  let destLive := balances.get to
  ownedAt.put to (Erc721.Enum.indexKey destLive) id |||
    ownedIndex.put (Erc721.Enum.idAddr id) (destLive + 1)

/-- Swap-remove `tokenId` from `source`'s owner list. Call before `Erc721.transfer` / `burn`. -/
@[pf_inline] def removeOwned (source : Address) (id : UInt64) : UInt64 :=
  let pos := ownedIndex.get (Erc721.Enum.idAddr id)
  let live := balances.get source
  if StorageEnumerableSet.movesLast pos live then
    let lastTok := ownedAt.get source (Erc721.Enum.indexKey (live - 1))
    ownedAt.put source (Erc721.Enum.indexKey (pos - 1)) lastTok |||
      ownedIndex.put (Erc721.Enum.idAddr lastTok) pos |||
      ownedIndex.put (Erc721.Enum.idAddr id) 0
  else
    ownedIndex.put (Erc721.Enum.idAddr id) 0

@[pf_entry]
def init (_owner : Address) : State :=
  { tokens := #v[0, 0, 0, 0], count := 0 }

@[pf_entry]
def totalSupply (s : State) : UInt256 :=
  if StorageEnumerableSet.wellFormed Erc721.Enum.capU64 s.count then
    Erc721.Enum.wideId s.count
  else
    UInt256.zero

@[pf_entry]
def tokenByIndex (s : State) (index : UInt256) : UInt256 :=
  if !Erc721.Enum.canEnumerate index then
    UInt256.zero
  else if StorageEnumerableSet.canValueAt Erc721.Enum.capU64 s.count index.w0 then
    Erc721.Enum.wideId s.tokens[index.w0.toNat]!
  else
    UInt256.zero

@[pf_entry]
def tokenOfOwnerByIndex (_s : State) (owner : Address) (index : UInt256) : UInt256 :=
  if !Erc721.Enum.canEnumerate index then
    UInt256.zero
  else if StorageEnumerableSet.canValueAt Erc721.Enum.capU64 (balances.get owner) index.w0 then
    Erc721.Enum.wideId (ownedAt.get owner (Erc721.Enum.indexKey index.w0))
  else
    UInt256.zero

@[pf_entry]
def ownerOf (_s : State) (tokenId : UInt256) : UInt256 :=
  if !Erc721.canEncode tokenId then UInt256.zero
  else owners.get (Erc721.tokenKey tokenId)

@[pf_entry]
def balanceOf (_s : State) (owner : Address) : UInt256 :=
  Erc721.Balances.balanceOf256 balances owner

@[pf_entry]
def mint (s : State) (to : Address) (tokenId : UInt256) : Except Error (State × UInt64) :=
  if Address.eqImmutable Context.caller then
    if !Erc721.Enum.canEnumerate tokenId then
      .ok (s, Revert.unauthorized Context.caller)
    else if Address.isZero to then
      .ok (s, Revert.zeroAddress)
    else if !StorageEnumerableSet.wellFormed Erc721.Enum.capU64 s.count then
      .error .malformed
    else if !Erc721.canMint owners balances to tokenId then
      .ok (s, Revert.unauthorized Context.caller)
    else if !StorageEnumerableSet.absent (allIndex.get tokenId.w0) then
      .error .malformed
    else if StorageEnumerableSet.isFull Erc721.Enum.capU64 s.count then
      .ok (s, Revert.capExceeded)
    else if h : s.count.toNat < 4 then
      .ok ({ s with
          tokens := s.tokens.set s.count.toNat tokenId.w0 h,
          count := s.count + 1 },
        appendOwned to tokenId.w0 |||
          Erc721.mint owners balances to tokenId |||
          allIndex.put tokenId.w0 (StorageEnumerableSet.insertPosition s.count) |||
          Erc721.Log.transfer Address.zero to tokenId)
    else
      .error .malformed
  else
    .ok (s, Revert.unauthorized Context.caller)

@[pf_entry]
def transferFrom (s : State) (source to : Address) (tokenId : UInt256) :
    Except Error (State × UInt64) :=
  if !Address.eq Context.caller source then
    .ok (s, Revert.unauthorized Context.caller)
  else if !Erc721.Enum.canEnumerate tokenId then
    .ok (s, Revert.unauthorized Context.caller)
  else if Address.isZero to then
    .ok (s, Revert.zeroAddress)
  else if !Erc721.canTransfer owners balances source to tokenId then
    .ok (s, Revert.unauthorized Context.caller)
  else if !StorageEnumerableSet.wellFormed Erc721.Enum.capU64 s.count then
    .error .malformed
  else if StorageEnumerableSet.absent (ownedIndex.get (Erc721.Enum.idAddr tokenId.w0)) then
    .error .malformed
  else if StorageEnumerableSet.forged
      (ownedIndex.get (Erc721.Enum.idAddr tokenId.w0)) (balances.get source) then
    .error .malformed
  else if StorageEnumerableSet.isPresent
      (ownedIndex.get (Erc721.Enum.idAddr tokenId.w0)) (balances.get source)
      (ownedAt.get source (Erc721.Enum.indexKey
        (ownedIndex.get (Erc721.Enum.idAddr tokenId.w0) - 1))) tokenId.w0 then
    if Address.eq source to then
      .ok (s,
        Erc721.transfer owners approvals balances source to tokenId |||
          Erc721.Log.transfer source to tokenId)
    else
      .ok (s,
        removeOwned source tokenId.w0 |||
          appendOwned to tokenId.w0 |||
          Erc721.transfer owners approvals balances source to tokenId |||
          Erc721.Log.transfer source to tokenId)
  else
    .error .malformed

@[pf_entry]
def burn (s : State) (tokenId : UInt256) : Except Error (State × UInt64) :=
  let owner := Erc721.Owners.ownerOf owners tokenId
  if !Address.eq Context.caller owner then
    .ok (s, Revert.unauthorized Context.caller)
  else if !Erc721.Enum.canEnumerate tokenId then
    .ok (s, Revert.unauthorized Context.caller)
  else if !Erc721.canBurn owners balances owner tokenId then
    .ok (s, Revert.unauthorized Context.caller)
  else if !StorageEnumerableSet.wellFormed Erc721.Enum.capU64 s.count then
    .error .malformed
  else if StorageEnumerableSet.absent (allIndex.get tokenId.w0) then
    .error .malformed
  else if StorageEnumerableSet.forged (allIndex.get tokenId.w0) s.count then
    .error .malformed
  else if StorageEnumerableSet.isPresent (allIndex.get tokenId.w0) s.count
      s.tokens[(allIndex.get tokenId.w0 - 1).toNat]! tokenId.w0 then
    if StorageEnumerableSet.absent (ownedIndex.get (Erc721.Enum.idAddr tokenId.w0)) then
      .error .malformed
    else if StorageEnumerableSet.forged
        (ownedIndex.get (Erc721.Enum.idAddr tokenId.w0)) (balances.get owner) then
      .error .malformed
    else if StorageEnumerableSet.isPresent
        (ownedIndex.get (Erc721.Enum.idAddr tokenId.w0)) (balances.get owner)
        (ownedAt.get owner (Erc721.Enum.indexKey
          (ownedIndex.get (Erc721.Enum.idAddr tokenId.w0) - 1))) tokenId.w0 then
      if h : (allIndex.get tokenId.w0 - 1).toNat < 4 then
        if StorageEnumerableSet.movesLast (allIndex.get tokenId.w0) s.count then
          if h2 : (s.count - 1).toNat < 4 then
            .ok ({ s with
                tokens := s.tokens.set ((allIndex.get tokenId.w0 - 1).toNat)
                  (s.tokens[(s.count - 1).toNat]) h,
                count := StorageEnumerableSet.removedCount s.count },
              removeOwned owner tokenId.w0 |||
                allIndex.put (s.tokens[(s.count - 1).toNat]) (allIndex.get tokenId.w0) |||
                allIndex.put tokenId.w0 0 |||
                Erc721.burn owners approvals balances owner tokenId |||
                Erc721.Log.transfer owner Address.zero tokenId)
          else
            .error .malformed
        else
          .ok ({ s with count := StorageEnumerableSet.removedCount s.count },
            removeOwned owner tokenId.w0 |||
              allIndex.put tokenId.w0 0 |||
              Erc721.burn owners approvals balances owner tokenId |||
              Erc721.Log.transfer owner Address.zero tokenId)
      else
        .error .malformed
    else
      .error .malformed
  else
    .error .malformed

/-- This partial ERC-721-shaped profile implements only IERC165. It does not advertise
IERC721 or IERC721Enumerable: owner-only transfer and the UInt64 id bound are not the
complete interfaces. -/
@[pf_entry]
def supportsInterface (_s : State) (interfaceId : Bytes4) : Bool :=
  Erc165.supports interfaceId Erc165.erc165

end Examples.Evm.Gallery
