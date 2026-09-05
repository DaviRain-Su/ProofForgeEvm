import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.Vest20Link

/-!
Bounded ERC-20 vesting map: `Vest20Link.release(address)` pays `releasable(token)` through
`SafeErc20.transfer`, `releasedOf` is a hashed `token → paid` map, `transferOwnership` rotates
the stored beneficiary, `cliff()` is the OZ `VestingWalletCliff` timestamp, and `ERC20Released`
is the typed log. Native-ETH `release()` stays on `VestLink`. `temporaryGapCount` stays 0.
-/

namespace Tests.EvmVest20Spec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard !Vesting.wellFormedToken Address.zero
#guard !Vesting.wellFormedBeneficiary Address.zero
#guard !Vesting.canSchedule Address.zero (100 : UInt64) (900 : UInt64) (0 : UInt64)
#guard Vesting.endAt (100 : UInt64) (900 : UInt64) == (1000 : UInt64)
#guard Vesting.cliffAt (100 : UInt64) (900 : UInt64) (400 : UInt64) == (500 : UInt64)

private partial def ctorHasZeroAddress (ops : Array IR.Op) : Bool :=
  ops.any fun
    | .component call => call.emitsZeroAddress
    | .ite _ _ _ t f => ctorHasZeroAddress t || ctorHasZeroAddress f
    | _ => false

private def expectVest20Link : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.Vest20Link with
    | .ok source => pure source
    | .error reason => throwError reason
  for ixName in
      #["beneficiary", "owner", "start", "duration", "cliff", "endTime", "releasedOf",
        "releasable", "vestedAmount", "transferOwnership", "release"] do
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
  let some transferEntry := program.entries.find? (·.ixName == "transferOwnership")
    | throwError "Vest20Link EVM IR lost transferOwnership"
  unless transferEntry.selector ==
      ProofForge.Crypto.Keccak.selector "transferOwnership" #["address"] do
    throwError s!"transferOwnership selector drifted: {transferEntry.selector}"
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"beneficiary\"" &&
      abi.contains "\"name\":\"cliff\"" &&
      abi.contains "\"name\":\"releasedOf\"" &&
      abi.contains "\"name\":\"releasable\"" &&
      abi.contains "\"name\":\"vestedAmount\"" &&
      abi.contains "\"name\":\"release\"" &&
      abi.contains "\"name\":\"owner\"" &&
      abi.contains "\"name\":\"transferOwnership\"" &&
      abi.contains "\"name\":\"OwnershipTransferred\"" &&
      abi.contains "\"name\":\"ERC20Released\"" do
    throwError s!"Vest20Link ABI lost ERC-20 vesting surface:\n{abi}"
  unless !abi.contains "\"name\":\"EtherReleased\"" do
    throwError "Vest20Link must not grow an EtherReleased surface"
  unless !abi.contains "\"type\":\"receive\"" do
    throwError "Vest20Link must not grow a receive entry"
  unless abi.contains "\"name\":\"ZeroAddress\"" do
    throwError "Vest20Link ABI lost ZeroAddress"
  unless ctorHasZeroAddress program.constructor.ops do
    throwError "Vest20Link constructor lost ZeroAddress revert"
  let yul ←
    match Emit.emitYul program with
    | .ok yul => pure yul
    | .error reason => throwError reason
  let ctorYul := (yul.splitOn "_runtime")[0]!
  unless ctorYul.contains "0xd92e233d" do
    throwError s!"Vest20Link constructor Yul lost ZeroAddress:\n{ctorYul}"
  let canon := IR.canonical program
  for ixName in #["releasable", "vestedAmount"] do
    let some entry := (canon.splitOn "/").find? (·.startsWith s!"view:{ixName}:")
      | throwError s!"Vest20Link canonical IR lost {ixName}"
    unless entry.contains "checkedDivMod256" do
      throwError s!"{ixName} lost the linear formula"
  unless IR.digestHex program == "198b50791da92adb" do
    throwError s!"Vest20Link digest drifted: {IR.digestHex program}"
  logInfo m!"vest20link: digest={IR.digestHex program} abi-ok"

elab "#pf_guard_evm_vest20" : command => expectVest20Link

#pf_guard_evm_vest20

#pf_evm_build Examples.Evm.Vest20Link

end Tests.EvmVest20Spec
