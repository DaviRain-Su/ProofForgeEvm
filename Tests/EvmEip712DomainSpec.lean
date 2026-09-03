import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.DomainLink

/-!
W4 slice 2: EIP-5267-style static domain fields — bounded name/version, runtime chainId and
verifyingContract, zero salt, fail-closed publish gates.
-/

namespace Tests.EvmEip712DomainSpec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open ProofForge.Core.Value
open Lean Elab Command

#guard Eip712Domain.defaultNameCapacity == 32
#guard Eip712Domain.defaultVersionCapacity == 8
#guard Eip712Domain.fieldsMask == 0x0f
#guard Eip712Domain.emptyName.length == 0
#guard Eip712Domain.emptyVersion.length == 0
#guard Eip712Domain.wellFormedName Examples.Evm.DomainLink.domainName
#guard Eip712Domain.wellFormedVersion Examples.Evm.DomainLink.domainVersion
#guard Eip712Domain.canPublish Examples.Evm.DomainLink.domainName Examples.Evm.DomainLink.domainVersion
#guard !Eip712Domain.canPublish Eip712Domain.emptyName Examples.Evm.DomainLink.domainVersion
#guard !Eip712Domain.canPublish Examples.Evm.DomainLink.domainName Eip712Domain.emptyVersion

private def invalidUtf8Version : Eip712Domain.Version :=
  { length := 2, values := #v[0xc0, 0x80, 0, 0, 0, 0, 0, 0] }

#guard !Eip712Domain.canPublish Examples.Evm.DomainLink.domainName invalidUtf8Version
#guard Eip712Domain.selectFields Examples.Evm.DomainLink.domainName Examples.Evm.DomainLink.domainVersion == 0x0f
#guard Eip712Domain.selectFields Eip712Domain.emptyName Eip712Domain.emptyVersion == 0

private def expectDomainLink : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.DomainLink with
    | .ok source => pure source
    | .error reason => throwError reason
  for ixName in
      #["eip712DomainFields", "eip712DomainName", "eip712DomainVersion",
        "eip712DomainChainId", "eip712DomainVerifyingContract", "eip712DomainSalt",
        "DOMAIN_SEPARATOR"] do
    unless source.methods.any (·.ixName == ixName) do
      throwError s!"DomainLink is missing {ixName}"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let some fieldsEntry := program.entries.find? (·.ixName == "eip712DomainFields")
    | throwError "DomainLink EVM IR lost eip712DomainFields"
  unless fieldsEntry.selector ==
      ProofForge.Crypto.Keccak.selector "eip712DomainFields" #[] do
    throwError s!"eip712DomainFields selector drifted: {fieldsEntry.selector}"
  unless fieldsEntry.retTypes == #[.uint 8] do
    throwError s!"eip712DomainFields return types drifted: {repr fieldsEntry.retTypes}"
  let some nameEntry := program.entries.find? (·.ixName == "eip712DomainName")
    | throwError "DomainLink EVM IR lost eip712DomainName"
  unless nameEntry.outputPlan == some (.dynamic (.packedBytes { capacity := 32, validateUtf8 := true })) do
    throwError s!"eip712DomainName output plan drifted: {repr nameEntry.outputPlan}"
  let some versionEntry := program.entries.find? (·.ixName == "eip712DomainVersion")
    | throwError "DomainLink EVM IR lost eip712DomainVersion"
  unless versionEntry.outputPlan == some (.dynamic (.packedBytes { capacity := 8, validateUtf8 := true })) do
    throwError s!"eip712DomainVersion output plan drifted: {repr versionEntry.outputPlan}"
  let some chainEntry := program.entries.find? (·.ixName == "eip712DomainChainId")
    | throwError "DomainLink EVM IR lost eip712DomainChainId"
  unless chainEntry.retTypes == #[.uint 256] do
    throwError s!"eip712DomainChainId return types drifted: {repr chainEntry.retTypes}"
  let some contractEntry := program.entries.find? (·.ixName == "eip712DomainVerifyingContract")
    | throwError "DomainLink EVM IR lost eip712DomainVerifyingContract"
  unless contractEntry.retTypes == #[.address 20] do
    throwError s!"eip712DomainVerifyingContract return types drifted: {repr contractEntry.retTypes}"
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"eip712DomainFields\"" &&
      abi.contains "\"name\":\"eip712DomainName\"" &&
      abi.contains "\"name\":\"eip712DomainVersion\"" &&
      abi.contains "\"name\":\"eip712DomainChainId\"" &&
      abi.contains "\"name\":\"eip712DomainVerifyingContract\"" &&
      abi.contains "\"name\":\"eip712DomainSalt\"" &&
      abi.contains "\"name\":\"DOMAIN_SEPARATOR\"" do
    throwError s!"DomainLink ABI lost domain field surface:\n{abi}"
  unless !abi.contains "\"name\":\"permit\"" do
    throwError "DomainLink must not grow a permit mutation surface"
  unless IR.digestHex program == "52e88ad42d5a8789" do
    throwError s!"DomainLink digest drifted: {IR.digestHex program}"
  logInfo m!"domainlink: digest={IR.digestHex program} abi-ok"

elab "#pf_guard_evm_eip712_domain" : command => expectDomainLink

#pf_guard_evm_eip712_domain

#pf_evm_build Examples.Evm.DomainLink

end Tests.EvmEip712DomainSpec
