import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.SafePay
import Examples.Evm.Vault

/-!
W2 fail-closed ERC-20 consumer gate. Helpers must stay closed CALL aliases (no raw calldata)
and SafePay must expose the zero-address-gated transfer/approve/allowance surface.
-/

namespace Tests.EvmSafeErc20Spec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard SafeErc20.transfer ⟨1, 2, 3⟩ ⟨4, 5, 6⟩ ⟨9, 0, 0, 0⟩ == 9
#guard SafeErc20.approve ⟨1, 2, 3⟩ ⟨4, 5, 6⟩ ⟨9, 0, 0, 0⟩ == 9
#guard SafeErc20.transferFrom ⟨1, 2, 3⟩ ⟨4, 5, 6⟩ ⟨7, 8, 9⟩ ⟨9, 0, 0, 0⟩ == 9
#guard SafeErc20.allowanceOfSelf ⟨1, 2, 3⟩ ⟨4, 5, 6⟩ == UInt256.zero
#guard SafeErc20.nextIncrease ⟨9, 0, 0, 0⟩ ⟨1, 0, 0, 0⟩ == ⟨9, 0, 0, 0⟩
#guard SafeErc20.nextDecrease ⟨9, 0, 0, 0⟩ ⟨1, 0, 0, 0⟩ == ⟨9, 0, 0, 0⟩

example (token destination : Address) (amount : UInt256) :
    SafeErc20.transfer token destination amount = ERC20.transfer token destination amount :=
  SafeErc20.transfer_eq token destination amount

private def expectSafePay : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.SafePay with
    | .ok source => pure source
    | .error reason => throwError reason
  let want := #["allowed", "bump", "drop", "force", "grant", "held", "initialize",
    "pull", "take"]
  let methods :=
    (source.methods.map (·.ixName)).qsort (· < ·)
  unless methods == want do
    throwError s!"SafePay method surface diverged: {methods}"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  for name in #["pull", "grant", "take", "bump", "drop", "force", "held", "allowed"] do
    unless abi.contains s!"\"name\":\"{name}\"" do
      throwError s!"SafePay ABI lost {name}:\n{abi}"
  unless !abi.contains "calldata" do
    throwError s!"SafePay ABI unexpectedly mentions calldata:\n{abi}"
  unless Registry.digestOf "SafePay" == some "cf69a0c64840876c" do
    throwError "SafePay digest drifted"
  unless Registry.digestOf "Vault" == some "bb2f93cb28d7501" do
    throwError "Vault digest drifted while adding SafePay"
  logInfo m!"safepay: digest={IR.digestHex program}"

elab "#pf_guard_evm_safepay" : command => expectSafePay

#pf_guard_evm_safepay

#pf_evm_build Examples.Evm.SafePay

end Tests.EvmSafeErc20Spec
