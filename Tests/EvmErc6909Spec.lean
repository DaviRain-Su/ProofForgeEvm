import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.NineLink

namespace Tests.EvmErc6909Spec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard Erc6909.matchesId ⟨7, 0, 0, 0⟩ ⟨7, 0, 0, 0⟩

private def expectNineLink : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.NineLink with
    | .ok source => pure source
    | .error reason => throwError reason
  for ixName in #["tokenId", "balanceOf", "allowance", "isOperator", "mint", "transfer"] do
    unless source.methods.any (·.ixName == ixName) do
      throwError s!"NineLink is missing {ixName}"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"Transfer\"" && abi.contains "\"name\":\"OperatorSet\"" do
    throwError s!"NineLink ABI lost ERC-6909 surface:\n{abi}"
  logInfo m!"ninelink: digest={IR.digestHex program} abi-ok"

elab "#pf_guard_evm_erc6909" : command => expectNineLink

#pf_guard_evm_erc6909

#pf_evm_build Examples.Evm.NineLink

end Tests.EvmErc6909Spec
