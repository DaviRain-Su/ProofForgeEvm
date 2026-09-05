import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.Vest20Link

/-!
Bounded ERC-20 vesting map: `Vest20Link.release(address)` pays `releasable(token)` through
`SafeErc20.transfer`, `releasedOf` is a hashed `token → paid` map, and `ERC20Released` is the
typed log. Native-ETH `release(uint256)` stays on `VestLink`. `temporaryGapCount` stays 0.
-/

namespace Tests.EvmVest20Spec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard !Vesting.wellFormedToken Address.zero
#guard !Vesting.wellFormedBeneficiary Address.zero
#guard !Vesting.canSchedule Address.zero (100 : UInt64) (900 : UInt64)
#guard Vesting.endAt (100 : UInt64) (900 : UInt64) == (1000 : UInt64)

private def expectVest20Link : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.Vest20Link with
    | .ok source => pure source
    | .error reason => throwError reason
  for ixName in
      #["beneficiary", "start", "duration", "endTime", "releasedOf", "releasable", "vestedAmount",
        "release"] do
    unless source.methods.any (·.ixName == ixName) do
      throwError s!"Vest20Link is missing {ixName}"
  unless !(source.methods.any (·.ixName == "receive")) do
    throwError "Vest20Link must not grow a native receive path"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let some releasableEntry := program.entries.find? (·.ixName == "releasable")
    | throwError "Vest20Link EVM IR lost releasable"
  unless releasableEntry.retTypes == #[.uint 256] do
    throwError s!"releasable return types drifted: {repr releasableEntry.retTypes}"
  let some releaseEntry := program.entries.find? (·.ixName == "release")
    | throwError "Vest20Link EVM IR lost release"
  unless releaseEntry.selector == ProofForge.Crypto.Keccak.selector "release" #["address"] do
    throwError s!"release selector drifted: {releaseEntry.selector}"
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"beneficiary\"" &&
      abi.contains "\"name\":\"releasedOf\"" &&
      abi.contains "\"name\":\"releasable\"" &&
      abi.contains "\"name\":\"vestedAmount\"" &&
      abi.contains "\"name\":\"release\"" &&
      abi.contains "\"name\":\"ERC20Released\"" do
    throwError s!"Vest20Link ABI lost ERC-20 vesting surface:\n{abi}"
  unless !abi.contains "\"name\":\"EtherReleased\"" do
    throwError "Vest20Link must not grow an EtherReleased surface"
  unless !abi.contains "\"type\":\"receive\"" do
    throwError "Vest20Link must not grow a receive entry"
  let canon := IR.canonical program
  for ixName in #["releasable", "vestedAmount"] do
    let some entry := (canon.splitOn "/").find? (·.startsWith s!"view:{ixName}:")
      | throwError s!"Vest20Link canonical IR lost {ixName}"
    unless entry.contains "checkedDivMod256" do
      throwError s!"{ixName} lost the linear formula"
  unless IR.digestHex program == "b1fb5c908d419901" do
    throwError s!"Vest20Link digest drifted: {IR.digestHex program}"
  logInfo m!"vest20link: digest={IR.digestHex program} abi-ok"

elab "#pf_guard_evm_vest20" : command => expectVest20Link

#pf_guard_evm_vest20

#pf_evm_build Examples.Evm.Vest20Link

end Tests.EvmVest20Spec
