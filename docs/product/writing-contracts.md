# Writing contracts (v0)

## Imports

User projects should import only:

```lean
import ProofForge.Attr
import ProofForge.Evm.Sdk
```

Do **not** import the `ProofForge` umbrella (it can pull Emit / Assemble / Registry).

## Entry shape

Mark chain entries with `@[pf_entry]`. Keep state in an explicit `structure`, errors in an
`inductive`, and mutations as `Except`-style transitions when you need revert. Two Lean roots
may share one ABI name when the second is spelled `name__tag` (`Collectible.safeTransferFrom__id`
is `safeTransferFrom(address,address,uint256)`). The types must differ or extraction refuses
`duplicate ABI`.

See `templates/evm-counter/MyContract/Counter.lean`, `Examples/Evm/TipJar.lean`, and
`Examples/Evm/Erc20Meta.lean` (ERC-20-shaped `string` metadata + standard selectors).

## What works today

- Storage layout cursors + typed maps
- Checked math / bit ops / bounded loops / narrow + wide ABI
- Ownable / roles / pause / reentrancy helpers
- Closed ETH + ERC-20/WETH calls, plus `SafeErc20` fail-closed transfer/approve/allowance helpers
- Typed OpenCall to a dynamic `Address` with a static ABI constructor (see [Call another contract](#call-another-contract))
- BoundedString returns as ABI `string` (see `Erc20Meta.name` / `symbol`)
- Static ERC-2981 `royaltyInfo` (see `Examples.Evm.RoyaltyArt`)
- Bounded nonce consumption + fixed-window rate limit (`Sdk.Nonces`, `Sdk.RateLimit`; see `Examples.Evm.EvmQuota`)
- Kernel proofs about the Lean `def` (not about bytecode)

## Call another contract

You do not need a proxy to call another contract. A proxy is an upgrade pattern: `delegatecall`
into a replaceable implementation behind an ERC-1967 slot. ProofForge does not ship proxies.
Calling a contract at a runtime `Address` is a different thing, and `OpenCall` does it today.

1. Declare the remote ABI as an inductive. Each constructor is one function. Its fields are the
   arguments in declaration order.
2. Call it with the helper whose result gate matches the callee.

```lean
inductive Remote where
  | transfer (to : Address) (amount : UInt256)
  | balanceOf (who : Address)
  | ownerOf
  | supportsInterface (interfaceId : Bytes4)
  | sink (tag : UInt256) (data : BoundedBytes 8)

-- ERC-20 `transfer(address,uint256)`: true, or empty returndata from an address with code.
OpenCall.call token (Remote.transfer dest amt)
-- STATICCALL `balanceOf(address)` that must return exactly one word.
OpenCall.staticWord token (Remote.balanceOf who)
-- STATICCALL `ownerOf()` that must return one canonical address word.
OpenCall.staticAddress token Remote.ownerOf
-- STATICCALL `supportsInterface(bytes4)` that must return one word equal to 0 or 1.
OpenCall.staticBool target (Remote.supportsInterface id)
-- CALL `sink(uint256,bytes)`: the `BoundedBytes` field is sent as ABI `bytes` at its runtime length.
OpenCall.callSuccess target (Remote.sink tag data)
```

| Helper | Opcode | `CallResult.Policy` | Result in source |
|---|---|---|---|
| `OpenCall.call` | CALL | `canonicalTrueOrCodeBackedEmpty` | `UInt64` effect carrier |
| `OpenCall.callSuccess` | CALL | `contractSuccess` | `UInt64` effect carrier |
| `OpenCall.callValue` | CALL with `msg.value` | `contractSuccess` | `UInt64` effect carrier |
| `OpenCall.callMagic` | CALL | `magicBytes4` (the plan's own selector) | `UInt64` effect carrier |
| `OpenCall.staticWord` | STATICCALL | `exactWord` | `UInt256` |
| `OpenCall.staticWords2` | STATICCALL | `exactWords 2` | first word as `UInt256` |
| `OpenCall.staticWords3` | STATICCALL | `exactWords 3` | first word as `UInt256` |
| `OpenCall.staticWords4` | STATICCALL | `exactWords 4` | first word as `UInt256` |
| `OpenCall.staticBool` | STATICCALL | `strictBool` | `Bool` |
| `OpenCall.staticAddress` | STATICCALL | `words #[.address20]` | `Address` |

`OpenCall.callMagic` is the receiver-hook shape. The callee must answer with exactly one word
equal to the selector it was called by, left-aligned, as `onERC721Received`,
`onERC1155Received`, `onERC1155BatchReceived`, and ERC-1271 `isValidSignature` do. The magic is
computed from the payload constructor; you never write a selector. A wrong selector, a dirty low
byte, an empty frame, a longer frame, or an EOA target reverts the transaction.

```lean
OpenCall.callMagic receiver (Remote.onERC721Received operator origin tokenId data)
```

For the two token hooks the SDK ships the OZ check ready-made: `Erc721.checkOnReceived` and
`Erc1155.checkOnReceived` skip a recipient without code and demand the selector from one with
code. `Ierc1271.checkSignature signer hash signature` is the ERC-1271-only check with a
65-byte `BoundedBytes` signature (one ECDSA `r ‖ s ‖ v`). It has no code-size branch, because a
signer without code answers an empty frame and the magic gate refuses it.
`Ierc1271.checkNow` is OZ `isValidSignatureNow`. A signer with code takes `checkSignature`.
A signer without code recovers the same 65 bytes through `Ecdsa.recover` and reverts
`Unauthorized(signer)` when the address differs. A CALL result is an
effect carrier, so it stands only as the entry's result word; a `safeTransferFrom` puts the
ledger move and the log in the state word and the check under `Effect.thenTrue` as the result,
and the stores land before the CALL:

```lean
.ok ({ dummy := Erc721.transfer owners approvals balances source to tokenId |||
    Erc721.Log.transfer source to tokenId },
  Effect.thenTrue (Erc721.checkOnReceived to Context.caller source tokenId data))
```

A signer check has the same shape. `SignerLink.requireNow` is the combined path.
`requireSigner` stays the 1271-only path. Both count in the state word and carry the check in
the result word, so a refused signature reverts with the counter where it was
(`runtime-tests/evm/anvil_signerlink.sh` drives both against a Solidity ERC-1271 wallet and
an EOA):

```lean
.ok ({ accepted := s.accepted + 1 },
  Effect.thenTrue (Ierc1271.checkNow signer hash signature))
```

The target may be a parameter or a stored `Address`. Arguments are at most eight one-word
scalars (integers, `Address`, fixed bytes), at most two `BoundedVec` array fields, and at most
one `BoundedBytes n` with `n ≤ 65` (the packed `bytes` ceiling, one ECDSA signature), sent as
ABI `bytes` at its runtime length. A plan with an array walks a byte cursor so a later tail can
follow a runtime-length prefix. `string` and a second `bytes` field are refused. A STATICCALL
read is a value. It
can be the body of a view entry, the condition of an `if`, an operand of a comparison, or the
argument of another call:

```lean
-- Run the CALL only when the callee says so. The read happens once, before the branch.
if OpenCall.staticBool target Remote.isOn then OpenCall.callSuccess target Remote.ping else 0
-- Compare a read with a parameter.
UInt256.ge (OpenCall.staticWord token (Remote.balanceOf who)) amt
Address.eq (OpenCall.staticAddress target Remote.ownerOf) who
-- Feed one read to another call.
OpenCall.staticWord token (Remote.echo (OpenCall.staticWord token (Remote.balanceOf who)))
```

A CALL helper's `UInt64` result is an effect carrier, not a value. The call policy has already
decided success before the carrier exists, and the carrier never holds the callee's word. It has
one home: the entry's result word, alone or under `Effect.thenTrue`, `Effect.abort`, or
`Effect.ensure`. A `let` whose binder reaches that word is the same home
(`let sent := Effect.thenTrue (OpenCall.callSuccess t Remote.ping)` followed by
`if s.flag == 0 then .ok ({ s with flag := 1 }, sent) else .error .locked`). Anywhere else does
not compile. A comparison (`OpenCall.callSuccess target Remote.ping == 1`),
an operator (`… + 1`), an `if` condition (with or without `Effect.thenTrue` around it), a state
field (`{ s with flag := OpenCall.callSuccess … }`), a call argument
(`Remote.echo ⟨OpenCall.callSuccess …, 0, 0, 0⟩`), or a `let` whose binder is dropped
(`let _ := OpenCall.callSuccess …`) fails extraction with the `CALL carrier out of place`
reason. Read the callee's answer through a STATICCALL instead. Before this refusal every such
entry compiled. The computed-with shapes lowered to the CALL followed by the constant `0`, so
`callSuccess t Remote.ping == 0` answered `false` on chain where the Lean function answers
`true`; a dropped `let` above an `if` lost the `if` and its stores; `if Effect.thenTrue (call)
then …` stored without running the CALL. `Tests/EvmOpenCallMisuse.lean` holds each refused
shape, and `runtime-tests/evm/anvil_opencall.sh` fails if `pf build` ever compiles it again.
If the callee reverts, or its returndata does not match the policy, your transaction reverts
with `revert(0, 0)`, so no partial state remains. Reentrancy is visible to the callee. Add
`Sdk.Reentrancy` yourself.

Evidence: `runtime-tests/evm/anvil_compose.sh` deploys `Erc20Meta`, `Badge`, and `EvmOpenCall`,
all compiled by `pf`. It moves tokens through `EvmOpenCall.openTransfer` and checks both
balances, the callee `Transfer` log inside the caller transaction, and that an over-balance
callee revert leaves no partial state. It then reads the token's `balanceOf` and `ownerOf` and
the badge's `supportsInterface` answer (both `true` and `false`) through STATICCALL.
`runtime-tests/evm/anvil_opencall.sh` covers every helper against a Solidity callee, including
a bool word of `2`, an address word with dirty high bytes, wrong-size frames, empty EOA
returndata, effect order, the receiver hook against a Solidity mock (the right magic, a wrong
selector, a dirty low byte, empty, four-byte, and two-word frames, an EOA), and reads in value
position (a `Bool` read gating a CALL and selecting
a word, a `UInt256` read under `UInt256.ge`, an `Address` read under `Address.eq`, and a read as
another read's argument), each driven to both outcomes.

Out of scope, and not needed for the call above: `delegatecall`, proxies (ERC-1967, UUPS,
beacons, clones), CREATE and CREATE2 factories, and raw calldata. Bounded ERC-721/1155 receiving
hooks are in via `ReceiverLink`. An ERC-1271 wallet stays out. The list lives in
[oz-sdk-backlog.md](oz-sdk-backlog.md) under permanent non-goals.

## Known sharp edges (be honest in examples)

1. **Effect carrier** — many contracts still park effect results in a `dummy : UInt64` field and thread `hold s`.
2. **Fake guards** — pure-effect methods may need a trivial branch so Extract treats the method as effectful.
3. **Constructor effects** — deployment-time map writes / logs / value transfers are tightly constrained.
4. **Events** — closed LOG helpers (`Event.tipped` / `Event.transfer`) plus typed constructors via `Event.emit` and `Event.Indexed` (S1b; see `Examples.Evm.EvmTypedEvents`). Product typed events are **named ABI events** (LOG1–4): topic0 is always the signature hash; ABI JSON is `"anonymous": false`. That is not anonymous LOG0 (a plan-layer geometry only, not a source `Event.emit` shape). Closed ERC-20 `Transfer`/`Approval` are LOG3. `Collectible` / `Badge` emit canonical ERC-721 `Transfer` / `Approval` / `ApprovalForAll` through `Erc721.Log`. `MultiToken` / `CraftToken` emit canonical ERC-1155 `TransferSingle` / `ApprovalForAll` through `Erc1155.Log`; `MultiToken.safeBatchTransferFrom` also emits `TransferBatch`, whose two `uint256[]` fields are bounded dynamic-array tails. A typed event may end with at most two non-indexed `BoundedVec` fields over a closed scalar (at most 63 elements each); they lower to the ABI head-offset plus length-prefixed tail layout, and an indexed array or a scalar declared after an array fails extraction. `TwoStepCounter` / `Credits` emit Ownable2Step `OwnershipTransferStarted` on `transferOwnership` and Ownable `OwnershipTransferred` on `acceptOwnership`/`renounceOwnership`; renunciation clears owner and pending nominee. They also emit Pausable `Paused`/`Unpaused`; `Capped` emits the pause pair. Constructor init stores the owner argument and empty pending state; it does not log. `EvmStaticCounter` / `EvmStaticRoster` emit canonical AccessControl `RoleGranted` / `RoleRevoked` through `Roles.Log` on actual grant/revoke (no `RoleAdminChanged`); `EvmCrew` extends the same pattern to `Roles.Set4`. `EvmQuota` combines `Nonces` and `RateLimit`; stale nonces revert as `Insufficient(current,provided)` and rate exhaustion uses typed `rateLimitExceeded()` (no quota events). Unbounded event payloads are still refused.
5. **Typed external CALL** — `OpenCall.call` / `callSuccess` / `callValue` / `callMagic` / `staticWord` / `staticWords2` / `staticWords3` / `staticWords4` / `staticBool` / `staticAddress` take a typed `Address` and an inductive constructor (name = ABI function, fields = args; at most two fields may be `BoundedVec` arrays, and one field may be a `BoundedBytes n` with `n ≤ 65`, sent as ABI `bytes` at its runtime length). The compiler assembles calldata and applies one `CallResult` policy. This is not raw CALL: no selector string, caller-built calldata buffer, `delegatecall`, or CREATE2. Reentrancy is visible to the callee; OpenCall does not insert a guard (see `Examples.Evm.EvmOpenCall`).
6. **NFT modules.** Bounded cores with the three canonical ERC-721 events on Collectible/Badge and the two canonical single-id ERC-1155 events on MultiToken/CraftToken. These advertise IERC165 only; incomplete ERC-721/1155 method surfaces must not claim the standard token ids. `MultiToken` adds a bounded `balanceOfBatch` and `safeBatchTransferFrom` over at most four slots (OZ-shaped `ERC1155InvalidArrayLength` and `ERC1155InsufficientBalance` reverts, `DuplicateId()` when two slots name the same id rather than OZ applying those slots in order, OZ log rule of one `TransferBatch` over the submitted slots or `TransferSingle` for a one-slot batch, then the outbound `onERC1155BatchReceived` check). `Collectible.safeTransferFrom`, `Collectible.safeTransferFrom__id`, `CraftToken.safeTransferFrom`, and `MultiToken.safeTransferFrom` run the outbound receiver check (`Erc721.checkOnReceived` / `Erc1155.checkOnReceived` over `OpenCall.callMagic`): the ledger move and the log land first, a recipient without code is not called, and a recipient with code must answer the hook with its own selector or the whole transaction reverts; `data` is at most 32 bytes. `safeTransferFrom__id` is the three-argument ERC-721 overload (empty `data`). `MultiToken.safeBatchTransferFrom` is the same shape with `Erc1155.checkOnBatchReceived`. `ReceiverLink` is the receiving side. `onERC721Received`, `onERC1155Received`, and `onERC1155BatchReceived` return those selectors as `bytes4`, record packed operator/from/id/value plus `data` length, and advertise IERC165 plus IERC721Receiver and IERC1155Receiver. `anvil_receiverlink.sh` drives Collectible, CraftToken, and MultiToken into it (2,145 runtime bytes). Not "ship ERC-721/1155" (no unbounded batches, duplicate ids revert `DuplicateId()` instead of OZ in-order application, no enumeration).
7. **`Examples.Evm.Token` metadata** — `name` / `symbol` are packed `bytes32` (Anvil gates use that shape). Prefer `Erc20Meta` when external tools expect ERC-20 `string` metadata.
8. **ERC-20 consumers.** `SafeErc20` / `SafePay` wrap the closed token CALLs. They are not a raw-calldata escape hatch and do not catch-and-retry a failed CALL. `forceApprove` always emits `approve(0)` then `approve(amount)`. `Vest20Link.release(address)` pays `releasable(token)` through `SafeErc20.transfer`, logs `ERC20Released`, and stores paid amounts in a hashed token map.
9. **ERC-2981** — `RoyaltyArt` is a static receiver + basis-point quote over the full UInt256 sale-price range. `tokenId` is ignored; a zero receiver is invalid and causes the deployment to advertise IERC165 only. There is no per-token royalty map or metadata URI.

These are product debts tracked in [roadmap.md](roadmap.md), not undocumented folklore.

## Build

```bash
# after `pf init demo` (CI job pf-init-user-project runs this same path)
lake build
lake env pf build
```

Artifacts: `Name.bin`, `Name.yul`, `Name.abi.json`.

## Prove

Keep theorems next to the contract. CI refuses `sorry` in the proof batch. Prove properties of the Lean function; do not claim the theorem proved the `.bin`.
