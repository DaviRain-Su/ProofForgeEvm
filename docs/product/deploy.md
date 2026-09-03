# Deploy story (Anvil → Base / VibeNet)

> Status: engineering notes, not a mainnet product claim. If this file disagrees with
> [support-matrix.md](support-matrix.md), the matrix wins.

## What ProofForge ships

`pf build` (via `lake env pf build` in user projects) emits:

| Artifact | Role |
|---|---|
| `Name.bin` | Creation bytecode (solc-assembled from emitted Yul) |
| `Name.yul` | Intermediate Yul |
| `Name.abi.json` | Solidity-compatible ABI JSON |

There is **no** `pf deploy` / `pf local` command. Deployment is ordinary EVM tooling against those artifacts. Artifact build is network-independent; only deploy scripts and chain tests consume RPC settings.

## Supported engineering gate: Anvil

CI and `runtime-tests/evm/anvil*.sh` deploy `.bin` to a locally launched Anvil node and drive `cast` calls. That is the **only** deployment surface with merge-gate coverage.

ProofForge runtime tests launch Anvil with `--chain-id "${PF_EVM_CHAIN_ID:-31338}"`. Stock `anvil` without flags uses chain id `31337`; do not treat those as the same identity.

Typical local pattern (after a green `pf build`):

```bash
# terminal A
anvil --chain-id 31338

# terminal B — same entry point as a configured Base-style RPC
scripts/deploy_evm.sh build/evm/Counter.bin -- constructor(uint64) 7
```

`scripts/deploy_evm.sh` runs `cast send --create`, then prints `chain-id`, `address`, `tx`, and `digest: sha256:…`. It reads the observed chain id and **refuses to sign** on mismatch. Private keys stay in the environment (`PF_EVM_PRIVATE_KEY`; default Anvil account 0) and are never written to generated config.

Anvil green means the bytecode ran under that node’s semantics. It does **not** mean proved on-chain behavior, mainnet readiness, or that a theorem about the Lean `def` refined to the `.bin`.

## External RPC mode (`PF_EVM_RPC_URL`)

`runtime-tests/evm/lib.sh` and `scripts/deploy_evm.sh` share one execution contract:

| Variable | Local Anvil | External RPC |
|---|---|---|
| `PF_EVM_RPC_URL` | unset → launch loopback Anvil | required JSON-RPC URL; Anvil is **not** started |
| `PF_EVM_CHAIN_ID` | default `31338` | **required** (fail-closed; no silent 31338 default) |
| `PF_EVM_PRIVATE_KEY` | Anvil account 0 | operator-supplied funded key; never persisted |

`cast chain-id` must equal `PF_EVM_CHAIN_ID` before every create/send. `anvil_setStorageAt` helpers run only against an Anvil node this repo launched; they fail closed on any other RPC.

The full suite `runtime-tests/evm/anvil.sh` stays Anvil-local (it refuses `PF_EVM_RPC_URL`) because it includes storage-corruption probes. Individual `anvil_*.sh` scripts honor an external URL.

```bash
# Same chain-guard script, pointing at a configured RPC (funded key required to send)
PF_EVM_RPC_URL=https://sepolia.base.org \
PF_EVM_CHAIN_ID=84532 \
PF_EVM_PRIVATE_KEY="$FUNDED_KEY" \
  runtime-tests/evm/anvil_chain_guard.sh
```

CI does **not** require a public funded key. Remote evidence is a manual/protected gate (`workflow_dispatch` `.github/workflows/deploy-testnet.yml` is a no-secret local Anvil stub).

## Public EVM networks (honest scope)

ProofForge EVM emits ordinary creation bytecode. Any EVM JSON-RPC that accepts `eth_sendTransaction`
/`eth_sendRawTransaction` create transactions can load a `.bin`, including:

| Network | Chain ID | RPC (public) | Product status |
|---|---|---|---|
| Anvil (ProofForge tests) | `31338` (override with `PF_EVM_CHAIN_ID`) | loopback, launched by `lib.sh` | **Supported engineering gate** |
| Anvil impersonating Base Sepolia / VibeNet | `84532` / `84538453` | loopback `--chain-id` | **Supported locally** via `EvmChainGuard` (not a public-network claim) |
| Base Sepolia | `84532` | `https://sepolia.base.org` | Same create path; **not CI-gated**; `EvmChainGuard` can pin this id |
| Base Mainnet | `8453` | `https://mainnet.base.org` | **Not endorsed** |
| Base VibeNet | `84538453` | `https://rpc.vibes.base.org` | Same create path; **not CI-gated**; see below |

Funding, explorers, gas markets, and wallet UX are outside this repo. Named networks are documented presets, not compiler special cases.

### Base VibeNet note

[VibeNet](https://chain.base.org/vibenet) is Base’s experimental devnet (chain id `84538453`,
RPC `https://rpc.vibes.base.org`, faucet `POST https://api.vibes.base.org/api/vibenet/faucet/drip`).
It hosts protocol experiments such as EIP-8130 native account abstraction.

ProofForge does **not** implement EIP-8130 wallets, payers, or AA transaction encoding. A
ProofForge `.bin` is still ordinary creation bytecode: you can deploy it with a classic EOA
create on VibeNet the same way you would on Base Sepolia, then call it with standard ABI tools.
Using VibeNet’s AA / 8130 client stack is a separate Base workflow and is out of scope for `pf`.

A green Anvil run with `--chain-id 84532` or `84538453` proves the chain-id gate under that
numeric identity. It is **not** evidence that ProofForge was exercised on public Base Sepolia
or VibeNet.

## Recommended path

1. Author + prove Lean entries.
2. `lake env pf build` → inspect `.abi.json` (especially string vs `bytes32` metadata).
3. Run or mirror Anvil gates locally (`runtime-tests/evm/anvil.sh`, or `anvil_chain_guard.sh` for Base-style chain ids).
4. Only then point `scripts/deploy_evm.sh` / Foundry / your wallet at a public RPC — at your own risk, with `PF_EVM_CHAIN_ID` set.
5. Do not claim “ProofForge verified on Base/VibeNet” from a Lean theorem, an Anvil pass, or a matching chain-id number.

## Related

- Support matrix: [support-matrix.md](support-matrix.md)
- Writing guide: [writing-contracts.md](writing-contracts.md)
- ERC-20-shaped metadata example: `Examples/Evm/Erc20Meta.lean`
- Chain-id example: `Examples/Evm/EvmChainGuard.lean`
