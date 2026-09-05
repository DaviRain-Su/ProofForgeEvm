import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.VestLink

/-!
Bounded native-ETH vesting: linear schedule with a constructor-stored OZ cliff, stored
beneficiary with one-step `transferOwnership`, OZ `release()` plus partial `release(uint256)`,
ordered reentrancy lock, fail-closed schedule gates, EtherReleased typed event.
`temporaryGapCount` stays 0.
-/

namespace Tests.EvmVestingSpec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard Vesting.wellFormedDuration (100 : UInt64) (900 : UInt64)
#guard Vesting.wellFormedCliff (100 : UInt64) (900 : UInt64) (0 : UInt64)
#guard Vesting.wellFormedCliff (100 : UInt64) (900 : UInt64) (900 : UInt64)
#guard !Vesting.wellFormedCliff (100 : UInt64) (900 : UInt64) (901 : UInt64)
#guard !Vesting.wellFormedBeneficiary Address.zero
#guard !Vesting.canSchedule Address.zero (100 : UInt64) (900 : UInt64) (0 : UInt64)
#guard Vesting.endAt (100 : UInt64) (900 : UInt64) == (1000 : UInt64)
#guard Vesting.cliffAt (100 : UInt64) (900 : UInt64) (400 : UInt64) == (500 : UInt64)
#guard Vesting.vestedAmount ⟨1000, 0, 0, 0⟩ (100 : UInt64) (1000 : UInt64) (500 : UInt64)
    (350 : UInt64) == UInt256.zero
#guard Vesting.vestedAmount ⟨1000, 0, 0, 0⟩ (100 : UInt64) (1000 : UInt64) (500 : UInt64)
    (1100 : UInt64) == ⟨1000, 0, 0, 0⟩

private partial def ctorHasZeroAddress (ops : Array IR.Op) : Bool :=
  ops.any fun
    | .component call => call.emitsZeroAddress
    | .ite _ _ _ t f => ctorHasZeroAddress t || ctorHasZeroAddress f
    | _ => false

private partial def ctorHasConstructorTransferred (ops : Array IR.Op) : Bool :=
  ops.any fun
    | .component call => call.isConstructorTransferred (fun | .lit 0 => true | _ => false)
    | .ite _ _ _ t f => ctorHasConstructorTransferred t || ctorHasConstructorTransferred f
    | _ => false

private def expectVestLink : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.VestLink with
    | .ok source => pure source
    | .error reason => throwError reason
  for ixName in
      #["beneficiary", "owner", "start", "duration", "cliff", "endTime", "releasedOf",
        "releasable", "vestedAmount", "transferOwnership", "release", "receive"] do
    unless source.methods.any (·.ixName == ixName) do
      throwError s!"VestLink is missing {ixName}"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let some releasableEntry := program.entries.find? (·.ixName == "releasable")
    | throwError "VestLink EVM IR lost releasable"
  unless releasableEntry.retTypes == #[.uint 256] do
    throwError s!"releasable return types drifted: {repr releasableEntry.retTypes}"
  let releaseSelectors :=
    (program.entries.filter (·.ixName == "release")).map (·.selector)
  unless releaseSelectors.contains (ProofForge.Crypto.Keccak.selector "release" #["uint256"]) &&
      releaseSelectors.contains (ProofForge.Crypto.Keccak.selector "release" #[]) &&
      releaseSelectors.size == 2 do
    throwError s!"release selectors drifted: {releaseSelectors}"
  let some transferEntry := program.entries.find? (·.ixName == "transferOwnership")
    | throwError "VestLink EVM IR lost transferOwnership"
  unless transferEntry.selector ==
      ProofForge.Crypto.Keccak.selector "transferOwnership" #["address"] do
    throwError s!"transferOwnership selector drifted: {transferEntry.selector}"
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"beneficiary\"" &&
      abi.contains "\"name\":\"start\"" &&
      abi.contains "\"name\":\"duration\"" &&
      abi.contains "\"name\":\"cliff\"" &&
      abi.contains "\"name\":\"endTime\"" &&
      abi.contains "\"name\":\"releasedOf\"" &&
      abi.contains "\"name\":\"releasable\"" &&
      abi.contains "\"name\":\"vestedAmount\"" &&
      abi.contains "\"name\":\"release\"" &&
      abi.contains "\"name\":\"owner\"" &&
      abi.contains "\"name\":\"transferOwnership\"" &&
      abi.contains "\"name\":\"OwnershipTransferred\"" &&
      abi.contains "\"type\":\"receive\"" &&
      abi.contains "\"name\":\"EtherReleased\"" do
    throwError s!"VestLink ABI lost vesting surface:\n{abi}"
  unless !abi.contains "\"name\":\"royaltyInfo\"" do
    throwError "VestLink must not grow a royalty surface"
  unless abi.contains "\"name\":\"ZeroAddress\"" do
    throwError "VestLink ABI lost ZeroAddress"
  unless ctorHasZeroAddress program.constructor.ops do
    throwError "VestLink constructor lost ZeroAddress revert"
  unless ctorHasConstructorTransferred program.constructor.ops do
    throwError "VestLink constructor lost OwnershipTransferred log"
  let yul ←
    match Emit.emitYul program with
    | .ok yul => pure yul
    | .error reason => throwError reason
  let ctorYul := (yul.splitOn "_runtime")[0]!
  unless ctorYul.contains "0xd92e233d" do
    throwError s!"VestLink constructor Yul lost ZeroAddress:\n{ctorYul}"
  let ownershipTopic :=
    "0x" ++ ProofForge.Crypto.Keccak.keccak256HexOfString "OwnershipTransferred(address,address)"
  unless ctorYul.contains ownershipTopic do
    throwError s!"VestLink constructor Yul lost OwnershipTransferred topic:\n{ctorYul}"
  -- The mid-vesting branch is the linear formula over the SELFBALANCE read, not the read. When
  -- the query scan still descended into operator arguments, the read under the arithmetic was
  -- taken as the body's result and `releasable()` answered the raw balance.
  let canon := IR.canonical program
  for ixName in #["releasable", "vestedAmount"] do
    let some entry := (canon.splitOn "/").find? (·.startsWith s!"view:{ixName}:")
      | throwError s!"VestLink canonical IR lost {ixName}"
    unless entry.contains "checkedDivMod256" && entry.contains "selfBalance256 0()" do
      throwError s!"{ixName} lost the linear formula around the SELFBALANCE read"
  unless IR.digestHex program == "2d53b56c1d9429f9" do
    throwError s!"VestLink digest drifted: {IR.digestHex program}"
  logInfo m!"vestlink: digest={IR.digestHex program} abi-ok"

elab "#pf_guard_evm_vesting" : command => expectVestLink

#pf_guard_evm_vesting

#pf_evm_build Examples.Evm.VestLink

end Tests.EvmVestingSpec
