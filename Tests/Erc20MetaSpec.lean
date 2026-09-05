import ProofForge
import ProofForge.Evm.Commands
import Examples.Evm.Erc20Meta

/-!
W5 slice 4–6: ERC-20 metadata SDK + canonical typed Transfer/Approval on `Erc20Meta`,
plus owner-gated mint. This slice adds issuer EIP-2612 `permit` / `DOMAIN_SEPARATOR` /
`nonces` (rows 8/19 stay PARTIAL; extensions/permit-votes remain the named restriction).

Pins the `Erc20Meta` digest and checks that `name` / `symbol` use the ERC-20 `string` ABI (not
packed `bytes32` like `Examples.Evm.Token`) and that Transfer/Approval appear as typed events.
-/

namespace Tests.Erc20MetaSpec

open ProofForge
open ProofForge.Evm
open ProofForge.Evm.Sdk
open ProofForge.Core.Value
open Lean Elab Command

#guard Erc20Meta.defaultNameCapacity == 32
#guard Erc20Meta.defaultSymbolCapacity == 8
#guard Erc20Meta.defaultDecimals == 18
#guard Erc20Meta.emptyName.length == 0
#guard Erc20Meta.emptySymbol.length == 0
#guard Erc20Meta.wellFormedName Examples.Evm.Erc20Meta.tokenName
#guard Erc20Meta.wellFormedSymbol Examples.Evm.Erc20Meta.tokenSymbol
#guard Erc20Meta.canPublish Examples.Evm.Erc20Meta.tokenName Examples.Evm.Erc20Meta.tokenSymbol
#guard !Erc20Meta.canPublish Erc20Meta.emptyName Examples.Evm.Erc20Meta.tokenSymbol
#guard !Erc20Meta.canPublish Examples.Evm.Erc20Meta.tokenName Erc20Meta.emptySymbol

private def invalidUtf8Name : BoundedString 8 :=
  { length := 2, values := #v[0xc0, 0x80, 0, 0, 0, 0, 0, 0] }

#guard !Erc20Meta.canPublish invalidUtf8Name Examples.Evm.Erc20Meta.tokenSymbol

private def sampleOwner : Address := ⟨1, 2, 3⟩
private def sampleSpender : Address := ⟨4, 5, 6⟩
private def nine : UInt256 := ⟨9, 0, 0, 0⟩

#guard Examples.Evm.Erc20Meta.nonces (Examples.Evm.Erc20Meta.init sampleOwner) sampleOwner ==
  ⟨0, 0, 0, 0⟩
#guard Examples.Evm.Erc20Meta.DOMAIN_SEPARATOR (Examples.Evm.Erc20Meta.init sampleOwner) ==
  ⟨0, 0, 0, 0⟩
#guard
  match Examples.Evm.Erc20Meta.permit (Examples.Evm.Erc20Meta.init sampleOwner)
      sampleOwner sampleSpender nine nine 27 ⟨1, 0, 0, 0⟩ ⟨2, 0, 0, 0⟩ with
  | .ok (_, ret) => ret == 9
  | .error _ => false

#guard Fungible.Log.transfer ⟨1, 2, 3⟩ ⟨4, 5, 6⟩ ⟨7, 0, 0, 0⟩ == 0
#guard Fungible.Log.approval ⟨1, 2, 3⟩ ⟨4, 5, 6⟩ ⟨7, 0, 0, 0⟩ == 0

private def transferAbi : String :=
  "{\"type\":\"event\",\"name\":\"Transfer\",\"inputs\":[" ++
    "{\"name\":\"from\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"to\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"value\",\"type\":\"uint256\",\"indexed\":false}],\"anonymous\":false}"

private def approvalAbi : String :=
  "{\"type\":\"event\",\"name\":\"Approval\",\"inputs\":[" ++
    "{\"name\":\"owner\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"spender\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"value\",\"type\":\"uint256\",\"indexed\":false}],\"anonymous\":false}"

private def transferTopic : String :=
  ProofForge.Crypto.Keccak.keccak256HexOfString "Transfer(address,address,uint256)"

private def approvalTopic : String :=
  ProofForge.Crypto.Keccak.keccak256HexOfString "Approval(address,address,uint256)"

private partial def sourceTypedFrames (ops : Array ProofForge.Extract.IR.Op) :
    Array (ProofForge.Core.Ops.EventFrame ProofForge.Extract.IR.Val) :=
  ops.foldl (init := #[]) fun frames op =>
    let frames := match op with
      | .ext (.evm (.component (.nativeFx (.logTyped frame _)))) => frames.push frame
      | _ => frames
    match op with
    | .ite _ _ _ yes no => frames ++ sourceTypedFrames yes ++ sourceTypedFrames no
    | .forBody _ body => frames ++ sourceTypedFrames body
    | _ => frames

private def eventMatches (frame : ProofForge.Core.Ops.EventFrame ProofForge.Extract.IR.Val)
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

elab "#pf_erc20_meta_check" : command => do
  let env ← getEnv
  let module := `Examples.Evm.Erc20Meta
  let source ←
    match ProofForge.Extract.extractModuleIR env module with
    | .ok source => pure source
    | .error reason => throwError reason
  let transferFrames := sourceTypedFrames (← methodOps source "transfer")
  let approveFrames := sourceTypedFrames (← methodOps source "approve")
  let transferFromFrames := sourceTypedFrames (← methodOps source "transferFrom")
  let mintFrames := sourceTypedFrames (← methodOps source "mint")
  unless transferFrames.size == 1 &&
      eventMatches transferFrames[0]! "Transfer"
        #[("from", true), ("to", true), ("value", false)] &&
      transferFrames[0]!.args[2]!.type == .uint256 do
    throwError s!"Erc20Meta.transfer Transfer frame diverged: {repr transferFrames}"
  unless approveFrames.size == 1 &&
      eventMatches approveFrames[0]! "Approval"
        #[("owner", true), ("spender", true), ("value", false)] do
    throwError s!"Erc20Meta.approve Approval frame diverged: {repr approveFrames}"
  unless transferFromFrames.size == 1 &&
      eventMatches transferFromFrames[0]! "Transfer"
        #[("from", true), ("to", true), ("value", false)] do
    throwError s!"Erc20Meta.transferFrom Transfer frame diverged: {repr transferFromFrames}"
  unless mintFrames.size == 1 &&
      eventMatches mintFrames[0]! "Transfer"
        #[("from", true), ("to", true), ("value", false)] &&
      mintFrames[0]!.args[2]!.type == .uint256 do
    throwError s!"Erc20Meta.mint Transfer frame diverged: {repr mintFrames}"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let digest := IR.digestHex program
  unless digest == "9e1221ef24a9c091" do
    throwError s!"Erc20Meta digest mismatch: {digest}"
  let want := #["DOMAIN_SEPARATOR", "allowance", "approve", "balanceOf", "decimals",
    "initialize", "mint", "name", "nonces", "ownerOf", "permit", "symbol", "totalSupply",
    "transfer", "transferFrom"]
  let methods :=
    (#[program.constructor.ixName] ++ program.entries.map (·.ixName)) |>.qsort (· < ·)
  unless methods == want do
    throwError s!"Erc20Meta method surface diverged: {methods}"
  let some nameEntry := program.entries.find? (·.ixName == "name")
    | throwError "missing name"
  let some symbolEntry := program.entries.find? (·.ixName == "symbol")
    | throwError "missing symbol"
  unless nameEntry.selector == ProofForge.Crypto.Keccak.selector "name" #[] do
    throwError s!"name selector drifted: {nameEntry.selector}"
  unless symbolEntry.selector == ProofForge.Crypto.Keccak.selector "symbol" #[] do
    throwError s!"symbol selector drifted: {symbolEntry.selector}"
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"name\"" && abi.contains "\"type\":\"string\"" do
    throwError "name() must advertise string output in ABI"
  unless abi.contains "\"name\":\"symbol\"" do
    throwError "missing symbol in ABI"
  unless abi.contains "\"name\":\"allowance\"" do
    throwError "missing standard allowance (not allowanceOf)"
  unless !abi.contains "\"name\":\"allowanceOf\"" do
    throwError "non-standard allowanceOf must not appear"
  unless !abi.contains "\"name\":\"nonceOf\"" do
    throwError "non-standard nonceOf must not appear; IERC2612 is nonces(address)"
  unless abi.contains "\"name\":\"permit\"" do
    throwError "missing issuer permit"
  unless abi.contains "\"name\":\"DOMAIN_SEPARATOR\"" &&
      abi.contains "\"type\":\"bytes32\"" do
    throwError "DOMAIN_SEPARATOR() must advertise bytes32"
  unless abi.contains "\"name\":\"nonces\"" do
    throwError "missing IERC2612 nonces(address)"
  unless abi.contains "\"name\":\"Expired\"" do
    throwError "permit must advertise Expired"
  unless abi.contains transferAbi && abi.contains approvalAbi do
    throwError s!"Erc20Meta ABI lost canonical typed Transfer/Approval:\n{abi}"
  let yul ←
    match Emit.emitYul program with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless yul.contains s!"log3(0, 32, 0x{transferTopic}" &&
      yul.contains s!"log3(0, 32, 0x{approvalTopic}" do
    throwError "Erc20Meta Yul omitted LOG3 Transfer/Approval"
  unless yul.contains "staticcall(gas(), 1," && yul.contains "0x1901" &&
      yul.contains "keccak256(0, 224)" do
    throwError "Erc20Meta Yul omitted closed permit ecrecover / EIP-712 / allowance slot"
  let some permitEntry := program.entries.find? (·.ixName == "permit")
    | throwError "missing permit"
  let some domainEntry := program.entries.find? (·.ixName == "DOMAIN_SEPARATOR")
    | throwError "missing DOMAIN_SEPARATOR"
  let some nonceEntry := program.entries.find? (·.ixName == "nonces")
    | throwError "missing nonces"
  unless domainEntry.view == true && domainEntry.retWidths == #[33] do
    throwError s!"DOMAIN_SEPARATOR view drifted: view={domainEntry.view} ret={domainEntry.retWidths}"
  unless nonceEntry.view == true && nonceEntry.retWidths == #[32] do
    throwError s!"nonces view drifted: view={nonceEntry.view} ret={nonceEntry.retWidths}"
  unless permitEntry.view == false do
    throwError "permit must be a mutation"
  logInfo m!"erc20-meta: digest={digest}"

#pf_erc20_meta_check

#pf_evm_build Examples.Evm.Erc20Meta

end Tests.Erc20MetaSpec
