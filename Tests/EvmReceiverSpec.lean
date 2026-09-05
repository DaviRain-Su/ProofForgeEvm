import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.ReceiverLink

/-!
Receiving-side ERC-721/1155 hooks: `ReceiverLink` answers `onERC721Received`,
`onERC1155Received`, and `onERC1155BatchReceived` with each selector as `Bytes4`.
The live matrix against Collectible, CraftToken, and MultiToken lives in
`runtime-tests/evm/anvil_receiverlink.sh`.
-/

namespace Tests.EvmReceiverSpec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open ProofForge.Core.Value
open Lean Elab Command

#guard Erc721.onReceivedSelector == (⟨0x027a0b15, 0, 0, 0⟩ : Bytes4)
#guard Erc1155.onReceivedSelector == (⟨0x616e3af2, 0, 0, 0⟩ : Bytes4)
#guard Erc1155.onBatchReceivedSelector == (⟨0x817c19bc, 0, 0, 0⟩ : Bytes4)
#guard Erc165.erc721Receiver == Erc721.onReceivedSelector
#guard Erc165.erc1155Receiver == (⟨0xe012234e, 0, 0, 0⟩ : Bytes4)
#guard Erc165.supports3 Erc165.erc165 Erc165.erc165 Erc165.erc721Receiver Erc165.erc1155Receiver
#guard Erc165.supports3 Erc165.erc721Receiver Erc165.erc165 Erc165.erc721Receiver
  Erc165.erc1155Receiver
#guard Erc165.supports3 Erc165.erc1155Receiver Erc165.erc165 Erc165.erc721Receiver
  Erc165.erc1155Receiver
#guard OzAudit.temporaryGapCount == 0
#guard Registry.digestOf "ReceiverLink" == some "9457ca840a166ba3"

private def expectMethodNames (program : IR.Program) (names : Array String) :
    CommandElabM Unit := do
  let got := program.entries.map (·.ixName)
  unless got.size == names.size && names.all (got.contains ·) && got.all (names.contains ·) do
    throwError s!"{program.name} method ABI diverged: {got}"

private def expectReceiverLink : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.ReceiverLink with
    | .ok source => pure source
    | .error reason => throwError reason
  unless ProofForge.Evm.Keccak.selector "onERC721Received"
      #["address", "address", "uint256", "bytes"] == "150b7a02" do
    throwError "onERC721Received selector drifted"
  unless ProofForge.Evm.Keccak.selector "onERC1155Received"
      #["address", "address", "uint256", "uint256", "bytes"] == "f23a6e61" do
    throwError "onERC1155Received selector drifted"
  unless ProofForge.Evm.Keccak.selector "onERC1155BatchReceived"
      #["address", "address", "uint256[]", "uint256[]", "bytes"] == "bc197c81" do
    throwError "onERC1155BatchReceived selector drifted"
  let evm ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  expectMethodNames evm
    #["onERC721Received", "onERC1155Received", "onERC1155BatchReceived",
      "seenOperator", "seenFrom", "seenId", "seenValue", "seenDataLen", "supportsInterface"]
  let abi ←
    match Emit.emitAbiChecked evm with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"onERC721Received\"" &&
      abi.contains "\"name\":\"onERC1155Received\"" &&
      abi.contains "\"name\":\"onERC1155BatchReceived\"" &&
      abi.contains "\"type\":\"bytes4\"" &&
      abi.contains "\"type\":\"uint256[]\"" &&
      abi.contains "\"type\":\"bytes\"" do
    throwError s!"ReceiverLink ABI lost a hook:\n{abi}"
  let yul ←
    match Emit.emitYul evm with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless yul.contains "pf_store_fixed_bytes(0, " && yul.contains "return(0, 32)" &&
      !yul.contains "return(0, 128)" do
    throwError "ReceiverLink Yul lost the left-aligned bytes4 return"
  unless IR.digestHex evm == "9457ca840a166ba3" do
    throwError s!"ReceiverLink digest drifted: {IR.digestHex evm}"
  logInfo m!"receiverlink: digest={IR.digestHex evm} abi-ok"

elab "#pf_guard_evm_receiver" : command => expectReceiverLink

#pf_guard_evm_receiver

#pf_evm_build Examples.Evm.ReceiverLink

end Tests.EvmReceiverSpec
