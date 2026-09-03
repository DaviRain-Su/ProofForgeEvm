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
| `access/Ownable.sol`, `Ownable2Step.sol` | PARTIAL | `Sdk.Access`, `Sdk.Ownable`, `TwoStepCounter`, `Credits` | Fixed single pending owner; no constructor or transfer-start log yet | Yes — W3 events only |
| `access/AccessControl.sol`, `IAccessControl.sol` | PARTIAL | `Sdk.Roles.Set2`, `EvmStaticCounter`, `EvmStaticRoster` | One fixed capacity-2 role, no role admin hierarchy/enumeration | `RoleAdminChanged`: no (no role-admin state/API); bounded named roles: later |
| `access/extensions/*`, `access/manager/*` | ABSENT | — | Delayed admin rules, enumeration, authority manager | No — require unbounded role/account relations or external authority dispatch |
| `account/**` | ABSENT | — | ERC-4337/7579 account, paymaster, execution modes | No — AA/paymaster and arbitrary execution are product non-goals |
| `crosschain/**` | ABSENT | — | Bridge state, remote executor, receiver callbacks | No — cross-chain authentication/callback model is absent |
| `finance/VestingWallet*.sol` | ABSENT | `Context.timestamp`, static storage primitives | Vesting schedule/releasable accounting | Yes — W4 bounded single-beneficiary schedule profile |
| `governance/**` | ABSENT | `Sdk.StorageCheckpoints` only | Proposal/vote/quorum/timelock lifecycle | No — Governor requires unconstrained proposal/voter relations and token snapshot semantics |
| `interfaces/IERC165.sol` | DONE | `Sdk.Erc165`, `Collectible`, `Badge`, `MultiToken`, `CraftToken` | Static, explicitly declared `IERC165` only; incomplete token interfaces return false | Yes — W1 shipped |
| `interfaces/IERC20*.sol`, `IERC2612.sol` | PARTIAL | `Sdk.Fungible`, `Erc20Meta`, `Token`, `Sdk.Payments` | Profiles, not a complete audited token implementation; permit is a closed call/internal profile | Yes — W2 standard helper/event/profile gaps |
| `interfaces/IERC721*.sol`, `IERC4906.sol`, `IERC2309.sol` | PARTIAL | `Sdk.Erc721`, `Collectible`, `Badge`, `Sdk.Erc165` | No safe receiver callback, metadata URI, enumeration, consecutive mint | Receiver/enumeration: no; bounded metadata: W4 |
| `interfaces/IERC1155*.sol` | PARTIAL | `Sdk.Erc1155`, `MultiToken`, `CraftToken`, `Sdk.Erc165` | No callbacks, metadata URI, `balanceOfBatch`, or `TransferBatch` | `TransferBatch`: no (dynamic arrays/events); bounded URI: W4 |
| `interfaces/IERC2981.sol` | ABSENT | `UInt256`, static config | Royalty info profile | Yes — W2 static royalty profile |
| `interfaces/IERC1271.sol` | ABSENT | `Precompile` internals | Contract signature validation response | No — requires arbitrary external contract call/result protocol |
| `interfaces/IERC3156*.sol`, `IERC4626.sol`, `IERC6909.sol`, `IERC777*.sol`, `IERC1363*.sol` | ABSENT | `Vault` is not ERC-4626 | Flash callbacks, hooks, multi-token operator model | No — callback/reentrancy and broader dynamic interface requirements |
| `interfaces/IERC1820*.sol`, `IERC1967.sol`, `IERC1822.sol` | ABSENT | — | Global registry/proxy-slot interoperability | No — registry/proxy non-goals |
| `interfaces/IERC5267.sol`, `IERC5313.sol`, `IERC6372.sol`, `IERC5805.sol` | ABSENT | `Context`, `Permit` | EIP-712 domain, owner, clock/votes views | EIP-5267 static domain: W4; others blocked by votes model |
| `interfaces/draft-IERC3009.sol`, `IERC7674.sol`, `IERC7751.sol`, `IERC7786.sol`, `IERC7802.sol`, `IERC7821.sol` | ABSENT | — | Authorization transfers, temporary approvals, cross-chain/account protocols | No — signed authorization state or cross-chain/account model absent |
| `metatx/ERC2771*.sol` | ABSENT | — | Trusted-forwarder sender/calldata suffix | No — raw/rewritten calldata is prohibited |
| `proxy/**`, `interfaces/IERC1967.sol` | ABSENT | — | Delegate proxy, beacon, clones, UUPS | No — `delegatecall`, proxy, CREATE2 are permanent non-goals |
| `token/ERC20/**` | PARTIAL | `Sdk.Fungible`, `Erc20Meta`, `Token` | No complete extensions/permit-votes ecosystem | Yes — W2 bounded safe-transfer and metadata/event profile work |
| `token/ERC721/**` | PARTIAL | `Sdk.Erc721`, `Collectible`, `Badge` | Core only, no receiver/metadata/enumeration | See IERC721 row |
| `token/ERC1155/**` | PARTIAL | `Sdk.Erc1155`, `MultiToken`, `CraftToken` | Single-id core only | See IERC1155 row |
| `token/ERC6909/**` | ABSENT | — | Multi-token transfer/operator semantics | No — broad dynamic multi-token standard is outside current bounded profile |
| `token/common/ERC2981.sol`, `ERC1363Utils.sol` | ABSENT | — | Royalty / transfer-and-call utility | Royalty: W2; transfer-and-call: no callbacks |
| `utils/Context.sol`, `Pausable.sol`, `ReentrancyGuard*.sol` | PARTIAL | `Sdk.Base.Context`, `Sdk.Pausable`, `Sdk.Reentrancy` | Explicit policy helpers, not Solidity inheritance/transient storage clone | Yes — W3 close event/profile gaps |
| `utils/Address.sol`, `LowLevelCall.sol`, `Multicall.sol`, `RelayedCall.sol`, `SimulateCall.sol`, `Calldata.sol`, `Memory.sol` | ABSENT | `OpenCall` is typed and closed | Arbitrary call/data/delegate/value helpers | No — arbitrary calldata/call and delegatecall prohibited |
| `utils/cryptography/**` | PARTIAL | Keccak/SHA-256, fixed EIP-712 permit path, precompile internals | No general ECDSA/Merkle/SignatureChecker public SDK | Bounded Merkle proof: W4; general signature checker: no arbitrary ERC-1271 call |
| `utils/math/**`, `SafeCast.sol`, `Panic.sol`, `Errors.sol`, `Comparators.sol` | PARTIAL | `Core.Math`, `Core.SafeCast`, `UInt256`, closed `Revert` | Not full Solidity numeric/type/error families | Yes — W3 bounded utility helpers where existing IR supports them |
| `utils/structs/**`, `Arrays.sol`, `Bytes.sol`, `Strings.sol`, `Base*`, `RLP.sol`, `Packing.sol`, `ShortStrings.sol` | PARTIAL | Bounded vec/ring/bitmap/enumerable structures, fixed bytes | No general dynamic bytes/strings/arrays/enumerable map semantics | Fixed-capacity variants only — W4; general versions no |
| `utils/Create2.sol`, `Create3.sol`, `StorageSlot.sol`, `SlotDerivation.sol`, `TransientSlot.sol`, `draft-InteroperableAddress.sol` | ABSENT | — | Contract creation, arbitrary slots, transient/interoperable address encodings | No — creation/slot escape hatches non-goals |
| `utils/Blockhash.sol`, `BlockHeader.sol`, `ERC6372Utils.sol`, `Nonces*.sol`, `RateLimiter.sol` | PARTIAL | `Context.blockHash`, block fields, hashed/static storage | No hardened nonce/rate/header utility profile | Bounded per-address nonce/rate profile: W3 |
| `vendor/**`, `mocks/**` | ABSENT | — | Upstream dependencies and test fixtures | No — not runtime SDK surface |

## Prioritized implementation waves

| Wave | Scope | Status |
|---|---|---|
| W1 | Static ERC-165 core (`bytes4` IDs, bounded support predicates), adopt `supportsInterface` in both ERC-721- and ERC-1155-shaped examples, compiler/ABI and Anvil gates | Verified on `cursor/oz-sdk-w1-e4eb`: targeted and full `lake build Tests`, plus four Anvil gates. The examples advertise `IERC165` only: their partial ERC-721/1155 method surfaces must return false for the standard token IDs. |
| W2 | ERC-20-shaped consumer ergonomics: explicit safe-transfer/allowance policy helpers and a static ERC-2981 royalty profile | Next |
| W3 | Bounded access/utility closeout: Ownable2Step start event and constructor-init policy where extractable; fixed-capacity role profiles; bounded nonce/rate helpers | Planned |
| W4 | Static metadata/finance/crypto profiles: bounded ERC-721/1155 URI response, EIP-5267-style static domain fields, single-beneficiary vesting, bounded Merkle proofs | Planned |
| W5 | Completion audit: re-inventory the then-current OZ tree, prove every remaining item is either DONE, a restricted PARTIAL profile, or blocked by a documented non-goal | Planned |

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
