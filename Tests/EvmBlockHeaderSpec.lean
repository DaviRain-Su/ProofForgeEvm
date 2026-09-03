import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.HeaderLink

/-!
W5 slice d: bounded Blockhash/BlockHeader profile — header field views and fail-closed history
window for `BLOCKHASH`.
-/

namespace Tests.EvmBlockHeaderSpec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard BlockHeader.historyDepth == 256
#guard BlockHeader.isInHistoryWindow 0
#guard !BlockHeader.isZeroHash ⟨1, 0, 0, 0⟩
#guard BlockHeader.isZeroHash ⟨0, 0, 0, 0⟩

private def expectHeaderLink : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.HeaderLink with
    | .ok source => pure source
    | .error reason => throwError reason
  for ixName in #[
      "number", "timestamp", "baseFee", "prevRandao", "gasLimit", "coinbase",
      "blockHash", "inHistoryWindow", "touch"
    ] do
    unless source.methods.any (·.ixName == ixName) do
      throwError s!"HeaderLink is missing {ixName}"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"blockHash\"" &&
      abi.contains "\"name\":\"inHistoryWindow\"" &&
      abi.contains "\"name\":\"coinbase\"" do
    throwError s!"HeaderLink ABI lost header surface:\n{abi}"
  unless IR.digestHex program == "8889343b4fdf7c4a" do
    throwError s!"HeaderLink digest drifted: {IR.digestHex program}"
  logInfo m!"headerlink: digest={IR.digestHex program} abi-ok"

elab "#pf_guard_evm_block_header" : command => expectHeaderLink

#pf_guard_evm_block_header

#pf_evm_build Examples.Evm.HeaderLink

end Tests.EvmBlockHeaderSpec
