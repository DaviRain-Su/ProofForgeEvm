import ProofForge.Evm.Sdk
import ProofForge.Core.Value

/-!
Owner-minted ERC-1155 consumer with a bounded static `uri`. The SDK owns the encodable-id gate;
this contract owns the immutable minter gate, zero-address policy, and canonical ERC-1155
`TransferSingle` logs. The URI is compile-time constant (`ipfs://QmPfPack`); there is no per-id
map or template suffix. This partial profile advertises IERC165 only.
-/

namespace Examples.Evm.PackLink
open ProofForge.Evm.Sdk
open ProofForge.Core.Value

structure State where
  dummy : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_inline] def balances : Erc1155.Balances :=
  Storage.Layout.root.addressPairMap256.handle

/-- UTF-8 bytes for `ipfs://QmPfPack` padded to the metadata capacity. -/
@[pf_inline] private def uriValues : Vector UInt8 32 :=
  #v[0x69, 0x70, 0x66, 0x73, 0x3a, 0x2f, 0x2f, 0x51, 0x6d, 0x50, 0x66, 0x50, 0x61, 0x63, 0x6b, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

/-- Static metadata URI: `ipfs://QmPfPack` (15 UTF-8 bytes). -/
@[pf_inline] def baseUri : MetadataUri.Uri :=
  { length := 15, values := uriValues }

@[pf_entry]
def init (_owner : Address) : State :=
  { dummy := 0 }

@[pf_entry]
def mint (s : State) (to : Address) (tokenId : UInt256) (amount : UInt256) :
    Except Error (State × UInt64) :=
  if Address.eqImmutable Context.caller then
    if Erc1155.canMint balances to tokenId amount then
      .ok ({ dummy := Erc1155.mint balances to tokenId amount },
        Erc1155.Log.transferSingle Context.caller Address.zero to tokenId amount)
    else if Address.isZero to then
      .ok (s, Revert.zeroAddress)
    else
      .ok (s, Revert.unauthorized Context.caller)
  else
    .ok (s, Revert.unauthorized Context.caller)

/-- Bounded static `uri(uint256) → string`. Unencodable ids fail closed to empty via length
zero (`MetadataUri.canRespond1155`). -/
@[pf_entry]
def uri (_s : State) (tokenId : UInt256) : BoundedString 32 :=
  { length := if MetadataUri.canRespond1155 tokenId then 15 else 0
    values := #v[0x69, 0x70, 0x66, 0x73, 0x3a, 0x2f, 0x2f, 0x51, 0x6d, 0x50, 0x66, 0x50, 0x61, 0x63, 0x6b, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] }

@[pf_entry]
def balanceOf (_s : State) (owner : Address) (tokenId : UInt256) : UInt256 :=
  Erc1155.Balances.balanceOf balances owner tokenId

/-- Partial ERC-1155-shaped profile: IERC165 only until the full standard surface is complete. -/
@[pf_entry]
def supportsInterface (_s : State) (interfaceId : Bytes4) : Bool :=
  Erc165.supports interfaceId Erc165.erc165

end Examples.Evm.PackLink
