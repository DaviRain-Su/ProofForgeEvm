import ProofForge.Evm.Sdk
import ProofForge.Core.Value

/-!
Bounded Merkle proof consumer. Constructor stores the trusted root; `verify` checks a fixed-capacity
`bytes32[]` proof using OpenZeppelin-style sorted pair hashing. Zero roots fail closed because
`verify256` compares the sorted-pair digest against stored root limbs (zero yields false for
nonzero leaves).
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
    let h1 := if proof.length.toUInt64 > 0 then MerkleProof.hashPair leaf proof.values[0]! else leaf
    let h2 := if proof.length.toUInt64 > 1 then MerkleProof.hashPair h1 proof.values[1]! else h1
    let h3 := if proof.length.toUInt64 > 2 then MerkleProof.hashPair h2 proof.values[2]! else h2
    let h4 := if proof.length.toUInt64 > 3 then MerkleProof.hashPair h3 proof.values[3]! else h3
    let h5 := if proof.length.toUInt64 > 4 then MerkleProof.hashPair h4 proof.values[4]! else h4
    let h6 := if proof.length.toUInt64 > 5 then MerkleProof.hashPair h5 proof.values[5]! else h5
    let h7 := if proof.length.toUInt64 > 6 then MerkleProof.hashPair h6 proof.values[6]! else h6
    let h8 := if proof.length.toUInt64 > 7 then MerkleProof.hashPair h7 proof.values[7]! else h7
    MerkleProof.eqRoot256 h8.w0 h8.w1 h8.w2 h8.w3 s.root0 s.root1 s.root2 s.root3

@[pf_entry]
def touch (_s : State) (v : UInt64) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then .ok ({ root0 := 0, root1 := 0, root2 := 0, root3 := 0 }, v)
  else .error .overflow

end Examples.Evm.ProofLink
