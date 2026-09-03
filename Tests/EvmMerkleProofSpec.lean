import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.ProofLink

/-!
W4 slice 4: bounded Merkle proof verification — sorted pair hashing, fixed-capacity
proof frame, fail-closed root/proof gates.
-/

namespace Tests.EvmMerkleProofSpec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open ProofForge.Core.Value
open Lean Elab Command

private def leafA : Bytes32 := MerkleProof.fromKeccakUtf8 "pf-leaf-a"

private def leafB : Bytes32 := MerkleProof.fromKeccakUtf8 "pf-leaf-b"

private def leafC : Bytes32 := MerkleProof.fromKeccakUtf8 "pf-leaf-c"

private def pairRoot : Bytes32 :=
  MerkleProof.hashPairPure leafA leafB

private def singletonProof : MerkleProof.Proof :=
  { length := 1, values := #v[leafB, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩] }

private def reverseProof : MerkleProof.Proof :=
  { length := 1, values := #v[leafA, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩] }

private def twoProof : MerkleProof.Proof :=
  { length := 2, values := #v[leafB, leafC, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩] }

private def malformedProof : MerkleProof.Proof :=
  { length := 9, values := #v[leafB, leafC, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩, ⟨0, 0, 0, 0⟩] }

#guard MerkleProof.defaultDepth == 8
#guard MerkleProof.wellFormedRoot pairRoot
#guard !MerkleProof.wellFormedRoot ⟨0, 0, 0, 0⟩
#guard MerkleProof.wellFormedProof singletonProof
#guard !MerkleProof.wellFormedProof malformedProof
#guard pairRoot == ⟨0xdad2bcfb1a1ede11, 0x3a60116d796036e0, 0x423faf256908cace, 0xab5ed13baaeb2950⟩
#guard MerkleProof.hashPairPure leafA leafB == MerkleProof.hashPairPure leafB leafA
#guard MerkleProof.verifyPure pairRoot leafA singletonProof
#guard MerkleProof.verifyPure pairRoot leafB reverseProof
#guard !MerkleProof.verifyPure pairRoot leafB singletonProof
#guard MerkleProof.verifyPure (MerkleProof.processProofPure leafA twoProof) leafA twoProof
#guard !MerkleProof.canVerify ⟨0, 0, 0, 0⟩ leafA singletonProof

private def expectProofLink : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.ProofLink with
    | .ok source => pure source
    | .error reason => throwError reason
  for ixName in #["rootOf", "verify", "touch"] do
    unless source.methods.any (·.ixName == ixName) do
      throwError s!"ProofLink is missing {ixName}"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let some verifyEntry := program.entries.find? (·.ixName == "verify")
    | throwError "ProofLink EVM IR lost verify"
  unless verifyEntry.selector == ProofForge.Crypto.Keccak.selector "verify" #["bytes32[]", "bytes32"] do
    throwError s!"verify selector drifted: {verifyEntry.selector}"
  let yul ←
    match Emit.emitYul program with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless yul.contains "keccak256(0, 64)" do
    throwError "ProofLink verify must emit sorted pair keccak256"
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"rootOf\"" &&
      abi.contains "\"name\":\"verify\"" &&
      abi.contains "\"type\":\"bytes32[]\"" do
    throwError s!"ProofLink ABI lost Merkle surface:\n{abi}"
  unless IR.digestHex program == "c41e5e834c987462" do
    throwError s!"ProofLink digest drifted: {IR.digestHex program}"
  logInfo m!"prooflink: digest={IR.digestHex program} abi-ok keccak-ok"

elab "#pf_guard_evm_merkle" : command => expectProofLink

#pf_guard_evm_merkle

#pf_evm_build Examples.Evm.ProofLink

end Tests.EvmMerkleProofSpec
