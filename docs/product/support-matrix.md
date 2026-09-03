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
| `pf init <name>` | Supported **inside a repo checkout** (copies `templates/evm-counter`, rewrites path-require) |
| `pf --version` / `-h` | Supported |
| `pf doctor` / `install` / `artifacts` / `local` | **Not implemented** |
| In-repo MCP server | **Not shipped** |

## Language / extract subset

| Area | Status |
|---|---|
| Ordinary `def` / `structure` / `Except` entries with `@[pf_entry]` | Supported |
| Profile refuse IO / partial / sorry / extern / unbounded recursion | Supported |
| Checked arithmetic, `ite`, bounded `for`, bit ops, narrow ABI, tuples | Supported |
| Env / Addr20 / payable / closed ETH send / typed errors / typed events (`Event.emit`) | Supported |
| Hashed maps + closed ERC-20 / WETH / UniswapV2 / Permit calls | Supported |
| CallResult S2 (`exactWords n`, `strictBool`, `magicBytes4`, typed `words`) | **Plan + Yul emit** (≤4 ABI words); ClosedCall still uses the original three policies. No OpenCall consumer yet (S3). Default fail mode is `revert(0, 0)` |
| Effect ergonomics without `dummy` / `hold` / fake guards | **Debt** (see roadmap) |
| Dynamic callee / `delegatecall` / `create2` / proxy / unbounded loops | **Out of scope** |

## SDK naming honesty

| Module | Say this | Do **not** say this |
|---|---|---|
| `Examples.Evm.Erc20Meta` | ERC-20-shaped ABI: `string` name/symbol, standard `allowance` / `transfer` / `approve` selectors | “Audited EIP-20” / mainnet token factory |
| Fungible + `Examples.Evm.Token` | ERC-20-style ledger / allowance policy; **`name`/`symbol` are packed `bytes32`**, and several views use `*Of` names | “Full ERC-20” / drop-in for MetaMask token import without checking ABI |
| `Erc721` / `Erc1155` | Bounded ownership/balance **core**; typed events are available via `Event.emit` for app-owned logs | Full ERC-721/1155 (safe callbacks, metadata, complete event surface) |
| Roles / Pausable / Reentrancy | Explicit policy helpers | Drop-in OpenZeppelin clone |

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
`pf init` currently requires the checkout (template path + require rewrite). A standalone installer / release tarball is roadmap work, not v0.

## Related

- Writing guide: [writing-contracts.md](writing-contracts.md)
- Deploy story: [deploy.md](deploy.md)
- Roadmap: [roadmap.md](roadmap.md)
- Module internals: [../modules/](../modules/)
- Historical research (archived): [../research/](../research/)
