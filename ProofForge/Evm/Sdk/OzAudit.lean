import ProofForge.Attr

namespace ProofForge.Evm.Sdk.OzAudit

/-!
# EVM SDK OZ completion-audit inventory

Compile-time counters for the bounded coverage table in `docs/product/oz-sdk-backlog.md` and the
authority snapshot of OpenZeppelin `contracts/` tree paths. This is an audit witness, not runtime
interface discovery: unknown rows fail closed via `isComplete` and `treeMatchesAuthority`.

Authority snapshot (2026-09-03 re-inventory for W5 slice 1):
- tree SHA `641ba990cad2f7f70878e0d66be1bfbef95710e8`
- 452 `contracts/` tree paths, 367 Solidity sources
- 32 backlog coverage rows: 2 DONE, 16 PARTIAL, 14 ABSENT
-/

/-- Rows in the coverage table (`oz-sdk-backlog.md`). -/
def coverageRows : UInt64 := 32

/-- Rows marked DONE (bounded capability shipped). -/
def doneCount : UInt64 := 2

/-- Rows marked PARTIAL (named restricted profile). -/
def partialCount : UInt64 := 16

/-- Rows marked ABSENT (no profile shipped). -/
def absentCount : UInt64 := 14

/-- Authority snapshot: `contracts/` tree paths. -/
def authorityTreePaths : UInt64 := 452

/-- Authority snapshot: Solidity sources under `contracts/`. -/
def authoritySoliditySources : UInt64 := 367

/-- Sum of classified backlog rows. -/
@[pf_inline] def classifiedCount : UInt64 :=
  doneCount + partialCount + absentCount

/-- True when every backlog row is accounted for. -/
@[pf_inline] def isComplete : Bool :=
  classifiedCount == coverageRows

/-- True when caller-supplied tree counts match the pinned authority snapshot. -/
@[pf_inline] def treeMatchesAuthority (paths sources : UInt64) : Bool :=
  paths == authorityTreePaths && sources == authoritySoliditySources

/-- Fail-closed audit gate: inventory complete and authority counts match. -/
@[pf_inline] def auditOk (paths sources : UInt64) : Bool :=
  isComplete && treeMatchesAuthority paths sources

end ProofForge.Evm.Sdk.OzAudit
