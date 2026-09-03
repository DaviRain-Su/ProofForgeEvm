import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.Collectible
import Examples.Evm.Badge
import Examples.Evm.MultiToken
import Examples.Evm.CraftToken

/-!
W1 ERC-165 gate. The SDK comparison is bounded to four `UInt64` carrier limbs and each adopted
example must expose a Solidity-shaped `supportsInterface(bytes4) -> bool` view in its ABI.
Live calldata/return decoding is covered by the corresponding Anvil scripts.
-/

namespace Tests.EvmErc165Spec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard Erc165.equal Erc165.erc165 Erc165.erc165
#guard Erc165.equal Erc165.erc721 Erc165.erc721
#guard Erc165.equal Erc165.erc1155 Erc165.erc1155
#guard !Erc165.equal Erc165.erc721 Erc165.erc1155
#guard Erc165.supportsToken Erc165.erc165 Erc165.erc721
#guard Erc165.supportsToken Erc165.erc721 Erc165.erc721
#guard !Erc165.supportsToken Erc165.erc1155 Erc165.erc721

private def expectErc165Abi (moduleName : Name) (tokenId : Erc165.InterfaceId) :
    CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env moduleName with
    | .ok source => pure source
    | .error reason => throwError reason
  let some method := source.methods.find? (·.ixName == "supportsInterface")
    | throwError s!"{moduleName} is missing supportsInterface"
  unless method.paramTypes == #[.fixedBytes 4] && method.retTypes == #[.boolean] do
    throwError s!"{moduleName}.supportsInterface lost its bytes4/bool source boundary"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"supportsInterface\"" &&
      abi.contains "\"name\":\"interfaceId\",\"type\":\"bytes4\"" &&
      abi.contains "\"type\":\"bool\"" do
    throwError s!"{moduleName} ABI lost supportsInterface(bytes4) -> bool:\n{abi}"
  let supportOps := (program.entries.find? (·.ixName == "supportsInterface")).get!.ops
  unless supportOps.size > 0 && (program.entries.map (·.ixName)).contains "supportsInterface" do
    throwError s!"{moduleName}.supportsInterface did not lower to EVM operations"
  -- Keep the exact intended profile present in extracted source. This avoids an ABI-only stub.
  unless Erc165.supportsToken tokenId tokenId do
    throwError s!"{moduleName} lost its static token interface declaration"

private def expectErc165 : CommandElabM Unit := do
  expectErc165Abi `Examples.Evm.Collectible Erc165.erc721
  expectErc165Abi `Examples.Evm.Badge Erc165.erc721
  expectErc165Abi `Examples.Evm.MultiToken Erc165.erc1155
  expectErc165Abi `Examples.Evm.CraftToken Erc165.erc1155

elab "#pf_guard_evm_erc165" : command => expectErc165

#pf_guard_evm_erc165

#pf_evm_build Examples.Evm.Collectible
#pf_evm_build Examples.Evm.Badge
#pf_evm_build Examples.Evm.MultiToken
#pf_evm_build Examples.Evm.CraftToken

end Tests.EvmErc165Spec
