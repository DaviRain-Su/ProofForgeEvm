import ProofForge.Core.SafeCast
import ProofForge.Core.Math
import ProofForge.Evm.Sdk.Base
import ProofForge.Evm.Sdk.Fungible
import ProofForge.Evm.Sdk.Erc20Meta
import ProofForge.Evm.Sdk.Erc165
import ProofForge.Evm.Sdk.Erc2981
import ProofForge.Evm.Sdk.Erc721
import ProofForge.Evm.Sdk.Erc1155
import ProofForge.Evm.Sdk.Payments
import ProofForge.Evm.Sdk.SafeErc20
import ProofForge.Evm.Sdk.Pausable
import ProofForge.Evm.Sdk.Ownable
import ProofForge.Evm.Sdk.Access
import ProofForge.Evm.Sdk.Storage
import ProofForge.Evm.Sdk.StorageVec
import ProofForge.Evm.Sdk.StorageBitmap
import ProofForge.Evm.Sdk.StorageRing
import ProofForge.Evm.Sdk.StorageEnumerableSet
import ProofForge.Evm.Sdk.StorageEnumerableMap
import ProofForge.Evm.Sdk.StorageCheckpoints
import ProofForge.Evm.Sdk.Roles
import ProofForge.Evm.Sdk.Nonces
import ProofForge.Evm.Sdk.RateLimit
import ProofForge.Evm.Sdk.MetadataUri
import ProofForge.Evm.Sdk.Eip712Domain
import ProofForge.Evm.Sdk.Vesting
import ProofForge.Evm.Sdk.MerkleProof
import ProofForge.Evm.Sdk.OzAudit
import ProofForge.Evm.Sdk.Reentrancy

/-!
# ProofForge EVM SDK

Contract-facing umbrella for EVM values, typed storage handles, target effects, reusable access /
pause/Ownable-event/reentrancy/payment/fungible/ERC-721/bounded-ERC-1155 ledger policy components,
bounded ERC-165 interface-id predicates, fail-closed ERC-20 consumer helpers, a static ERC-2981
royalty quote,
compile-time static storage declarations, persistent bounded UInt64 storage vectors/bitmaps/ring
queues/enumerable sets/maps/checkpoints, bounded static role sets with canonical RoleGranted /
RoleRevoked logs, bounded per-address nonce and fixed-window rate-limit helpers, bounded static
ERC-721/1155 metadata URI helpers, EIP-5267-style static EIP-712 domain field helpers, bounded
single-beneficiary native-ETH vesting schedule helpers, bounded Merkle proof verification helpers,
OZ completion-audit inventory counters, and shared allocation-free checked wide-to-UInt8/UInt16/UInt32/UInt64
narrowing and bounded UInt64 math. Applications import this module rather than target Runtime, Ops,
IR, or Emit internals.
-/
