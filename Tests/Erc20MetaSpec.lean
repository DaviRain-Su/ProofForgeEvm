import ProofForge
import ProofForge.Evm.Commands
import Examples.Evm.Erc20Meta

/-!
# ERC-20 metadata profile

Pins the `Erc20Meta` digest and checks that `name` / `symbol` use the ERC-20
`string` ABI (not packed `bytes32` like `Examples.Evm.Token`).
-/

namespace Tests.Erc20MetaSpec

#guard ProofForge.Evm.Registry.digestOf "Erc20Meta" == some "59d38a1c7dd96ecb"

open Lean Elab Command
open ProofForge

elab "#pf_erc20_meta_check" : command => do
  let env ← getEnv
  let module := `Examples.Evm.Erc20Meta
  let program ←
    match Extract.extractModuleIR env module none >>= ProofForge.Evm.IR.fromExtracted with
    | Except.error reason => throwError reason
    | Except.ok program => pure program
  let digest := ProofForge.Evm.IR.digestHex program
  unless digest == "59d38a1c7dd96ecb" do
    throwError s!"Erc20Meta digest mismatch: {digest}"
  let want := #["allowance", "approve", "balanceOf", "decimals", "initialize",
    "name", "symbol", "totalSupply", "transfer", "transferFrom"]
  let methods :=
    (#[program.constructor.ixName] ++ program.entries.map (·.ixName)) |>.qsort (· < ·)
  unless methods == want do
    throwError s!"Erc20Meta method surface diverged: {methods}"
  let some nameEntry := program.entries.find? (·.ixName == "name")
    | throwError "missing name"
  let some symbolEntry := program.entries.find? (·.ixName == "symbol")
    | throwError "missing symbol"
  unless nameEntry.selector == ProofForge.Crypto.Keccak.selector "name" #[] do
    throwError s!"name selector drifted: {nameEntry.selector}"
  unless symbolEntry.selector == ProofForge.Crypto.Keccak.selector "symbol" #[] do
    throwError s!"symbol selector drifted: {symbolEntry.selector}"
  let abi := ProofForge.Evm.Emit.emitAbi program
  unless abi.contains "\"name\":\"name\"" && abi.contains "\"type\":\"string\"" do
    throwError "name() must advertise string output in ABI"
  unless abi.contains "\"name\":\"symbol\"" do
    throwError "missing symbol in ABI"
  unless abi.contains "\"name\":\"allowance\"" do
    throwError "missing standard allowance (not allowanceOf)"
  unless !abi.contains "\"name\":\"allowanceOf\"" do
    throwError "non-standard allowanceOf must not appear"
  logInfo m!"erc20-meta: digest={digest}"

#pf_erc20_meta_check

#pf_evm_build Examples.Evm.Erc20Meta

end Tests.Erc20MetaSpec
