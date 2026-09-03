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

There is **no** `pf deploy` / `pf local` command. Deployment is ordinary EVM tooling against those artifacts.

## Supported engineering gate: Anvil

CI and `runtime-tests/evm/anvil*.sh` deploy `.bin` to a local Anvil node and drive `cast` calls.
That is the **only** deployment surface with merge-gate coverage.

Typical local pattern (after a green `pf build`):

```bash
# terminal A
anvil

# terminal B — example shapes only; scripts under runtime-tests/evm/ are authoritative
cast send --rpc-url http://127.0.0.1:8545 --private-key "$ANVIL_KEY" \
  --create "$(cat build/out/Counter.bin)"
```

Anvil green means the bytecode ran under that node’s semantics. It does **not** mean proved
on-chain behavior, mainnet readiness, or that a theorem about the Lean `def` refined to the `.bin`.

## Public EVM networks (honest scope)

ProofForge EVM emits ordinary creation bytecode. Any EVM JSON-RPC that accepts `eth_sendTransaction`
/`eth_sendRawTransaction` create transactions can load a `.bin`, including:

| Network | Chain ID | RPC (public) | Product status |
|---|---|---|---|
| Anvil (local) | 31337 (default) | `http://127.0.0.1:8545` | **Supported engineering gate** |
| Base Sepolia | `84532` | `https://sepolia.base.org` | Untested public testnet — same EVM create path |
| Base Mainnet | `8453` | `https://mainnet.base.org` | **Not endorsed** (see non-goals) |
| Base VibeNet | `84538453` | `https://rpc.vibes.base.org` | Untested public devnet — see below |

Funding, explorers, gas markets, and wallet UX are outside this repo.

### Base VibeNet note

[VibeNet](https://chain.base.org/vibenet) is Base’s experimental devnet (chain id `84538453`,
RPC `https://rpc.vibes.base.org`, faucet `POST https://api.vibes.base.org/api/vibenet/faucet/drip`).
It hosts protocol experiments such as EIP-8130 native account abstraction.

ProofForge does **not** implement EIP-8130 wallets, payers, or AA transaction encoding. A
ProofForge `.bin` is still ordinary creation bytecode: you can deploy it with a classic EOA
create on VibeNet the same way you would on Base Sepolia, then call it with standard ABI tools.
Using VibeNet’s AA / 8130 client stack is a separate Base workflow and is out of scope for `pf`.

## Recommended path

1. Author + prove Lean entries.
2. `lake env pf build` → inspect `.abi.json` (especially string vs `bytes32` metadata).
3. Run or mirror Anvil gates locally.
4. Only then point `cast` / Foundry / your wallet at a public RPC — at your own risk.
5. Do not claim “ProofForge verified on Base/VibeNet” from a Lean theorem or an Anvil pass.

## Related

- Support matrix: [support-matrix.md](support-matrix.md)
- Writing guide: [writing-contracts.md](writing-contracts.md)
- ERC-20-shaped metadata example: `Examples/Evm/Erc20Meta.lean`
