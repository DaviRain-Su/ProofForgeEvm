import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.AuditLink

/-!
W5 slice 3: OZ completion-audit permanent non-goal evidence — per-row nonGoalTagOf aligned with
`oz-sdk-backlog.md` § Permanent non-goals, fail-closed allBlockedRowsTagged gate.

Phase 3 hooks: row 12 (`interfaces/IERC1271.sol`) was the one temporary gap while the 65-byte
signature could not enter a frame. `Sdk.Ierc1271.checkSignature` over `OpenCall.callMagic` closes
it, `checkNow` is the combined fail-closed `isValidSignatureNow` gate, and `validNow` is the Bool
path over `OpenCall.staticTryMagic`. No row
is a temporary gap. The witness still exposes `isTemporaryGap` / `temporaryGapCount` so the
next reopened row has a home. IERC1155 `DuplicateId()` is a named PARTIAL bound, not a
temporary gap. Row 5 VestLink ETH-only is the same kind of named restriction.
Row 12 remaining named restriction is that the receiving side stays a permanent non-goal,
plus wider payloads. `temporaryGapCount` stays 0. Counters stay 2 DONE / 21 PARTIAL / 9 ABSENT /
9 blocked / 0 gap. Rows 8 and 19 stay PARTIAL after issuer `permit` on `Erc20Meta`.
Row 16 stays PARTIAL after `cancelAuthorization`.
Row 16 remaining named restriction is the remaining draft interfaces.
Row 2 remaining named restriction is enumeration/manager.
Row 13 remaining named restriction is flash/777/1363.
Row 22 remaining named restriction is dynamic multi-id registration.
Row 1 nominate-zero nominates the zero address (OZ cancel).
VestLink and Vest20Link ship `renounceOwnership`.
-/

namespace Tests.EvmOzAuditSpec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard OzAudit.coverageRows == 32
#guard OzAudit.doneCount == 2
#guard OzAudit.partialCount == 21
#guard OzAudit.absentCount == 9
#guard OzAudit.blockedCount == 9
#guard OzAudit.temporaryGapCount == 0
#guard OzAudit.absentCount == OzAudit.blockedCount + OzAudit.temporaryGapCount
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
#guard OzAudit.nonGoalTagOf 2 == OzAudit.nonGoalNone
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
#guard OzAudit.statusOf 2 == OzAudit.statusPartial
#guard !OzAudit.isBlocked 2
#guard !OzAudit.isAbsent 2
#guard !OzAudit.isTemporaryGap 2
#guard OzAudit.pathTagOf 13 == OzAudit.tagIfaceFinance
#guard OzAudit.statusOf 13 == OzAudit.statusPartial
#guard !OzAudit.isBlocked 13
#guard !OzAudit.isTemporaryGap 13
#guard OzAudit.pathTagOf 22 == OzAudit.tagToken6909
#guard OzAudit.statusOf 22 == OzAudit.statusPartial
#guard !OzAudit.isBlocked 22
#guard !OzAudit.isTemporaryGap 22
#guard OzAudit.pathTagOf 16 == OzAudit.tagIfaceDraft
#guard OzAudit.statusOf 16 == OzAudit.statusPartial
#guard !OzAudit.isBlocked 16
#guard !OzAudit.isAbsent 16
#guard !OzAudit.isTemporaryGap 16
#guard OzAudit.blockedRowTagged 16
#guard OzAudit.pathTagOf 5 == OzAudit.tagFinanceVesting
#guard OzAudit.statusOf 5 == OzAudit.statusPartial
#guard !OzAudit.isBlocked 5
#guard !OzAudit.isTemporaryGap 5
#guard OzAudit.nonGoalTagOf 5 == OzAudit.nonGoalNone
#guard OzAudit.pathTagOf 8 == OzAudit.tagIface20
#guard OzAudit.statusOf 8 == OzAudit.statusPartial
#guard !OzAudit.isBlocked 8
#guard !OzAudit.isTemporaryGap 8
#guard OzAudit.pathTagOf 19 == OzAudit.tagToken20
#guard OzAudit.statusOf 19 == OzAudit.statusPartial
#guard !OzAudit.isBlocked 19
#guard !OzAudit.isTemporaryGap 19
#guard OzAudit.pathTagOf 12 == OzAudit.tagIface1271
#guard OzAudit.statusOf 12 == OzAudit.statusPartial
#guard !OzAudit.isAbsent 12
#guard !OzAudit.isBlocked 12
#guard !OzAudit.isTemporaryGap 12
#guard OzAudit.nonGoalTagOf 12 == OzAudit.nonGoalNone
#guard OzAudit.blockedRowTagged 12
#guard OzAudit.blockedImpliesAbsent 12
#guard !OzAudit.isTemporaryGap 25
#guard !OzAudit.isTemporaryGap 9
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
#guard countStatus OzAudit.statusPartial == 21
#guard countStatus OzAudit.statusAbsent == 9

private def countBlocked : Nat := Id.run do
  let mut n : Nat := 0
  for row in [0:32] do
    if OzAudit.isBlocked row.toUInt64 then
      n := n + 1
  return n

#guard countBlocked == 9

private def countTemporaryGap : Nat := Id.run do
  let mut n : Nat := 0
  for row in [0:32] do
    if OzAudit.isTemporaryGap row.toUInt64 then
      n := n + 1
  return n

#guard countTemporaryGap == 0

private def auditLinkState : Examples.Evm.AuditLink.State :=
  { dummy := 0 }

private def auditLinkMirrorsCompileTable : Bool := Id.run do
  let mut aligned := true
  for row in [0:32] do
    let ix := row.toUInt64
    aligned := aligned &&
      Examples.Evm.AuditLink.pathTagOf auditLinkState ix == OzAudit.pathTagOf ix &&
      Examples.Evm.AuditLink.statusOf auditLinkState ix == OzAudit.statusOf ix &&
      Examples.Evm.AuditLink.isBlocked auditLinkState ix == OzAudit.isBlocked ix &&
      Examples.Evm.AuditLink.nonGoalTagOf auditLinkState ix == OzAudit.nonGoalTagOf ix &&
      Examples.Evm.AuditLink.isTemporaryGap auditLinkState ix == OzAudit.isTemporaryGap ix &&
      Examples.Evm.AuditLink.isClassified auditLinkState ix == OzAudit.isClassified ix
  return aligned

#guard Examples.Evm.AuditLink.coverageRows auditLinkState == OzAudit.coverageRows
#guard Examples.Evm.AuditLink.classifiedCount auditLinkState == OzAudit.classifiedCount
#guard Examples.Evm.AuditLink.blockedCount auditLinkState == OzAudit.blockedCount
#guard Examples.Evm.AuditLink.temporaryGapCount auditLinkState == OzAudit.temporaryGapCount
#guard auditLinkMirrorsCompileTable
#guard !Examples.Evm.AuditLink.isClassified auditLinkState 32
#guard Examples.Evm.AuditLink.statusOf auditLinkState 32 == OzAudit.statusUnknown

private def expectAuditLink : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.AuditLink with
    | .ok source => pure source
    | .error reason => throwError reason
  for ixName in #[
      "coverageRows", "classifiedCount", "blockedCount", "temporaryGapCount", "isComplete",
      "isClassified", "pathTagOf", "statusOf", "isBlocked", "isTemporaryGap", "nonGoalTagOf",
      "auditOk", "touch"
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
      abi.contains "\"name\":\"isTemporaryGap\"" &&
      abi.contains "\"name\":\"temporaryGapCount\"" &&
      abi.contains "\"name\":\"isClassified\"" &&
      abi.contains "\"name\":\"auditOk\"" do
    throwError s!"AuditLink ABI lost audit surface:\n{abi}"
  unless IR.digestHex program == "ad40c48e855ad5ef" do
    throwError s!"AuditLink digest drifted: {IR.digestHex program}"
  logInfo m!"auditlink: digest={IR.digestHex program} abi-ok"

elab "#pf_guard_evm_oz_audit" : command => expectAuditLink

#pf_guard_evm_oz_audit

#pf_evm_build Examples.Evm.AuditLink

end Tests.EvmOzAuditSpec
