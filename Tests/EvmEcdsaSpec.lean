import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import ProofForge.Evm.Precompile
import Examples.Evm.RecoverLink

/-!
W5 slice 5b: public typed ECDSA recover SDK facade + minimal RecoverLink consumer.
-/

namespace Tests.EvmEcdsaSpec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard Precompile.Plan.ecrecover.wellFormed

private def expectRecoverLink : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.RecoverLink with
    | .ok source => pure source
    | .error reason => throwError reason
  unless source.methods.any (·.ixName == "recover") do
    throwError "RecoverLink is missing recover"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let some recoverEntry := program.entries.find? (·.ixName == "recover")
    | throwError "RecoverLink EVM IR lost recover"
  unless recoverEntry.selector ==
      ProofForge.Crypto.Keccak.selector "recover" #["bytes32", "uint8", "bytes32", "bytes32"] do
    throwError s!"recover selector drifted: {recoverEntry.selector}"
  unless recoverEntry.retTypes == #[.address 20] do
    throwError s!"recover return types drifted: {repr recoverEntry.retTypes}"
  let yul ←
    match Emit.emitYul program with
    | .ok txt => pure txt
    | .error reason => throwError reason
  unless yul.contains " := staticcall(gas(), 1, 0, 128, 0, 32)\n" &&
      yul.contains "if iszero(eq(returndatasize(), 32)) { revert(0, 0) }" do
    throwError "RecoverLink must spell the closed ecrecover precompile contract"
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"recover\"" do
    throwError s!"RecoverLink ABI lost recover():\n{abi}"
  unless IR.digestHex program == "c3097c1dfd4fd261" do
    throwError s!"RecoverLink digest drifted: {IR.digestHex program}"
  logInfo m!"recoverlink: digest={IR.digestHex program} abi-ok"

elab "#pf_guard_evm_ecdsa" : command => expectRecoverLink

#pf_guard_evm_ecdsa

#pf_evm_build Examples.Evm.RecoverLink

end Tests.EvmEcdsaSpec
