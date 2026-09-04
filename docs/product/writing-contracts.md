# Writing contracts (v0)

## Imports

User projects should import only:

```lean
import ProofForge.Attr
import ProofForge.Evm.Sdk
```

Do **not** import the `ProofForge` umbrella (it can pull Emit / Assemble / Registry).

## Entry shape

Mark chain entries with `@[pf_entry]`. Keep state in an explicit `structure`, errors in an `inductive`, and mutations as `Except`-style transitions when you need revert.

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

-- ERC-20 `transfer(address,uint256)`: true, or empty returndata from an address with code.
OpenCall.call token (Remote.transfer dest amt)
-- STATICCALL `balanceOf(address)` that must return exactly one word.
OpenCall.staticWord token (Remote.balanceOf who)
-- STATICCALL `ownerOf()` that must return one canonical address word.
OpenCall.staticAddress token Remote.ownerOf
-- STATICCALL `supportsInterface(bytes4)` that must return one word equal to 0 or 1.
OpenCall.staticBool target (Remote.supportsInterface id)
```

| Helper | Opcode | `CallResult.Policy` | Result in source |
|---|---|---|---|
| `OpenCall.call` | CALL | `canonicalTrueOrCodeBackedEmpty` | `UInt64` effect carrier |
| `OpenCall.callSuccess` | CALL | `contractSuccess` | `UInt64` effect carrier |
| `OpenCall.callValue` | CALL with `msg.value` | `contractSuccess` | `UInt64` effect carrier |
| `OpenCall.staticWord` | STATICCALL | `exactWord` | `UInt256` |
| `OpenCall.staticWords2` | STATICCALL | `exactWords 2` | first word as `UInt256` |
| `OpenCall.staticWords3` | STATICCALL | `exactWords 3` | first word as `UInt256` |
| `OpenCall.staticWords4` | STATICCALL | `exactWords 4` | first word as `UInt256` |
| `OpenCall.staticBool` | STATICCALL | `strictBool` | `Bool` |
| `OpenCall.staticAddress` | STATICCALL | `words #[.address20]` | `Address` |

The target may be a parameter or a stored `Address`. Arguments are at most eight one-word
scalars (integers, `Address`, fixed bytes). `bytes`, `string`, and arrays are not accepted as
arguments yet. A STATICCALL read is the whole body of a view entry: `readOwner target :=
OpenCall.staticAddress target Remote.ownerOf` compiles, but the same read inside an `if`, an
arithmetic expression, or another call's argument is refused. If the callee reverts, or its
returndata does not match the policy, your transaction reverts with `revert(0, 0)`, so no
partial state remains. Reentrancy is visible to the callee. Add `Sdk.Reentrancy` yourself.

Evidence: `runtime-tests/evm/anvil_compose.sh` deploys `Erc20Meta`, `Badge`, and `EvmOpenCall`,
all compiled by `pf`. It moves tokens through `EvmOpenCall.openTransfer` and checks both
balances, the callee `Transfer` log inside the caller transaction, and that an over-balance
callee revert leaves no partial state. It then reads the token's `balanceOf` and `ownerOf` and
the badge's `supportsInterface` answer (both `true` and `false`) through STATICCALL.
`runtime-tests/evm/anvil_opencall.sh` covers every helper against a Solidity callee, including
a bool word of `2`, an address word with dirty high bytes, wrong-size frames, empty EOA
returndata, and effect order.

Out of scope, and not needed for the call above: `delegatecall`, proxies (ERC-1967, UUPS,
beacons, clones), CREATE and CREATE2 factories, raw calldata, and receiving callbacks such as
`onERC721Received`. The list lives in [oz-sdk-backlog.md](oz-sdk-backlog.md) under permanent
non-goals.

## Known sharp edges (be honest in examples)

1. **Effect carrier** — many contracts still park effect results in a `dummy : UInt64` field and thread `hold s`.
2. **Fake guards** — pure-effect methods may need a trivial branch so Extract treats the method as effectful.
3. **Constructor effects** — deployment-time map writes / logs / value transfers are tightly constrained.
4. **Events** — closed LOG helpers (`Event.tipped` / `Event.transfer`) plus typed constructors via `Event.emit` and `Event.Indexed` (S1b; see `Examples.Evm.EvmTypedEvents`). Product typed events are **named ABI events** (LOG1–4): topic0 is always the signature hash; ABI JSON is `"anonymous": false`. That is not anonymous LOG0 (a plan-layer geometry only, not a source `Event.emit` shape). Closed ERC-20 `Transfer`/`Approval` are LOG3. `Collectible` / `Badge` emit canonical ERC-721 `Transfer` / `Approval` / `ApprovalForAll` through `Erc721.Log`. `MultiToken` / `CraftToken` emit canonical ERC-1155 `TransferSingle` / `ApprovalForAll` through `Erc1155.Log`; `MultiToken.batchTransferFrom` also emits `TransferBatch`, whose two `uint256[]` fields are bounded dynamic-array tails. A typed event may end with at most two non-indexed `BoundedVec` fields over a closed scalar (at most 63 elements each); they lower to the ABI head-offset plus length-prefixed tail layout, and an indexed array or a scalar declared after an array fails extraction. `TwoStepCounter` / `Credits` emit Ownable2Step `OwnershipTransferStarted` on `transferOwnership` and Ownable `OwnershipTransferred` on `acceptOwnership`/`renounceOwnership`; renunciation clears owner and pending nominee. They also emit Pausable `Paused`/`Unpaused`; `Capped` emits the pause pair. Constructor init stores the owner argument and empty pending state; it does not log. `EvmStaticCounter` / `EvmStaticRoster` emit canonical AccessControl `RoleGranted` / `RoleRevoked` through `Roles.Log` on actual grant/revoke (no `RoleAdminChanged`); `EvmCrew` extends the same pattern to `Roles.Set4`. `EvmQuota` combines `Nonces` and `RateLimit`; stale nonces revert as `Insufficient(current,provided)` and rate exhaustion uses typed `rateLimitExceeded()` (no quota events). Unbounded event payloads are still refused.
5. **Typed external CALL** — `OpenCall.call` / `callSuccess` / `callValue` / `staticWord` / `staticWords2` / `staticWords3` / `staticWords4` / `staticBool` / `staticAddress` take a typed `Address` and an inductive constructor (name = ABI function, fields = args). The compiler assembles calldata and applies one `CallResult` policy. This is not raw CALL: no selector string, bytes buffer, `delegatecall`, or CREATE2. Reentrancy is visible to the callee; OpenCall does not insert a guard (see `Examples.Evm.EvmOpenCall`).
6. **NFT modules** — bounded cores with the three canonical ERC-721 events on Collectible/Badge and the two canonical single-id ERC-1155 events on MultiToken/CraftToken. These advertise IERC165 only; incomplete ERC-721/1155 method surfaces must not claim the standard token ids. `MultiToken` adds a bounded `balanceOfBatch` and `batchTransferFrom` over at most four slots (OZ-shaped `ERC1155InvalidArrayLength` and `ERC1155InsufficientBalance` reverts, OZ log rule of one `TransferBatch` over the submitted slots or `TransferSingle` for a one-slot batch, no receiver hook). Not “ship ERC-721/1155” (no safe callbacks, no unbounded batches).
7. **`Examples.Evm.Token` metadata** — `name` / `symbol` are packed `bytes32` (Anvil gates use that shape). Prefer `Erc20Meta` when external tools expect ERC-20 `string` metadata.
8. **ERC-20 consumers** — `SafeErc20` / `SafePay` wrap the closed token CALLs. They are not a raw-calldata escape hatch and do not catch-and-retry a failed CALL. `forceApprove` always emits `approve(0)` then `approve(amount)`.
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
