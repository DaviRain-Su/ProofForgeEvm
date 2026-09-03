import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.ClockLink

/-!
W5 slice 5b: IERC6372 `clock()` / `CLOCK_MODE()` bounded strings from Context block fields.
-/

namespace Tests.EvmIerc6372Spec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open ProofForge.Core.Value
open Lean Elab Command

#guard Ierc6372.defaultModeCapacity == 32
#guard Ierc6372.canPublish Ierc6372.ClockKind.blockNumber
#guard Ierc6372.canPublish Ierc6372.ClockKind.timestamp
#guard (Ierc6372.selectMode Ierc6372.ClockKind.blockNumber).length == 29
#guard (Ierc6372.selectMode Ierc6372.ClockKind.timestamp).length == 28
#guard Ierc6372.wellFormedMode Ierc6372.blockNumberMode
#guard Ierc6372.wellFormedMode Ierc6372.timestampMode
#guard Ierc6372.blockNumberMode.length == 29
#guard Ierc6372.timestampMode.length == 28

private def expectClockLink : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.ClockLink with
    | .ok source => pure source
    | .error reason => throwError reason
  for ixName in #["clock", "CLOCK_MODE"] do
    unless source.methods.any (·.ixName == ixName) do
      throwError s!"ClockLink is missing {ixName}"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let some clockEntry := program.entries.find? (·.ixName == "clock")
    | throwError "ClockLink EVM IR lost clock"
  unless clockEntry.retTypes == #[.uint 64] do
    throwError s!"clock return types drifted: {repr clockEntry.retTypes}"
  let some modeEntry := program.entries.find? (·.ixName == "CLOCK_MODE")
    | throwError "ClockLink EVM IR lost CLOCK_MODE"
  unless modeEntry.outputPlan == some (.dynamic (.packedBytes { capacity := 32, validateUtf8 := true })) do
    throwError s!"CLOCK_MODE output plan drifted: {repr modeEntry.outputPlan}"
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"clock\"" && abi.contains "\"name\":\"CLOCK_MODE\"" do
    throwError s!"ClockLink ABI lost clock surface:\n{abi}"
  unless IR.digestHex program == "6aaaa4e3809c1df5" do
    throwError s!"ClockLink digest drifted: {IR.digestHex program}"
  logInfo m!"clocklink: digest={IR.digestHex program} abi-ok"

elab "#pf_guard_evm_ierc6372" : command => expectClockLink

#pf_guard_evm_ierc6372

#pf_evm_build Examples.Evm.ClockLink

end Tests.EvmIerc6372Spec
