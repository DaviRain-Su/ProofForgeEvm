import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.Auth3009Link

/-!
W5 slice e: bounded ERC-3009 transfer-with-authorization — typed closed-call profile over static
address/uint256/bytes32/v/r/s operands reusing EIP-712 domain and ecrecover.
-/

namespace Tests.EvmErc3009Spec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard Erc3009.domainSeparator == Permit.domainSeparator

private def expectAuth3009Link : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.Auth3009Link with
    | .ok source => pure source
    | .error reason => throwError reason
  for ixName in #[
      "DOMAIN_SEPARATOR", "balanceOf", "mint", "totalSupply",
      "transferWithAuthorization"
    ] do
    unless source.methods.any (·.ixName == ixName) do
      throwError s!"Auth3009Link is missing {ixName}"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"transferWithAuthorization\"" &&
      abi.contains "\"name\":\"DOMAIN_SEPARATOR\"" do
    throwError s!"Auth3009Link ABI lost ERC-3009 surface:\n{abi}"
  unless IR.digestHex program == "c0188e81405c51f5" do
    throwError s!"Auth3009Link digest drifted: {IR.digestHex program}"

elab "#pf_guard_evm_erc3009" : command => expectAuth3009Link

#pf_guard_evm_erc3009

#pf_evm_build Examples.Evm.Auth3009Link

end Tests.EvmErc3009Spec
