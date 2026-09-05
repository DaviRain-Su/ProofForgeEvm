import ProofForge.Evm.Sdk.Base
import ProofForge.Evm.Sdk.Ecdsa

namespace ProofForge.Evm.Sdk.Ierc1271

/-!
# EVM SDK ERC-1271 signer check

`checkSignature` is the contract-signer half of OZ `SignatureChecker.isValidERC1271SignatureNow`
over `OpenCall.callMagic`: the signer must answer `isValidSignature(bytes32,bytes)` with exactly
one word equal to that selector, `0x1626ba7e`, left-aligned, or the transaction reverts
(`revert(0, 0)`, so no partial state remains and the signer's reason is not bubbled). The
signature is one ECDSA `r ‖ s ‖ v`, 65 bytes, sent as ABI `bytes` at its runtime length; the
calldata is byte-identical to `abi.encodeWithSelector`.

`checkNow` is the combined OZ `isValidSignatureNow` gate: a signer with code takes
`checkSignature`; a signer without code splits the same 65 bytes into `(v, r, s)` with the
existing UInt8/`UInt64` shift-or path and recovers through `Sdk.Ecdsa.recover`. `v < 27` is
normalized by adding 27, matching RecoverLink's Anvil gate. A short frame or a recovered
address other than `signer` reverts `Unauthorized(signer)`. Invalid ECDSA still empty-reverts
inside the precompile.

Departures from OZ:
- `checkSignature` and `checkNow` are CALL/effect carriers for the
  entry's result word under `Effect.thenTrue`, so a rejected signature is a revert. Reentrancy
  is application-visible, as for every open CALL.
- `validSignature` and `validNow` are the OZ `false` path: a STATICCALL (`OpenCall.staticTryMagic`)
  whose call-result policy binds ABI `true` on exact magic and `false` on any other outcome,
  including a failed call. They are values. A rejected signature does not revert. Invalid ECDSA
  on the EOA arm of `validNow` still empty-reverts inside the precompile.
- `checkSignature` has no code-size branch. `checkNow` and `validNow` are the code-size branch.
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

/-- Pack eight source-order bytes into one FixedBytes lane. Byte `i` of the lane is bits
`8*i .. 8*i+7`, the same order `pf_store_fixed_bytes` writes into an ABI word. -/
@[pf_inline] def packLane (b0 b1 b2 b3 b4 b5 b6 b7 : UInt8) : UInt64 :=
  b0.toUInt64 ||| (b1.toUInt64 <<< (8 : UInt64)) ||| (b2.toUInt64 <<< (16 : UInt64)) |||
    (b3.toUInt64 <<< (24 : UInt64)) ||| (b4.toUInt64 <<< (32 : UInt64)) |||
    (b5.toUInt64 <<< (40 : UInt64)) ||| (b6.toUInt64 <<< (48 : UInt64)) |||
    (b7.toUInt64 <<< (56 : UInt64))

/-- First 32 bytes of a 65-byte `r ‖ s ‖ v` signature as source-order `Bytes32`. -/
@[pf_inline] def rWord (signature : BoundedBytes 65) : Bytes32 :=
  ⟨packLane signature.values[0] signature.values[1] signature.values[2] signature.values[3]
      signature.values[4] signature.values[5] signature.values[6] signature.values[7],
    packLane signature.values[8] signature.values[9] signature.values[10] signature.values[11]
      signature.values[12] signature.values[13] signature.values[14] signature.values[15],
    packLane signature.values[16] signature.values[17] signature.values[18] signature.values[19]
      signature.values[20] signature.values[21] signature.values[22] signature.values[23],
    packLane signature.values[24] signature.values[25] signature.values[26] signature.values[27]
      signature.values[28] signature.values[29] signature.values[30] signature.values[31]⟩

/-- Bytes 32..63 of a 65-byte `r ‖ s ‖ v` signature as source-order `Bytes32`. -/
@[pf_inline] def sWord (signature : BoundedBytes 65) : Bytes32 :=
  ⟨packLane signature.values[32] signature.values[33] signature.values[34] signature.values[35]
      signature.values[36] signature.values[37] signature.values[38] signature.values[39],
    packLane signature.values[40] signature.values[41] signature.values[42] signature.values[43]
      signature.values[44] signature.values[45] signature.values[46] signature.values[47],
    packLane signature.values[48] signature.values[49] signature.values[50] signature.values[51]
      signature.values[52] signature.values[53] signature.values[54] signature.values[55],
    packLane signature.values[56] signature.values[57] signature.values[58] signature.values[59]
      signature.values[60] signature.values[61] signature.values[62] signature.values[63]⟩

/-- Last byte of a 65-byte signature as ecrecover `v`. Values below 27 are raised by 27 so a
`0/1` recovery id matches RecoverLink's Anvil normalization. -/
@[pf_inline] def vByte (signature : BoundedBytes 65) : UInt8 :=
  let raw := signature.values[64]
  if raw.toUInt64 < (27 : UInt64) then (raw.toUInt64 + (27 : UInt64)).toUInt8 else raw

/-- OZ `isValidERC1271SignatureNow` as a fail-closed gate: CALL `isValidSignature` on `signer`
and require its own selector back; any other frame, including the empty one a signer without
code answers, reverts. A CALL carrier for the entry's result word under `Effect.thenTrue`; see
the module doc. -/
@[pf_inline] def checkSignature (signer : Address) (hash : Bytes32)
    (signature : BoundedBytes 65) : UInt64 :=
  OpenCall.callMagic signer (Check.isValidSignature hash signature)

/-- OZ `isValidERC1271SignatureNow` as a Bool. STATICCALL `isValidSignature` on `signer` and
answer `true` only when the callee returns its own selector as one clean word. A failed call,
an empty frame, a wrong selector, or a dirty low byte is `false`. A signer without code answers
the empty frame and therefore `false`. -/
@[pf_inline] def validSignature (signer : Address) (hash : Bytes32)
    (signature : BoundedBytes 65) : Bool :=
  OpenCall.staticTryMagic signer (Check.isValidSignature hash signature)

/-- OZ `SignatureChecker.isValidSignatureNow` as a fail-closed carrier. A signer with code takes
`checkSignature`. A signer without code requires a 65-byte frame, recovers through
`Ecdsa.recover`, and reverts `Unauthorized(signer)` when the recovered address differs.
Invalid ECDSA empty-reverts inside the precompile. Length is an `if`, not `&&`, because
`Bool.and` lowers to `bitAnd` and would still run ecrecover on a short frame. -/
@[pf_inline] def checkNow (signer : Address) (hash : Bytes32)
    (signature : BoundedBytes 65) : UInt64 :=
  if Address.hasCode signer then
    checkSignature signer hash signature
  else if signature.length.toUInt64 == 65 then
    if Address.eq (Ecdsa.recover hash (vByte signature) (rWord signature) (sWord signature))
        signer then
      0
    else
      Revert.unauthorized signer
  else
      Revert.unauthorized signer

/-- OZ `SignatureChecker.isValidSignatureNow` as a Bool. A signer with code takes
`validSignature`. A signer without code requires a 65-byte frame, recovers through
`Ecdsa.recover`, and answers `false` when the recovered address differs or the frame is short.
Invalid ECDSA still empty-reverts inside the precompile. -/
@[pf_inline] def validNow (signer : Address) (hash : Bytes32)
    (signature : BoundedBytes 65) : Bool :=
  if Address.hasCode signer then
    validSignature signer hash signature
  else if signature.length.toUInt64 == 65 then
    Address.eq (Ecdsa.recover hash (vByte signature) (rWord signature) (sWord signature))
        signer
  else
    false

end ProofForge.Evm.Sdk.Ierc1271
