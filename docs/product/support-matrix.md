# Support matrix (v0 product surface)

> Status: living product contract. If the website, README, and this file disagree, **this file wins**.

## Product one-liner

ProofForge EVM is a **checkout-first Lean 4 → Yul → solc** compiler for a fail-closed single-contract subset, with Anvil engineering gates. It is **not** a mainnet deployment product, not a full ERC suite, and not a proved-bytecode toolchain.

## Backends

| Backend | Product status | CI posture | Notes |
|---|---|---|---|
| `solc` 0.8.34 (pinned) | **Supported default** | Required merge gate | Emits `.bin` / `.yul` / `.abi.json` |
| powdr `yulc` | **Experimental** | Weekly / manual only | Same Yul input; may refuse `gas()` / some CALL shapes; dual-backend Anvil covers Counter / Capped / Const / Flag / Phase / Wide / TipJar. **S2 `CallResult`:** every CALL/STATICCALL already emits `gas()`, so yulc rejects the established ClosedCall path; opt-in `FailMode.bubble` additionally uses dynamic `returndatacopy(0, 0, returndatasize())` / `revert(0, returndatasize())`, which is outside the verified fragment and not dual-backend gated. Multiword `mload` itself is ordinary Yul. Default `FailMode.revert0` keeps ClosedCall spellings. |

## CLI surface

| Command | Status |
|---|---|
| `pf build` | Supported |
| `pf init <name>` | Supported **inside a repo checkout** (copies `templates/evm-counter`, rewrites the published git-tag require to a path require) |
| `pf --version` / `-h` | Supported |
| `pf doctor` / `install` / `artifacts` / `local` | **Not implemented** |
| In-repo MCP server | **Not shipped** |

## Language / extract subset

| Area | Status |
|---|---|
| Ordinary `def` / `structure` / `Except` entries with `@[pf_entry]` | Supported |
| Profile refuse IO / partial / sorry / extern / unbounded recursion | Supported |
| Checked arithmetic, `ite`, bounded `for`, bit ops, narrow ABI, tuples | Supported |
| Env / Addr20 / payable / closed ETH send / typed errors / typed events (`Event.emit`) | Supported. Product typed events are **named ABI events** (LOG1–4: signature topic is always topic0; ABI `"anonymous": false`). Fields are closed scalars (up to three indexed, up to four data words) plus at most two bounded dynamic-array tails: non-indexed `BoundedVec` fields over a closed scalar, declared after every scalar field, at most 63 elements each, lowered to the ABI head-offset and length-prefixed tail layout (`uint256[]` in the signature). Anonymous LOG0 is a plan-layer geometry only; it is not a source `Event.emit` shape. |
| Hashed maps + closed ERC-20 / WETH / UniswapV2 / Permit calls | Supported |
| Typed OpenCall (`OpenCall.call` / `callSuccess` / `callValue` / `callMagic` / `staticWord` / `staticWords2` / `staticWords3` / `staticWords4` / `staticBool` / `staticAddress`) | **Supported** (S3, on `main` as #10; read shapes widened in the Phase 1 expansion PR): CALL/STATICCALL to a typed `Address` target with a compile-time constructor ABI (≤8 args, one-word scalars plus at most two `BoundedVec` array fields and at most one `BoundedBytes n` field with `n ≤ 65`, the packed `bytes` ceiling `Codec.maxPackedBytesCapacity` (one ECDSA signature), sent as ABI `bytes` at its runtime length so the calldata equals `abi.encodeWithSelector`; a plan with an array walks a byte cursor so later tails follow a runtime-length prefix; `BoundedString` and a second `bytes` field are refused). Result gates are S2 `CallResult` policies; `callMagic` is the receiver-hook shape, a CALL whose one returned word must be the plan's own selector (`onERC721Received`, `onERC1155Received`, `onERC1155BatchReceived`, ERC-1271 `isValidSignature`), with the magic computed from the constructor; STATICCALL reads come back typed as `UInt256`, `Bool`, or `Address` and stand anywhere such a value can: an entry's result, an `if` condition, a comparison operand, or another call's argument. A read used in several limbs runs once. CALL results are effect carriers, not values: a carrier stands only as the entry's result word, alone or under `Effect.thenTrue`; a comparison, an operator, an `if` condition, a state field, a call argument, or a dropped `let` around one is refused at extraction with the `CALL carrier out of place` reason (`Tests/EvmOpenCallMisuse.lean` is the refused fixture; `anvil_opencall.sh` fails if `pf build` compiles it). No raw calldata, selector string, return-buffer length, opcode, `delegatecall`, CREATE2, or proxy. Reentrancy is application-visible. Calling another contract needs no proxy: `runtime-tests/evm/anvil_compose.sh` moves tokens from one `pf`-compiled contract into another through `OpenCall.call`. See [writing-contracts.md](writing-contracts.md#call-another-contract). |
| CallResult S2 (`exactWords n`, `strictBool`, `magicBytes4`, typed `words`) | **Supported** (S2, on `main` as #9): ≤4 ABI words. ClosedCall still uses the original three policies. OpenCall consumes `canonicalTrueOrCodeBackedEmpty` / `contractSuccess` / `exactWord` / `exactWords 2..4` / `strictBool` / `words #[.address20]` via the nine helpers above. Default fail mode is `revert(0, 0)` |
| Effect ergonomics without `dummy` / `hold` / fake guards | **Debt** (see roadmap) |
| `delegatecall` / CREATE2 / proxy / arbitrary calldata / unbounded loops | **Out of scope**. These are upgrade, creation, and raw-payload mechanisms. They are not required to call another contract (see the OpenCall row) |

## SDK naming honesty

| Module | Say this | Do **not** say this |
|---|---|---|
| `Examples.Evm.Erc20Meta` | ERC-20-shaped ABI: `string` name/symbol, standard `allowance` / `transfer` / `approve` selectors | “Audited EIP-20” / mainnet token factory |
| Fungible + `Examples.Evm.Token` | ERC-20-style ledger / allowance policy; **`name`/`symbol` are packed `bytes32`**, and several views use `*Of` names | “Full ERC-20” / drop-in for MetaMask token import without checking ABI |
| `Erc165` | Static `bytes4` interface IDs and bounded, explicitly declared support predicates. The four partial token examples advertise `IERC165` only and return false for ERC-721/1155, `0xffffffff`, and other undeclared IDs. `ReceiverLink` advertises IERC165 plus IERC721Receiver and IERC1155Receiver. `RoyaltyArt` advertises IERC165 + complete IERC2981 only with a nonzero receiver | Runtime discovery, inferred interface lists, or claiming an incomplete standard interface |
| `SafeErc20` + `SafePay` | Fail-closed ERC-20 consumer helpers: closed `transfer`/`approve`/`transferFrom`, zero-address gates, checked increase/decrease, USDT `forceApprove` as always `approve(0)` then `approve(amount)`. No raw calldata | Drop-in OpenZeppelin SafeERC20; catching a failed CALL and retrying |
| `Vesting` + `VestLink` / `Vest20Link` | Native-ETH `VestLink.release(uint256)` pays an explicit amount at or below `releasable()`. `Vest20Link.release(address)` pays `releasable(token)` through `SafeErc20.transfer`, logs `ERC20Released`, and stores paid amounts in a hashed token map. Driven in `anvil_vest20link.sh` | Drop-in OpenZeppelin VestingWallet (beneficiary rotation, parameterless ETH `release()`) |
| `Erc2981` + `RoyaltyArt` | Static royalty quote: nonzero constructor receiver + compile-time basis points; exact full-range `royaltyInfo(uint256,uint256) → (address,uint256)`; token id ignored; zero receiver advertises IERC165 only | Per-token royalty map, metadata URI, or an OpenZeppelin ERC2981 clone |
| `Erc721` + `Collectible` / `Badge` / `Gallery` / `ReceiverLink` | Bounded ownership/approval/balance **core**, plus the outbound receiver check: `Collectible.safeTransferFrom(address,address,uint256,bytes)` moves the token, emits `Transfer`, then runs `Erc721.checkOnReceived` (OZ `checkOnERC721Received` over `OpenCall.callMagic`: a recipient with code must answer `onERC721Received` with its own selector or the whole transaction reverts empty; a recipient without code is not called; `data` at most 32 bytes). `Collectible.safeTransferFrom__id` is the three-argument overload (empty `data`, selector `0x42842e0e`). A receiver reading `ownerOf` inside the hook sees itself. Collectible and Badge emit the three canonical ERC-721 events via `Erc721.Log` (`Transfer` LOG4, `Approval` LOG4, `ApprovalForAll` LOG3); neither advertises the incomplete IERC721 interface ID. `Gallery` is the bounded IERC721Enumerable profile: `totalSupply`, `tokenByIndex`, and `tokenOfOwnerByIndex` over UInt64 ids with compile-time capacity 4, owner-only `transferFrom`/`burn`, and IERC165 only. Driven in `anvil_gallery.sh`. `ReceiverLink.onERC721Received` is the receiving side and returns `0x150b7a02` as `bytes4`; 2,145 runtime bytes, driven in `anvil_receiverlink.sh` | Full ERC-721 (metadata URI, unbounded IERC721Enumerable, complete function set) |
| `Ierc1271` + `SignerLink` | `Ierc1271.checkNow signer hash signature` is OZ `isValidSignatureNow` as a fail-closed carrier. A signer with code takes `checkSignature` (`isValidSignature` via `OpenCall.callMagic`, magic `0x1626ba7e`). A signer without code recovers a 65-byte `r ‖ s ‖ v` through `Ecdsa.recover` and reverts `Unauthorized(signer)` on mismatch. `SignerLink.requireNow` counts accepted checks. `requireSigner` stays the 1271-only path. Driven in `anvil_signerlink.sh` against an EOA and a Solidity ERC-1271 wallet, including an `extcodesize` mutation | Drop-in OpenZeppelin SignatureChecker (`false` instead of revert, signatures wider than 65 bytes); an ERC-1271 wallet (the receiving side is a non-goal) |
| `Erc1155` + `MultiToken` / `CraftToken` / `ReceiverLink` | Bounded single-id ownership/balance **core**, plus a bounded `balanceOfBatch` on `MultiToken` (at most four pairs; unequal lengths answer `[]` because a view cannot revert) and a bounded `safeBatchTransferFrom` on `MultiToken` (at most four slots; duplicate ids revert `DuplicateId()`, which is not OZ's in-order application; OZ-shaped `ERC1155InvalidArrayLength` and `ERC1155InsufficientBalance` reverts; OZ log rule, one `TransferBatch` over the submitted slots or `TransferSingle` for a one-slot batch; then the outbound `onERC1155BatchReceived` check). `CraftToken.safeTransferFrom` and `MultiToken.safeTransferFrom(address,address,uint256,uint256,bytes)` are the single transfer with the outbound receiver check (`Erc1155.checkOnReceived`, OZ `checkOnERC1155Received` over `OpenCall.callMagic`: a recipient with code must answer `onERC1155Received` with its own selector or the whole transaction reverts empty; a recipient without code is not called; `data` at most 32 bytes); a receiver reading `balanceOf` inside the hook sees the credited balance. `MultiToken.safeBatchTransferFrom` is the same shape with `Erc1155.checkOnBatchReceived` over two `uint256[]` OpenCall args plus `bytes`. `MultiToken` is 18,925 runtime bytes after the pair-map load helper (5,651 under EIP-170). These two examples emit canonical ERC-1155 `TransferSingle` (LOG4, `id`+`value` data words) and `ApprovalForAll` (LOG3, bool data) via `Erc1155.Log`; `MultiToken` also emits `TransferBatch` (LOG4, two bounded `uint256[]` tails); neither advertises the incomplete IERC1155 interface ID. `ReceiverLink` answers `onERC1155Received` (`0xf23a6e61`) and `onERC1155BatchReceived` (`0xbc197c81`) as `bytes4`; 2,145 runtime bytes | Full ERC-1155 (unbounded batches, OZ in-order duplicate-id application, complete function set) |
| `Ownable.Log` + `TwoStepCounter` / `Credits` | Canonical `OwnershipTransferred` (LOG3) on **`acceptOwnership`** and **`renounceOwnership`**, and Ownable2Step `OwnershipTransferStarted` (LOG3) on **`transferOwnership`**. Renunciation clears owner plus the sole `pendingOwner()` nominee. Constructor init stores the owner argument and empty pending state; constructor logs and zero-owner constructor reverts are not lowered | Drop-in OpenZeppelin Ownable / Ownable2Step |
| `Pausable.Log` + `TwoStepCounter` / `Credits` / `Capped` | Canonical `Paused` / `Unpaused` (LOG1, non-indexed `account` = caller) on **`pause` / `unpause`**. `Token` pause still does not emit these | Drop-in OpenZeppelin Pausable |
| `Roles.Log` + `EvmStaticCounter` / `EvmStaticRoster` | Canonical `RoleGranted` / `RoleRevoked` (LOG4, empty data; `bytes32` role + account + sender all indexed) on **actual** bounded `Set2` grant/revoke. Idempotent no-ops do not log. No `RoleAdminChanged`, ERC-165, or `mapping(bytes32 => …)` AccessControl | Drop-in OpenZeppelin AccessControl |
| `Roles.Log` + `EvmCrew` | Same LOG4 role events on **actual** bounded `Set4` grant/revoke (four explicit address slots). Fifth distinct grant fails closed with `CapExceeded()` | Drop-in OpenZeppelin AccessControl |
| `Nonces` + `RateLimit` + `EvmQuota` | Per-address nonce map (`AddressMap256`) with checked consumption; fixed-window rate limit (`capacity`/`window` + per-caller `lastUsed`/window-start maps). Stale nonces use the closed `Insufficient(current,provided)` revert; rate exhaustion uses typed `rateLimitExceeded()`. No token-bucket refill or sliding-window limiter | Drop-in OpenZeppelin Nonces / RateLimiter |
| Reentrancy | Explicit policy helpers | Drop-in OpenZeppelin clone |

## Networks / deploy

| Target | Status |
|---|---|
| Anvil + `runtime-tests/evm/` (default chain id `31338`) | **Supported** engineering gate |
| External RPC (`PF_EVM_RPC_URL` + required `PF_EVM_CHAIN_ID`) | Same `anvil_*.sh` / `scripts/deploy_evm.sh` path; fail-closed chain-id; `anvil_setStorageAt` disabled; **not** a merge-required public-network gate |
| Anvil `--chain-id 84532` / `84538453` (`EvmChainGuard`) | **Supported locally** — impersonates Base Sepolia / VibeNet numeric ids; not a public-RPC claim |
| Base Sepolia (`84532`) / Base VibeNet (`84538453`) ordinary EOA create of `.bin` | Possible as generic EVM RPC; **not CI-gated**; do not claim “verified on Base” from Anvil |
| Base Mainnet / any production chain | **Not endorsed** |
| VibeNet EIP-8130 AA / payers | **Out of scope** for ProofForge |

See [deploy.md](deploy.md) for the checkout → `.bin` → RPC story, including `scripts/deploy_evm.sh`.

## Proof boundary

| Claim | Status |
|---|---|
| Kernel-checked theorems about user `def` / static fields | Yes (examples + no-sorry CI) |
| Theorems about hashed-map balances / world state | Not yet |
| Theorems about Yul / `.bin` / EVM refinement | **Not claimed** |
| Anvil green ⇒ proved on-chain behavior | **Not claimed** (engineering gate only) |

## User-project path (supported)

From repo root after toolchain setup:

```bash
lake build pf
export PATH="$PWD/.lake/build/bin:$PATH"
pf init demo
cd demo
lake build
lake env pf build
```

CI job `pf-init-user-project` gates this exact command (`pf init demo`, then build artifacts).
`pf init` copies `templates/evm-counter` and, from a checkout, rewrites the published git-tag `require` (`@ "v0.1.0"`) to a path `require`. That is the CI path.

When a `v0.1.0` GitHub Release exists, download `pf-linux-x86_64` or `pf-macos-aarch64` and use Lake `require … @ "v0.1.0"` for `proofforge`. `proofforge-common` stays `@ "main"`. There is no standalone installer and no `curl | sh` install. `pf init` still needs the checkout for templates.

## Related

- Writing guide: [writing-contracts.md](writing-contracts.md)
- Deploy story: [deploy.md](deploy.md)
- Roadmap: [roadmap.md](roadmap.md)
- OpenZeppelin-shaped SDK backlog: [oz-sdk-backlog.md](oz-sdk-backlog.md)
- Module internals: [../modules/](../modules/)
- Historical research (archived): [../research/](../research/)
