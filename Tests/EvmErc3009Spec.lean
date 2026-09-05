import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.Auth3009Link

/-!
W5 slice e plus this expansion: bounded ERC-3009 transfer-with-authorization and
receive-with-authorization. Receive uses a distinct EIP-712 typehash and `caller == to`.
Cancellation stays out.
-/

namespace Tests.EvmErc3009Spec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard Erc3009.domainSeparator == Permit.domainSeparator

private def authUsedTopic : String :=
  ProofForge.Crypto.Keccak.keccak256HexOfString "AuthorizationUsed(address,bytes32)"

private def receiveTypeHash : String :=
  ProofForge.Crypto.Keccak.keccak256HexOfString
    "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"

private def transferTypeHash : String :=
  ProofForge.Crypto.Keccak.keccak256HexOfString
    "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"

#guard receiveTypeHash != transferTypeHash

private def expectAuth3009Link : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.Auth3009Link with
    | .ok source => pure source
    | .error reason => throwError reason
  for ixName in #[
      "DOMAIN_SEPARATOR", "balanceOf", "mint", "totalSupply",
      "transferWithAuthorization", "receiveWithAuthorization"
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
      abi.contains "\"name\":\"receiveWithAuthorization\"" &&
      abi.contains "\"name\":\"DOMAIN_SEPARATOR\"" do
    throwError s!"Auth3009Link ABI lost ERC-3009 surface:\n{abi}"
  let yul ←
    match Emit.emitYul program with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless yul.contains s!"0x{authUsedTopic}" &&
      yul.contains "iszero(gt(timestamp()" &&
      yul.contains "iszero(lt(timestamp()" do
    throwError "Auth3009Link Yul missing AuthorizationUsed or exclusive validity bounds"
  unless yul.contains s!"0x{receiveTypeHash}" &&
      yul.contains ":= caller()" do
    throwError "Auth3009Link Yul missing ReceiveWithAuthorization typehash or caller-is-payee gate"
  unless IR.digestHex program == "3f8b259e6f5b6c23" do
    throwError s!"Auth3009Link digest drifted: {IR.digestHex program}"

elab "#pf_guard_evm_erc3009" : command => expectAuth3009Link

#pf_guard_evm_erc3009

#pf_evm_build Examples.Evm.Auth3009Link

end Tests.EvmErc3009Spec
