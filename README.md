# ProofForge EVM

[![CI](https://github.com/DaviRain-Su/ProofForgeEvm/actions/workflows/ci.yml/badge.svg)](https://github.com/DaviRain-Su/ProofForgeEvm/actions/workflows/ci.yml)

[中文](README.zh-CN.md)

A Lean 4 → EVM contract compiler. Mark entries with `@[pf_entry]` in ordinary
Lean source; ProofForge extracts a checked IR, emits Yul, and assembles EVM
bytecode + ABI via solc (or the powdr `yulc` backend). This repository is the
EVM single-target fork of ProofForge.

## Layout

- `ProofForge/Core/` — target-independent value/effect IR, CFG, codec, schema
- `ProofForge/Extract/` — Lean expression → IR extractor (EVM-only)
- `ProofForge/Evm/` — EVM Ops / IR / Yul Emit / Assemble (solc, yulc) / Registry
- `ProofForge/Evm/Sdk/` — contract-facing SDK (storage, ERC-721/1155, roles, pausable, …)
- `ProofForge/Cli.lean` — the `pf` command line (`pf build` / `pf init`)
- `Examples/` — EVM contract examples (digests pinned in `ProofForge/Evm/Registry.lean`)
- `Tests/` — elaboration-time specs (`#guard` / `example`)
- `templates/evm-counter/` — `pf init` user project template
- `runtime-tests/evm/` — Anvil on-chain integration gates
- `powdr-probe/` — powdr EVM/Yul semantics probe (standalone Lake package)
- `website/` — project site (Vite + React)

## Build & test

```text
./.agents/setup        # pinned toolchain: elan/Lake v4.31.0, solc 0.8.34, foundry 1.7.1
lake build             # compiler library
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
Bare names map to in-tree `Examples` fixtures; user projects pass `--module`
or list `[[program]]` entries in `pf.toml`.

## On-chain gates

```text
runtime-tests/evm/anvil.sh     # full Anvil gate suite (skips when Foundry is absent)
```

## User projects

```text
pf init demo && cd demo && lake build && lake env pf build
```

Contracts import only `ProofForge.Attr` + `ProofForge.Evm.Sdk` — never the
`ProofForge` umbrella. The SDK transitive closure must not reach
Emit/Assemble/Registry (enforced in CI by `scripts/check_sdk_import_closure.py`).

## License

[MIT](LICENSE)
