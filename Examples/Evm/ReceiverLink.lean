import ProofForge.Evm.Sdk
import ProofForge.Core.Value

/-!
Bounded ERC-721/1155 receiver. Each hook records the operator, from, id, first value, and
`data` length, then returns that hook's own selector as `Bytes4`. `data` is at most 32 bytes
and a batch is at most four slots; the recorded id/value for a batch is slot 0. Driven from
Collectible, CraftToken, and MultiToken in `runtime-tests/evm/anvil_receiverlink.sh`.
-/

namespace Examples.Evm.ReceiverLink
open ProofForge.Evm.Sdk
open ProofForge.Core.Value

structure State where
  operator : UInt256
  fromAddr : UInt256
  id : UInt256
  value : UInt256
  dataLen : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_inline] def remember (operator source : Address) (id value : UInt256)
    (dataLen : UInt64) : State :=
  { operator := Erc721.packAddress operator
    fromAddr := Erc721.packAddress source
    id := id
    value := value
    dataLen := dataLen }

@[pf_entry]
def init (_owner : Address) : State :=
  { operator := UInt256.zero, fromAddr := UInt256.zero, id := UInt256.zero,
    value := UInt256.zero, dataLen := 0 }

/-- `onERC721Received(address,address,uint256,bytes)` returns `0x150b7a02`. -/
@[pf_entry]
def onERC721Received (_s : State) (operator «from» : Address) (tokenId : UInt256)
    (data : BoundedBytes 32) : Except Error (State × Bytes4) :=
  if (0 : UInt64) ≠ 1 then
    .ok (remember operator «from» tokenId UInt256.zero data.length.toUInt64,
      Erc721.onReceivedSelector)
  else
    .error .overflow

/-- `onERC1155Received(address,address,uint256,uint256,bytes)` returns `0xf23a6e61`. -/
@[pf_entry]
def onERC1155Received (_s : State) (operator «from» : Address) (id value : UInt256)
    (data : BoundedBytes 32) : Except Error (State × Bytes4) :=
  if (0 : UInt64) ≠ 1 then
    .ok (remember operator «from» id value data.length.toUInt64,
      Erc1155.onReceivedSelector)
  else
    .error .overflow

/-- `onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)` returns `0xbc197c81`.
The recorded id and value are slot 0. -/
@[pf_entry]
def onERC1155BatchReceived (_s : State) (operator «from» : Address)
    (ids values : BoundedVec UInt256 4) (data : BoundedBytes 32) :
    Except Error (State × Bytes4) :=
  if (0 : UInt64) ≠ 1 then
    .ok (remember operator «from» ids.values[0] values.values[0] data.length.toUInt64,
      Erc1155.onBatchReceivedSelector)
  else
    .error .overflow

@[pf_entry]
def seenOperator (s : State) : UInt256 :=
  s.operator

@[pf_entry]
def seenFrom (s : State) : UInt256 :=
  s.fromAddr

@[pf_entry]
def seenId (s : State) : UInt256 :=
  s.id

@[pf_entry]
def seenValue (s : State) : UInt256 :=
  s.value

@[pf_entry]
def seenDataLen (s : State) : UInt64 :=
  s.dataLen

/-- IERC165 plus the two receiver interface ids, because this contract implements those
complete method surfaces. IERC721 and IERC1155 stay false. -/
@[pf_entry]
def supportsInterface (_s : State) (interfaceId : Bytes4) : Bool :=
  Erc165.supports3 interfaceId Erc165.erc165 Erc165.erc721Receiver Erc165.erc1155Receiver

end Examples.Evm.ReceiverLink
