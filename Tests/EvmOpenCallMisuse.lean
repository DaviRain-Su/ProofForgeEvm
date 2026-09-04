import ProofForge.Evm.Sdk

/-!
A contract that puts a CALL's `UInt64` anywhere but the result word. Extraction refuses every
entry with the `CALL carrier` reason: the word of `OpenCall.call`, `callSuccess`, or `callValue`
is a sequencing carrier the call policy already decided, not the callee's answer, and it may
stand only as the entry's result word, alone or under `Effect.thenTrue`. `Tests.EvmOpenCallSpec`
pins each entry through `extractMethod`; `runtime-tests/evm/anvil_opencall.sh` pins the
`pf build` surface, which must refuse this module.

Before the refusal each entry compiled. The computed-with shapes lowered to the CALL followed by
the constant `0`: on Anvil `isZero` answered `false` where the Lean function answers `true`,
`plusOne` answered `0` for `1`, `gated` never ran the CALL, `stored` wrote `0` into `flag`, and
`callArg` and `readArg` dropped the inner CALL and the STATICCALL. `letGuarded` lowered to the
CALL and `return 1` with no guard and no store, and `thenTrueGated` stored `1` without running
the CALL.
-/

namespace Tests.EvmOpenCallMisuse
open ProofForge.Evm.Sdk

structure State where
  dummy : UInt64
  flag : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

inductive Remote where
  | ping
  | echo (n : UInt256)
  | deposit
  deriving Inhabited

@[pf_entry]
def init (_seed : UInt64) : State :=
  { dummy := 0, flag := 0 }

@[pf_entry]
def flagOf (s : State) : UInt64 :=
  s.flag

@[pf_entry]
def compared (_s : State) (target : Address) : Bool :=
  OpenCall.callSuccess target Remote.ping == 1

@[pf_entry]
def isZero (_s : State) (target : Address) : Bool :=
  OpenCall.callSuccess target Remote.ping == 0

@[pf_entry]
def plusOne (_s : State) (target : Address) : UInt64 :=
  OpenCall.callSuccess target Remote.ping + 1

@[pf_entry]
def stored (s : State) (target : Address) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ s with flag := OpenCall.callSuccess target Remote.ping }, 1)
  else
    .error .overflow

@[pf_entry]
def gated (s : State) (target : Address) : Except Error (State × UInt64) :=
  if OpenCall.callSuccess target Remote.ping == 1 then
    .ok ({ s with flag := 1 }, 1)
  else
    .ok ({ s with flag := 2 }, 0)

@[pf_entry]
def readArg (_s : State) (target : Address) : UInt256 :=
  OpenCall.staticWord target (Remote.echo ⟨OpenCall.callSuccess target Remote.ping, 0, 0, 0⟩)

@[pf_entry]
def callArg (s : State) (target : Address) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ s with dummy := 0 },
      OpenCall.callSuccess target
        (Remote.echo ⟨OpenCall.callSuccess target Remote.ping, 0, 0, 0⟩))
  else
    .error .overflow

@[pf_entry]
def valueCompared (_s : State) (target : Address) (amt : UInt256) :
    Except Error (State × Bool) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := Ether.accept amt, flag := _s.flag },
      OpenCall.callValue target amt Remote.deposit == amt.w0)
  else
    .error .overflow

@[pf_entry]
def thenTrueGated (s : State) (target : Address) : Except Error (State × UInt64) :=
  if Effect.thenTrue (OpenCall.callSuccess target Remote.ping) then
    .ok ({ s with flag := 1 }, 1)
  else
    .ok ({ s with flag := 2 }, 0)

@[pf_entry]
def thenTrueCompared (_s : State) (target : Address) : Bool :=
  Effect.thenTrue (OpenCall.callSuccess target Remote.ping) == false

@[pf_entry]
def letDropped (s : State) (target : Address) : Except Error (State × UInt64) :=
  let _sent := OpenCall.callSuccess target Remote.ping
  .ok ({ s with flag := 1 }, 1)

@[pf_entry]
def letGuarded (s : State) (target : Address) : Except Error (State × UInt64) :=
  let _sent := OpenCall.callSuccess target Remote.ping
  if s.flag == 0 then
    .ok ({ s with flag := 1 }, 1)
  else
    .error .overflow

end Tests.EvmOpenCallMisuse
