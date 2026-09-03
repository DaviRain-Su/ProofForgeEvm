import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.MetaGateLink
import Examples.Evm.Erc20Meta

/-!
Codex P2: `canPublish` UTF-8 fail-closed — extractor must preserve `BoundedString.wellFormed`,
not treat nonzero length alone as publishable.
-/

namespace Tests.EvmCanPublishSpec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open ProofForge.Core.Value
open Lean Elab Command

private def invalidUtf8Name : BoundedString 8 :=
  { length := 2, values := #v[0xc0, 0x80, 0, 0, 0, 0, 0, 0] }

#guard !invalidUtf8Name.wellFormed
#guard !Erc20Meta.canPublish invalidUtf8Name Examples.Evm.Erc20Meta.tokenSymbol
#guard !Erc20Meta.canPublish invalidUtf8Name Erc20Meta.emptySymbol

private def expectMetaGateLink : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.MetaGateLink with
    | .ok source => pure source
    | .error reason => throwError reason
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let some nameEntry := program.entries.find? (·.ixName == "name")
    | throwError "MetaGateLink missing name entry"
  unless nameEntry.outputPlan == some (.dynamic (.packedBytes { capacity := 8, validateUtf8 := true })) do
    throwError s!"MetaGateLink name output plan drifted: {repr nameEntry.outputPlan}"
  unless IR.digestHex program == "b7a3eb3bad62bb7" do
    throwError s!"MetaGateLink digest drifted: {IR.digestHex program}"
  logInfo m!"metagatelink: digest={IR.digestHex program} canPublish-utf8-ok"

elab "#pf_guard_evm_can_publish" : command => expectMetaGateLink

#pf_guard_evm_can_publish

#pf_evm_build Examples.Evm.MetaGateLink

end Tests.EvmCanPublishSpec
