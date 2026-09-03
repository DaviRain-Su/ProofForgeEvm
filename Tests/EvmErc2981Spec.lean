import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.RoyaltyArt

/-!
W2 static ERC-2981 gate. The profile must publish `royaltyInfo(uint256,uint256) -> (address,uint256)`
and advertise IERC165 + IERC2981 only.
-/

namespace Tests.EvmErc2981Spec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard Erc165.erc2981 == ⟨0x5a20552a, 0, 0, 0⟩
#guard Erc2981.interfaceId == Erc165.erc2981
#guard Erc2981.feeDenominator == ⟨10000, 0, 0, 0⟩
#guard Examples.Evm.RoyaltyArt.feeNumerator == ⟨250, 0, 0, 0⟩
#guard Erc165.supportsRoyalty Erc165.erc165
#guard Erc165.supportsRoyalty Erc165.erc2981

private def expectRoyaltyArt : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.RoyaltyArt with
    | .ok source => pure source
    | .error reason => throwError reason
  unless source.methods.any (·.ixName == "royaltyInfo") do
    throwError "RoyaltyArt is missing royaltyInfo"
  let some support := source.methods.find? (·.ixName == "supportsInterface")
    | throwError "RoyaltyArt is missing supportsInterface"
  unless support.paramTypes == #[.fixedBytes 4] && support.retTypes == #[.boolean] do
    throwError s!"RoyaltyArt.supportsInterface lost its bytes4/bool source boundary"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let some royalty := program.entries.find? (·.ixName == "royaltyInfo")
    | throwError "RoyaltyArt EVM IR lost royaltyInfo"
  unless royalty.selector == ProofForge.Crypto.Keccak.selector "royaltyInfo" #["uint256", "uint256"] do
    throwError s!"royaltyInfo selector drifted: {royalty.selector}"
  unless royalty.retTypes == #[.address 20, .uint 256] do
    throwError s!"royaltyInfo return types drifted: {repr royalty.retTypes}"
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"royaltyInfo\"" do
    throwError s!"RoyaltyArt ABI lost royaltyInfo:\n{abi}"
  unless abi.contains "\"name\":\"supportsInterface\"" do
    throwError s!"RoyaltyArt ABI lost supportsInterface:\n{abi}"
  unless abi.contains "\"type\":\"address\"" && abi.contains "\"type\":\"uint256\"" do
    throwError s!"RoyaltyArt ABI lost address/uint256 royalty outputs:\n{abi}"
  unless !abi.contains "\"name\":\"tokenURI\"" do
    throwError "RoyaltyArt must not grow a metadata URI surface"
  unless IR.digestHex program == "89fe67825f5f9c28" do
    throwError s!"RoyaltyArt digest drifted: {IR.digestHex program}"
  logInfo m!"royaltyart: digest={IR.digestHex program} abi-ok"

elab "#pf_guard_evm_erc2981" : command => expectRoyaltyArt

#pf_guard_evm_erc2981

#pf_evm_build Examples.Evm.RoyaltyArt

end Tests.EvmErc2981Spec
