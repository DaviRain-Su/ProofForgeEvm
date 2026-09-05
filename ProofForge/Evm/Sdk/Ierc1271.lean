import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.Ierc1271

/-!
# EVM SDK ERC-1271 signer check

`checkSignature` is the contract-signer half of OZ `SignatureChecker.isValidERC1271SignatureNow`
over `OpenCall.callMagic`: the signer must answer `isValidSignature(bytes32,bytes)` with exactly
one word equal to that selector, `0x1626ba7e`, left-aligned, or the transaction reverts
(`revert(0, 0)`, so no partial state remains and the signer's reason is not bubbled). The
signature is one ECDSA `r ‖ s ‖ v`, 65 bytes, sent as ABI `bytes` at its runtime length; the
calldata is byte-identical to `abi.encodeWithSelector`.

Three departures from OZ are the product boundary:
- OZ answers `false` and lets the caller decide; this check is a CALL carrier for the entry's
  result word under `Effect.thenTrue` (or the result word itself), so a rejected signature is a
  revert. Reentrancy is application-visible, as for every open CALL.
- A signer without code answers an empty frame, which the magic policy refuses. There is no
  code-size branch and no ECDSA fallback here; an EOA signer goes through `Sdk.Ecdsa.recover`
  with `(v, r, s)` split by the caller.
- The signature is bounded to 65 bytes (`Check` spells the literal because the open-call decoder
  wants one), so multi-signature wallets whose `signature` is wider are out.

Implementing the receiving side (`isValidSignature` on this contract) stays a non-goal.
-/

open ProofForge.Core.Value

/-- The check a contract signer must answer. Constructor and field names are the ABI surface:
`isValidSignature(bytes32 hash, bytes signature)`, magic `0x1626ba7e`. `signature` is bounded to
65 bytes, one ECDSA `r ‖ s ‖ v`. -/
inductive Check where
  | isValidSignature (hash : Bytes32) (signature : BoundedBytes 65)

/-- OZ `isValidERC1271SignatureNow` as a fail-closed gate: CALL `isValidSignature` on `signer`
and require its own selector back; any other frame, including the empty one a signer without
code answers, reverts. A CALL carrier for the entry's result word under `Effect.thenTrue`; see
the module doc. -/
@[pf_inline] def checkSignature (signer : Address) (hash : Bytes32)
    (signature : BoundedBytes 65) : UInt64 :=
  OpenCall.callMagic signer (Check.isValidSignature hash signature)

end ProofForge.Evm.Sdk.Ierc1271
