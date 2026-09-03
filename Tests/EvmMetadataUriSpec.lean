import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.ArtLink
import Examples.Evm.PackLink

/-!
W4 slice 1b: bounded static metadata URI profile — ERC-721 `tokenURI` with mint-state
fail-closed gates and ERC-1155 `uri` consumer using `MetadataUri`.
-/

namespace Tests.EvmMetadataUriSpec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open ProofForge.Core.Value
open Lean Elab Command

#guard MetadataUri.defaultCapacity == 32
#guard MetadataUri.empty.length == 0
#guard MetadataUri.wellFormed Examples.Evm.ArtLink.baseUri
#guard MetadataUri.wellFormed Examples.Evm.PackLink.baseUri
#guard !MetadataUri.canRespond721 Examples.Evm.ArtLink.owners ⟨0, 0, 0, 1⟩
#guard MetadataUri.canRespond1155 ⟨1, 0, 0, 0⟩
#guard !MetadataUri.canRespond1155 ⟨0, 0, 0, 1⟩

private def expectArtLink : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.ArtLink with
    | .ok source => pure source
    | .error reason => throwError reason
  unless source.methods.any (·.ixName == "tokenURI") do
    throwError "ArtLink is missing tokenURI"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let some tokenUri := program.entries.find? (·.ixName == "tokenURI")
    | throwError "ArtLink EVM IR lost tokenURI"
  unless tokenUri.selector == ProofForge.Crypto.Keccak.selector "tokenURI" #["uint256"] do
    throwError s!"tokenURI selector drifted: {tokenUri.selector}"
  unless tokenUri.outputPlan == some (.dynamic (.packedBytes { capacity := 32, validateUtf8 := true })) do
    throwError s!"tokenURI output plan drifted: {repr tokenUri.outputPlan}"
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"tokenURI\"" && abi.contains "\"type\":\"string\"" do
    throwError s!"ArtLink ABI lost tokenURI string output:\n{abi}"
  unless !abi.contains "\"name\":\"uri\"" do
    throwError "ArtLink must not grow ERC-1155 uri surface"
  unless IR.digestHex program == "e95d5b45be20b193" do
    throwError s!"ArtLink digest drifted: {IR.digestHex program}"
  logInfo m!"artlink: digest={IR.digestHex program} abi-ok"

private def expectPackLink : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.PackLink with
    | .ok source => pure source
    | .error reason => throwError reason
  unless source.methods.any (·.ixName == "uri") do
    throwError "PackLink is missing uri"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let some uriEntry := program.entries.find? (·.ixName == "uri")
    | throwError "PackLink EVM IR lost uri"
  unless uriEntry.selector == ProofForge.Crypto.Keccak.selector "uri" #["uint256"] do
    throwError s!"uri selector drifted: {uriEntry.selector}"
  unless uriEntry.outputPlan == some (.dynamic (.packedBytes { capacity := 32, validateUtf8 := true })) do
    throwError s!"uri output plan drifted: {repr uriEntry.outputPlan}"
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"uri\"" && abi.contains "\"type\":\"string\"" do
    throwError s!"PackLink ABI lost uri string output:\n{abi}"
  unless !abi.contains "\"name\":\"tokenURI\"" do
    throwError "PackLink must not grow ERC-721 tokenURI surface"
  unless IR.digestHex program == "58b4fe91408c541e" do
    throwError s!"PackLink digest drifted: {IR.digestHex program}"
  logInfo m!"packlink: digest={IR.digestHex program} abi-ok"

private def expectMetadataUri : CommandElabM Unit := do
  expectArtLink
  expectPackLink

elab "#pf_guard_evm_metadata_uri" : command => expectMetadataUri

#pf_guard_evm_metadata_uri

#pf_evm_build Examples.Evm.ArtLink
#pf_evm_build Examples.Evm.PackLink

end Tests.EvmMetadataUriSpec
