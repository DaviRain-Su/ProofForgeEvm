import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.MultiToken
import Examples.Evm.CraftToken

/-!
EVM-SDK-8 focused suite: bounded ERC-1155 key envelope, predicate surface, and two independent
consumers. MultiToken/CraftToken emit canonical ERC-1155 typed events (LOG4 TransferSingle with
two data words, LOG3 ApprovalForAll). Live mint/burn/transfer/operator matrices live in
`runtime-tests/evm/anvil_multitoken.sh` and `anvil_crafttoken.sh`.
-/

namespace Tests.EvmErc1155Spec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

namespace UnsupportedConditionFixture

structure State where
  value : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

/-- An unmarked host definition is not an extraction contract and must never be constant-folded. -/
@[irreducible] def hostPredicate (_value : UInt64) : Bool := true

@[pf_entry] def init (value : UInt64) : State := ⟨value⟩

@[pf_entry] def guarded (state : State) (value : UInt64) : Except Error State :=
  if hostPredicate value then .ok ⟨value⟩ else .ok state

end UnsupportedConditionFixture

-- Key envelope: only ids with a zero top limb are encodable; tokenKey truncates, so every
-- consumer path must gate first.
#guard Erc1155.canEncode ⟨1, 0, 0, 0⟩
#guard Erc1155.canEncode ⟨0, 1, 0, 0⟩
#guard Erc1155.canEncode ⟨0, 0, 1, 0⟩
#guard !Erc1155.canEncode ⟨0, 0, 0, 1⟩
#guard !Erc1155.canEncode ⟨1, 0, 0, 1⟩
#guard Erc1155.tokenKey ⟨7, 8, 9, 0⟩ == (⟨7, 8, 9⟩ : Address)
#guard Erc1155.tokenKey ⟨7, 8, 9, 1⟩ == (⟨7, 8, 9⟩ : Address)
#guard Erc1155.Log.transferSingle ⟨1, 2, 3⟩ ⟨4, 5, 6⟩ ⟨7, 8, 9⟩ ⟨10, 0, 0, 0⟩ ⟨11, 0, 0, 0⟩ == 0
#guard Erc1155.Log.approvalForAll ⟨1, 2, 3⟩ ⟨4, 5, 6⟩ true == 0

-- Closed ERC-20-shaped programs keep their digests; this slice only refreshes MultiToken/CraftToken.
#guard Registry.digestOf "Token" == some "7d01d10202d87dd3"
#guard Registry.digestOf "Erc20Meta" == some "fb7b729e9b7ea596"

def specBalances : Erc1155.Balances := Storage.Layout.root.addressPairMap256.handle
def specOperators : Erc1155.Operators :=
  Storage.Layout.root.addressPairMap256.next.addressPairMap.handle
def specOwner : Address := ⟨1, 2, 3⟩
def specOther : Address := ⟨4, 5, 6⟩
def specId : UInt256 := ⟨7, 0, 0, 0⟩
def specAliasId : UInt256 := ⟨7, 0, 0, 1⟩
def specAmount : UInt256 := ⟨9, 0, 0, 0⟩

-- Disjoint compile-time namespaces for both consumers.
#guard Examples.Evm.MultiToken.balances.base == 0
#guard Examples.Evm.MultiToken.operators.base == 1
#guard Examples.Evm.CraftToken.balances.base == 0
#guard Examples.Evm.CraftToken.operators.base == 1
#guard Examples.Evm.CraftToken.supply.base == 2
#guard Examples.Evm.CraftToken.maxPerId == (⟨1000, 0, 0, 0⟩ : UInt256)

-- The SDK-owned checked view rejects an unencodable alias before its hashed-map read.
-- `canEncode` is honest Bool arithmetic, so these guards are kernel-checkable on host; the
-- hashed-map load itself host-evaluates to zero (empty map).
#guard Examples.Evm.MultiToken.balanceOf ⟨0⟩ specOwner specId == UInt256.zero
#guard Examples.Evm.MultiToken.balanceOf ⟨0⟩ specOwner specAliasId == UInt256.zero
#guard Examples.Evm.CraftToken.balanceOf ⟨0⟩ specOwner specAliasId == UInt256.zero
#guard Examples.Evm.CraftToken.supplyOf ⟨0⟩ specAliasId == UInt256.zero

-- Pre-write/pre-auth envelope gates: unencodable ids fail every mutation and authorization
-- predicate. These guards are honest on host because `canEncode` is the first `&&` conjunct and
-- short-circuits before the comparison leaves. Positive encodable-id predicate semantics are NOT
-- host-checkable: `Runtime.evmGe256`/`evmEq20` are placeholder constants (`true`) whose real
-- behavior is an extraction contract, covered end-to-end by the Anvil fixtures.
#guard !Erc1155.Balances.canCredit specBalances specOwner specAliasId specAmount
#guard !Erc1155.Balances.canDebit specBalances specOwner specAliasId specAmount
#guard !Erc1155.Balances.canTransfer specBalances specOwner specOther specAliasId specAmount
#guard !Erc1155.canMint specBalances specOwner specAliasId specAmount
#guard !Erc1155.canBurn specBalances specOwner specAliasId specAmount
#guard !Erc1155.isApprovedOrOwner specOperators specOwner specOwner specAliasId
#guard !Erc1155.isApprovedOrOwner specOperators specOther specOwner specAliasId

/-- Compile-time surface check for the checked mint/burn/transfer branches. Map/comparison
Runtime leaves are extraction contracts and are not assigned host-evaluation semantics. -/
def erc1155TransferSurface (source to : Address) (tokenId amount : UInt256) : UInt64 :=
  if Erc1155.Balances.canTransfer specBalances source to tokenId amount then
    Erc1155.Balances.transfer specBalances source to tokenId amount
  else
    0

private partial def valContainsBalanceRead : ProofForge.Extract.IR.Val → Bool
  | .arg _ | .local _ | .lit _ | .loopIx => false
  | .field base _ | .bitNot base => valContainsBalanceRead base
  | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
  | .shiftL lhs rhs | .shiftR lhs rhs
  | .addU64 lhs rhs | .subU64 lhs rhs | .mulU64 lhs rhs
  | .divU64 lhs rhs | .modU64 lhs rhs =>
      valContainsBalanceRead lhs || valContainsBalanceRead rhs
  | .indexGet base _ idx _ _ =>
      valContainsBalanceRead base || valContainsBalanceRead idx
  | .select _ lhs rhs thn els =>
      valContainsBalanceRead lhs || valContainsBalanceRead rhs ||
        valContainsBalanceRead thn || valContainsBalanceRead els
  | .ext kind operands =>
      (match kind with
        | .evm (.component (.hashedMap (.getPair256 _))) => true
        | _ => false) || operands.any valContainsBalanceRead

private def opValues : ProofForge.Extract.IR.Op → Array ProofForge.Extract.IR.Val
  | .letLocal _ value | .setLocal _ value | .forAccum _ value _
  | .storeField _ value | .okState value | .returnU64 value | .returnState value => #[value]
  | .checkedAddU64 lhs rhs | .checkedSubU64 lhs rhs | .checkedMulU64 lhs rhs
  | .checkedDivU64 lhs rhs | .checkedModU64 lhs rhs => #[lhs, rhs]
  | .ite _ lhs rhs _ _ => #[lhs, rhs]
  | .indexSetLeaf _ idx value _ _ | .indexSet _ idx value _ _ => #[idx, value]
  | .ext payload => ProofForge.Extract.IR.OpExt.values payload
  | .errorTyped frame => frame.values
  | .joinLocal _ | .forBody _ _ | .errorOverflow | .errorNamed _ => #[]

private partial def opsContainBalanceRead (ops : Array ProofForge.Extract.IR.Op) : Bool :=
  ops.any fun op =>
    (opValues op).any valContainsBalanceRead || match op with
      | .ite _ _ _ thn els => opsContainBalanceRead thn || opsContainBalanceRead els
      | .forBody _ body => opsContainBalanceRead body
      | _ => false

/-- A checked SDK view must not evaluate a truncated hashed-map key before entering its gate. -/
private partial def balanceReadsAreGuarded
    (ops : Array ProofForge.Extract.IR.Op) (guarded := false) : Bool :=
  ops.all fun op =>
    (guarded || !(opValues op).any valContainsBalanceRead) && match op with
      | .ite _ _ _ thn els =>
          balanceReadsAreGuarded thn true && balanceReadsAreGuarded els true
      | .forBody _ body => balanceReadsAreGuarded body guarded
      | _ => true

private partial def hasControlFlow (ops : Array ProofForge.Extract.IR.Op) : Bool :=
  ops.any fun op => match op with
    | .ite _ _ _ _ _ => true
    | .forBody _ body => hasControlFlow body
    | _ => false

private partial def valContainsNamedCapComparison : ProofForge.Extract.IR.Val → Bool
  | .arg _ | .local _ | .lit _ | .loopIx => false
  | .field base _ | .bitNot base => valContainsNamedCapComparison base
  | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
  | .shiftL lhs rhs | .shiftR lhs rhs
  | .addU64 lhs rhs | .subU64 lhs rhs | .mulU64 lhs rhs
  | .divU64 lhs rhs | .modU64 lhs rhs =>
      valContainsNamedCapComparison lhs || valContainsNamedCapComparison rhs
  | .indexGet base _ idx _ _ =>
      valContainsNamedCapComparison base || valContainsNamedCapComparison idx
  | .select _ lhs rhs thn els =>
      valContainsNamedCapComparison lhs || valContainsNamedCapComparison rhs ||
        valContainsNamedCapComparison thn || valContainsNamedCapComparison els
  | .ext (.evm (.component (.wideWord .ge256))) operands =>
      operands.size == 8 && operands[0]! == .lit 1000 && operands[1]! == .lit 0 &&
        operands[2]! == .lit 0 && operands[3]! == .lit 0
  | .ext _ operands => operands.any valContainsNamedCapComparison

/-- The application-owned named `UInt256` cap must remain a real packed comparison condition. -/
private partial def hasNamedCapGate (ops : Array ProofForge.Extract.IR.Op) : Bool :=
  ops.any fun op => match op with
    | .ite .ne lhs (.lit 0) thn els =>
        valContainsNamedCapComparison lhs || hasNamedCapGate thn || hasNamedCapGate els
    | .ite _ _ _ thn els => hasNamedCapGate thn || hasNamedCapGate els
    | .forBody _ body => hasNamedCapGate body
    | _ => false

private def transferSingleAbi : String :=
  "{\"type\":\"event\",\"name\":\"TransferSingle\",\"inputs\":[" ++
    "{\"name\":\"operator\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"from\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"to\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"id\",\"type\":\"uint256\",\"indexed\":false}," ++
    "{\"name\":\"value\",\"type\":\"uint256\",\"indexed\":false}],\"anonymous\":false}"

private def approvalForAllAbi : String :=
  "{\"type\":\"event\",\"name\":\"ApprovalForAll\",\"inputs\":[" ++
    "{\"name\":\"account\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"operator\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"approved\",\"type\":\"bool\",\"indexed\":false}],\"anonymous\":false}"

private def erc20TransferAbi : String :=
  "{\"type\":\"event\",\"name\":\"Transfer\",\"inputs\":[" ++
    "{\"name\":\"from\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"to\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"value\",\"type\":\"uint256\",\"indexed\":false}],\"anonymous\":false}"

private def transferSingleTopic : String :=
  ProofForge.Crypto.Keccak.keccak256HexOfString
    "TransferSingle(address,address,address,uint256,uint256)"

private def approvalForAllTopic : String :=
  ProofForge.Crypto.Keccak.keccak256HexOfString "ApprovalForAll(address,address,bool)"

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

private def expectTypedAbiYul (evm : IR.Program) : CommandElabM Unit := do
  let abi ←
    match Emit.emitAbiChecked evm with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains transferSingleAbi && abi.contains approvalForAllAbi &&
      !abi.contains erc20TransferAbi && !abi.contains "TransferBatch" do
    throwError s!"{evm.name} ABI lost ERC-1155 TransferSingle/ApprovalForAll:\n{abi}"
  let yul ←
    match Emit.emitYul evm with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless yul.contains s!"log4(0, 64, 0x{transferSingleTopic}" &&
      yul.contains s!"log3(0, 32, 0x{approvalForAllTopic}" do
    throwError s!"{evm.name} Yul omitted LOG4 TransferSingle or LOG3 ApprovalForAll"

private def expectMultiTokenEvents : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.MultiToken with
    | .ok source => pure source
    | .error reason => throwError reason
  let mintFrames := sourceTypedFrames (← methodOps source "mint")
  let operatorFrames := sourceTypedFrames (← methodOps source "setApprovalForAll")
  let transferFrames := sourceTypedFrames (← methodOps source "transferFrom")
  let burnFrames := sourceTypedFrames (← methodOps source "burn")
  unless mintFrames.size == 1 &&
      eventMatches mintFrames[0]! "TransferSingle"
        #[("operator", true), ("from", true), ("to", true), ("id", false), ("value", false)] &&
      mintFrames[0]!.args[3]!.type == .uint256 &&
      mintFrames[0]!.args[4]!.type == .uint256 do
    throwError s!"MultiToken.mint TransferSingle frame diverged: {repr mintFrames}"
  unless operatorFrames.size == 1 &&
      eventMatches operatorFrames[0]! "ApprovalForAll"
        #[("account", true), ("operator", true), ("approved", false)] &&
      operatorFrames[0]!.args[2]!.type == .boolean do
    throwError s!"MultiToken.setApprovalForAll frame diverged: {repr operatorFrames}"
  unless transferFrames.size == 1 &&
      eventMatches transferFrames[0]! "TransferSingle"
        #[("operator", true), ("from", true), ("to", true), ("id", false), ("value", false)] do
    throwError s!"MultiToken.transferFrom TransferSingle frame diverged: {repr transferFrames}"
  unless burnFrames.size == 1 &&
      eventMatches burnFrames[0]! "TransferSingle"
        #[("operator", true), ("from", true), ("to", true), ("id", false), ("value", false)] do
    throwError s!"MultiToken.burn TransferSingle frame diverged: {repr burnFrames}"
  let evm ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  expectMethodNames evm
    #["mint", "burn", "setApprovalForAll", "transferFrom", "balanceOf", "isApprovedForAll",
      "supportsInterface"]
  expectTypedAbiYul evm

private def expectCraftTokenEvents : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.CraftToken with
    | .ok source => pure source
    | .error reason => throwError reason
  let mintFrames := sourceTypedFrames (← methodOps source "mint")
  let operatorFrames := sourceTypedFrames (← methodOps source "setApprovalForAll")
  let transferFrames := sourceTypedFrames (← methodOps source "transferFrom")
  let burnFrames := sourceTypedFrames (← methodOps source "burn")
  unless mintFrames.size == 1 &&
      eventMatches mintFrames[0]! "TransferSingle"
        #[("operator", true), ("from", true), ("to", true), ("id", false), ("value", false)] do
    throwError s!"CraftToken.mint TransferSingle frame diverged: {repr mintFrames}"
  unless operatorFrames.size == 1 &&
      eventMatches operatorFrames[0]! "ApprovalForAll"
        #[("account", true), ("operator", true), ("approved", false)] &&
      operatorFrames[0]!.args[2]!.type == .boolean do
    throwError s!"CraftToken.setApprovalForAll frame diverged: {repr operatorFrames}"
  unless transferFrames.size == 1 &&
      eventMatches transferFrames[0]! "TransferSingle"
        #[("operator", true), ("from", true), ("to", true), ("id", false), ("value", false)] do
    throwError s!"CraftToken.transferFrom TransferSingle frame diverged: {repr transferFrames}"
  unless burnFrames.size == 1 &&
      eventMatches burnFrames[0]! "TransferSingle"
        #[("operator", true), ("from", true), ("to", true), ("id", false), ("value", false)] do
    throwError s!"CraftToken.burn TransferSingle frame diverged: {repr burnFrames}"
  let evm ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  expectMethodNames evm
    #["mint", "burn", "setApprovalForAll", "transferFrom", "balanceOf", "supplyOf",
      "isApprovedForAll", "supportsInterface"]
  expectTypedAbiYul evm

private def expectErc1155 : CommandElabM Unit := do
  expectMultiTokenEvents
  expectCraftTokenEvents
  expectDigest `Examples.Evm.MultiToken "22ffde18b95a2030"
  expectDigest `Examples.Evm.CraftToken "2252ee4200d2bedc"
  let env ← getEnv
  let multi := (ProofForge.Extract.extractModuleIR env `Examples.Evm.MultiToken).toOption.get!
  let balanceOps := (multi.methods.find? (·.ixName == "balanceOf")).get!.ops
  unless hasControlFlow balanceOps && opsContainBalanceRead balanceOps &&
      balanceReadsAreGuarded balanceOps do
    throwError "MultiToken.balanceOf: checked SDK view lost its pre-read key-envelope gate"
  let craft := (ProofForge.Extract.extractModuleIR env `Examples.Evm.CraftToken).toOption.get!
  let mintOps := (craft.methods.find? (·.ixName == "mint")).get!.ops
  unless hasNamedCapGate mintOps do
    throwError "CraftToken.mint: named UInt256 maxPerId did not remain a packed comparison gate"
  match ProofForge.Extract.extractModuleIR env `Tests.EvmErc1155Spec.UnsupportedConditionFixture with
  | .error _ => pure ()
  | .ok _ =>
      throwError "unsupported unmarked Bool condition was unsafely host-folded during extraction"

elab "#pf_guard_evm_erc1155" : command => expectErc1155

#pf_guard_evm_erc1155

#pf_evm_build Examples.Evm.MultiToken
#pf_evm_build Examples.Evm.CraftToken

end Tests.EvmErc1155Spec
