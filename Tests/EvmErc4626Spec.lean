import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.Vault4626Link

namespace Tests.EvmErc4626Spec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard Erc4626.canVault Address.zero == false

private def expectVault4626Link : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.Vault4626Link with
    | .ok source => pure source
    | .error reason => throwError reason
  for ixName in #["asset", "totalAssets", "deposit", "redeem", "balanceOf", "totalSupply"] do
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
  logInfo m!"vault4626link: digest={IR.digestHex program} abi-ok"

elab "#pf_guard_evm_erc4626" : command => expectVault4626Link

#pf_guard_evm_erc4626

#pf_evm_build Examples.Evm.Vault4626Link

end Tests.EvmErc4626Spec
