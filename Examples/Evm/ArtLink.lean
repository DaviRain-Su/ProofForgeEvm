import ProofForge.Evm.Sdk
import ProofForge.Core.Value

/-!
Owner-minted ERC-721 consumer with a bounded static `tokenURI`. The SDK owns the encodable-id
and mint-state gates; this contract owns the immutable minter gate, zero-address policy, and
canonical ERC-721 `Transfer` logs. The URI is compile-time constant (`ipfs://QmPfLink`); there
is no per-token map or template suffix. This partial profile advertises IERC165 only.
-/

namespace Examples.Evm.ArtLink
open ProofForge.Evm.Sdk
open ProofForge.Core.Value

structure State where
  dummy : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_inline] def owners : Erc721.Owners :=
  Storage.Layout.root.addressMap256.handle

@[pf_inline] def balances : Erc721.Balances :=
  Storage.Layout.root.addressMap256.next.addressMap.handle

/-- UTF-8 bytes for `ipfs://QmPfLink` padded to the metadata capacity. -/
@[pf_inline] private def uriValues : Vector UInt8 32 :=
  #v[0x69, 0x70, 0x66, 0x73, 0x3a, 0x2f, 0x2f, 0x51, 0x6d, 0x50, 0x66, 0x4c, 0x69, 0x6e, 0x6b, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

/-- Static metadata URI: `ipfs://QmPfLink` (15 UTF-8 bytes). -/
@[pf_inline] def baseUri : MetadataUri.Uri :=
  { length := 15, values := uriValues }

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

/-- Bounded static `tokenURI(uint256) → string`. Unencodable ids and unminted tokens fail closed
to empty via length zero (`MetadataUri.canRespond721`). -/
@[pf_entry]
def tokenURI (_s : State) (tokenId : UInt256) : BoundedString 32 :=
  { length := if MetadataUri.canRespond721 owners tokenId then 15 else 0
    values := #v[0x69, 0x70, 0x66, 0x73, 0x3a, 0x2f, 0x2f, 0x51, 0x6d, 0x50, 0x66, 0x4c, 0x69, 0x6e, 0x6b, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] }

@[pf_entry]
def ownerOf (_s : State) (tokenId : UInt256) : UInt256 :=
  if !Erc721.canEncode tokenId then UInt256.zero
  else owners.get (Erc721.tokenKey tokenId)

@[pf_entry]
def balanceOf (_s : State) (owner : Address) : UInt256 :=
  Erc721.Balances.balanceOf256 balances owner

/-- Partial ERC-721-shaped profile: IERC165 only until the full standard surface is complete. -/
@[pf_entry]
def supportsInterface (_s : State) (interfaceId : Bytes4) : Bool :=
  Erc165.supports interfaceId Erc165.erc165

end Examples.Evm.ArtLink
