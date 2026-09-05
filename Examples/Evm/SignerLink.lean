import ProofForge.Evm.Sdk
import ProofForge.Core.Value

/-!
Minimal ERC-1271 / combined-signer consumer. `requireSigner` asks a contract signer whether it
stands behind `hash` through `Sdk.Ierc1271.checkSignature`. `requireNow` is OZ
`isValidSignatureNow`: a signer with code takes that same CALL, a signer without code recovers
the 65-byte `r ‖ s ‖ v` through `Ecdsa.recover`. A refused check reverts and leaves `accepted`
where it was. `tryNow` is the OZ `false` path: `Ierc1271.validNow` over a STATICCALL, so a
refused signature answers `false` and leaves `accepted` in place. Driven in
`runtime-tests/evm/anvil_signerlink.sh` against a Solidity ERC-1271 wallet and against an EOA.
This contract does not implement `isValidSignature`.
-/

namespace Examples.Evm.SignerLink
open ProofForge.Evm.Sdk
open ProofForge.Core.Value

structure State where
  accepted : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

private def u64Max : UInt64 := 18446744073709551615

@[pf_entry]
def init (_owner : Address) : State :=
  { accepted := 0 }

/-- Require `signer` to accept `signature` over `hash` under ERC-1271; count it when it does.
The counter movement rides the state word and the signer check the result word, so a refused
check leaves `accepted` where it was. -/
@[pf_entry]
def requireSigner (s : State) (signer : Address) (hash : Bytes32) (signature : BoundedBytes 65) :
    Except Error (State × Bool) :=
  if s.accepted < u64Max then
    .ok ({ accepted := s.accepted + 1 },
      Effect.thenTrue (Ierc1271.checkSignature signer hash signature))
  else
    Effect.abort s Revert.capExceeded

/-- Combined EOA-or-contract check. Same counter rule as `requireSigner`. -/
@[pf_entry]
def requireNow (s : State) (signer : Address) (hash : Bytes32) (signature : BoundedBytes 65) :
    Except Error (State × Bool) :=
  if s.accepted < u64Max then
    .ok ({ accepted := s.accepted + 1 },
      Effect.thenTrue (Ierc1271.checkNow signer hash signature))
  else
    Effect.abort s Revert.capExceeded

/-- OZ `isValidSignatureNow` as a Bool. Count only when the check answers `true`. A refused
signature answers `false` and leaves `accepted` where it was. Invalid ECDSA still
empty-reverts inside the precompile. -/
@[pf_entry]
def tryNow (s : State) (signer : Address) (hash : Bytes32) (signature : BoundedBytes 65) :
    Except Error (State × Bool) :=
  if Ierc1271.validNow signer hash signature then
    if s.accepted < u64Max then
      .ok ({ accepted := s.accepted + 1 }, true)
    else
      Effect.abort s Revert.capExceeded
  else
    .ok (s, false)

@[pf_entry]
def accepted (s : State) : UInt64 :=
  s.accepted

end Examples.Evm.SignerLink
