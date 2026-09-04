import ProofForge.Evm.Sdk

/-!
A map write bound to an unused `let` must run even when the following `if` skips the
ordinary count store. `flag != 0` keeps `count` at 0 and still persists the map entry.
-/

namespace Examples.Evm.DroppedLetLink
open ProofForge.Evm.Sdk

structure State where
  count : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_inline] def cells : Storage.U64Map := Storage.Layout.root.u64Map.handle

@[pf_entry]
def init (_seed : UInt64) : State :=
  { count := 0 }

@[pf_entry]
def countOf (s : State) : UInt64 :=
  s.count

@[pf_entry]
def get (_s : State) (key : UInt64) : UInt64 :=
  cells.get key

@[pf_entry]
def putThenGuard (s : State) (flag key value : UInt64) : Except Error (State × Bool) :=
  let _sent := cells.put key value
  if flag == 0 then
    .ok ({ s with count := s.count + 1 }, true)
  else
    .ok (s, false)

end Examples.Evm.DroppedLetLink
