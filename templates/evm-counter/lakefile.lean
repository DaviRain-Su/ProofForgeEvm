import Lake
open Lake DSL

package «my-contract» where
  version := v!"0.1.0"

/-- Path require for monorepo / `pf init` (rewritten by init to the checkout root).
A published git-tag require for the target repo is not available yet; the shared
Core comes from ProofForgeCommon on GitHub (tracked at main, same as this repo).
Keep imports on `ProofForge.Attr` + `ProofForge.Evm.Sdk` only. -/
require «proofforge» from ".." / ".."
require «proofforge-common» from git
  "https://github.com/DaviRain-Su/ProofForgeCommon.git" @ "main"

@[default_target]
lean_lib «MyContract»
