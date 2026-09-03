# Product roadmap (after 715a419)

## Already landed on main

- EVM-only module docs under `docs/modules/`
- Public site under `website/` + GitHub Pages workflow
- Compiler/SDK slice coverage well past the old E-RT / E-LANG / E-ASSET / E-OWN / E-TOK research plan

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
13. Generic typed events; richer constructors.
14. Decide yulc: full second backend vs permanent experimental subset.
15. Formal powdr bridge beyond probe status.

## Explicit non-goals

Dynamic callee, delegatecall, create2, proxies, unbounded recursion, mainnet endorsement, bytecode refinement proofs.
