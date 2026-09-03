import Examples.Counter
import ProofForge.Core.Value

namespace Tests.Fixtures

/-- 负向：入口类型带 `Nat`。 -/
def usesNat (n : Nat) : Nat := n + 1

/-- Positive profile fixture: a bounded literal index is compile-time type metadata, not runtime Nat. -/
def usesFixedBytes12 (value : ProofForge.Core.Value.FixedBytes 12) :
    ProofForge.Core.Value.FixedBytes 12 := value

/-- Positive profile fixture: a literal Vector length is compile-time schema metadata. -/
def usesVector4 (value : Vector UInt64 4) : Vector UInt64 4 := value

/-- Positive profile fixture: bounded capacity is compile-time metadata; length stays UInt32. -/
def usesBoundedVec4 (value : ProofForge.Core.Value.BoundedVec UInt64 4) : UInt32 := value.length

/-- Positive profile fixtures: byte/string capacities are compile-time metadata. -/
def usesBoundedBytes16 (value : ProofForge.Core.Value.BoundedBytes 16) : UInt32 := value.length
def usesBoundedString32 (value : ProofForge.Core.Value.BoundedString 32) : UInt32 := value.length

/-- Negative profile fixture: a polymorphic fixed-byte size is still a runtime-shaped Nat boundary. -/
def usesDynamicFixedBytes (n : Nat) (value : ProofForge.Core.Value.FixedBytes n) :
    ProofForge.Core.Value.FixedBytes n := value

/-- Negative profile fixture: bounded capacities must also be literals. -/
def usesDynamicBoundedVec (n : Nat) (value : ProofForge.Core.Value.BoundedVec UInt64 n) :
    UInt32 := value.length

def usesDynamicBoundedBytes (n : Nat) (value : ProofForge.Core.Value.BoundedBytes n) :
    UInt32 := value.length

/-- 负向：partial。 -/
partial def loops (n : UInt64) : UInt64 :=
  loops n

/-- 负向：sorry。 -/
def usesSorry (s : Examples.Counter.State) : UInt64 :=
  sorry

/-- 负向：IO。 -/
def usesIO : IO Unit :=
  pure ()

/-- 负向：extern（无实现，只为属性门）。 -/
@[extern "solana_lean_fixture_extern"]
opaque usesExtern : UInt64 → UInt64

/-- 负向：implemented_by 指向 unsafe。 -/
unsafe def usesImplByImpl (x : UInt64) : UInt64 := x

@[implemented_by usesImplByImpl]
def usesImplBy (x : UInt64) : UInt64 := x

/-- Narrow vector leaves exercise physical indexed loads and stores in both backends. -/
structure NarrowState where
  cells : Vector UInt8 2
  deriving Repr, DecidableEq

def initNarrow (initial : UInt8) : NarrowState :=
  { cells := #v[initial, 0] }

def setNarrow (s : NarrowState) (i : UInt64) (value : UInt8) :
    Except Examples.Counter.Error (NarrowState × UInt64) :=
  if h : i.toNat < 2 then
    .ok ({ cells := s.cells.set i.toNat value }, value.toUInt64)
  else
    .error .overflow

def getNarrow (s : NarrowState) (i : UInt64) : UInt64 :=
  if i < 2 then s.cells[i.toNat]!.toUInt64 else 0

/-- `Nat.sub` saturates: index zero stays zero instead of wrapping to `UInt64.max`. -/
def getNarrowPrevious (s : NarrowState) (i : UInt64) : UInt64 :=
  s.cells[(i.toNat - 1) % 2]!.toUInt64

end Tests.Fixtures
