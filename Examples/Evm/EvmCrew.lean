import ProofForge

/-!
EVM-SDK-3 consumer C: bounded static four-slot crew role set (`Roles.Set4`).

`declared` threads the `Storage.Static` cursor in the exact declaration order of `State`;
role decisions rebuild a `Roles.Set4` value from the four explicit fields and every role write is
a literal-slot field update. Successful grants/revokes emit canonical `RoleGranted` /
`RoleRevoked` for `CREW_ROLE`; idempotent no-ops do not log.
-/

namespace Examples.Evm.EvmCrew
open ProofForge.Evm.Sdk

structure State where
  paused : UInt8
  crew0 : Address
  crew1 : Address
  crew2 : Address
  crew3 : Address
  deriving Repr, DecidableEq, Inhabited

structure Handles where
  paused : Storage.Static.Handle UInt8
  crew0 : Storage.Static.Handle Address
  crew1 : Storage.Static.Handle Address
  crew2 : Storage.Static.Handle Address
  crew3 : Storage.Static.Handle Address

@[pf_inline] def declared : Storage.Static.Allocated Handles :=
  let paused := Storage.Static.Layout.root.uint8 "paused"
  let crew0 := paused.next.address "crew0"
  let crew1 := crew0.next.address "crew1"
  let crew2 := crew1.next.address "crew2"
  let crew3 := crew2.next.address "crew3"
  { handle := { paused := paused.handle, crew0 := crew0.handle, crew1 := crew1.handle,
                crew2 := crew2.handle, crew3 := crew3.handle }
    next := crew3.next }

@[pf_inline] def layout : Storage.Static.Layout := declared.next

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

/-- keccak256("CREW_ROLE") as source-order `Bytes32` limbs. -/
@[pf_inline] def CREW_ROLE : Bytes32 :=
  ⟨0x0f37ec37942ef16b, 0xacc47a17cb9504a0, 0x320a0ccfe901852c, 0x892e9b5630d43e9d⟩

@[pf_inline] private def crewSet (s : State) : Roles.Set4 :=
  ⟨s.crew0, s.crew1, s.crew2, s.crew3⟩

@[pf_entry]
def init (_seed : UInt64) (_owner : Address) : State :=
  { paused := 0, crew0 := Address.zero, crew1 := Address.zero,
    crew2 := Address.zero, crew3 := Address.zero }

@[pf_entry]
def pause (s : State) : Except Error (State × UInt64) :=
  if Address.eqImmutable Context.caller then
    .ok ({ s with paused := 1 }, 1)
  else
    .ok (s, Revert.unauthorized Context.caller)

@[pf_entry]
def unpause (s : State) : Except Error (State × UInt64) :=
  if Address.eqImmutable Context.caller then
    .ok ({ s with paused := 0 }, 0)
  else
    .ok (s, Revert.unauthorized Context.caller)

@[pf_entry]
def pausedOf (s : State) : UInt8 :=
  s.paused

/-- Immutable-owner-gated crew grant over the four explicit fields. -/
@[pf_entry]
def grantCrew (s : State) (who : Address) : Except Error (State × UInt64) :=
  if Address.eqImmutable Context.caller then
    let rs := crewSet s
    if Address.isZero who then
      .ok (s, Revert.zeroAddress)
    else if rs.member who then
      .ok (s, 0)
    else if rs.grantSlot0 who then
      .ok ({ s with crew0 := who }, Roles.Log.roleGranted CREW_ROLE who Context.caller)
    else if rs.grantSlot1 who then
      .ok ({ s with crew1 := who }, Roles.Log.roleGranted CREW_ROLE who Context.caller)
    else if rs.grantSlot2 who then
      .ok ({ s with crew2 := who }, Roles.Log.roleGranted CREW_ROLE who Context.caller)
    else if rs.grantSlot3 who then
      .ok ({ s with crew3 := who }, Roles.Log.roleGranted CREW_ROLE who Context.caller)
    else
      .ok (s, Revert.capExceeded)
  else
    .ok (s, Revert.unauthorized Context.caller)

@[pf_entry]
def revokeCrew (s : State) (who : Address) : Except Error (State × UInt64) :=
  if Address.eqImmutable Context.caller then
    let rs := crewSet s
    if rs.revokeSlot0 who then
      .ok ({ s with crew0 := Address.zero },
        Roles.Log.roleRevoked CREW_ROLE who Context.caller)
    else if rs.revokeSlot1 who then
      .ok ({ s with crew1 := Address.zero },
        Roles.Log.roleRevoked CREW_ROLE who Context.caller)
    else if rs.revokeSlot2 who then
      .ok ({ s with crew2 := Address.zero },
        Roles.Log.roleRevoked CREW_ROLE who Context.caller)
    else if rs.revokeSlot3 who then
      .ok ({ s with crew3 := Address.zero },
        Roles.Log.roleRevoked CREW_ROLE who Context.caller)
    else
      .ok (s, 0)
  else
    .ok (s, Revert.unauthorized Context.caller)

@[pf_entry]
def isCrew (s : State) (who : Address) : Bool :=
  if Roles.Set4.member (crewSet s) who then true else false

end Examples.Evm.EvmCrew
