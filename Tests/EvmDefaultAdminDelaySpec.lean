import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.AdminDelayLink

/-!
W5 slice e: bounded delayed default-admin profile — schedule/cancel/accept decisions and
canonical DefaultAdmin* events.
-/

namespace Tests.EvmDefaultAdminDelaySpec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard DefaultAdminDelay.scheduleAccept 100 50 == 150
#guard DefaultAdminDelay.scheduleAccept 100 0 == 100
#guard !DefaultAdminDelay.pendingActive Address.zero
#guard !DefaultAdminDelay.isNominee Address.zero Address.zero

private def expectAdminDelayLink : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.AdminDelayLink with
    | .ok source => pure source
    | .error reason => throwError reason
  for ixName in #[
      "defaultAdmin", "pendingDefaultAdmin", "acceptSchedule", "defaultAdminDelay",
      "beginDefaultAdminTransfer", "cancelDefaultAdminTransfer", "acceptDefaultAdminTransfer",
      "bump", "get"
    ] do
    unless source.methods.any (·.ixName == ixName) do
      throwError s!"AdminDelayLink is missing {ixName}"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"beginDefaultAdminTransfer\"" &&
      abi.contains "\"name\":\"acceptDefaultAdminTransfer\"" &&
      abi.contains "\"name\":\"defaultAdminDelay\"" do
    throwError s!"AdminDelayLink ABI lost admin-delay surface:\n{abi}"
  unless IR.digestHex program == "200dd10d949030a7" do
    throwError s!"AdminDelayLink digest drifted: {IR.digestHex program}"

elab "#pf_guard_evm_default_admin_delay" : command => expectAdminDelayLink

#pf_guard_evm_default_admin_delay

#pf_evm_build Examples.Evm.AdminDelayLink

end Tests.EvmDefaultAdminDelaySpec
