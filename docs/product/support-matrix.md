# Support matrix (v0 product surface)

> Status: living product contract. If the website, README, and this file disagree, **this file wins**.

## Product one-liner

ProofForge EVM is a **checkout-first Lean 4 → Yul → solc** compiler for a fail-closed single-contract subset, with Anvil engineering gates. It is **not** a mainnet deployment product, not a full ERC suite, and not a proved-bytecode toolchain.

## Backends

| Backend | Product status | CI posture | Notes |
|---|---|---|---|
| `solc` 0.8.34 (pinned) | **Supported default** | Required merge gate | Emits `.bin` / `.yul` / `.abi.json` |
| powdr `yulc` | **Experimental** | Weekly / manual only | Same Yul input; may refuse `gas()` / some CALL shapes; dual-backend Anvil covers Counter / Capped / Const / Flag / Phase / Wide / TipJar |

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
| Env / Addr20 / payable / closed ETH send / typed errors | Supported |
| Hashed maps + closed ERC-20 / WETH / UniswapV2 / Permit calls | Supported |
| Effect ergonomics without `dummy` / `hold` / fake guards | **Debt** (see roadmap) |
| Dynamic callee / `delegatecall` / `create2` / proxy / unbounded loops | **Out of scope** |

## SDK naming honesty

| Module | Say this | Do **not** say this |
|---|---|---|
| Fungible + Token examples | ERC-20-style ledger / allowance policy | “Full ERC-20” without checking ABI/metadata |
| `Erc721` / `Erc1155` | Bounded ownership/balance **core** | Full ERC-721/1155 (events, safe callbacks, metadata) |
| Roles / Pausable / Reentrancy | Explicit policy helpers | Drop-in OpenZeppelin clone |

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
lake exe pf -- init demo
cd demo
lake build
../.lake/build/bin/pf build
```

`pf init` currently requires the checkout (template path + require rewrite). A standalone installer / release tarball is roadmap work, not v0.

## Related

- Writing guide: [writing-contracts.md](writing-contracts.md)
- Roadmap: [roadmap.md](roadmap.md)
- Module internals: [../modules/](../modules/)
- Historical research (archived): [../research/](../research/)
