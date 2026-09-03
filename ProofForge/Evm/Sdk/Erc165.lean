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
-/

/-- ABI-facing ERC-165 interface identifier. -/
abbrev InterfaceId := Bytes4

/-- `IERC165`: `0x01ffc9a7`, packed in the source fixed-bytes limb order. -/
@[pf_inline] def erc165 : InterfaceId :=
  ⟨0xa7c9ff01, 0, 0, 0⟩

/-- `IERC721`: `0x80ac58cd`, packed in the source fixed-bytes limb order. -/
@[pf_inline] def erc721 : InterfaceId :=
  ⟨0xcd58ac80, 0, 0, 0⟩

/-- `IERC1155`: `0xd9b67a26`, packed in the source fixed-bytes limb order. -/
@[pf_inline] def erc1155 : InterfaceId :=
  ⟨0x267ab6d9, 0, 0, 0⟩

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

end ProofForge.Evm.Sdk.Erc165
