import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.AuditLink

/-!
W5 slice 3: OZ completion-audit permanent non-goal evidence — per-row nonGoalTagOf aligned with
`oz-sdk-backlog.md` § Permanent non-goals, fail-closed allBlockedRowsTagged gate.
-/

namespace Tests.EvmOzAuditSpec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard OzAudit.coverageRows == 32
#guard OzAudit.doneCount == 2
#guard OzAudit.partialCount == 16
#guard OzAudit.absentCount == 14
#guard OzAudit.blockedCount == 14
#guard OzAudit.classifiedCount == 32
#guard OzAudit.isComplete
#guard OzAudit.allRowsClassified
#guard OzAudit.authorityTreePaths == 452
#guard OzAudit.authoritySoliditySources == 367
#guard OzAudit.treeMatchesAuthority 452 367
#guard !OzAudit.treeMatchesAuthority 451 367
#guard OzAudit.auditOk 452 367
#guard !OzAudit.auditOk 451 367
#guard OzAudit.auditOkClassified 452 367
#guard !OzAudit.auditOkClassified 451 367
#guard OzAudit.allBlockedRowsTagged
#guard OzAudit.auditOkEvidence 452 367
#guard !OzAudit.auditOkEvidence 451 367

#guard OzAudit.nonGoalTagOf 0 == OzAudit.nonGoalNone
#guard OzAudit.nonGoalTagOf 2 == OzAudit.nonGoalUnboundedGovernance
#guard OzAudit.nonGoalTagOf 3 == OzAudit.nonGoalAccountAbstraction
#guard OzAudit.nonGoalTagOf 18 == OzAudit.nonGoalProxyCreateSlot
#guard OzAudit.nonGoalTagOf 25 == OzAudit.nonGoalArbitraryCall
#guard OzAudit.nonGoalTagOf 31 == OzAudit.nonGoalNotRuntime
#guard OzAudit.isKnownNonGoalTag OzAudit.nonGoalProxyCreateSlot
#guard !OzAudit.isKnownNonGoalTag 0
#guard OzAudit.blockedRowTagged 2
#guard OzAudit.blockedRowTagged 7
#guard !OzAudit.blockedRowTagged 32

#guard OzAudit.pathTagOf 0 == OzAudit.tagAccessOwnable
#guard OzAudit.statusOf 0 == OzAudit.statusPartial
#guard !OzAudit.isBlocked 0
#guard OzAudit.pathTagOf 7 == OzAudit.tagIface165
#guard OzAudit.statusOf 7 == OzAudit.statusDone
#guard !OzAudit.isBlocked 7
#guard OzAudit.pathTagOf 11 == OzAudit.tagIface2981
#guard OzAudit.statusOf 11 == OzAudit.statusDone
#guard !OzAudit.isBlocked 11
#guard OzAudit.pathTagOf 2 == OzAudit.tagAccessExt
#guard OzAudit.statusOf 2 == OzAudit.statusAbsent
#guard OzAudit.isBlocked 2
#guard OzAudit.pathTagOf 31 == OzAudit.tagVendor
#guard OzAudit.statusOf 31 == OzAudit.statusAbsent
#guard OzAudit.isBlocked 31
#guard !OzAudit.isClassified 32
#guard OzAudit.statusOf 32 == OzAudit.statusUnknown
#guard OzAudit.pathTagOf 32 == 0

private def countStatus (status : UInt8) : Nat := Id.run do
  let mut n : Nat := 0
  for row in [0:32] do
    if OzAudit.statusOf row.toUInt64 == status then
      n := n + 1
  return n

#guard countStatus OzAudit.statusDone == 2
#guard countStatus OzAudit.statusPartial == 16
#guard countStatus OzAudit.statusAbsent == 14

private def countBlocked : Nat := Id.run do
  let mut n : Nat := 0
  for row in [0:32] do
    if OzAudit.isBlocked row.toUInt64 then
      n := n + 1
  return n

#guard countBlocked == 14

private def expectAuditLink : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.AuditLink with
    | .ok source => pure source
    | .error reason => throwError reason
  for ixName in #[
      "coverageRows", "classifiedCount", "blockedCount", "isComplete", "isClassified",
      "pathTagOf", "statusOf", "isBlocked", "nonGoalTagOf", "auditOk", "touch"
    ] do
    unless source.methods.any (·.ixName == ixName) do
      throwError s!"AuditLink is missing {ixName}"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"coverageRows\"" &&
      abi.contains "\"name\":\"pathTagOf\"" &&
      abi.contains "\"name\":\"statusOf\"" &&
      abi.contains "\"name\":\"isBlocked\"" &&
      abi.contains "\"name\":\"nonGoalTagOf\"" &&
      abi.contains "\"name\":\"isClassified\"" &&
      abi.contains "\"name\":\"auditOk\"" do
    throwError s!"AuditLink ABI lost audit surface:\n{abi}"
  unless IR.digestHex program == "46dd623883b2ee8e" do
    throwError s!"AuditLink digest drifted: {IR.digestHex program}"
  logInfo m!"auditlink: digest={IR.digestHex program} abi-ok"

elab "#pf_guard_evm_oz_audit" : command => expectAuditLink

#pf_guard_evm_oz_audit

#pf_evm_build Examples.Evm.AuditLink

end Tests.EvmOzAuditSpec
