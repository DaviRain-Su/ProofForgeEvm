# OpenZeppelin-shaped runtime SDK backlog

> Status: living implementation inventory. This is a compatibility-shaped SDK plan, not a claim
> that ProofForge is a Solidity/OpenZeppelin replacement.
>
> **Authority snapshot:** `contracts/` from
> [`OpenZeppelin/openzeppelin-contracts` master tree
> `641ba990cad2f7f70878e0d66be1bfbef95710e8`](https://api.github.com/repos/OpenZeppelin/openzeppelin-contracts/git/trees/641ba990cad2f7f70878e0d66be1bfbef95710e8),
> fetched on 2026-09-03 with
> `gh api 'repos/OpenZeppelin/openzeppelin-contracts/git/trees/master?recursive=1'`.
> It contained 452 `contracts/` tree paths (367 Solidity sources), spanning `access`, `account`,
> `crosschain`, `finance`, `governance`, `interfaces`, `metatx`, `mocks`, `proxy`, `token`,
> `utils`, `vendor`, documentation, and package metadata.
>
> Status labels describe the fail-closed ProofForge product boundary, not source-code similarity:
> **DONE** means the bounded runtime capability is shipped; **PARTIAL** means a named restricted
> profile exists; **ABSENT** means no corresponding profile is shipped.

## Coverage

| OZ path | Status | ProofForge module / example | Gap relative to OZ | Implementable? (blocker) |
|---|---|---|---|---|
| `access/Ownable.sol`, `Ownable2Step.sol` | PARTIAL | `Sdk.Access`, `Sdk.Ownable`, `TwoStepCounter`, `Credits` | Constructor logs/zero-owner revert not lowered; bounded runtime transfer/accept/renounce profile shipped | Start event: W3; `renounceOwnership`: W5 slice 5; constructor effects: no (`Emit` refuses constructor effects) |
| `access/AccessControl.sol`, `IAccessControl.sol` | PARTIAL | `Sdk.Roles.Set2`/`Set4`, `EvmStaticCounter`, `EvmStaticRoster` | Set2/Set4 fixed capacity, no role admin hierarchy/enumeration | `RoleAdminChanged`: no (no role-admin state/API); unbounded named roles: no |
| `access/extensions/*`, `access/manager/*` | PARTIAL | `Sdk.DefaultAdminDelay`, `AdminDelayLink` | Bounded delayed default-admin only; no role enumeration or authority manager | Yes — W5 slice e shipped bounded delayed default-admin profile; enumeration/manager remain blocked |
| `account/**` | ABSENT | — | ERC-4337/7579 account, paymaster, execution modes | No — AA/paymaster and arbitrary execution are product non-goals |
| `crosschain/**` | ABSENT | — | Bridge state, remote executor, receiver callbacks | No — cross-chain authentication/callback model is absent |
| `finance/VestingWallet*.sol` | PARTIAL | `Sdk.Vesting`, `VestLink`, `Context.timestamp` | ERC-20 vesting map, beneficiary rotation, parameterless release mutation | Yes — W4 slice 3 shipped a native-ETH single-beneficiary profile whose `release(uint256)` permits only partial payouts at or below current `releasable()` and uses an ordered reentrancy lock |
| `governance/**` | ABSENT | `Sdk.StorageCheckpoints` only | Proposal/vote/quorum/timelock lifecycle | No — Governor requires unconstrained proposal/voter relations and token snapshot semantics |
| `interfaces/IERC165.sol` | DONE | `Sdk.Erc165`, `Collectible`, `Badge`, `MultiToken`, `CraftToken` | Static, explicitly declared `IERC165` only; incomplete token interfaces return false | Yes — W1 shipped |
| `interfaces/IERC20*.sol`, `IERC2612.sol` | PARTIAL | `Sdk.Fungible`, `Sdk.Erc20Meta`, `Sdk.SafeErc20`, `Erc20Meta`, `Token`, `SafePay`, `Sdk.Payments` | Profiles, not a complete audited token; permit is closed call/internal; no extensions/permit-votes ecosystem; mint gap closed on `Erc20Meta` (owner-gated) | Yes — W5 slice 4 shipped bounded string metadata SDK + typed canonical Transfer/Approval on `Erc20Meta`; W5 slice 6 closed owner-gated mint on `Erc20Meta`; extensions/permit-votes remain blocked |
| `interfaces/IERC721*.sol`, `IERC4906.sol`, `IERC2309.sol` | PARTIAL | `Sdk.Erc721`, `Sdk.MetadataUri`, `Collectible`, `Badge`, `ArtLink`, `Sdk.Erc165` | No safe receiver callback, enumeration, or consecutive mint; bounded metadata URI shipped | Receiver/enumeration: no; bounded metadata: W4 |
| `interfaces/IERC1155*.sol` | PARTIAL | `Sdk.Erc1155`, `Sdk.MetadataUri`, `MultiToken`, `CraftToken`, `PackLink`, `Sdk.Erc165` | No callbacks, `balanceOfBatch`, or `TransferBatch`; bounded metadata URI shipped | `TransferBatch`: no (dynamic arrays/events); bounded URI: W4 |
| `interfaces/IERC2981.sol` | DONE | `Sdk.Erc2981`, `RoyaltyArt`, `Sdk.Erc165` | Static receiver + basis-point quote; `tokenId` ignored | Yes — W2 shipped |
| `interfaces/IERC1271.sol` | ABSENT | `Precompile` internals | Contract signature validation response | No — requires arbitrary external contract call/result protocol |
| `interfaces/IERC3156*.sol`, `IERC4626.sol`, `IERC6909.sol`, `IERC777*.sol`, `IERC1363*.sol` | PARTIAL | `Sdk.Erc4626`, `Sdk.Erc6909`, `Vault4626Link`, `NineLink` | Flash callbacks, hooks, dynamic exchange-rate vault math, broad multi-id operator model | Yes — W5 slice 7 shipped bounded 1:1 ERC-4626 vault profile; W5 slice 8 shipped bounded fixed-id ERC-6909; flash/777/1363 remain blocked |
| `interfaces/IERC1820*.sol`, `IERC1967.sol`, `IERC1822.sol` | ABSENT | — | Global registry/proxy-slot interoperability | No — registry/proxy non-goals |
| `interfaces/IERC5267.sol`, `IERC5313.sol`, `IERC6372.sol`, `IERC5805.sol` | PARTIAL | `Context`, `Permit`, `Sdk.Eip712Domain`, `Sdk.Ierc5313`, `Sdk.Ierc6372`, `DomainLink`, `OwnerLink`, `ClockLink` | EIP-712 domain, owner, clock/votes views | Static domain fields: W4 slice 2; owner/clock views: W5 slice 5b; votes (IERC5805) blocked by votes model |
| `interfaces/draft-IERC3009.sol`, `IERC7674.sol`, `IERC7751.sol`, `IERC7786.sol`, `IERC7802.sol`, `IERC7821.sol` | PARTIAL | `Sdk.Erc3009`, `Auth3009Link` | Bounded `transferWithAuthorization` only; no receive-with-authorization, cancellation, or cross-chain/account protocols | Yes — W5 slice e shipped typed bounded ERC-3009 closed-call profile; remaining draft interfaces remain blocked |
| `metatx/ERC2771*.sol` | ABSENT | — | Trusted-forwarder sender/calldata suffix | No — raw/rewritten calldata is prohibited |
| `proxy/**`, `interfaces/IERC1967.sol` | ABSENT | — | Delegate proxy, beacon, clones, UUPS | No — `delegatecall`, proxy, CREATE2 are permanent non-goals |
| `token/ERC20/**` | PARTIAL | `Sdk.Fungible`, `Sdk.Erc20Meta`, `Sdk.SafeErc20`, `Erc20Meta`, `Token`, `SafePay` | No complete extensions/permit-votes ecosystem; `Token` keeps packed `bytes32` metadata; mint gap closed on `Erc20Meta` (owner-gated) | Yes — W5 slice 4 shipped `Sdk.Erc20Meta` + `Fungible.Log` typed Transfer/Approval on `Erc20Meta`; W5 slice 6 closed owner-gated mint on `Erc20Meta`; extensions/permit-votes remain blocked |
| `token/ERC721/**` | PARTIAL | `Sdk.Erc721`, `Sdk.MetadataUri`, `Collectible`, `Badge`, `ArtLink` | Core plus bounded metadata; no receiver/enumeration | See IERC721 row |
| `token/ERC1155/**` | PARTIAL | `Sdk.Erc1155`, `Sdk.MetadataUri`, `MultiToken`, `CraftToken`, `PackLink` | Single-id core plus bounded metadata | See IERC1155 row |
| `token/ERC6909/**` | PARTIAL | `Sdk.Erc6909`, `NineLink` | Fixed single-id profile only; no dynamic multi-id registration | Yes — W5 slice 8 shipped bounded fixed-id ERC-6909 using existing map primitives |
| `token/common/ERC2981.sol`, `ERC1363Utils.sol` | PARTIAL | `Sdk.Erc2981`, `RoyaltyArt` | Static royalty only; no transfer-and-call | Royalty: W2 shipped; transfer-and-call: no callbacks |
| `utils/Context.sol`, `Pausable.sol`, `ReentrancyGuard*.sol` | PARTIAL | `Sdk.Base.Context`, `Sdk.Pausable`, `Sdk.Reentrancy` | Explicit policy helpers, not Solidity inheritance/transient storage clone | Pause events shipped S4b; no further W3 event gap |
| `utils/Address.sol`, `LowLevelCall.sol`, `Multicall.sol`, `RelayedCall.sol`, `SimulateCall.sol`, `Calldata.sol`, `Memory.sol` | ABSENT | `OpenCall` is typed and closed | Arbitrary call/data/delegate/value helpers | No — arbitrary calldata/call and delegatecall prohibited |
| `utils/cryptography/**` | PARTIAL | Keccak/SHA-256, fixed EIP-712 permit path, `Sdk.Ecdsa`, precompile internals | No general Merkle/SignatureChecker public SDK beyond bounded recover | Bounded Merkle proof: W4; public typed ecrecover: W5 slice 5b (`Sdk.Ecdsa`, `RecoverLink`); general signature checker: no arbitrary ERC-1271 call |
| `utils/math/**`, `SafeCast.sol`, `Panic.sol`, `Errors.sol`, `Comparators.sol` | PARTIAL | `Core.Math`, `Core.SafeCast`, `UInt256`, closed `Revert` | Not full Solidity numeric/type/error families | Existing IR already covers the bounded UInt64 math / SafeCast profiles; remaining families stay PARTIAL |
| `utils/structs/**`, `Arrays.sol`, `Bytes.sol`, `Strings.sol`, `Base*`, `RLP.sol`, `Packing.sol`, `ShortStrings.sol` | PARTIAL | Bounded vec/ring/bitmap/enumerable structures, fixed bytes | No general dynamic bytes/strings/arrays/enumerable map semantics | Fixed-capacity variants only — W4; general versions no |
| `utils/Create2.sol`, `Create3.sol`, `StorageSlot.sol`, `SlotDerivation.sol`, `TransientSlot.sol`, `draft-InteroperableAddress.sol` | ABSENT | — | Contract creation, arbitrary slots, transient/interoperable address encodings | No — creation/slot escape hatches non-goals |
| `utils/Blockhash.sol`, `BlockHeader.sol`, `ERC6372Utils.sol`, `Nonces*.sol`, `RateLimiter.sol` | PARTIAL | `Sdk.Nonces`, `Sdk.RateLimit`, `Sdk.BlockHeader`, `Sdk.Ierc6372`, `EvmQuota`, `HeaderLink`, `ClockLink`, `Context.blockHash`, block fields, hashed/static storage | Fixed-window counter only; no token-bucket refill or sliding window | Nonce/rate profile: W3 slice 2; header profile: W5 slice d (`Sdk.BlockHeader`, `HeaderLink`); bounded ERC6372 clock helpers: W5 slice 5b (`Sdk.Ierc6372`, `ClockLink`) |
| `vendor/**`, `mocks/**` | ABSENT | — | Upstream dependencies and test fixtures | No — not runtime SDK surface |

## Prioritized implementation waves

| Wave | Scope | Status |
|---|---|---|
| W1 | Static ERC-165 core (`bytes4` IDs, bounded support predicates), adopt `supportsInterface` in both ERC-721- and ERC-1155-shaped examples, compiler/ABI and Anvil gates | Verified on `cursor/oz-sdk-w1-e4eb`: targeted and full `lake build Tests`, plus four Anvil gates. The examples advertise `IERC165` only: their partial ERC-721/1155 method surfaces must return false for the standard token IDs. |
| W2 | ERC-20-shaped consumer ergonomics: explicit safe-transfer/allowance policy helpers and a static ERC-2981 royalty profile | Verified on `cursor/oz-sdk-w2-e4eb`: targeted `Tests.EvmSafeErc20Spec` / `Tests.EvmErc2981Spec` and full `lake build Tests` (218 jobs), plus `anvil_safepay.sh` and `anvil_royaltyart.sh`. `forceApprove` is always `approve(0)` then `approve(amount)`. With a nonzero receiver, `RoyaltyArt` advertises IERC165 + complete IERC2981, returns false for IERC721/IERC1155, and quotes the full UInt256 sale-price range; a zero receiver advertises IERC165 only. |
| W3 | Bounded access/utility closeout: Ownable2Step start event and constructor-init policy where extractable; fixed-capacity role profiles; bounded nonce/rate helpers | Verified on `cursor/oz-sdk-w3-e4eb`: slice 1 (PR #18, Ownable2Step LOG3 `OwnershipTransferStarted`, `canInit`); slice 2 (`Sdk.Nonces`, `Sdk.RateLimit`, `EvmQuota`, `Roles.Set4`/`EvmCrew` with LOG4 role events, closed nonce/rate failures, `anvil_evmquota.sh` + `anvil_evmcrew.sh`, full `lake build Tests` (228 jobs)) |
| W4 | Static metadata/finance/crypto profiles: bounded ERC-721/1155 URI response, EIP-5267-style static domain fields, single-beneficiary vesting, bounded Merkle proofs | Verified on `cursor/oz-sdk-w4-e4eb`: slice 1b bounded ERC-721/1155 URI (`MetadataUri`, `ArtLink`, `PackLink`); slice 2 EIP-5267-style split domain fields (`Eip712Domain`, `DomainLink`); slice 3 bounded native-ETH vesting with constrained partial release and ordered reentrancy lock (`Vesting`, `VestLink`, `anvil_vestlink.sh`); slice 4 true depth-8 bounded Merkle proof folding (`MerkleProof`, `ProofLink`, sorted-pair ABI-order `keccak256`, fail-closed zero-root/over-capacity gates, `Tests.EvmMerkleProofSpec`, `anvil_prooflink.sh`). |
| W5 | Completion audit: re-inventory the then-current OZ tree, prove every remaining item is either DONE, a restricted PARTIAL profile, or blocked by a documented non-goal | Slice 1 on `cursor/oz-sdk-w5-e4eb`: authority tree re-inventory unchanged (`641ba990`, 452 paths / 367 `.sol`); `Sdk.OzAudit` compile-time counters (32 rows: 2 DONE / 16 PARTIAL / 14 ABSENT), `AuditLink` witness, `Tests.EvmOzAuditSpec`, `anvil_auditlink.sh`. Slice 2: bounded static table with per-row path tag + DONE/PARTIAL/ABSENT + blocker bit, `statusOf`/`isBlocked`/`pathTagOf`/`allRowsClassified` predicates, extended `AuditLink` + spec + Anvil loop over all 32 rows. Slice 3: permanent non-goal category tags (`nonGoalTagOf`, six documented categories + `nonGoalNone`, `allBlockedRowsTagged`, `auditOkEvidence`) linking each of the 14 ABSENT rows to `§ Permanent non-goals` evidence; extended `AuditLink` + spec + Anvil non-goal checks. Slice 4: ERC-20 metadata/event closeout — `Sdk.Erc20Meta` bounded string name/symbol publish gates, `Fungible.Log` typed canonical Transfer/Approval, `Erc20Meta` consumer refactor, `Tests.Erc20MetaSpec` typed-event ABI pins, `anvil_erc20meta.sh`. Slice 5: strict-audit closeout of bounded runtime `renounceOwnership` on `TwoStepCounter`/`Credits`, clearing owner and pending nominee and emitting canonical `OwnershipTransferred(owner,address(0))`; constructor effects remain blocked. Slice 6: owner-gated mint on `Erc20Meta` (fail-closed `Unauthorized`/`ZeroAddress`, canonical mint `Transfer` from zero, `totalSupply` tracks minted supply); `anvil_erc20meta.sh` mints via transaction (no storage injection); rows 9/20 mint gap closed — IERC20/`token/ERC20` rows stay PARTIAL (extensions/permit-votes ecosystem blocked). Slice d: `Sdk.OzAudit` blocker model honesty (`isBlocked` independent of `isAbsent`, `isTemporaryGap`/`blockedImpliesAbsent`, `temporaryGapCount`); bounded Blockhash/BlockHeader profile (`Sdk.BlockHeader`, `HeaderLink`, `Tests.EvmBlockHeaderSpec`, `anvil_headerlink.sh`); row 30 header gap closed. Slice 7: bounded ERC-4626 vault profile — `Sdk.Erc4626`, `Vault4626Link`, `Tests.EvmErc4626Spec`, `anvil_vault4626link.sh`; row 13 PARTIAL. Slice 8: bounded fixed-id ERC-6909 — `Sdk.Erc6909`, `NineLink`, `Tests.EvmErc6909Spec`, `anvil_ninelink.sh`; row 22 PARTIAL. Slice e: bounded delayed default-admin profile (`Sdk.DefaultAdminDelay`, `AdminDelayLink`, row 2 PARTIAL) and typed bounded ERC-3009 transfer-with-authorization (`Sdk.Erc3009`, `Auth3009Link`, row 16 PARTIAL); `Tests.EvmDefaultAdminDelaySpec` / `Tests.EvmErc3009Spec`, `anvil_admindelaylink.sh` / `anvil_auth3009link.sh`. Branch bases on W4 + merges `main` for W3 slice 2 deps. |

W5 slice 5b is also stacked on the completion branch: `Sdk.Ierc5313`/`OwnerLink`,
`Sdk.Ierc6372`/`ClockLink`, and public typed `Sdk.Ecdsa.recover`/`RecoverLink`, with focused Lean
and Anvil gates.

## Expansion phases after W5

W5 closed the audit: every row is DONE, a named PARTIAL profile, or blocked by a documented
non-goal, and `temporaryGapCount` is 0. The phases below widen the PARTIAL profiles toward the
contract shapes people build most often. Each phase lands as its own PR with a Lean spec, an
Anvil gate listed in `runtime-tests/evm/anvil.sh`, and a row edit in the coverage table. The
`Sdk.OzAudit` counters must equal the coverage table at every commit.

Reopening a line under § Permanent non-goals takes one PR that edits that line, changes the
matching `Sdk.OzAudit` row or tag with new `Tests.EvmOzAuditSpec` pins, and ships the Anvil gate.
A phase that only widens a PARTIAL profile does not touch that section.

| Phase | Goal | What changes | Evidence | Non-goal touched |
|---|---|---|---|---|
| 0 | Prove and document that one contract calls another without a proxy. Close the gate drift. | `anvil.sh` runs `clocklink`, `ownerlink`, `recoverlink`, and the new `anvil_compose.sh` (`EvmOpenCall` CALLs `Erc20Meta`, both `pf`-compiled). `scripts/check_anvil_suite.py` fails CI when a committed gate is not run. `writing-contracts.md` § Call another contract. Website Limits copy no longer says "dynamic callee". | `anvil_compose.sh` ok; `check_anvil_suite.py` ok (75 gates); counters unchanged | None |
| 1 | Richer typed call shapes for composition: STATICCALL returns typed as `Bool` and `Address`, three and four exact words, and one bounded `bytes` argument. | New `Runtime` stubs and `OpenCall.Source` helpers, `Decode` recognition, `OpenCall/Emit.lean` calldata tail for `BoundedBytes n`. `argScalarSupported` grows one bounded-bytes carrier. | `Tests.EvmOpenCallSpec` plan pins; `anvil_opencall.sh` and `anvil_compose.sh` read a balance and an owner through STATICCALL | None. Arbitrary calldata stays out; the tail is one typed bounded argument |
| 2 | Bounded ERC-1155 batch: `safeBatchTransferFrom` and `balanceOfBatch` over `BoundedVec UInt256 n`, and a bounded `TransferBatch` event. | `Sdk.Erc1155` batch predicates and effects; `MultiToken` gains the two entries. `NativeFx.eventScalarSupported` admits a bounded array field, `LogError.maxLogDataWords` grows to hold two offsets, two lengths, and `2n` elements, and topic0 renders `uint256[]`. | `Tests.EvmErc1155Spec`; `anvil_multitoken.sh` decodes `TransferBatch` and `balanceOfBatch` | Yes. The "ERC-1155 dynamic batches" line becomes "bounded batches of at most `n`"; rows 10 and 21 stay PARTIAL with a narrower gap |
| 3 | Outbound receiver and signer checks through typed CALL with the `magicBytes4` policy: `onERC721Received`, `onERC1155Received`, and ERC-1271 `isValidSignature` with a `BoundedBytes 65` signature. | Depends on Phase 1. `Sdk.Erc721`/`Sdk.Erc1155` safe-transfer decisions; `Sdk.Ierc1271` bounded check. | Anvil gates against a Solidity receiver and a Solidity ERC-1271 wallet | Yes. Row 12 flips ABSENT to PARTIAL (`absentCount` 9, `blockedCount` 9, `partialCount` 21). The callback line narrows to "receiving hooks"; calling a known hook with a fixed ABI is in |
| Never | Delegatecall proxies, CREATE and CREATE2 factories, account abstraction, Governor, raw calldata | | | Stay listed below |

## Permanent non-goals

The following do not become supported merely because OZ has a module with a similar name:

- Proxies, UUPS/beacons/clones, `delegatecall`, CREATE/CREATE2/CREATE3, arbitrary storage-slot
  derivation, and transient-slot APIs.
- Raw or arbitrary calldata, generic low-level calls, multicall/simulation, ERC-2771 forwarded
  calldata, and callback-driven receiver/hook protocols.
- Account abstraction, ERC-4337/7579 execution, paymasters, and EIP-8130 payer flows.
- Governor/timelock/votes systems, unbounded proposal/voter/account relations, and unbounded
  enumerable map/set semantics. Existing hashed-map leaves are fixed-purpose storage primitives;
  they are not a promise to provide arbitrary, enumerable unbounded map APIs.
- ERC-1155 dynamic batches and `TransferBatch`; current typed event frames are static and bounded.
- Cross-chain bridge/executor protocols, global registries, mainnet endorsement, and bytecode
  refinement proofs.

For the general product boundary and engineering claims, see the
[support matrix](support-matrix.md).
