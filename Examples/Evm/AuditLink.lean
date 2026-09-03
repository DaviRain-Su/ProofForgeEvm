import ProofForge.Evm.Sdk
import ProofForge.Core.Value

/-!
OZ completion-audit witness consumer. Constructor stores no mutable audit state; views expose the
pinned backlog counters and fail-closed `auditOk` gate against caller-supplied authority tree counts.
-/

namespace Examples.Evm.AuditLink
open ProofForge.Evm.Sdk
open ProofForge.Core.Value

structure State where
  dummy : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_entry]
def init (_witness : UInt64) : State :=
  { dummy := 0 }

@[pf_entry]
def touch (_s : State) (v : UInt64) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := v }, v)
  else
    .error .overflow

@[pf_entry]
def coverageRows (_s : State) : UInt64 :=
  OzAudit.coverageRows

@[pf_entry]
def classifiedCount (_s : State) : UInt64 :=
  OzAudit.classifiedCount

@[pf_entry]
def isComplete (_s : State) : Bool :=
  OzAudit.isComplete

@[pf_entry]
def auditOk (_s : State) (paths sources : UInt64) : Bool :=
  OzAudit.auditOk paths sources

end Examples.Evm.AuditLink
