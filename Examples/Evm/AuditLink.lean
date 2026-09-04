import ProofForge.Evm.Sdk
import ProofForge.Core.Value

/-!
OZ completion-audit witness consumer. Constructor stores no mutable audit state; views expose the
pinned backlog counters, per-row path tag / status / blocker predicates, and fail-closed `auditOk`
gate against caller-supplied authority tree counts.

Row lookup tables are spelled inline for extraction; compile-time mirrors live in `Sdk.OzAudit`.
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
def blockedCount (_s : State) : UInt64 :=
  OzAudit.blockedCount

@[pf_entry]
def temporaryGapCount (_s : State) : UInt64 :=
  OzAudit.temporaryGapCount

@[pf_entry]
def isComplete (_s : State) : Bool :=
  OzAudit.isComplete

@[pf_entry]
def pathTagOf (_s : State) (row : UInt64) : UInt8 :=
  if row == 0 then 1
  else if row == 1 then 2
  else if row == 2 then 3
  else if row == 3 then 4
  else if row == 4 then 5
  else if row == 5 then 6
  else if row == 6 then 7
  else if row == 7 then 8
  else if row == 8 then 9
  else if row == 9 then 10
  else if row == 10 then 11
  else if row == 11 then 12
  else if row == 12 then 13
  else if row == 13 then 14
  else if row == 14 then 15
  else if row == 15 then 16
  else if row == 16 then 17
  else if row == 17 then 18
  else if row == 18 then 19
  else if row == 19 then 20
  else if row == 20 then 21
  else if row == 21 then 22
  else if row == 22 then 23
  else if row == 23 then 24
  else if row == 24 then 25
  else if row == 25 then 26
  else if row == 26 then 27
  else if row == 27 then 28
  else if row == 28 then 29
  else if row == 29 then 30
  else if row == 30 then 31
  else if row == 31 then 32
  else 0

@[pf_entry]
def statusOf (_s : State) (row : UInt64) : UInt8 :=
  if row == 0 then 2
  else if row == 1 then 2
  else if row == 2 then 2
  else if row == 3 then 3
  else if row == 4 then 3
  else if row == 5 then 2
  else if row == 6 then 3
  else if row == 7 then 1
  else if row == 8 then 2
  else if row == 9 then 2
  else if row == 10 then 2
  else if row == 11 then 1
  else if row == 12 then 2
  else if row == 13 then 2
  else if row == 14 then 3
  else if row == 15 then 2
  else if row == 16 then 2
  else if row == 17 then 3
  else if row == 18 then 3
  else if row == 19 then 2
  else if row == 20 then 2
  else if row == 21 then 2
  else if row == 22 then 2
  else if row == 23 then 2
  else if row == 24 then 2
  else if row == 25 then 3
  else if row == 26 then 2
  else if row == 27 then 2
  else if row == 28 then 2
  else if row == 29 then 3
  else if row == 30 then 2
  else if row == 31 then 3
  else 0

@[pf_entry]
def isBlocked (_s : State) (row : UInt64) : Bool :=
  if row == 3 then true
  else if row == 4 then true
  else if row == 6 then true
  else if row == 14 then true
  else if row == 17 then true
  else if row == 18 then true
  else if row == 25 then true
  else if row == 29 then true
  else if row == 31 then true
  else false

/-- ABSENT without a permanent non-goal. No row today: row 12, `interfaces/IERC1271.sol`, was the
last one and shipped as `Sdk.Ierc1271`; the view stays so the next reopened row has a home. -/
@[pf_entry]
def isTemporaryGap (_s : State) (_row : UInt64) : Bool :=
  false

@[pf_entry]
def nonGoalTagOf (_s : State) (row : UInt64) : UInt8 :=
  if row == 3 then 3
  else if row == 4 then 5
  else if row == 6 then 4
  else if row == 14 then 5
  else if row == 17 then 2
  else if row == 18 then 1
  else if row == 25 then 2
  else if row == 29 then 1
  else if row == 31 then 6
  else 0

@[pf_entry]
def isClassified (_s : State) (row : UInt64) : Bool :=
  if row == 32 then false
  else if row == 0 then true
  else if row == 1 then true
  else if row == 2 then true
  else if row == 3 then true
  else if row == 4 then true
  else if row == 5 then true
  else if row == 6 then true
  else if row == 7 then true
  else if row == 8 then true
  else if row == 9 then true
  else if row == 10 then true
  else if row == 11 then true
  else if row == 12 then true
  else if row == 13 then true
  else if row == 14 then true
  else if row == 15 then true
  else if row == 16 then true
  else if row == 17 then true
  else if row == 18 then true
  else if row == 19 then true
  else if row == 20 then true
  else if row == 21 then true
  else if row == 22 then true
  else if row == 23 then true
  else if row == 24 then true
  else if row == 25 then true
  else if row == 26 then true
  else if row == 27 then true
  else if row == 28 then true
  else if row == 29 then true
  else if row == 30 then true
  else if row == 31 then true
  else false

@[pf_entry]
def auditOk (_s : State) (paths sources : UInt64) : Bool :=
  OzAudit.isComplete && OzAudit.treeMatchesAuthority paths sources

end Examples.Evm.AuditLink
