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
    Id.run do
      let mut c0 := leaf.w0
      let mut c1 := leaf.w1
      let mut c2 := leaf.w2
      let mut c3 := leaf.w3
      if proof.length.toUInt64 > 0 then
        let next := MerkleProof.hashPair ⟨c0, c1, c2, c3⟩ proof.values[0]!
        c0 := next.w0; c1 := next.w1; c2 := next.w2; c3 := next.w3
      if proof.length.toUInt64 > 1 then
        let next := MerkleProof.hashPair ⟨c0, c1, c2, c3⟩ proof.values[1]!
        c0 := next.w0; c1 := next.w1; c2 := next.w2; c3 := next.w3
      if proof.length.toUInt64 > 2 then
        let next := MerkleProof.hashPair ⟨c0, c1, c2, c3⟩ proof.values[2]!
        c0 := next.w0; c1 := next.w1; c2 := next.w2; c3 := next.w3
      if proof.length.toUInt64 > 3 then
        let next := MerkleProof.hashPair ⟨c0, c1, c2, c3⟩ proof.values[3]!
        c0 := next.w0; c1 := next.w1; c2 := next.w2; c3 := next.w3
      if proof.length.toUInt64 > 4 then
        let next := MerkleProof.hashPair ⟨c0, c1, c2, c3⟩ proof.values[4]!
        c0 := next.w0; c1 := next.w1; c2 := next.w2; c3 := next.w3
      if proof.length.toUInt64 > 5 then
        let next := MerkleProof.hashPair ⟨c0, c1, c2, c3⟩ proof.values[5]!
        c0 := next.w0; c1 := next.w1; c2 := next.w2; c3 := next.w3
      if proof.length.toUInt64 > 6 then
        let next := MerkleProof.hashPair ⟨c0, c1, c2, c3⟩ proof.values[6]!
        c0 := next.w0; c1 := next.w1; c2 := next.w2; c3 := next.w3
      if proof.length.toUInt64 > 7 then
        let next := MerkleProof.hashPair ⟨c0, c1, c2, c3⟩ proof.values[7]!
        c0 := next.w0; c1 := next.w1; c2 := next.w2; c3 := next.w3
      return ProofForge.Evm.Runtime.evmEqBytes32
        c0 c1 c2 c3 s.root0 s.root1 s.root2 s.root3

@[pf_entry]
def touch (_s : State) (v : UInt64) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then .ok ({ root0 := 0, root1 := 0, root2 := 0, root3 := 0 }, v)
  else .error .overflow

end Examples.Evm.ProofLink
