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
- Closed ETH + ERC-20/WETH calls
- Typed OpenCall to a dynamic `Address` with a static ABI constructor (see sharp edge 5)
- BoundedString returns as ABI `string` (see `Erc20Meta.name` / `symbol`)
- Kernel proofs about the Lean `def` (not about bytecode)

## Known sharp edges (be honest in examples)

1. **Effect carrier** — many contracts still park effect results in a `dummy : UInt64` field and thread `hold s`.
2. **Fake guards** — pure-effect methods may need a trivial branch so Extract treats the method as effectful.
3. **Constructor effects** — deployment-time map writes / logs / value transfers are tightly constrained.
4. **Events** — closed LOG helpers (`Event.tipped` / `Event.transfer`) plus typed constructors via `Event.emit` and `Event.Indexed` (S1b; see `Examples.Evm.EvmTypedEvents`). `Collectible` / `Badge` emit canonical ERC-721 `Transfer` / `Approval` / `ApprovalForAll` through `Erc721.Log`. `TwoStepCounter` / `Credits` emit canonical Ownable `OwnershipTransferred` (on `acceptOwnership`) and Pausable `Paused`/`Unpaused`; `Capped` emits the pause pair. Dynamic/unbounded event payloads are still refused.
5. **Typed external CALL** — `OpenCall.call` / `callSuccess` / `callValue` / `staticWord` / `staticWords2` take a typed `Address` and an inductive constructor (name = ABI function, fields = args). The compiler assembles calldata and applies one `CallResult` policy. This is not raw CALL: no selector string, bytes buffer, `delegatecall`, or CREATE2. Reentrancy is visible to the callee; OpenCall does not insert a guard (see `Examples.Evm.EvmOpenCall`).
6. **NFT modules** — bounded cores with the three canonical ERC-721 events on Collectible/Badge, not “ship ERC-721” (no ERC-165, safe callbacks, or metadata URI).
7. **`Examples.Evm.Token` metadata** — `name` / `symbol` are packed `bytes32` (Anvil gates use that shape). Prefer `Erc20Meta` when external tools expect ERC-20 `string` metadata.

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
