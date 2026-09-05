import ProofForge.Evm.Sdk

/-!
Open-mint bounded ERC-1155 consumer with an application-owned per-id supply cap. Independently
reuses the Erc1155 balance/operator core while owning its mint policy (any caller, per-id supply
capped at `maxPerId`), burn accounting (supply moves with the balance), and error ordering.
The supply map is a separate `Storage.AddressMap256` namespace keyed by `tokenKey`, so it shares
the same 192-bit key envelope and never aliases the balance/operator namespaces. Successful mint,
burn, and transfer emit canonical ERC-1155 `TransferSingle`; operator writes emit `ApprovalForAll`.
The single transfer is `safeTransferFrom` with the SDK's receiver check (`Erc1155.checkOnReceived`);
`MultiToken` keeps the hook-less `transferFrom` because the hook entry does not fit it under
EIP-170.
-/

namespace Examples.Evm.CraftToken
open ProofForge.Evm.Sdk
open ProofForge.Core.Value (BoundedBytes)

structure State where
  dummy : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

-- Application-owned per-id supply cap.
@[pf_inline] def maxPerId : UInt256 := ⟨1000, 0, 0, 0⟩

@[pf_inline] def balances : Erc1155.Balances :=
  Storage.Layout.root.addressPairMap256.handle

@[pf_inline] def operators : Erc1155.Operators :=
  Storage.Layout.root.addressPairMap256.next.addressPairMap.handle

/-- Per-id minted supply in its own disjoint namespace. Keys are `Erc1155.tokenKey`, so reads and
writes must stay behind the same `canEncode` envelope as the balance core. -/
@[pf_inline] def supply : Storage.AddressMap256 :=
  Storage.Layout.root.addressPairMap256.next.addressPairMap.next.addressMap256.handle

@[pf_inline] def nextSupply (tokenId : UInt256) (amount : UInt256) : UInt256 :=
  supply.nextAdd (Erc1155.tokenKey tokenId) amount

@[pf_inline] def capped (tokenId : UInt256) (amount : UInt256) : Bool :=
  UInt256.ge maxPerId (nextSupply tokenId amount)

@[pf_entry]
def init (_owner : Address) : State :=
  { dummy := 0 }

/-- Open mint to the caller, bounded by the per-id supply cap. Unencodable ids are
`Unauthorized`; cap overflow is `CapExceeded()`. -/
@[pf_entry]
def mint (s : State) (tokenId : UInt256) (amount : UInt256) :
    Except Error (State × UInt64) :=
  if Erc1155.canMint balances Context.caller tokenId amount then
    if capped tokenId amount then
      .ok ({ dummy :=
          supply.put (Erc1155.tokenKey tokenId) (nextSupply tokenId amount) |||
            Erc1155.mint balances Context.caller tokenId amount },
        Erc1155.Log.transferSingle Context.caller Address.zero Context.caller tokenId amount)
    else
      .ok (s, Revert.capExceeded)
  else if !Erc1155.canEncode tokenId then
    .ok (s, Revert.unauthorized Context.caller)
  else
    .ok (s, Revert.capExceeded)

/-- Burn from the caller's own balance; supply debits with the balance in the same effect. -/
@[pf_entry]
def burn (s : State) (tokenId : UInt256) (amount : UInt256) :
    Except Error (State × UInt64) :=
  if Erc1155.canBurn balances Context.caller tokenId amount then
    .ok ({ dummy :=
        Erc1155.burn balances Context.caller tokenId amount |||
          supply.put (Erc1155.tokenKey tokenId)
            (supply.nextSub (Erc1155.tokenKey tokenId) amount) },
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

/-- `safeTransferFrom(address,address,uint256,uint256,bytes)`, the single transfer ERC-1155 has:
the checked move and the `TransferSingle` log land first, then OZ's receiver check. A recipient
without code is not called; a recipient with code must answer `onERC1155Received` with its own
selector or the whole transaction reverts, and a receiver that reads `balanceOf` inside the hook
sees the credited balance. `data` is bounded to 32 bytes. -/
@[pf_entry]
def safeTransferFrom (s : State) (source to : Address) (tokenId : UInt256) (amount : UInt256)
    (data : BoundedBytes 32) : Except Error (State × Bool) :=
  if !Erc1155.isApprovedOrOwner operators Context.caller source tokenId then
    Effect.abort s (Revert.unauthorized Context.caller)
  else if Address.isZero to then
    Effect.abort s Revert.zeroAddress
  else if Erc1155.Balances.canTransfer balances source to tokenId amount then
    .ok ({ dummy := Erc1155.Balances.transfer balances source to tokenId amount |||
        Erc1155.Log.transferSingle Context.caller source to tokenId amount },
      Effect.thenTrue
        (Erc1155.checkOnReceived to Context.caller source tokenId amount data))
  else
    Effect.abort s (Erc1155.Balances.insufficient balances source tokenId amount)

@[pf_entry]
def balanceOf (_s : State) (owner : Address) (tokenId : UInt256) : UInt256 :=
  Erc1155.Balances.balanceOf balances owner tokenId

/-- Per-id supply view with the same key-envelope gate as the balance core. -/
@[pf_entry]
def supplyOf (_s : State) (tokenId : UInt256) : UInt256 :=
  if !Erc1155.canEncode tokenId then UInt256.zero
  else supply.get (Erc1155.tokenKey tokenId)

@[pf_entry]
def isApprovedForAll (_s : State) (owner operator : Address) : Bool :=
  Erc1155.Operators.isApprovedForAll operators owner operator

/-- This partial ERC-1155-shaped profile implements only IERC165. It deliberately does not
advertise the IERC1155 identifier until every required ERC-1155 method is implemented. -/
@[pf_entry]
def supportsInterface (_s : State) (interfaceId : Bytes4) : Bool :=
  Erc165.supports interfaceId Erc165.erc165

end Examples.Evm.CraftToken
