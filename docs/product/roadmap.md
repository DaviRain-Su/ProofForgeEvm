# Product roadmap (after 715a419)

## Already landed on main

- EVM-only module docs under `docs/modules/`
- Public site under `website/` + GitHub Pages workflow
- Compiler/SDK slice coverage well past the old E-RT / E-LANG / E-ASSET / E-OWN / E-TOK research plan
- Named user-project CI gate (`pf init demo`)
- `Examples.Evm.Erc20Meta` string metadata profile (Token remains the richer non-standard surface)
- Deploy story docs (`docs/product/deploy.md`)
- CallResult S2 (#9): bounded multiword returndata policies (`exactWords n`, `strictBool`, `magicBytes4`, typed `words`)
- Base RPC gates (#8): `PF_EVM_RPC_URL` + required `PF_EVM_CHAIN_ID`, fail-closed mismatch, Anvil-local storage probes
- Typed OpenCall S3 (#10): CALL/STATICCALL to a typed `Address` with a compile-time constructor ABI
- S4a–c (#11–#13): canonical ERC-721 `Transfer`/`Approval`/`ApprovalForAll`; Ownable `OwnershipTransferred` + Pausable `Paused`/`Unpaused`; ERC-1155 `TransferSingle`/`ApprovalForAll`

## Now (product surface)

1. **Honest public claims** — website/README match CLI + CI reality (solc supported, yulc experimental, no fake MCP/doctor).
2. **Support matrix + writing guide** — this directory.
3. **Checkout quickstart that is copy-paste true** — `lake build pf` → `pf init` → `pf build`.
4. **Research archive banners** — `docs/research/04|05` marked historical.
5. **Template honesty** — no nonexistent git tags / wrong repo names as if released.

## Next

6. **Named user-project CI gate** — `pf init demo` → `lake build` → `lake env pf build` (solc) for the counter template. *(landed as CI job `pf-init-user-project`)*
7. **Standard ERC-20 example profile** — `Examples.Evm.Erc20Meta`: `string` name/symbol + standard selectors; Token remains the richer non-standard metadata surface. *(landed)*
8. **Deploy story docs** — Anvil vs Base Sepolia / VibeNet honesty in `docs/product/deploy.md`. *(landed)*
9. **Release v0.1** — tagged `pf` binary + template `require … @ tag` path; stop rewriting absolute checkout paths as the only story.
10. **Website artifact honesty** — generate Forge panel excerpts from real `pf build` output, or keep them clearly labeled illustrative.

## Later (compiler depth; not P0 product copy)

11. Effect representation rewrite (remove `dummy` / `hold` / fake guards).
12. Reference `World` semantics + Lean↔Anvil differential.
13. Generic typed events; richer constructors. *(S1a frames + S1b `Event.emit` extract/SDK/Anvil path landed. Product typed events are named ABI events (LOG1–4, signature topic always), not anonymous LOG0.)*
14. Typed OpenCall (S3). *(landed on `main` as #10)*
15. Decide yulc: full second backend vs permanent experimental subset.
16. Formal powdr bridge beyond probe status.

Remaining S4 (not a “full ERC” claim): ERC-165, ERC-1155 `TransferBatch`, Roles events, constructor `OwnershipTransferred`, Ownable2Step `OwnershipTransferStarted`. S4d is not on `main`.

## Explicit non-goals

`delegatecall`, CREATE2, proxies, unbounded recursion, arbitrary calldata, mainnet endorsement, bytecode refinement proofs.

Typed `OpenCall` selects a target address only inside a statically typed, bounded ABI constructor. It is not a route around those non-goals.
