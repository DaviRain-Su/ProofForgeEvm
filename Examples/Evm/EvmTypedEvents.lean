import ProofForge.Evm.Sdk

/-!
S1b source consumer of typed events. Constructors stay ordinary Lean data: `Event.Indexed`
marks topic fields, and `Event.emit` preserves the constructor name, field names, ABI types,
and indexed flags as one `EventFrame`.
-/

namespace Examples.Evm.EvmTypedEvents
open ProofForge.Evm.Sdk

structure State where
  ticks : UInt64
  flag : Bool
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

/-- Approved typed events for this contract. `Transferred` is address-indexed plus `uint256`
data; `Flagged` is boolean data; `Ticked` is used from both sides of a nested `ite`. -/
inductive Notice where
  | Transferred (from : Event.Indexed Address) (to : Event.Indexed Address) (value : UInt256)
  | Flagged (ok : Bool)
  | Ticked (n : UInt64)
  deriving Repr, DecidableEq, Inhabited

@[pf_entry]
def init (_seed : UInt64) : State :=
  { ticks := 0, flag := false }

@[pf_entry]
def ticksOf (s : State) : UInt64 :=
  s.ticks

@[pf_entry]
def flagOf (s : State) : Bool :=
  s.flag

/-- LOG3 `Transferred(address indexed from, address indexed to, uint256 value)`. -/
@[pf_entry]
def transfer (_s : State) (src dest : Address) (amount : UInt256) : Except Error (State × Bool) :=
  .ok (_s, Effect.thenTrue (Event.emit
    (.Transferred (Event.indexed src) (Event.indexed dest) amount)))

/-- LOG1 `Flagged(bool)` data word. -/
@[pf_entry]
def setFlag (s : State) (ok : Bool) : Except Error (State × Bool) :=
  .ok ({ s with flag := ok }, Effect.thenTrue (Event.emit (.Flagged ok)))

/-- Both branches emit `Ticked`; ABI metadata must include it once. -/
@[pf_entry]
def pulse (s : State) (n : UInt64) : Except Error (State × UInt64) :=
  if n == 0 then
    .ok (s, Event.emit (.Ticked 0))
  else
    .ok ({ s with ticks := n }, Event.emit (.Ticked n))

end Examples.Evm.EvmTypedEvents
