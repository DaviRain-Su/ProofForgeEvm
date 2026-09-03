import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.AuditLink

/-!
W5 slice 1: OZ completion-audit inventory — authority tree re-inventory counters and fail-closed
completeness gate.
-/

namespace Tests.EvmOzAuditSpec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard OzAudit.coverageRows == 32
#guard OzAudit.doneCount == 2
#guard OzAudit.partialCount == 16
#guard OzAudit.absentCount == 14
#guard OzAudit.classifiedCount == 32
#guard OzAudit.isComplete
#guard OzAudit.authorityTreePaths == 452
#guard OzAudit.authoritySoliditySources == 367
#guard OzAudit.treeMatchesAuthority 452 367
#guard !OzAudit.treeMatchesAuthority 451 367
#guard OzAudit.auditOk 452 367
#guard !OzAudit.auditOk 451 367

private def expectAuditLink : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.AuditLink with
    | .ok source => pure source
    | .error reason => throwError reason
  for ixName in #["coverageRows", "classifiedCount", "isComplete", "auditOk", "touch"] do
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
      abi.contains "\"name\":\"auditOk\"" &&
      abi.contains "\"name\":\"isComplete\"" do
    throwError s!"AuditLink ABI lost audit surface:\n{abi}"
  unless IR.digestHex program == "db0604e71ffe0f7f" do
    throwError s!"AuditLink digest drifted: {IR.digestHex program}"
  logInfo m!"auditlink: digest={IR.digestHex program} abi-ok"

elab "#pf_guard_evm_oz_audit" : command => expectAuditLink

#pf_guard_evm_oz_audit

#pf_evm_build Examples.Evm.AuditLink

end Tests.EvmOzAuditSpec
