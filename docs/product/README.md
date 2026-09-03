# Product docs

- [support-matrix.md](support-matrix.md) — what v0 actually supports / refuses
- [writing-contracts.md](writing-contracts.md) — how to write a user contract today
- [deploy.md](deploy.md) — Anvil / Base / VibeNet deploy honesty
- [oz-sdk-backlog.md](oz-sdk-backlog.md) — OpenZeppelin-shaped SDK coverage waves
- [roadmap.md](roadmap.md) — product-first backlog after the website + module-doc landing

Checkout CI job `pf-init-user-project` is the named user-project build gate:
`pf init demo` → `lake build` → `lake env pf build` (solc), asserting Counter artifacts.
It is not an opaque “smoke” check.
