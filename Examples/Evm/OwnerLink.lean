import ProofForge.Evm.Sdk
import ProofForge.Core.Value

/-!
IERC5313 `owner()` consumer. Reuses explicit Ownable owner storage from `init`; renounced
(zero) owners fail closed to `address(0)` at the view boundary.
-/

namespace Examples.Evm.OwnerLink
open ProofForge.Evm.Sdk

structure State where
  owner : Address
  dummy : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_entry]
def init (owner : Address) : State :=
  { owner, dummy := 0 }

/-- IERC5313 `owner()`. Fail closed to zero when ownership was renounced. -/
@[pf_entry]
def owner (s : State) : Address :=
  if Ierc5313.canPublish s.owner then s.owner else Address.zero

@[pf_entry]
def touch (s : State) (v : UInt64) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then .ok ({ s with dummy := v }, v) else .error .overflow

end Examples.Evm.OwnerLink
