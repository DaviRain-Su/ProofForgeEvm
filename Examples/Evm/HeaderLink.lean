import ProofForge.Evm.Sdk

/-!
Bounded block header / blockhash witness. Views expose the OpenZeppelin-shaped header profile over
`Sdk.BlockHeader` and fail-closed history-window checks for `BLOCKHASH`.
-/

namespace Examples.Evm.HeaderLink
open ProofForge.Evm.Sdk

structure State where
  dummy : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_entry]
def init (_witness : UInt64) : State :=
  { dummy := 0 }

@[pf_entry]
def number (_s : State) : UInt64 :=
  BlockHeader.number

@[pf_entry]
def timestamp (_s : State) : UInt64 :=
  BlockHeader.timestamp

@[pf_entry]
def baseFee (_s : State) : UInt256 :=
  BlockHeader.baseFee

@[pf_entry]
def prevRandao (_s : State) : UInt256 :=
  BlockHeader.prevRandao

@[pf_entry]
def gasLimit (_s : State) : UInt256 :=
  BlockHeader.gasLimit

@[pf_entry]
def coinbase (_s : State) : Address :=
  BlockHeader.coinbase

@[pf_entry]
def blockHash (_s : State) (blockNumber : UInt64) : UInt256 :=
  BlockHeader.hashOf blockNumber

@[pf_entry]
def inHistoryWindow (_s : State) (blockNumber : UInt64) : Bool :=
  if blockNumber > Context.blockNumber then
    false
  else if Context.blockNumber >= blockNumber + BlockHeader.historyDepth then
    false
  else
    true

@[pf_entry]
def touch (_s : State) (v : UInt64) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then .ok ({ dummy := v }, v) else .error .overflow

end Examples.Evm.HeaderLink
