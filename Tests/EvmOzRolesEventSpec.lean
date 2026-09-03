import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.EvmStaticCounter
import Examples.Evm.EvmStaticRoster

/-!
S4d: canonical AccessControl `RoleGranted` / `RoleRevoked` (LOG4, empty data) helpers.
EvmStaticCounter/EvmStaticRoster adopt both on actual Set2 slot writes. There is no
`RoleAdminChanged` (no admin-role rotation API). Live receipt matrices live in
`runtime-tests/evm/anvil_static_counter.sh` and `anvil_static_roster.sh`.
-/

namespace Tests.EvmOzRolesEventSpec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard Roles.Log.roleGranted ⟨1, 2, 3, 4⟩ ⟨5, 6, 7⟩ ⟨8, 9, 10⟩ == 0
#guard Roles.Log.roleRevoked ⟨1, 2, 3, 4⟩ ⟨5, 6, 7⟩ ⟨8, 9, 10⟩ == 0

#guard Examples.Evm.EvmStaticCounter.OPERATOR_ROLE ==
  (⟨0x82f14ec570706697, 0xc1ea4b038b85f5b0, 0x8b18d3a29a08f3b6, 0x29b9a94f9f92e8b1⟩ : Bytes32)
#guard Examples.Evm.EvmStaticRoster.WRITER_ROLE ==
  (⟨0x39c11a368f168f2b, 0x9a89faadd43e163a, 0x675164717c7bbe87, 0xc853e42a82ddadbd⟩ : Bytes32)

private def roleGrantedAbi : String :=
  "{\"type\":\"event\",\"name\":\"RoleGranted\",\"inputs\":[" ++
    "{\"name\":\"role\",\"type\":\"bytes32\",\"indexed\":true}," ++
    "{\"name\":\"account\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"sender\",\"type\":\"address\",\"indexed\":true}],\"anonymous\":false}"

private def roleRevokedAbi : String :=
  "{\"type\":\"event\",\"name\":\"RoleRevoked\",\"inputs\":[" ++
    "{\"name\":\"role\",\"type\":\"bytes32\",\"indexed\":true}," ++
    "{\"name\":\"account\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"sender\",\"type\":\"address\",\"indexed\":true}],\"anonymous\":false}"

private def roleAdminChangedAbi : String :=
  "{\"type\":\"event\",\"name\":\"RoleAdminChanged\""

private def roleGrantedTopic : String :=
  ProofForge.Crypto.Keccak.keccak256HexOfString "RoleGranted(bytes32,address,address)"

private def roleRevokedTopic : String :=
  ProofForge.Crypto.Keccak.keccak256HexOfString "RoleRevoked(bytes32,address,address)"

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

private def roleFrameOk (frame : ProofForge.Core.Ops.EventFrame V) (constructor : String) : Bool :=
  eventMatches frame constructor #[("role", true), ("account", true), ("sender", true)] &&
    frame.args[0]!.type == .bytes32 &&
    frame.args[1]!.type == .address20 &&
    frame.args[2]!.type == .address20

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

private def expectRoleEvents (moduleName : Name) (grantName revokeName : String) :
    CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env moduleName with
    | .ok source => pure source
    | .error reason => throwError reason
  let grantFrames := sourceTypedFrames (← methodOps source grantName)
  let revokeFrames := sourceTypedFrames (← methodOps source revokeName)
  unless grantFrames.size == 2 && grantFrames.toList.all (roleFrameOk · "RoleGranted") do
    throwError s!"{moduleName}.{grantName} RoleGranted frames diverged: {repr grantFrames}"
  unless revokeFrames.size == 2 && revokeFrames.toList.all (roleFrameOk · "RoleRevoked") do
    throwError s!"{moduleName}.{revokeName} RoleRevoked frames diverged: {repr revokeFrames}"
  let evm ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let abi ←
    match Emit.emitAbiChecked evm with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains roleGrantedAbi && abi.contains roleRevokedAbi do
    throwError s!"{moduleName} ABI lost RoleGranted/RoleRevoked:\n{abi}"
  unless !abi.contains roleAdminChangedAbi do
    throwError s!"{moduleName} ABI unexpectedly contains RoleAdminChanged:\n{abi}"
  let yul ←
    match Emit.emitYul evm with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless yul.contains s!"log4(0, 0, 0x{roleGrantedTopic}" &&
      yul.contains s!"log4(0, 0, 0x{roleRevokedTopic}" do
    throwError s!"{moduleName} Yul omitted LOG4 RoleGranted/RoleRevoked"

private def expectOzRoles : CommandElabM Unit := do
  expectRoleEvents `Examples.Evm.EvmStaticCounter "grantOperator" "revokeOperator"
  expectRoleEvents `Examples.Evm.EvmStaticRoster "grantWriter" "revokeWriter"
  expectDigest `Examples.Evm.EvmStaticCounter "6225c3939859e297"
  expectDigest `Examples.Evm.EvmStaticRoster "a87e8840e3904357"

elab "#pf_guard_evm_oz_roles_events" : command => expectOzRoles

#pf_guard_evm_oz_roles_events

#pf_evm_build Examples.Evm.EvmStaticCounter
#pf_evm_build Examples.Evm.EvmStaticRoster

end Tests.EvmOzRolesEventSpec
