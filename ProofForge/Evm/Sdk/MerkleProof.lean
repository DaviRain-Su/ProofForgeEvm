import ProofForge.Core.Value
import ProofForge.Core.Collections
import ProofForge.Crypto.Keccak
import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.MerkleProof

/-!
# EVM SDK bounded Merkle proof verification

Fixed-capacity `bytes32[]` proofs over OpenZeppelin-style sorted pair hashing
(`keccak256(abi.encodePacked(min(a,b), max(a,b)))`). There is no dynamic proof
allocator, multiproof, or calldata-only fast path. Consumers must validate
`canVerify` before advertising verification views.

Fail-closed gates:
- Zero root or malformed proof frames should yield false verification.
- Proof length above compile-time capacity is rejected before processing.

Extract note: `pf_entry` verification must gate on `canVerify` at the consumer
boundary and spell the bounded proof loop inline using `hashPair` (which erases
to `Runtime.evmKeccak256Pair32`). Do not route returns through parameterized
SDK loop helpers.
-/

open ProofForge.Core.Value

/-- Default compile-time maximum Merkle proof depth for this profile. -/
def defaultDepth : Nat := 8

abbrev Proof := BoundedVec Bytes32 defaultDepth

private def appendU64LE (ba : ByteArray) (w : UInt64) : ByteArray := Id.run do
  let mut out := ba
  for i in [0:8] do
    out := out.push <| UInt64.shiftRight w (UInt64.ofNat (8 * i)) |>.toUInt8
  return out

private def bytes32Bytes (b : Bytes32) : ByteArray :=
  appendU64LE (appendU64LE (appendU64LE (appendU64LE ByteArray.empty b.w0) b.w1) b.w2) b.w3

private def byteArrayToBytes32 (bytes : ByteArray) : Bytes32 :=
  let readLane (offset : Nat) : UInt64 := Id.run do
    let mut lane : UInt64 := 0
    for i in [0:8] do
      lane := lane ||| UInt64.shiftLeft bytes[offset + i]!.toUInt64 (UInt64.ofNat (8 * i))
    return lane
  ⟨readLane 0, readLane 8, readLane 16, readLane 24⟩

private def asUInt256 (b : Bytes32) : UInt256 :=
  ⟨b.w0, b.w1, b.w2, b.w3⟩

/-- True when the configured root is nonzero. -/
@[pf_inline] def wellFormedRoot (root : Bytes32) : Bool :=
  root.w0 != 0 || root.w1 != 0 || root.w2 != 0 || root.w3 != 0

/-- True when the proof frame is canonical for its compile-time capacity. -/
@[pf_inline] def wellFormedProof (proof : Proof) : Bool :=
  BoundedVec.wellFormed proof

/-- Verification may run only with a nonzero root and a well-formed proof frame. -/
@[pf_inline] def canVerify (root _leaf : Bytes32) (proof : Proof) : Bool :=
  wellFormedRoot root && wellFormedProof proof

open ProofForge.Crypto.Keccak

/-- Construct a `bytes32` from the Keccak-256 digest of a UTF-8 string. -/
@[pf_inline] def fromKeccakUtf8 (s : String) : Bytes32 :=
  byteArrayToBytes32 (keccak256 s.toUTF8)

/-- Reference sorted pair hash for tests and host evaluation. -/
@[pf_inline] def hashPairPure (a b : Bytes32) : Bytes32 :=
  let (left, right) :=
    if UInt256.lt (asUInt256 a) (asUInt256 b) then (a, b) else (b, a)
  byteArrayToBytes32 (keccak256 (bytes32Bytes left ++ bytes32Bytes right))

/-- Extractable single-step Merkle verify; erases to `Runtime.evmMerkleVerify256`. -/
@[pf_inline] def verify256 (leaf sibling : Bytes32) (r0 r1 r2 r3 : UInt64) : Bool :=
  Runtime.evmMerkleVerify256 leaf sibling r0 r1 r2 r3

/-- Extractable `bytes32` equality for folded Merkle roots; erases to `Runtime.evmEqBytes32`. -/
@[pf_inline] def eqRoot256 (c0 c1 c2 c3 r0 r1 r2 r3 : UInt64) : Bool :=
  Runtime.evmEqBytes32 c0 c1 c2 c3 r0 r1 r2 r3

/-- Extractable sorted pair hash; erases to `Runtime.evmKeccak256Pair32`. -/
@[pf_inline] def hashPair (a b : Bytes32) : Bytes32 :=
  Runtime.evmKeccak256Pair32 a b

/-- Reference proof processing for tests and host evaluation. -/
def processProofPure (leaf : Bytes32) (proof : Proof) : Bytes32 :=
  Id.run do
    let mut computed := leaf
    for i in [0:defaultDepth] do
      if i.toUInt32 < proof.length then
        computed := hashPairPure computed proof.values[i]!
    return computed

/-- Compare two `bytes32` values limb-wise. -/
@[pf_inline] def matchesRoot (computed root : Bytes32) : Bool :=
  computed.w0 == root.w0 && computed.w1 == root.w1 &&
    computed.w2 == root.w2 && computed.w3 == root.w3

/-- Reference verification for tests and host evaluation. -/
@[pf_inline] def verifyPure (root leaf : Bytes32) (proof : Proof) : Bool :=
  if canVerify root leaf proof then
    matchesRoot (processProofPure leaf proof) root
  else
    false

end ProofForge.Evm.Sdk.MerkleProof
