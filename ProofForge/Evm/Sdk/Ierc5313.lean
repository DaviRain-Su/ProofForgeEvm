import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.Ierc5313

/-!
# EVM SDK IERC5313 `owner()` view helper

Reuses explicit `Ownable` / `Access` owner storage without adding layout. Consumers store the
owner `Address` in application state and gate publication with `canPublish` before advertising
`owner()`. Renounced ownership (zero owner) fails closed to `Address.zero`.

Extract note: `pf_entry` owner views must return explicit address constructors (`if canPublish
then owner else Address.zero`). Do not route returns through parameterized SDK helpers.
-/

/-- True when a nonzero owner may be advertised through IERC5313 `owner()`. -/
@[pf_inline] def canPublish (owner : Address) : Bool :=
  !Address.isZero owner

/-- Fail-closed owner view: zero when renounced or unset. -/
@[pf_inline] def selectOwner (owner : Address) : Address :=
  if canPublish owner then owner else Address.zero

end ProofForge.Evm.Sdk.Ierc5313
