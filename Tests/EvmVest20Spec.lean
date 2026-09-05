import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.Vest20Link

/-!
Dual-asset vesting: `Vest20Link.release(address)` pays `releasable(token)` through
`SafeErc20.transfer`, `released(address)` is a hashed `token → paid` map, `release()` pays
`releasable()` native ETH, `released()` is the native counter, `transferOwnership` nominates
and `acceptOwnership` rotates the stored beneficiary, `cliff()` is the OZ `VestingWalletCliff`
timestamp, and both `ERC20Released` and `EtherReleased` are typed logs. VestLink stays the
ETH-only smaller profile. `temporaryGapCount` stays 0.
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

private partial def ctorHasOwnableInvalidOwner (ops : Array IR.Op) : Bool :=
  ops.any fun
    | .component call => call.emitsOwnableInvalidOwner
    | .ite _ _ _ t f => ctorHasOwnableInvalidOwner t || ctorHasOwnableInvalidOwner f
    | _ => false

private partial def ctorHasConstructorTransferred (ops : Array IR.Op) : Bool :=
  ops.any fun
    | .component call => call.isConstructorTransferred (fun | .lit 0 => true | _ => false)
    | .ite _ _ _ t f => ctorHasConstructorTransferred t || ctorHasConstructorTransferred f
    | _ => false

private def expectVest20Link : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.Vest20Link with
    | .ok source => pure source
    | .error reason => throwError reason
  for ixName in
      #["beneficiary", "owner", "start", "duration", "cliff", "endTime", "released",
        "releasable", "vestedAmount", "transferOwnership", "acceptOwnership", "pendingOwner",
        "release", "receive"] do
    unless source.methods.any (·.ixName == ixName) do
      throwError s!"Vest20Link is missing {ixName}"
  unless (source.methods.filter (·.ixName == "release")).size >= 2 do
    throwError "Vest20Link lost the release() / release(address) overload pair"
  unless (source.methods.filter (·.ixName == "releasable")).size >= 2 do
    throwError "Vest20Link lost the releasable() / releasable(address) overload pair"
  unless (source.methods.filter (·.ixName == "released")).size >= 2 do
    throwError "Vest20Link lost the released() / released(address) overload pair"
  unless (source.methods.filter (·.ixName == "vestedAmount")).size >= 2 do
    throwError "Vest20Link lost the vestedAmount(uint64) / vestedAmount(address,uint64) overload pair"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let some releasableEntry := program.entries.find? (·.ixName == "releasable")
    | throwError "Vest20Link EVM IR lost releasable"
  unless releasableEntry.retTypes == #[.uint 256] do
    throwError s!"releasable return types drifted: {repr releasableEntry.retTypes}"
  unless program.entries.any (fun e =>
      e.ixName == "release" && e.selector == ProofForge.Crypto.Keccak.selector "release" #["address"]) do
    throwError "Vest20Link lost release(address)"
  unless program.entries.any (fun e =>
      e.ixName == "release" && e.selector == ProofForge.Crypto.Keccak.selector "release" #[]) do
    throwError "Vest20Link lost release()"
  unless program.entries.any (fun e =>
      e.ixName == "releasable" && e.selector == ProofForge.Crypto.Keccak.selector "releasable" #[]) do
    throwError "Vest20Link lost releasable()"
  unless program.entries.any (fun e =>
      e.ixName == "released" && e.selector == ProofForge.Crypto.Keccak.selector "released" #[]) do
    throwError "Vest20Link lost released()"
  unless program.entries.any (fun e =>
      e.ixName == "released" &&
        e.selector == ProofForge.Crypto.Keccak.selector "released" #["address"]) do
    throwError "Vest20Link lost released(address)"
  unless program.entries.any (fun e =>
      e.ixName == "vestedAmount" &&
        e.selector == ProofForge.Crypto.Keccak.selector "vestedAmount" #["uint64"]) do
    throwError "Vest20Link lost vestedAmount(uint64)"
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
      abi.contains "\"name\":\"released\"" &&
      abi.contains "\"name\":\"releasable\"" &&
      abi.contains "\"name\":\"vestedAmount\"" &&
      abi.contains "\"name\":\"release\"" &&
      abi.contains "\"name\":\"owner\"" &&
      abi.contains "\"name\":\"transferOwnership\"" &&
      abi.contains "\"name\":\"acceptOwnership\"" &&
      abi.contains "\"name\":\"pendingOwner\"" &&
      abi.contains "\"name\":\"OwnershipTransferred\"" &&
      abi.contains "\"name\":\"OwnershipTransferStarted\"" &&
      abi.contains "\"name\":\"ERC20Released\"" &&
      abi.contains "\"name\":\"EtherReleased\"" &&
      abi.contains "\"type\":\"receive\"" do
    throwError s!"Vest20Link ABI lost dual-asset vesting surface:\n{abi}"
  unless !abi.contains "\"name\":\"releasedOf\"" do
    throwError "Vest20Link must not advertise releasedOf"
  unless abi.contains "\"name\":\"ZeroAddress\"" do
    throwError "Vest20Link ABI lost ZeroAddress"
  unless abi.contains "\"name\":\"OwnableInvalidOwner\"" do
    throwError "Vest20Link ABI lost OwnableInvalidOwner"
  unless abi.contains "\"name\":\"OwnableUnauthorizedAccount\"" do
    throwError "Vest20Link ABI lost OwnableUnauthorizedAccount"
  unless !abi.contains "\"name\":\"Unauthorized\"" do
    throwError "Vest20Link must not advertise Unauthorized"
  unless ctorHasOwnableInvalidOwner program.constructor.ops do
    throwError "Vest20Link constructor lost OwnableInvalidOwner revert"
  unless ctorHasConstructorTransferred program.constructor.ops do
    throwError "Vest20Link constructor lost OwnershipTransferred log"
  let yul ←
    match Emit.emitYul program with
    | .ok yul => pure yul
    | .error reason => throwError reason
  let ctorYul := (yul.splitOn "_runtime")[0]!
  let invalidOwnerSel :=
    "0x" ++ ProofForge.Evm.Keccak.selector "OwnableInvalidOwner" #["address"]
  unless ctorYul.contains invalidOwnerSel do
    throwError s!"Vest20Link constructor Yul lost OwnableInvalidOwner:\n{ctorYul}"
  let ownershipTopic :=
    "0x" ++ ProofForge.Crypto.Keccak.keccak256HexOfString "OwnershipTransferred(address,address)"
  unless ctorYul.contains ownershipTopic do
    throwError s!"Vest20Link constructor Yul lost OwnershipTransferred topic:\n{ctorYul}"
  let canon := IR.canonical program
  for ixName in #["releasable", "vestedAmount"] do
    let some entry := (canon.splitOn "/").find? (·.startsWith s!"view:{ixName}:")
      | throwError s!"Vest20Link canonical IR lost {ixName}"
    unless entry.contains "checkedDivMod256" do
      throwError s!"{ixName} lost the linear formula"
  unless IR.digestHex program == "9a9cce6e0d2a58a2" do
    throwError s!"Vest20Link digest drifted: {IR.digestHex program}"
  logInfo m!"vest20link: digest={IR.digestHex program} abi-ok"

elab "#pf_guard_evm_vest20" : command => expectVest20Link

#pf_guard_evm_vest20

#pf_evm_build Examples.Evm.Vest20Link

end Tests.EvmVest20Spec
