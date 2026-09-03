import Lake
open Lake DSL

package «my-contract» where
  version := v!"0.1.0"

/-- Path require for monorepo / `pf init` (rewritten by init to the checkout root).
A published git-tag require is not available yet; do not pretend `v0.0.1` exists.
Keep imports on `ProofForge.Attr` + `ProofForge.Evm.Sdk` only. -/
require «proofforge» from ".." / ".."
require «proofforge-common» from ".." / ".." / ".."

@[default_target]
lean_lib «MyContract»
