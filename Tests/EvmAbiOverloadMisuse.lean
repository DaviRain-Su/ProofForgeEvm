import ProofForge.Evm.Sdk

/-!
Two mutating roots that collapse to the same ABI `bump()`. Extraction must refuse them.
`Tests.EvmErc721Spec` pins `extractModuleIR` on this module.
-/

namespace Tests.EvmAbiOverloadMisuse
open ProofForge.Evm.Sdk

structure State where
  value : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_entry]
def init (_seed : UInt64) : State :=
  { value := 0 }

@[pf_entry]
def get (s : State) : UInt64 :=
  s.value

@[pf_entry]
def bump (s : State) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ value := s.value + 1 }, 0)
  else
    .error .overflow

@[pf_entry]
def bump__ (s : State) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ value := s.value + 1 }, 0)
  else
    .error .overflow

end Tests.EvmAbiOverloadMisuse
