import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.VestLink

/-!
W4 slice 3: bounded single-beneficiary native-ETH vesting — linear schedule, releasable
accounting, fail-closed schedule gates, EtherReleased typed event.
-/

namespace Tests.EvmVestingSpec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard Vesting.wellFormedDuration (100 : UInt64) (900 : UInt64)
#guard !Vesting.wellFormedBeneficiary Address.zero
#guard !Vesting.canSchedule Address.zero (100 : UInt64) (900 : UInt64)
#guard Vesting.endAt (100 : UInt64) (900 : UInt64) == (1000 : UInt64)

private def expectVestLink : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.VestLink with
    | .ok source => pure source
    | .error reason => throwError reason
  for ixName in
      #["beneficiary", "start", "duration", "endTime", "releasedOf", "releasable", "vestedAmount",
        "release", "receive"] do
    unless source.methods.any (·.ixName == ixName) do
      throwError s!"VestLink is missing {ixName}"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let some releasableEntry := program.entries.find? (·.ixName == "releasable")
    | throwError "VestLink EVM IR lost releasable"
  unless releasableEntry.retTypes == #[.uint 256] do
    throwError s!"releasable return types drifted: {repr releasableEntry.retTypes}"
  let some releaseEntry := program.entries.find? (·.ixName == "release")
    | throwError "VestLink EVM IR lost release"
  unless releaseEntry.selector == ProofForge.Crypto.Keccak.selector "release" #["uint256"] do
    throwError s!"release selector drifted: {releaseEntry.selector}"
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"beneficiary\"" &&
      abi.contains "\"name\":\"start\"" &&
      abi.contains "\"name\":\"duration\"" &&
      abi.contains "\"name\":\"endTime\"" &&
      abi.contains "\"name\":\"releasedOf\"" &&
      abi.contains "\"name\":\"releasable\"" &&
      abi.contains "\"name\":\"vestedAmount\"" &&
      abi.contains "\"name\":\"release\"" &&
      abi.contains "\"type\":\"receive\"" &&
      abi.contains "\"name\":\"EtherReleased\"" do
    throwError s!"VestLink ABI lost vesting surface:\n{abi}"
  unless !abi.contains "\"name\":\"royaltyInfo\"" do
    throwError "VestLink must not grow a royalty surface"
  unless IR.digestHex program == "f7868e5f9647638f" do
    throwError s!"VestLink digest drifted: {IR.digestHex program}"
  logInfo m!"vestlink: digest={IR.digestHex program} abi-ok"

elab "#pf_guard_evm_vesting" : command => expectVestLink

#pf_guard_evm_vesting

#pf_evm_build Examples.Evm.VestLink

end Tests.EvmVestingSpec
