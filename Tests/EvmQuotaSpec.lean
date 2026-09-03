import ProofForge
import Examples.Evm.EvmQuota

/-!
W3 EvmQuota consumer suite: map namespace wiring, extract surface, and digest guard.
Host note: checked-runtime stubs keep map reads at zero; Anvil gate owns live behavior.
-/

namespace Tests.EvmQuotaSpec

open ProofForge.Evm.Sdk
open Lean Elab Command

#guard Examples.Evm.EvmQuota.maps.nonces.base == 0
#guard Examples.Evm.EvmQuota.maps.lastUsed.base == 1
#guard Examples.Evm.EvmQuota.maps.lastTimepoint.base == 2

private def expectQuotaEntries : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.EvmQuota with
    | .ok source => pure source
    | .error reason => throwError reason
  let program ←
    match ProofForge.Evm.IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let entries := program.entries.toList.map (·.ixName)
  for entry in ["act", "noncesOf", "capacityOf", "windowOf", "lastUsedOf", "lastTimepointOf", "totalActionsOf"] do
    unless entries.contains entry do
      throwError s!"EvmQuota: missing extracted entry {entry} in {entries}"

elab "#pf_guard_evm_quota" : command => expectQuotaEntries

#pf_guard_evm_quota

private def expectQuotaDigest : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.EvmQuota with
    | .ok source => pure source
    | .error reason => throwError reason
  let program ←
    match ProofForge.Evm.IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  unless ProofForge.Evm.IR.digestHex program == "e414f3a5e7b949f8" do
    throwError s!"EvmQuota digest drifted: {ProofForge.Evm.IR.digestHex program}"

elab "#pf_guard_evm_quota_digest" : command => expectQuotaDigest

#pf_guard_evm_quota_digest

end Tests.EvmQuotaSpec
