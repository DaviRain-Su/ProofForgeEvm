import ProofForge
import ProofForge.Evm.Commands
import Examples.TokenShape

/-!
# TokenShape conformance (EVM)

`Examples.TokenShape` is the **transfer-shaped** UInt64 ledger subset (`initialize` / `get` /
`credit` / `debit`). The EVM digest is pinned below and in `ProofForge.Evm.Registry`.
-/

namespace Tests.TokenShapeSpec

#guard ProofForge.Evm.Registry.digestOf "TokenShape" == some "2517523f63989d26"

open Lean Elab Command
open ProofForge
elab "#pf_token_shape_check" : command => do
  let env ← getEnv
  let module := `Examples.TokenShape
  let evmProgram ←
    match Extract.extractModuleIR env module none >>= ProofForge.Evm.IR.fromExtracted with
    | .ok program => pure program
    | .error reason => throwError reason
  let evmDigest := ProofForge.Evm.IR.digestHex evmProgram
  unless evmDigest == "2517523f63989d26" do
    throwError s!"TokenShape digest mismatch: evm={evmDigest}"
  let shared := #["credit", "debit", "get", "initialize"]
  let evmMethods :=
    (#[evmProgram.constructor.ixName] ++ evmProgram.entries.map (·.ixName)) |>.qsort (· < ·)
  unless evmMethods == shared do
    throwError s!"TokenShape method surface diverged: evm={evmMethods}"
  logInfo m!"token-shape: evm={evmDigest}"

#pf_token_shape_check

#pf_evm_build Examples.TokenShape

end Tests.TokenShapeSpec
