import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.Erc165

/-!
# EVM SDK bounded ERC-165 core

ERC-165 is a pure `bytes4` capability query. This module provides canonical interface identifiers
and bounded static-set predicates for consumers that explicitly expose
`supportsInterface(bytes4)`. It introduces no storage, callback, dynamic calldata, or dispatch
escape hatch.

The helpers intentionally model only a finite, source-declared interface set. They do not infer an
interface from a method list, probe another contract, or emulate the ERC-165 receiver handshake.
Consumers must explicitly select every supported id, including `IERC165` itself.

A standard identifier such as `IERC721` or `IERC1155` may be selected only after the consumer
implements that interface's complete required method surface. Partial token profiles must return
`false` for the corresponding standard identifier.
-/

/-- ABI-facing ERC-165 interface identifier. -/
abbrev InterfaceId := Bytes4

/-- `IERC165`: `0x01ffc9a7`, packed in the source fixed-bytes limb order. -/
@[pf_inline] def erc165 : InterfaceId :=
  ⟨0xa7c9ff01, 0, 0, 0⟩

/-- `IERC721`: `0x80ac58cd`, packed in the source fixed-bytes limb order. -/
@[pf_inline] def erc721 : InterfaceId :=
  ⟨0xcd58ac80, 0, 0, 0⟩

/-- `IERC721Enumerable`: `0x780e9d63`. Advertise only when the consumer implements the complete
IERC721 surface plus `totalSupply` / `tokenByIndex` / `tokenOfOwnerByIndex`. A bounded
enumerable profile that still omits IERC721 methods must return false. -/
@[pf_inline] def erc721Enumerable : InterfaceId :=
  ⟨0x639d0e78, 0, 0, 0⟩

/-- `IERC1155`: `0xd9b67a26`, packed in the source fixed-bytes limb order. -/
@[pf_inline] def erc1155 : InterfaceId :=
  ⟨0x267ab6d9, 0, 0, 0⟩

/-- `IERC2981`: `0x2a55205a`, packed in the source fixed-bytes limb order. Advertise this id only
when the consumer implements the complete `royaltyInfo(uint256,uint256)` surface. -/
@[pf_inline] def erc2981 : InterfaceId :=
  ⟨0x5a20552a, 0, 0, 0⟩

/-- `IERC721Receiver`: `0x150b7a02`. Advertise only when the consumer implements
`onERC721Received`. Same packing as `Erc721.onReceivedSelector`. -/
@[pf_inline] def erc721Receiver : InterfaceId :=
  ⟨0x027a0b15, 0, 0, 0⟩

/-- `IERC1155Receiver`: `0x4e2312e0`. Advertise only when the consumer implements both
`onERC1155Received` and `onERC1155BatchReceived`. -/
@[pf_inline] def erc1155Receiver : InterfaceId :=
  ⟨0xe012234e, 0, 0, 0⟩

/-- Equality over canonical ABI `bytes4` values, lowered through the closed two-operand runtime
leaf rather than structural carrier inspection. -/
@[pf_inline] def equal (left right : InterfaceId) : Bool :=
  WideWord.Source.eqBytes4 left right

/-- Support a single explicitly declared interface. -/
@[pf_inline] def supports (requested implemented : InterfaceId) : Bool :=
  equal requested implemented

/-- Support either of two explicitly declared interfaces. -/
@[pf_inline] def supports2 (requested first second : InterfaceId) : Bool :=
  supports requested first || supports requested second

/-- Support any of the common bounded two-interface profiles: ERC-165 plus one token interface. -/
@[pf_inline] def supportsToken (requested token : InterfaceId) : Bool :=
  supports2 requested erc165 token

/-- Support any of three explicitly declared interfaces. -/
@[pf_inline] def supports3 (requested first second third : InterfaceId) : Bool :=
  supports2 requested first second || supports requested third

/-- ERC-165 plus IERC2981. Valid only when `royaltyInfo` is implemented. -/
@[pf_inline] def supportsRoyalty (requested : InterfaceId) : Bool :=
  supports2 requested erc165 erc2981

end ProofForge.Evm.Sdk.Erc165
