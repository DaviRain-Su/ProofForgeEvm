import ProofForge.Evm.Sdk
import ProofForge.Core.Value

/-!
Minimal ERC-1271 consumer. `requireSigner` asks a contract signer whether it stands behind
`hash` through `Sdk.Ierc1271.checkSignature`, and counts the signatures it accepted. A signer
that answers anything but its own `isValidSignature` selector, or has no code, reverts the
transaction, so `accepted` only ever counts checks the signer passed. Driven against a
Solidity ERC-1271 wallet in `runtime-tests/evm/anvil_signerlink.sh`.
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

@[pf_entry]
def accepted (s : State) : UInt64 :=
  s.accepted

end Examples.Evm.SignerLink
