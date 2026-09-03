import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.Erc3009

/-!
# EVM SDK bounded ERC-3009 transfer-with-authorization

Typed closed-call profile over static `address` / `uint256` / `bytes32` / `v` / `r` / `s` operands,
reusing the existing EIP-712 domain and `ecrecover` precompile path. There is no receive-with-
authorization, cancellation, or authorization-state enumeration API.
-/

@[pf_inline] def authorize (sender to : Address) (value validAfter validBefore : UInt256)
    (nonce : Bytes32) (v : UInt8) (r s : Bytes32) : UInt64 :=
  Runtime.evmTransferWithAuthorization sender to value validAfter validBefore nonce v r s

@[pf_inline] def domainSeparator : Bytes32 :=
  Permit.domainSeparator

end ProofForge.Evm.Sdk.Erc3009
