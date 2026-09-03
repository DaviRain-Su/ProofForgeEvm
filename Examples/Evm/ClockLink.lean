import ProofForge.Evm.Sdk
import ProofForge.Core.Value

/-!
IERC6372 clock consumer using compile-time block-number mode. `clock()` reads
`Context.blockNumber`; `CLOCK_MODE()` returns the bounded `mode=blocknumber&from=default`
string. Timestamp mode remains available through the SDK for other consumers.
-/

namespace Examples.Evm.ClockLink
open ProofForge.Evm.Sdk
open ProofForge.Core.Value

structure State where
  dummy : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_inline] private def clockKind : Ierc6372.ClockKind := .blockNumber

@[pf_entry]
def init (_owner : Address) : State :=
  { dummy := 0 }

/-- IERC6372 `clock()` for block-number mode. -/
@[pf_entry]
def clock (_s : State) : UInt64 :=
  if Ierc6372.canPublish clockKind then Ierc6372.clock clockKind else 0

/-- IERC6372 `CLOCK_MODE()` bounded string for block-number mode. -/
@[pf_entry]
def CLOCK_MODE (_s : State) : BoundedString 32 :=
  { length := if Ierc6372.canPublish clockKind then 29 else 0
    values := #v[0x6d, 0x6f, 0x64, 0x65, 0x3d, 0x62, 0x6c, 0x6f, 0x63, 0x6b, 0x6e, 0x75, 0x6d, 0x62,
      0x65, 0x72, 0x26, 0x66, 0x72, 0x6f, 0x6d, 0x3d, 0x64, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0, 0,
      0] }

@[pf_entry]
def touch (_s : State) (v : UInt64) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then .ok ({ dummy := v }, v) else .error .overflow

end Examples.Evm.ClockLink
