import Lean
import ProofForge.Extract
import ProofForge.Profile
import ProofForge.Evm.IR
import ProofForge.Evm.Emit
import ProofForge.Evm.Registry

open Lean Elab Command
open ProofForge
open ProofForge.Evm

namespace ProofForge.Evm.Commands

/-- Chain-neutral profile gate: accept/reject a declaration per `ProofForge.Profile`. -/
elab "#pf_check " n:ident : command => do
  let name ← liftCoreM <| realizeGlobalConstNoOverload n
  let env ← getEnv
  match Profile.check env name with
  | .accept => logInfo m!"proofforge: accept {name}"
  | .reject reason => throwError reason

/-- Chain-neutral constant dumper. -/
elab "#pf_dump " n:ident : command => do
  let name ← liftCoreM <| realizeGlobalConstNoOverload n
  let env ← getEnv
  match env.find? name with
  | none => throwError "unknown {name}"
  | some info =>
    match info.value? with
    | none => throwError "no value {name}"
    | some e => logInfo m!"{name} := {e}"

elab "#pf_evm_build " n:ident : command => do
  let ns := n.getId
  let env ← getEnv
  match Extract.extractModuleIR env ns none >>= IR.fromExtracted with
  | .error reason => throwError reason
  | .ok program => do
    match Emit.emitYul program with
    | .error reason => throwError reason
    | .ok yul =>
        unless yul.contains "object \"" do
          throwError "assemble/tool: missing yul object"
        let digest := IR.digestHex program
        match Registry.digestOf program.name with
        | some want =>
            if digest != want then
              throwError s!"ir/mismatch: extracted evm {program.name} digest {digest} != fixture {want}"
        | none => pure ()
        logInfo m!"proofforge-evm: program {program.name} slots = {program.slots.map (·.name)}"
        logInfo m!"proofforge-evm: entries = {program.entries.map (fun m => m.ixName)}"
        logInfo m!"proofforge-evm: digest = {digest}"
        logInfo m!"proofforge-evm: emitted {yul.length} bytes of Yul"

elab "#pf_evm_dump " n:ident : command => do
  let ns := n.getId
  let env ← getEnv
  match Extract.extractModuleIR env ns none >>= IR.fromExtracted with
  | .error reason => throwError reason
  | .ok program =>
      let methods := #[program.constructor] ++ program.entries
      logInfo m!"proofforge-evm-dump: {program.name} methods = {methods.map (·.ixName)}"
      for m in methods do
        logInfo m!"proofforge-evm-dump: {m.ixName} pc={m.paramCount} ops={repr m.ops}"
      logInfo m!"proofforge-evm-dump: digest = {IR.digestHex program}"

end ProofForge.Evm.Commands
