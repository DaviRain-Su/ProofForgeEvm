import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.TwoStepCounter
import Examples.Evm.Credits
import Examples.Evm.Capped

/-!
S4b: canonical Ownable `OwnershipTransferred` (LOG3) and Pausable `Paused`/`Unpaused` (LOG1)
helpers. TwoStepCounter/Credits adopt both; Capped adopts pause events only (immutable owner).
Live receipt matrices live in `runtime-tests/evm/anvil_twostep_counter.sh`, `anvil_credits.sh`,
and `anvil_capped.sh`.
-/

namespace Tests.EvmOzPolicyEventSpec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard Ownable.Log.ownershipTransferred ⟨1, 2, 3⟩ ⟨4, 5, 6⟩ == 0
#guard Pausable.Log.paused ⟨1, 2, 3⟩ == 0
#guard Pausable.Log.unpaused ⟨1, 2, 3⟩ == 0

private def ownershipAbi : String :=
  "{\"type\":\"event\",\"name\":\"OwnershipTransferred\",\"inputs\":[" ++
    "{\"name\":\"previousOwner\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"newOwner\",\"type\":\"address\",\"indexed\":true}],\"anonymous\":false}"

private def pausedAbi : String :=
  "{\"type\":\"event\",\"name\":\"Paused\",\"inputs\":[" ++
    "{\"name\":\"account\",\"type\":\"address\",\"indexed\":false}],\"anonymous\":false}"

private def unpausedAbi : String :=
  "{\"type\":\"event\",\"name\":\"Unpaused\",\"inputs\":[" ++
    "{\"name\":\"account\",\"type\":\"address\",\"indexed\":false}],\"anonymous\":false}"

private def ownershipTopic : String :=
  ProofForge.Crypto.Keccak.keccak256HexOfString "OwnershipTransferred(address,address)"

private def pausedTopic : String :=
  ProofForge.Crypto.Keccak.keccak256HexOfString "Paused(address)"

private def unpausedTopic : String :=
  ProofForge.Crypto.Keccak.keccak256HexOfString "Unpaused(address)"

private partial def sourceTypedFrames (ops : Array ProofForge.Extract.IR.Op) :
    Array (ProofForge.Core.Ops.EventFrame ProofForge.Extract.IR.Val) :=
  ops.foldl (init := #[]) fun frames op =>
    let frames := match op with
      | .ext (.evm (.component (.nativeFx (.logTyped frame)))) => frames.push frame
      | _ => frames
    match op with
    | .ite _ _ _ yes no => frames ++ sourceTypedFrames yes ++ sourceTypedFrames no
    | .forBody _ body => frames ++ sourceTypedFrames body
    | _ => frames

private def eventMatches (frame : ProofForge.Core.Ops.EventFrame V)
    (constructor : String) (fields : Array (String × Bool)) : Bool :=
  frame.constructor == constructor &&
    frame.args.size == fields.size &&
    (List.zip frame.args.toList fields.toList).all fun
      | (arg, (name, indexed)) => arg.name == name && arg.indexed == indexed

private def methodOps (source : ProofForge.Extract.IR.Program) (name : String) :
    CommandElabM (Array ProofForge.Extract.IR.Op) := do
  let some method := source.methods.find? (·.ixName == name)
    | throwError s!"method {name} missing"
  return method.ops

private def expectDigest (moduleName : Name) (digest : String) : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env moduleName with
    | .ok source => pure source
    | .error reason => throwError reason
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  unless IR.digestHex program == digest do
    throwError s!"{moduleName} digest drifted: {IR.digestHex program}"

private def expectPolicyEvents (moduleName : Name) (wantOwnership : Bool) : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env moduleName with
    | .ok source => pure source
    | .error reason => throwError reason
  let pauseFrames := sourceTypedFrames (← methodOps source "pause")
  let unpauseFrames := sourceTypedFrames (← methodOps source "unpause")
  unless pauseFrames.size == 1 &&
      eventMatches pauseFrames[0]! "Paused" #[("account", false)] &&
      pauseFrames[0]!.args[0]!.type == .address20 do
    throwError s!"{moduleName}.pause Paused frame diverged: {repr pauseFrames}"
  unless unpauseFrames.size == 1 &&
      eventMatches unpauseFrames[0]! "Unpaused" #[("account", false)] &&
      unpauseFrames[0]!.args[0]!.type == .address20 do
    throwError s!"{moduleName}.unpause Unpaused frame diverged: {repr unpauseFrames}"
  if wantOwnership then
    let acceptFrames := sourceTypedFrames (← methodOps source "acceptOwnership")
    unless acceptFrames.size == 1 &&
        eventMatches acceptFrames[0]! "OwnershipTransferred"
          #[("previousOwner", true), ("newOwner", true)] &&
        acceptFrames[0]!.args[0]!.type == .address20 do
      throwError s!"{moduleName}.acceptOwnership OwnershipTransferred frame diverged: {repr acceptFrames}"
  let evm ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let abi ←
    match Emit.emitAbiChecked evm with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains pausedAbi && abi.contains unpausedAbi do
    throwError s!"{moduleName} ABI lost Paused/Unpaused:\n{abi}"
  unless abi.contains "{\"type\":\"error\",\"name\":\"Paused\",\"inputs\":[]}" do
    throwError s!"{moduleName} ABI lost Paused() error:\n{abi}"
  if wantOwnership then
    unless abi.contains ownershipAbi do
      throwError s!"{moduleName} ABI lost OwnershipTransferred:\n{abi}"
  else
    unless !abi.contains ownershipAbi do
      throwError s!"{moduleName} ABI unexpectedly contains OwnershipTransferred:\n{abi}"
  let yul ←
    match Emit.emitYul evm with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless yul.contains s!"log1(0, 32, 0x{pausedTopic}" &&
      yul.contains s!"log1(0, 32, 0x{unpausedTopic}" do
    throwError s!"{moduleName} Yul omitted LOG1 Paused/Unpaused"
  if wantOwnership then
    unless yul.contains s!"log3(0, 0, 0x{ownershipTopic}" do
      throwError s!"{moduleName} Yul omitted LOG3 OwnershipTransferred"
  else
    unless !yul.contains ownershipTopic do
      throwError s!"{moduleName} Yul unexpectedly contains OwnershipTransferred"

private def expectOzPolicy : CommandElabM Unit := do
  expectPolicyEvents `Examples.Evm.TwoStepCounter true
  expectPolicyEvents `Examples.Evm.Credits true
  expectPolicyEvents `Examples.Evm.Capped false
  expectDigest `Examples.Evm.TwoStepCounter "8aa4d044a935390e"
  expectDigest `Examples.Evm.Credits "3447fa1464d2897a"
  expectDigest `Examples.Evm.Capped "b0b0b7244ebb8aed"

elab "#pf_guard_evm_oz_policy_events" : command => expectOzPolicy

#pf_guard_evm_oz_policy_events

#pf_evm_build Examples.Evm.TwoStepCounter
#pf_evm_build Examples.Evm.Credits
#pf_evm_build Examples.Evm.Capped

end Tests.EvmOzPolicyEventSpec
