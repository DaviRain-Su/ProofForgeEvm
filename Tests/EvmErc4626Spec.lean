import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.Vault4626Link

namespace Tests.EvmErc4626Spec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

private def expectVault4626Link : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.Vault4626Link with
    | .ok source => pure source
    | .error reason => throwError reason
  for ixName in #["asset", "totalAssets", "deposit", "redeem", "balanceOf",
      "totalSupply", "convertToShares", "convertToAssets"] do
    unless source.methods.any (·.ixName == ixName) do
      throwError s!"Vault4626Link is missing {ixName}"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"Deposit\"" && abi.contains "\"name\":\"Withdraw\"" do
    throwError s!"Vault4626Link ABI lost vault surface:\n{abi}"
  let rec collectStores (fuel : Nat) (ops : Array IR.Op) (acc : Array String) : Array String :=
    match fuel with
    | 0 => acc
    | fuel' + 1 =>
      ops.foldl (init := acc) fun acc op =>
        match op with
        | .storeField actual _ => acc.push actual
        | .ite _ _ _ thn els =>
            collectStores fuel' els (collectStores fuel' thn acc)
        | .forBody _ body => collectStores fuel' body acc
        | _ => acc
  let some deposit := program.entries.find? (·.ixName == "deposit")
    | throwError "Vault4626Link is missing deposit"
  let names := collectStores 64 deposit.ops #[]
  unless names.any (· == "totalShares_w0") do
    throwError s!"Vault4626Link.deposit stores {names} but not totalShares_w0"
  logInfo m!"vault4626link: digest={IR.digestHex program} abi-ok"

elab "#pf_guard_evm_erc4626" : command => expectVault4626Link

#pf_guard_evm_erc4626

#pf_evm_build Examples.Evm.Vault4626Link

end Tests.EvmErc4626Spec
