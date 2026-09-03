import ProofForge
import Examples.Evm.EvmCrew

/-!
W3 Set4 focused suite: fixed-capacity shape, compile-time `Storage.Static` declaration pins,
and extraction-level proofs for the four-slot crew consumer.
-/

namespace Tests.EvmCrewSpec

open ProofForge.Evm.Sdk
open ProofForge.Evm.Sdk.Storage.Static
open Lean Elab Command

#guard Roles.capacity4 == 4
#guard Roles.Set4.empty == ⟨Address.zero, Address.zero, Address.zero, Address.zero⟩

open Examples.Evm.EvmCrew in
#guard (init 0 ⟨0, 0, 0⟩).crew0 == Address.zero &&
  (init 0 ⟨0, 0, 0⟩).crew3 == Address.zero

#guard Examples.Evm.EvmCrew.declared.handle.crew0.baseSlot == 1
#guard Examples.Evm.EvmCrew.declared.handle.crew1.baseSlot == 4
#guard Examples.Evm.EvmCrew.declared.handle.crew2.baseSlot == 7
#guard Examples.Evm.EvmCrew.declared.handle.crew3.baseSlot == 10
#guard Examples.Evm.EvmCrew.layout.nextSlot == 13
#guard Examples.Evm.EvmCrew.layout.wellFormed

def crewRoleSlots : List (String × Nat) :=
  [("paused", 1),
    ("crew0_w0", 8), ("crew0_w1", 8), ("crew0_w2", 8),
    ("crew1_w0", 8), ("crew1_w1", 8), ("crew1_w2", 8),
    ("crew2_w0", 8), ("crew2_w1", 8), ("crew2_w2", 8),
    ("crew3_w0", 8), ("crew3_w1", 8), ("crew3_w2", 8)]

#guard Examples.Evm.EvmCrew.layout.matchesFlattened crewRoleSlots

private def expectCrewLayout : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.EvmCrew with
    | .ok source => pure source
    | .error reason => throwError reason
  let program ←
    match ProofForge.Evm.IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let slots := program.slots.toList.map fun s => (s.name, s.width)
  unless slots == crewRoleSlots do
    throwError s!"EvmCrew: extracted static slots diverge: {slots}"
  let entries := program.entries.toList.map (·.ixName)
  for entry in ["grantCrew", "revokeCrew", "isCrew"] do
    unless entries.contains entry do
      throwError s!"EvmCrew: missing extracted entry {entry} in {entries}"

elab "#pf_guard_evm_crew" : command => expectCrewLayout

#pf_guard_evm_crew

end Tests.EvmCrewSpec
