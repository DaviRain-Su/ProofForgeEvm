import ProofForge.Evm.Sdk
import ProofForge.Core.Value

namespace Examples.Evm.MetaGateLink
open ProofForge.Evm.Sdk
open ProofForge.Core.Value

structure State where
  dummy : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_inline] def invalidName : BoundedString 8 :=
  { length := 2, values := #v[0xc0, 0x80, 0, 0, 0, 0, 0, 0] }

@[pf_inline] def validSymbol : BoundedString 4 :=
  { length := 2, values := #v[0x50, 0x46, 0, 0] }

@[pf_entry]
def init (_owner : Address) : State :=
  { dummy := 0 }

@[pf_entry]
def name (_s : State) : BoundedString 8 :=
  { length := if Erc20Meta.canPublish invalidName validSymbol then 2 else 0
    values := #v[0xc0, 0x80, 0, 0, 0, 0, 0, 0] }

@[pf_entry]
def touch (_s : State) (v : UInt64) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then .ok ({ dummy := v }, v) else .error .overflow

end Examples.Evm.MetaGateLink
