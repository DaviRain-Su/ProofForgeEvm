import ProofForge.Core.Value
import ProofForge.Core.Collections
import ProofForge.Evm.Sdk.Erc721
import ProofForge.Evm.Sdk.Erc1155

namespace ProofForge.Evm.Sdk.MetadataUri

/-!
# EVM SDK bounded static metadata URI

Compile-time `BoundedString` responses for ERC-721 `tokenURI` and ERC-1155 `uri`. There is no
per-token URI map, template interpolation, or dynamic allocation. Consumers must validate
`wellFormed` on configured URIs before advertising metadata methods.

Fail-closed gates:
- ERC-721: unencodable ids and unminted tokens should return `empty`.
- ERC-1155: unencodable ids should return `empty`; mint state is not required.

Extract note: `pf_entry` views must return explicit bounded-string constructors (`if gate then uri
else empty`). Do not route returns through parameterized SDK helpers; use the predicates here
and assemble the bounded frame at the consumer boundary.
-/

open ProofForge.Core.Value

/-- Default compile-time capacity for static metadata URIs in this profile. -/
def defaultCapacity : Nat := 32

abbrev Uri := BoundedString 32

/-- Empty bounded UTF-8 string (fail-closed response). -/
@[pf_inline] def empty : Uri :=
  { length := 0
    values := #v[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0] }

/-- True when the configured URI is valid UTF-8 within capacity. -/
@[pf_inline] def wellFormed (uri : Uri) : Bool :=
  BoundedString.wellFormed uri

/-- ERC-721 metadata is exposed only for encodable, minted token ids. -/
@[pf_inline] def canRespond721 (owners : Erc721.Owners) (tokenId : UInt256) : Bool :=
  Erc721.canEncode tokenId && Erc721.Owners.isMinted owners tokenId

/-- ERC-1155 metadata is exposed only for encodable token ids. -/
@[pf_inline] def canRespond1155 (tokenId : UInt256) : Bool :=
  Erc1155.canEncode tokenId

/-- Publish `uri` when the ERC-721 gate passes; otherwise fail closed to `empty` via length zero. -/
@[pf_inline] def select721 (uri : Uri) (owners : Erc721.Owners) (tokenId : UInt256) : Uri :=
  { length := if canRespond721 owners tokenId then uri.length else 0, values := uri.values }

/-- Publish `uri` when the ERC-1155 gate passes; otherwise fail closed to `empty` via length zero. -/
@[pf_inline] def select1155 (uri : Uri) (tokenId : UInt256) : Uri :=
  { length := if canRespond1155 tokenId then uri.length else 0, values := uri.values }

end ProofForge.Evm.Sdk.MetadataUri
