import ProofForge.Evm.Sdk
import ProofForge.Core.Value

/-!
Minimal typed ECDSA recover consumer. Calls the public `Sdk.Ecdsa.recover` facade, which lowers
to the closed ecrecover precompile contract. Invalid signatures revert (fail-closed).
-/

namespace Examples.Evm.RecoverLink
open ProofForge.Evm.Sdk
open ProofForge.Core.Value

structure State where
  dummy : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_entry]
def init (_owner : Address) : State :=
  { dummy := 0 }

/-- Recover signer from `(digest, v, r, s)` via the closed ecrecover precompile. -/
@[pf_entry]
def recover (_s : State) (digest : Bytes32) (v : UInt8) (r s : Bytes32) : Address :=
  Ecdsa.recover digest v r s

@[pf_entry]
def touch (_s : State) (v : UInt64) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then .ok ({ dummy := v }, v) else .error .overflow

end Examples.Evm.RecoverLink
