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

6. **Init smoke in CI** — empty-dir `pf init` → `lake build` → `pf build` (solc) for the counter template.
7. **Release v0.1** — tagged `pf` binary + template `require … @ tag` path; stop rewriting absolute checkout paths as the only story.
8. **Website artifact honesty** — generate Forge panel excerpts from real `pf build` output, or keep them clearly labeled illustrative.
9. **Standard ERC-20 example profile** — ABI/metadata that external tools recognize, without over-claiming NFT standards.

## Later (compiler depth; not P0 product copy)

10. Effect representation rewrite (remove `dummy` / `hold` / fake guards).
11. Reference `World` semantics + Lean↔Anvil differential.
12. Generic typed events; richer constructors.
13. Decide yulc: full second backend vs permanent experimental subset.
14. Formal powdr bridge beyond probe status.

## Explicit non-goals

Dynamic callee, delegatecall, create2, proxies, unbounded recursion, mainnet endorsement, bytecode refinement proofs.
