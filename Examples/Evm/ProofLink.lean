import ProofForge.Evm.Sdk
import ProofForge.Core.Value

/-!
Bounded Merkle proof consumer. Constructor stores the trusted root; `verify` folds the active
prefix of a depth-8 `bytes32[]` proof using OpenZeppelin-style sorted pair hashing. The ABI decoder
rejects over-capacity arrays, and source policy independently rejects malformed frames and zero
roots before comparing all four computed root limbs.
-/

namespace Examples.Evm.ProofLink
open ProofForge.Evm.Sdk
open ProofForge.Core.Value

structure State where
  root0 : UInt64
  root1 : UInt64
  root2 : UInt64
  root3 : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_entry]
def init (root : Bytes32) : State :=
  { root0 := root.w0, root1 := root.w1, root2 := root.w2, root3 := root.w3 }

@[pf_entry]
def rootOf (s : State) : Bytes32 :=
  ⟨s.root0, s.root1, s.root2, s.root3⟩

@[pf_entry]
def verify (s : State) (proof : BoundedVec Bytes32 8) (leaf : Bytes32) : Bool :=
  if (s.root0 == 0 && s.root1 == 0 && s.root2 == 0 && s.root3 == 0) ||
      proof.length.toUInt64 > 8 then
    false
  else
    let p1 := MerkleProof.hashPair leaf proof.values[0]!
    let h1 : Bytes32 :=
      ⟨if proof.length.toUInt64 > 0 then p1.w0 else leaf.w0,
       if proof.length.toUInt64 > 0 then p1.w1 else leaf.w1,
       if proof.length.toUInt64 > 0 then p1.w2 else leaf.w2,
       if proof.length.toUInt64 > 0 then p1.w3 else leaf.w3⟩
    let p2 := MerkleProof.hashPair h1 proof.values[1]!
    let h2 : Bytes32 :=
      ⟨if proof.length.toUInt64 > 1 then p2.w0 else h1.w0,
       if proof.length.toUInt64 > 1 then p2.w1 else h1.w1,
       if proof.length.toUInt64 > 1 then p2.w2 else h1.w2,
       if proof.length.toUInt64 > 1 then p2.w3 else h1.w3⟩
    let p3 := MerkleProof.hashPair h2 proof.values[2]!
    let h3 : Bytes32 :=
      ⟨if proof.length.toUInt64 > 2 then p3.w0 else h2.w0,
       if proof.length.toUInt64 > 2 then p3.w1 else h2.w1,
       if proof.length.toUInt64 > 2 then p3.w2 else h2.w2,
       if proof.length.toUInt64 > 2 then p3.w3 else h2.w3⟩
    let p4 := MerkleProof.hashPair h3 proof.values[3]!
    let h4 : Bytes32 :=
      ⟨if proof.length.toUInt64 > 3 then p4.w0 else h3.w0,
       if proof.length.toUInt64 > 3 then p4.w1 else h3.w1,
       if proof.length.toUInt64 > 3 then p4.w2 else h3.w2,
       if proof.length.toUInt64 > 3 then p4.w3 else h3.w3⟩
    let p5 := MerkleProof.hashPair h4 proof.values[4]!
    let h5 : Bytes32 :=
      ⟨if proof.length.toUInt64 > 4 then p5.w0 else h4.w0,
       if proof.length.toUInt64 > 4 then p5.w1 else h4.w1,
       if proof.length.toUInt64 > 4 then p5.w2 else h4.w2,
       if proof.length.toUInt64 > 4 then p5.w3 else h4.w3⟩
    let p6 := MerkleProof.hashPair h5 proof.values[5]!
    let h6 : Bytes32 :=
      ⟨if proof.length.toUInt64 > 5 then p6.w0 else h5.w0,
       if proof.length.toUInt64 > 5 then p6.w1 else h5.w1,
       if proof.length.toUInt64 > 5 then p6.w2 else h5.w2,
       if proof.length.toUInt64 > 5 then p6.w3 else h5.w3⟩
    let p7 := MerkleProof.hashPair h6 proof.values[6]!
    let h7 : Bytes32 :=
      ⟨if proof.length.toUInt64 > 6 then p7.w0 else h6.w0,
       if proof.length.toUInt64 > 6 then p7.w1 else h6.w1,
       if proof.length.toUInt64 > 6 then p7.w2 else h6.w2,
       if proof.length.toUInt64 > 6 then p7.w3 else h6.w3⟩
    let p8 := MerkleProof.hashPair h7 proof.values[7]!
    let h8 : Bytes32 :=
      ⟨if proof.length.toUInt64 > 7 then p8.w0 else h7.w0,
       if proof.length.toUInt64 > 7 then p8.w1 else h7.w1,
       if proof.length.toUInt64 > 7 then p8.w2 else h7.w2,
       if proof.length.toUInt64 > 7 then p8.w3 else h7.w3⟩
    ProofForge.Evm.Runtime.evmEqBytes32
      h8.w0 h8.w1 h8.w2 h8.w3 s.root0 s.root1 s.root2 s.root3

@[pf_entry]
def touch (_s : State) (v : UInt64) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then .ok ({ root0 := 0, root1 := 0, root2 := 0, root3 := 0 }, v)
  else .error .overflow

end Examples.Evm.ProofLink
