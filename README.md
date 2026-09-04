# ProofForge EVM

[![CI](https://github.com/DaviRain-Su/ProofForgeEvm/actions/workflows/ci.yml/badge.svg)](https://github.com/DaviRain-Su/ProofForgeEvm/actions/workflows/ci.yml)

[中文](README.zh-CN.md)

A Lean 4 → EVM contract compiler. Mark entries with `@[pf_entry]` in ordinary
Lean source; ProofForge extracts a checked IR, emits Yul, and assembles EVM
bytecode + ABI via **pinned solc** (powdr `yulc` is an **experimental** backend).
This repository is the EVM single-target fork of ProofForge.

Product contract: [`docs/product/support-matrix.md`](docs/product/support-matrix.md).
Writing guide: [`docs/product/writing-contracts.md`](docs/product/writing-contracts.md).
Site: [`website/`](website/) (GitHub Pages).

## Layout

- `ProofForge/Core/` — target-independent value/effect IR, CFG, codec, schema
- `ProofForge/Extract/` — Lean expression → IR extractor (EVM-only)
- `ProofForge/Evm/` — EVM Ops / IR / Yul Emit / Assemble (solc, experimental yulc) / Registry
- `ProofForge/Evm/Sdk/` — contract-facing SDK (storage, fungible, SafeErc20, ERC-2981, bounded ERC-721/1155 cores, roles, pausable, …)
- `ProofForge/Cli.lean` — the `pf` CLI (`pf build` / `pf init` / `pf --version`)
- `Examples/` — EVM contract examples (digests pinned in `ProofForge/Evm/Registry.lean`)
- `Tests/` — elaboration-time specs (`#guard` / `example`)
- `templates/evm-counter/` — `pf init` user project template
- `runtime-tests/evm/` — Anvil on-chain integration gates
- `powdr-probe/` — powdr EVM/Yul semantics probe (standalone Lake package)
- `docs/product/` — support matrix, writing guide, roadmap
- `docs/research/` — **historical** decision notes (archived)
- `website/` — project site (Vite + React)

## Build & test

```text
./.agents/setup        # pinned toolchain: elan/Lake v4.31.0, solc 0.8.34, foundry 1.7.1
lake build             # compiler library
lake build pf          # CLI executable
lake build Tests       # test suite (elaboration-time assertions)
lake build Examples    # example contracts
```

Local CI mirror: `scripts/ci_local.sh` (`--fast` runs the Python guards only).

## CLI

```text
pf build [--out DIR] [--backend solc|yulc] [--module MOD] [Contract ...]
pf init <name>
pf --version
```

`pf build` writes `Name.bin` / `Name.yul` / `Name.abi.json` per program.
Default backend is **solc**. `--backend yulc` is experimental (weekly/manual CI, not a merge gate).
Bare names map to in-tree `Examples` fixtures; user projects pass `--module`
or list `[[program]]` entries in `pf.toml`.

## On-chain gates

```text
runtime-tests/evm/anvil.sh     # full Anvil gate suite (skips when Foundry is absent)
scripts/deploy_evm.sh          # cast send --create; fail-closed chain-id (see docs/product/deploy.md)
```

## User projects (from this checkout)

```text
lake build pf
export PATH="$PWD/.lake/build/bin:$PATH"
pf init demo
cd demo
lake build
lake env pf build
```

CI job `pf-init-user-project` (check name **pf init demo**) runs this same path:
`pf init demo` creates a named project, then `lake build` and `lake env pf build`
must produce `Counter.bin` / `Counter.yul` / `Counter.abi.json`.

`pf init` copies `templates/evm-counter` and, when run from a checkout, rewrites
the published git-tag `require` (`@ "v0.1.0"`) to a path `require` against this
tree. CI can then build the generated project before the tag exists.

Once a `v0.1.0` GitHub Release exists, download `pf-linux-x86_64` or
`pf-macos-aarch64` and pin a user lakefile with Lake
`require … @ "v0.1.0"`. `proofforge-common` stays `@ "main"`.
There is no standalone installer and no `curl | sh` install. `pf init` still needs
a checkout for the template files.

Contracts import only `ProofForge.Attr` + `ProofForge.Evm.Sdk` — never the
`ProofForge` umbrella. The SDK transitive closure must not reach
Emit/Assemble/Registry (enforced in CI by `scripts/check_sdk_import_closure.py`).

## Trust boundary

- Kernel theorems are about user `def`s / static fields — **not** about `.bin` or EVM refinement.
- Anvil green is an **engineering** gate, not a proof.
- ERC-721/1155 SDK modules are **bounded cores**, not full standard implementations.

## License

[MIT](LICENSE)
