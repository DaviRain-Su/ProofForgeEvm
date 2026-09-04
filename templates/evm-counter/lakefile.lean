import Lake
open Lake DSL

package «my-contract» where
  version := v!"0.1.0"

/-- Published require is git @ tag. `pf init` from a checkout rewrites it to a
path require for local CI. Common stays `@ "main"`.
Keep imports on `ProofForge.Attr` + `ProofForge.Evm.Sdk` only. -/
require «proofforge» from git
  "https://github.com/DaviRain-Su/ProofForgeEvm.git" @ "v0.1.0"
require «proofforge-common» from git
  "https://github.com/DaviRain-Su/ProofForgeCommon.git" @ "main"

@[default_target]
lean_lib «MyContract»
