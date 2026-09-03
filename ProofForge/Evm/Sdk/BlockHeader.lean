import ProofForge.Attr
import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.BlockHeader

/-!
# EVM SDK bounded block header and blockhash profile

OpenZeppelin-shaped helpers over the existing `Context` environment observations. This is a
read-only profile: there is no storage, no historical header cache, and no general-purpose block
query API beyond what the EVM exposes at the observation point.

`hashOf` wraps `Context.blockHash` (the `BLOCKHASH` opcode). EVM returns zero for future blocks
and for blocks older than the 256-block history window; `isInHistoryWindow` exposes that bound
without pretending to recover unavailable headers.
-/

/-- EVM `BLOCKHASH` history depth in blocks. -/
def historyDepth : UInt64 := 256

/-- Current block number (`NUMBER`). -/
@[pf_inline] def number : UInt64 := Context.blockNumber

/-- Current block timestamp (`TIMESTAMP`). -/
@[pf_inline] def timestamp : UInt64 := Context.timestamp

/-- Current block base fee (`BASEFEE`). -/
@[pf_inline] def baseFee : UInt256 := Context.baseFee

/-- Current block prevrandao (`PREVRANDAO`). -/
@[pf_inline] def prevRandao : UInt256 := Context.prevRandao

/-- Current block gas limit (`GASLIMIT`). -/
@[pf_inline] def gasLimit : UInt256 := Context.gasLimit

/-- Current block coinbase (`COINBASE`). -/
@[pf_inline] def coinbase : Address := Context.coinbase

/-- Full-width hash of block `blockNumber` (`BLOCKHASH`). Returns zero outside the history window. -/
@[pf_inline] def hashOf (blockNumber : UInt64) : UInt256 := Context.blockHash blockNumber

/-- True when `blockNumber` is not in the future and within the 256-block history window. -/
def isInHistoryWindow (blockNumber : UInt64) : Bool :=
  if blockNumber > number then
    false
  else if number >= blockNumber + historyDepth then
    false
  else
    true

/-- True when a `BLOCKHASH` observation is the EVM zero word (unavailable or future block). -/
@[pf_inline] def isZeroHash (hash : UInt256) : Bool :=
  hash.w0 == 0 && hash.w1 == 0 && hash.w2 == 0 && hash.w3 == 0

end ProofForge.Evm.Sdk.BlockHeader
