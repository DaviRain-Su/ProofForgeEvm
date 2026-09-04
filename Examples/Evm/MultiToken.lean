import ProofForge.Evm.Sdk

/-!
Owner-minted bounded ERC-1155 consumer. The SDK owns the token-id key envelope, the
(owner, id) balance and (owner, operator) operator maps, and checked mint/burn/transfer
movement. This contract owns the immutable minter gate, zero-address policy, error ordering
(`Unauthorized`/`ZeroAddress`/`Insufficient`) and canonical ERC-1155 `TransferSingle` /
`ApprovalForAll` logs (`Erc1155.Log`). `balanceOfBatch` is bounded to four pairs. There is no
`safeBatchTransferFrom`, `TransferBatch`, or safe callback; `supportsInterface` exposes IERC165
only, not the incomplete IERC1155 interface.
-/

namespace Examples.Evm.MultiToken
open ProofForge.Evm.Sdk
open ProofForge.Core.Value (BoundedVec)

structure State where
  dummy : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_inline] def balances : Erc1155.Balances :=
  Storage.Layout.root.addressPairMap256.handle

@[pf_inline] def operators : Erc1155.Operators :=
  Storage.Layout.root.addressPairMap256.next.addressPairMap.handle

@[pf_entry]
def init (_owner : Address) : State :=
  { dummy := 0 }

@[pf_entry]
def mint (s : State) (to : Address) (tokenId : UInt256) (amount : UInt256) :
    Except Error (State × UInt64) :=
  if Address.eqImmutable Context.caller then
    if Erc1155.canMint balances to tokenId amount then
      .ok ({ dummy := Erc1155.mint balances to tokenId amount },
        Erc1155.Log.transferSingle Context.caller Address.zero to tokenId amount)
    else if Address.isZero to then
      .ok (s, Revert.zeroAddress)
    else
      .ok (s, Revert.unauthorized Context.caller)
  else
    .ok (s, Revert.unauthorized Context.caller)

/-- Burn from the caller's own balance. Unencodable ids are `Unauthorized`; an encodable id
whose balance is short is `Insufficient(held, wanted)`. Successful burns emit `TransferSingle`
to the zero address. -/
@[pf_entry]
def burn (s : State) (tokenId : UInt256) (amount : UInt256) :
    Except Error (State × UInt64) :=
  if Erc1155.canBurn balances Context.caller tokenId amount then
    .ok ({ dummy := Erc1155.burn balances Context.caller tokenId amount },
      Erc1155.Log.transferSingle Context.caller Context.caller Address.zero tokenId amount)
  else if !Erc1155.canEncode tokenId then
    .ok (s, Revert.unauthorized Context.caller)
  else
    .ok (s, Erc1155.Balances.insufficient balances Context.caller tokenId amount)

@[pf_entry]
def setApprovalForAll (s : State) (operator : Address) (approved : Bool) :
    Except Error (State × UInt64) :=
  if Address.isZero operator then
    .ok (s, Revert.zeroAddress)
  else if Address.eq operator Context.caller then
    .ok (s, Revert.unauthorized Context.caller)
  else
    .ok ({ dummy :=
        Erc1155.Operators.setApprovalForAll operators Context.caller operator approved },
      Erc1155.Log.approvalForAll Context.caller operator approved)

@[pf_entry]
def transferFrom (s : State) (source to : Address) (tokenId : UInt256) (amount : UInt256) :
    Except Error (State × UInt64) :=
  if !Erc1155.isApprovedOrOwner operators Context.caller source tokenId then
    .ok (s, Revert.unauthorized Context.caller)
  else if Address.isZero to then
    .ok (s, Revert.zeroAddress)
  else if Erc1155.Balances.canTransfer balances source to tokenId amount then
    .ok ({ dummy := Erc1155.Balances.transfer balances source to tokenId amount },
      Erc1155.Log.transferSingle Context.caller source to tokenId amount)
  else
    .ok (s, Erc1155.Balances.insufficient balances source tokenId amount)

/-- Single-id balance view through the SDK-owned checked key-envelope gate. -/
@[pf_entry]
def balanceOf (_s : State) (owner : Address) (tokenId : UInt256) : UInt256 :=
  Erc1155.Balances.balanceOf balances owner tokenId

@[pf_entry]
def isApprovedForAll (_s : State) (owner operator : Address) : Bool :=
  Erc1155.Operators.isApprovedForAll operators owner operator

/-- Bounded `balanceOfBatch(address[],uint256[])` over at most `Erc1155.batchCapacity` pairs.
Unequal lengths answer an empty array; longer inputs are rejected by the ABI decoder. The
signature spells `BoundedVec _ 4` because the profile accepts only a literal capacity in an entry
type; the SDK helper's `Erc1155.Batch` parameters refuse any other literal. -/
@[pf_entry]
def balanceOfBatch (_s : State) (owners : BoundedVec Address 4) (ids : BoundedVec UInt256 4) :
    BoundedVec UInt256 4 :=
  Erc1155.Balances.balanceOfBatch balances owners ids

/-- This partial ERC-1155-shaped profile implements only IERC165. It deliberately does not
advertise the IERC1155 identifier until every required ERC-1155 method is implemented. -/
@[pf_entry]
def supportsInterface (_s : State) (interfaceId : Bytes4) : Bool :=
  Erc165.supports interfaceId Erc165.erc165

end Examples.Evm.MultiToken
