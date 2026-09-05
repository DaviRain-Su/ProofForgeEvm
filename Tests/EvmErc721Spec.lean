import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.Collectible
import Examples.Evm.Badge
import Tests.EvmAbiOverloadMisuse

/-!
EVM-SDK-7a focused suite: ERC-721 core predicates, token-id encoding limits, and two independent
consumers. Collectible/Badge emit canonical ERC-721 typed events (LOG4 Transfer/Approval, LOG3
ApprovalForAll). Live mint/approve/transfer/burn matrices live in
`runtime-tests/evm/anvil_collectible.sh` and `anvil_badge.sh`.
-/

namespace Tests.EvmErc721Spec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard Erc721.canEncode ⟨1, 0, 0, 0⟩
#guard Erc721.canEncode ⟨0, 1, 0, 0⟩
#guard Erc721.canEncode ⟨0, 0, 1, 0⟩
#guard !Erc721.canEncode ⟨0, 0, 0, 1⟩
#guard !Erc721.canEncode ⟨1, 0, 0, 1⟩
#guard Erc721.tokenKey ⟨7, 8, 9, 0⟩ == (⟨7, 8, 9⟩ : Address)
#guard Erc721.tokenKey ⟨7, 8, 9, 1⟩ == (⟨7, 8, 9⟩ : Address)
#guard Erc721.packAddress ⟨1, 2, 3⟩ == (⟨1, 2, 3, 0⟩ : UInt256)
#guard Erc721.unpackAddress ⟨1, 2, 3, 9⟩ == (⟨1, 2, 3⟩ : Address)
#guard Erc721.one == (⟨1, 0, 0, 0⟩ : UInt256)
#guard Erc721.onReceivedSelector == (⟨0x027a0b15, 0, 0, 0⟩ : Bytes4)

#guard
  match ProofForge.Extract.abiNameOfLean "safeTransferFrom__id" with
  | .ok n => n == "safeTransferFrom"
  | .error _ => false
#guard
  match ProofForge.Extract.abiNameOfLean "init" with
  | .ok n => n == "initialize"
  | .error _ => false

#guard Erc721.Log.transfer ⟨1, 2, 3⟩ ⟨4, 5, 6⟩ ⟨7, 0, 0, 0⟩ == 0
#guard Erc721.Log.approval ⟨1, 2, 3⟩ ⟨4, 5, 6⟩ ⟨7, 0, 0, 0⟩ == 0
#guard Erc721.Log.approvalForAll ⟨1, 2, 3⟩ ⟨4, 5, 6⟩ true == 0
-- The host stub has no code behind any address, so the receiver check is the skipped branch.
#guard Erc721.checkOnReceived ⟨1, 2, 3⟩ ⟨4, 5, 6⟩ ⟨7, 8, 9⟩ ⟨7, 0, 0, 0⟩
  { length := 0, values := Vector.replicate 32 0 } == 0

#guard Examples.Evm.Collectible.owners.base == 0
#guard Examples.Evm.Collectible.approvals.base == 1
#guard Examples.Evm.Collectible.operators.base == 2
#guard Examples.Evm.Collectible.balances.base == 3
#guard Examples.Evm.Badge.owners.base == 0
#guard Examples.Evm.Badge.approvals.base == 1
#guard Examples.Evm.Badge.operators.base == 2
#guard Examples.Evm.Badge.balances.base == 3

-- Closed ERC-20-shaped programs keep their digests; this slice only refreshes Collectible/Badge.
#guard Registry.digestOf "Token" == some "e25dfb4e1eaa54c"
#guard Registry.digestOf "Erc20Meta" == some "3dfa816778bd3ef6"

private def transferAbi : String :=
  "{\"type\":\"event\",\"name\":\"Transfer\",\"inputs\":[" ++
    "{\"name\":\"from\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"to\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"tokenId\",\"type\":\"uint256\",\"indexed\":true}],\"anonymous\":false}"

private def approvalAbi : String :=
  "{\"type\":\"event\",\"name\":\"Approval\",\"inputs\":[" ++
    "{\"name\":\"owner\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"approved\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"tokenId\",\"type\":\"uint256\",\"indexed\":true}],\"anonymous\":false}"

private def approvalForAllAbi : String :=
  "{\"type\":\"event\",\"name\":\"ApprovalForAll\",\"inputs\":[" ++
    "{\"name\":\"owner\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"operator\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"approved\",\"type\":\"bool\",\"indexed\":false}],\"anonymous\":false}"

/-- `safeTransferFrom(address,address,uint256,bytes)` answering the `Effect.thenTrue` bool. -/
private def safeTransferFromAbi : String :=
  "{\"type\":\"function\",\"name\":\"safeTransferFrom\",\"stateMutability\":\"nonpayable\"," ++
    "\"inputs\":[{\"name\":\"arg0\",\"type\":\"address\"},{\"name\":\"arg1\",\"type\":\"address\"}," ++
    "{\"name\":\"arg2\",\"type\":\"uint256\"},{\"name\":\"arg3\",\"type\":\"bytes\"}]," ++
    "\"outputs\":[{\"name\":\"\",\"type\":\"bool\"}]}"

/-- `safeTransferFrom(address,address,uint256)`, the OZ three-argument overload. -/
private def safeTransferFromIdAbi : String :=
  "{\"type\":\"function\",\"name\":\"safeTransferFrom\",\"stateMutability\":\"nonpayable\"," ++
    "\"inputs\":[{\"name\":\"arg0\",\"type\":\"address\"},{\"name\":\"arg1\",\"type\":\"address\"}," ++
    "{\"name\":\"arg2\",\"type\":\"uint256\"}]," ++
    "\"outputs\":[{\"name\":\"\",\"type\":\"bool\"}]}"

private def transferTopic : String :=
  ProofForge.Crypto.Keccak.keccak256HexOfString "Transfer(address,address,uint256)"

private def approvalTopic : String :=
  ProofForge.Crypto.Keccak.keccak256HexOfString "Approval(address,address,uint256)"

private def approvalForAllTopic : String :=
  ProofForge.Crypto.Keccak.keccak256HexOfString "ApprovalForAll(address,address,bool)"

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

private partial def sourceOpenCalls (ops : Array ProofForge.Extract.IR.Op) :
    Array (OpenCall.Plan ProofForge.Extract.IR.Val) :=
  ops.foldl (init := #[]) fun acc op =>
    let acc := match op with
      | .ext (.evm (.component (.openCall (.invoke plan)))) => acc.push plan
      | _ => acc
    match op with
    | .ite _ _ _ yes no => acc ++ sourceOpenCalls yes ++ sourceOpenCalls no
    | .forBody _ body => acc ++ sourceOpenCalls body
    | _ => acc

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

private def methodOpsArity (source : ProofForge.Extract.IR.Program) (name : String) (arity : Nat) :
    CommandElabM (Array ProofForge.Extract.IR.Op) := do
  let some method := source.methods.find? (fun m => m.ixName == name && m.paramCount == arity)
    | throwError s!"method {name}/{arity} missing"
  return method.ops

private def expectMethodNames (program : IR.Program) (names : Array String) : CommandElabM Unit := do
  let got := program.entries.map (·.ixName)
  unless got.size == names.size && names.all (got.contains ·) && got.all (names.contains ·) do
    throwError s!"{program.name} method ABI diverged: {got}"

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

private def expectCollectibleEvents : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.Collectible with
    | .ok source => pure source
    | .error reason => throwError reason
  let mintFrames := sourceTypedFrames (← methodOps source "mint")
  let approveFrames := sourceTypedFrames (← methodOps source "approve")
  let transferFrames := sourceTypedFrames (← methodOps source "transferFrom")
  unless mintFrames.size == 1 &&
      eventMatches mintFrames[0]! "Transfer"
        #[("from", true), ("to", true), ("tokenId", true)] &&
      mintFrames[0]!.args[2]!.type == .uint256 do
    throwError s!"Collectible.mint Transfer frame diverged: {repr mintFrames}"
  unless approveFrames.size == 1 &&
      eventMatches approveFrames[0]! "Approval"
        #[("owner", true), ("approved", true), ("tokenId", true)] do
    throwError s!"Collectible.approve Approval frame diverged: {repr approveFrames}"
  unless transferFrames.size == 1 &&
      eventMatches transferFrames[0]! "Transfer"
        #[("from", true), ("to", true), ("tokenId", true)] do
    throwError s!"Collectible.transferFrom Transfer frame diverged: {repr transferFrames}"
  let safeOps ← methodOpsArity source "safeTransferFrom" 4
  let safeFrames := sourceTypedFrames safeOps
  unless safeFrames.size == 1 &&
      eventMatches safeFrames[0]! "Transfer"
        #[("from", true), ("to", true), ("tokenId", true)] do
    throwError s!"Collectible.safeTransferFrom Transfer frame diverged: {repr safeFrames}"
  -- The receiver hook is one CALL plan whose magic is its own selector, four head words plus the
  -- 32-byte bounded `data` tail (4 + 4 * 32 + 32 = 164 static calldata bytes).
  let hookSelector := ProofForge.Evm.Keccak.selector "onERC721Received"
    #["address", "address", "uint256", "bytes"]
  unless hookSelector == "150b7a02" do
    throwError s!"onERC721Received selector is {hookSelector}"
  let hookPlans := sourceOpenCalls safeOps
  unless hookPlans.size == 1 && hookPlans[0]!.name == "onERC721Received" &&
      hookPlans[0]!.kind == .call && hookPlans[0]!.policy == .magicBytes4 hookSelector &&
      hookPlans[0]!.args.size == 4 &&
      hookPlans[0]!.args[0]!.name == "operator" && hookPlans[0]!.args[1]!.name == "from" &&
      hookPlans[0]!.args[2]!.name == "tokenId" && hookPlans[0]!.args[3]!.name == "data" &&
      hookPlans[0]!.args[3]!.type == .bytes 32 && hookPlans[0]!.inSize == 164 &&
      hookPlans[0]!.abiTypes matches .ok #["address", "address", "uint256", "bytes"] do
    throwError s!"Collectible.safeTransferFrom hook plan diverged: {repr hookPlans}"
  let safe3Ops ← methodOpsArity source "safeTransferFrom" 3
  let safe3Plans := sourceOpenCalls safe3Ops
  unless safe3Plans.size == 1 && safe3Plans[0]!.name == "onERC721Received" &&
      safe3Plans[0]!.args[3]!.type == .bytes 32 && safe3Plans[0]!.inSize == 164 do
    throwError s!"Collectible.safeTransferFrom(address,address,uint256) hook plan diverged: {repr safe3Plans}"
  let evm ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  expectMethodNames evm
    #["mint", "approve", "transferFrom", "safeTransferFrom", "safeTransferFrom", "ownerOf",
      "getApproved", "balanceOf", "supportsInterface"]
  let abi ←
    match Emit.emitAbiChecked evm with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains transferAbi && abi.contains approvalAbi &&
      !abi.contains approvalForAllAbi &&
      !abi.contains "\"name\":\"value\"" do
    throwError s!"Collectible ABI lost ERC-721 Transfer/Approval:\n{abi}"
  unless abi.contains safeTransferFromAbi do
    throwError s!"Collectible ABI lost safeTransferFrom(address,address,uint256,bytes):\n{abi}"
  unless abi.contains safeTransferFromIdAbi do
    throwError s!"Collectible ABI lost safeTransferFrom(address,address,uint256):\n{abi}"
  let selectors :=
    (evm.entries.filter (·.ixName == "safeTransferFrom")).map (·.selector)
  unless selectors.contains "42842e0e" && selectors.contains "b88d4fde" && selectors.size == 2 do
    throwError s!"Collectible safeTransferFrom selectors diverged: {selectors}"
  let yul ←
    match Emit.emitYul evm with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless yul.contains s!"log4(0, 0, 0x{transferTopic}" &&
      yul.contains s!"log4(0, 0, 0x{approvalTopic}" &&
      !yul.contains "log3(" &&
      !yul.contains approvalForAllTopic do
    throwError "Collectible Yul omitted LOG4 Transfer/Approval"
  -- OZ order: the recipient's code size decides whether the hook runs, and a hook answer other
  -- than the left-aligned selector reverts.
  unless yul.contains "extcodesize(" &&
      yul.contains s!"shl(224, 0x{hookSelector}))) \{ revert(0, 0) }" do
    throwError "Collectible Yul lost the receiver code-size guard or the magic equality gate"

private def expectBadgeEvents : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.Badge with
    | .ok source => pure source
    | .error reason => throwError reason
  let mintFrames := sourceTypedFrames (← methodOps source "mint")
  let operatorFrames := sourceTypedFrames (← methodOps source "setApprovalForAll")
  let transferFrames := sourceTypedFrames (← methodOps source "transferFrom")
  let burnFrames := sourceTypedFrames (← methodOps source "burn")
  unless mintFrames.size == 1 &&
      eventMatches mintFrames[0]! "Transfer"
        #[("from", true), ("to", true), ("tokenId", true)] do
    throwError s!"Badge.mint Transfer frame diverged: {repr mintFrames}"
  unless operatorFrames.size == 1 &&
      eventMatches operatorFrames[0]! "ApprovalForAll"
        #[("owner", true), ("operator", true), ("approved", false)] &&
      operatorFrames[0]!.args[2]!.type == .boolean do
    throwError s!"Badge.setApprovalForAll frame diverged: {repr operatorFrames}"
  unless transferFrames.size == 1 &&
      eventMatches transferFrames[0]! "Transfer"
        #[("from", true), ("to", true), ("tokenId", true)] do
    throwError s!"Badge.transferFrom Transfer frame diverged: {repr transferFrames}"
  unless burnFrames.size == 1 &&
      eventMatches burnFrames[0]! "Transfer"
        #[("from", true), ("to", true), ("tokenId", true)] do
    throwError s!"Badge.burn Transfer frame diverged: {repr burnFrames}"
  let evm ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  expectMethodNames evm
    #["mint", "setApprovalForAll", "transferFrom", "burn", "ownerOf", "getApproved",
      "isApprovedForAll", "balanceOf", "supportsInterface"]
  let abi ←
    match Emit.emitAbiChecked evm with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains transferAbi && abi.contains approvalForAllAbi &&
      !abi.contains approvalAbi do
    throwError s!"Badge ABI lost ERC-721 Transfer/ApprovalForAll:\n{abi}"
  let yul ←
    match Emit.emitYul evm with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless yul.contains s!"log4(0, 0, 0x{transferTopic}" &&
      yul.contains s!"log3(0, 32, 0x{approvalForAllTopic}" &&
      !yul.contains approvalTopic do
    throwError "Badge Yul omitted LOG4 Transfer or LOG3 ApprovalForAll"

private def expectErc721 : CommandElabM Unit := do
  let env ← getEnv
  match ProofForge.Extract.extractModuleIR env `Tests.EvmAbiOverloadMisuse with
  | .error reason =>
    unless reason.contains "duplicate ABI bump()" do
      throwError s!"overload misuse reason diverged: {reason}"
  | .ok _ => throwError "duplicate bump() extracted"
  expectCollectibleEvents
  expectBadgeEvents
  expectDigest `Examples.Evm.Collectible "19250482fbd80a03"
  expectDigest `Examples.Evm.Badge "bdb4d1d1a4e9baa7"

elab "#pf_guard_evm_erc721" : command => expectErc721

#pf_guard_evm_erc721

#pf_evm_build Examples.Evm.Collectible
#pf_evm_build Examples.Evm.Badge

end Tests.EvmErc721Spec
