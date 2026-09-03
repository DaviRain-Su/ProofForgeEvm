import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.OwnerLink

/-!
W5 slice 5b: IERC5313 `owner()` view helper — fail-closed zero owner, reuse Ownable storage.
-/

namespace Tests.EvmIerc5313Spec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard Ierc5313.canPublish Address.zero == false
#guard !Ierc5313.canPublish Address.zero
#guard Address.eq (Ierc5313.selectOwner Address.zero) Address.zero

private def expectOwnerLink : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.OwnerLink with
    | .ok source => pure source
    | .error reason => throwError reason
  unless source.methods.any (·.ixName == "owner") do
    throwError "OwnerLink is missing owner()"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let some ownerEntry := program.entries.find? (·.ixName == "owner")
    | throwError "OwnerLink EVM IR lost owner"
  unless ownerEntry.selector == ProofForge.Crypto.Keccak.selector "owner" #[] do
    throwError s!"owner selector drifted: {ownerEntry.selector}"
  unless ownerEntry.retTypes == #[.address 20] do
    throwError s!"owner return types drifted: {repr ownerEntry.retTypes}"
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"owner\"" do
    throwError s!"OwnerLink ABI lost owner():\n{abi}"
  unless IR.digestHex program == "9d2521b3536b3df6" do
    throwError s!"OwnerLink digest drifted: {IR.digestHex program}"
  logInfo m!"ownerlink: digest={IR.digestHex program} abi-ok"

elab "#pf_guard_evm_ierc5313" : command => expectOwnerLink

#pf_guard_evm_ierc5313

#pf_evm_build Examples.Evm.OwnerLink

end Tests.EvmIerc5313Spec
