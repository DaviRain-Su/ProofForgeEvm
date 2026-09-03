import ProofForge.Evm.Sdk

/-!
Bounded delayed default-admin witness. Constructor stores the initial default admin and delay;
state tracks one pending nominee and accept timestamp as flat fields. All storage writes stay
in this file.
-/

namespace Examples.Evm.AdminDelayLink
open ProofForge.Evm.Sdk

def u64Max : UInt64 := ~~~(0 : UInt64)

structure State where
  defaultAdmin : Address
  pendingAdmin : Address
  acceptSchedule : UInt64
  count : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_entry]
def init (admin : Address) (_delay : UInt64) : State :=
  { defaultAdmin := admin, pendingAdmin := Address.zero, acceptSchedule := 0, count := 0 }

@[pf_entry]
def defaultAdmin (s : State) : Address :=
  s.defaultAdmin

@[pf_entry]
def pendingDefaultAdmin (s : State) : Address :=
  s.pendingAdmin

@[pf_entry]
def acceptSchedule (s : State) : UInt64 :=
  s.acceptSchedule

@[pf_entry]
def defaultAdminDelay (_s : State) : UInt64 :=
  Immutable.u64

@[pf_entry]
def beginDefaultAdminTransfer (s : State) (newAdmin : Address) :
    Except Error (State × UInt64) :=
  if DefaultAdminDelay.canBegin s.defaultAdmin newAdmin then
    let schedule := DefaultAdminDelay.scheduleAccept Context.timestamp Immutable.u64
    .ok ({ s with pendingAdmin := newAdmin, acceptSchedule := schedule },
      DefaultAdminDelay.Log.transferScheduled newAdmin schedule)
  else
    .ok (s, Access.ownerViolation)

@[pf_entry]
def cancelDefaultAdminTransfer (s : State) : Except Error (State × UInt64) :=
  if DefaultAdminDelay.canCancel s.defaultAdmin s.pendingAdmin then
    .ok ({ s with pendingAdmin := Address.zero, acceptSchedule := 0 },
      DefaultAdminDelay.Log.transferCanceled)
  else
    .ok (s, Access.ownerViolation)

@[pf_entry]
def acceptDefaultAdminTransfer (s : State) : Except Error (State × UInt64) :=
  if DefaultAdminDelay.canAccept s.pendingAdmin s.acceptSchedule Context.timestamp then
    .ok ({ defaultAdmin := s.pendingAdmin, pendingAdmin := Address.zero, acceptSchedule := 0,
           count := s.count },
      DefaultAdminDelay.Log.transferred s.defaultAdmin s.pendingAdmin)
  else
    .ok (s, Access.ownerViolation)

@[pf_entry]
def bump (s : State) (delta : UInt64) : Except Error (State × UInt64) :=
  if DefaultAdminDelay.requireDefaultAdmin s.defaultAdmin then
    if s.count ≤ u64Max - delta then
      .ok ({ s with count := s.count + delta }, s.count + delta)
    else
      .error .overflow
  else
    .ok (s, Access.ownerViolation)

@[pf_entry]
def get (s : State) : UInt64 :=
  s.count

end Examples.Evm.AdminDelayLink
