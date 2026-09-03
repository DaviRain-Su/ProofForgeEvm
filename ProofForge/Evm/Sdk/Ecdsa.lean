import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.Ecdsa

/-!
# EVM SDK typed ECDSA recover facade

Public SDK spelling of the closed ecrecover precompile contract (EVM-RT-2d). The helper erases
to `Runtime.evmEcrecover`, which emits the fixed STATICCALL to precompile address `1` with the
128-byte `hash ‖ v ‖ r ‖ s` frame, success gate, exact-32-byte returndata gate, and nonzero-signer
gate. Invalid signatures revert; there is no zero-address fallback.

Extract note: consumers call `recover` directly; do not introduce alternate precompile addresses,
input sizes, or unchecked recovery paths.
-/

/-- Recover the signer of `digest` from `(v, r, s)` via the closed ecrecover precompile. Invalid
signatures revert at runtime. -/
@[pf_inline] def recover (digest : Bytes32) (v : UInt8) (r s : Bytes32) : Address :=
  Runtime.evmEcrecover digest v r s

end ProofForge.Evm.Sdk.Ecdsa
