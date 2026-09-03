import ProofForge.Attr
import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.DefaultAdminDelay

/-!
# EVM SDK bounded delayed default-admin profile

OpenZeppelin `AccessControlDefaultAdminRules`-shaped helpers over fixed flat state: one current
default admin, one pending nominee address, one accept timestamp, and one configured delay. There
is no role hierarchy, enumeration, or delay-increase scheduling API.

Applications own authorization, error terminals, and literal state-field updates. This module
exposes schedule/accept/cancel decisions and canonical events only.
-/

def u64Max : UInt64 := ~~~(0 : UInt64)

/-- True when a nonzero pending default admin is scheduled. -/
@[pf_inline] def pendingActive (pendingAdmin : Address) : Bool :=
  !Address.isZero pendingAdmin

/-- Default-admin gate: the caller holds the explicit stored admin handle. -/
@[pf_inline] def requireDefaultAdmin (admin : Address) : Bool :=
  Address.eq Context.caller admin

/-- True when the current default admin may schedule `newAdmin` (nonzero nominee). -/
@[pf_inline] def canBegin (admin newAdmin : Address) : Bool :=
  requireDefaultAdmin admin && !Address.isZero newAdmin

/-- Accept timestamp for a transfer begun at `now` with configured `delay`. Zero delay accepts
immediately. Overflow saturates to `u64Max`. -/
@[pf_inline] def scheduleAccept (now delay : UInt64) : UInt64 :=
  if delay == 0 then
    now
  else if now ≤ u64Max - delay then
    now + delay
  else
    u64Max

/-- True when `who` is the sole pending default admin. -/
@[pf_inline] def isNominee (pendingAdmin who : Address) : Bool :=
  pendingActive pendingAdmin && Address.eq pendingAdmin who

/-- True when the caller is the pending nominee and the accept schedule has elapsed. -/
@[pf_inline] def canAccept (pendingAdmin : Address) (schedule now : UInt64) : Bool :=
  isNominee pendingAdmin Context.caller && now ≥ schedule

/-- True when the current default admin may cancel a live pending transfer. -/
@[pf_inline] def canCancel (admin pendingAdmin : Address) : Bool :=
  requireDefaultAdmin admin && pendingActive pendingAdmin

/-- Canonical OpenZeppelin delayed default-admin events. -/
inductive Notice where
  | DefaultAdminTransferScheduled (newAdmin : Event.Indexed Address) (acceptSchedule : UInt64)
  | DefaultAdminTransferCanceled
  | DefaultAdminTransferred (previousAdmin : Event.Indexed Address)
      (newAdmin : Event.Indexed Address)
  deriving Repr, DecidableEq, Inhabited

namespace Log

/-- LOG3 `DefaultAdminTransferScheduled(address indexed newAdmin, uint48 acceptSchedule)`. -/
@[pf_inline] def transferScheduled (newAdmin : Address) (acceptSchedule : UInt64) : UInt64 :=
  Event.emit (Notice.DefaultAdminTransferScheduled (Event.indexed newAdmin) acceptSchedule)

/-- LOG0 `DefaultAdminTransferCanceled()`. -/
@[pf_inline] def transferCanceled : UInt64 :=
  Event.emit Notice.DefaultAdminTransferCanceled

/-- LOG3 `DefaultAdminTransferred(address indexed previousAdmin, address indexed newAdmin)`. -/
@[pf_inline] def transferred (previousAdmin newAdmin : Address) : UInt64 :=
  Event.emit (Notice.DefaultAdminTransferred (Event.indexed previousAdmin)
    (Event.indexed newAdmin))

end Log

end ProofForge.Evm.Sdk.DefaultAdminDelay
