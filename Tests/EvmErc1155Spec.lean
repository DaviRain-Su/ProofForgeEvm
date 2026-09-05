import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.MultiToken
import Examples.Evm.CraftToken

/-!
EVM-SDK-8 focused suite: bounded ERC-1155 key envelope, predicate surface, and two independent
consumers. MultiToken/CraftToken emit canonical ERC-1155 typed events (LOG4 TransferSingle with
two data words, LOG3 ApprovalForAll). Live mint/burn/safeTransferFrom/operator matrices live in
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
-- The host stub has no code behind any address, so the receiver check is the skipped branch.
#guard Erc1155.checkOnReceived ⟨1, 2, 3⟩ ⟨4, 5, 6⟩ ⟨7, 8, 9⟩ ⟨10, 0, 0, 0⟩ ⟨11, 0, 0, 0⟩
  { length := 0, values := Vector.replicate 32 0 } == 0
#guard Erc1155.onReceivedSelector == (⟨0x616e3af2, 0, 0, 0⟩ : Bytes4)
#guard Erc1155.onBatchReceivedSelector == (⟨0x817c19bc, 0, 0, 0⟩ : Bytes4)
#guard Erc1155.checkOnBatchReceived ⟨1, 2, 3⟩ ⟨4, 5, 6⟩ ⟨7, 8, 9⟩
  ⟨0, #v[UInt256.zero, UInt256.zero, UInt256.zero, UInt256.zero]⟩
  ⟨0, #v[UInt256.zero, UInt256.zero, UInt256.zero, UInt256.zero]⟩
  { length := 0, values := Vector.replicate 32 0 } == 0

-- Closed ERC-20-shaped programs keep their digests; this slice only refreshes MultiToken/CraftToken.
#guard Registry.digestOf "Token" == some "e25dfb4e1eaa54c"
#guard Registry.digestOf "Erc20Meta" == some "3dfa816778bd3ef6"

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

-- Bounded batch: the length rule answers zero for unequal lengths, and the view reads one
-- checked balance per slot (host maps are empty, so every slot is zero).
private def specOwners : Erc1155.Batch Address :=
  ⟨2, #v[specOwner, specOwner, Address.zero, Address.zero]⟩
private def specIds : Erc1155.Batch UInt256 :=
  ⟨2, #v[specId, specAliasId, UInt256.zero, UInt256.zero]⟩
#guard Erc1155.batchCapacity == 4
#guard Erc1155.batchLength specOwners specIds == 2
#guard Erc1155.batchLength ⟨0, specOwners.values⟩ ⟨0, specIds.values⟩ == 0
#guard Erc1155.batchLength ⟨1, specOwners.values⟩ specIds == 0
#guard Erc1155.batchLength specOwners ⟨3, specIds.values⟩ == 0
#guard (Examples.Evm.MultiToken.balanceOfBatch ⟨0⟩ specOwners specIds).length == 2
#guard (Examples.Evm.MultiToken.balanceOfBatch ⟨0⟩ specOwners specIds).values.toList ==
  [UInt256.zero, UInt256.zero, UInt256.zero, UInt256.zero]
#guard (Examples.Evm.MultiToken.balanceOfBatch ⟨0⟩ specOwners ⟨1, specIds.values⟩).length == 0

-- Bounded batch transfer: slot activity, the OZ length word, limb-wise id equality, the
-- distinct-id bound, and the key envelope over every slot are Bool arithmetic, so the host pins
-- them. OZ applies duplicate ids in array order with per-slot writes. This ledger reverts
-- `DuplicateId()` first so every pre-write check stays exact. An inactive slot is movable
-- whatever its balance; an active alias id fails the envelope.
private def specSecondId : UInt256 := ⟨8, 0, 0, 0⟩
private def specGoodIds : Erc1155.Batch UInt256 :=
  ⟨2, #v[specId, specSecondId, UInt256.zero, UInt256.zero]⟩
private def specDupIds : Erc1155.Batch UInt256 :=
  ⟨2, #v[specId, specId, UInt256.zero, UInt256.zero]⟩
private def specAmounts : Erc1155.Batch UInt256 :=
  ⟨2, #v[specAmount, specAmount, UInt256.zero, UInt256.zero]⟩
#guard Erc1155.slotActive specIds 0
#guard Erc1155.slotActive specIds 1
#guard !Erc1155.slotActive specIds 2
#guard !Erc1155.slotActive (⟨0, specIds.values⟩ : Erc1155.Batch UInt256) 0
#guard Erc1155.lengthWord specIds == (⟨2, 0, 0, 0⟩ : UInt256)
#guard Erc1155.lengthWord (⟨0, specIds.values⟩ : Erc1155.Batch UInt256) == UInt256.zero
#guard Erc1155.idEq specId specId
#guard !Erc1155.idEq specId specAliasId
#guard !Erc1155.idEq specId specSecondId
#guard Erc1155.distinctIds specGoodIds
#guard !Erc1155.distinctIds specDupIds
#guard Erc1155.distinctIds (⟨1, specDupIds.values⟩ : Erc1155.Batch UInt256)
#guard !Erc1155.distinctIds ⟨4, #v[specId, specSecondId, specAliasId, specId]⟩
#guard !Erc1155.distinctIds ⟨4, #v[specId, specSecondId, specAliasId, specSecondId]⟩
#guard !Erc1155.distinctIds ⟨4, #v[specId, specSecondId, specAliasId, specAliasId]⟩
#guard Erc1155.distinctIds ⟨3, #v[specId, specSecondId, specAliasId, specId]⟩
#guard Erc1155.allEncodable specGoodIds
#guard !Erc1155.allEncodable specIds
#guard !Erc1155.isApprovedOrOwnerBatch specOperators specOwner specOwner specIds
#guard Erc1155.Balances.canTransferSlot specBalances specOwner specOther false specAliasId specAmount
#guard !Erc1155.Balances.canTransferSlot specBalances specOwner specOther true specAliasId specAmount
#guard !Erc1155.Balances.canBatchTransfer specBalances specOwner specOther specIds specAmounts
#guard Erc1155.Balances.transferSlot specBalances specOwner specOther false specId specAmount == 0
#guard Erc1155.Log.transferBatch specOwner specOwner specOther specGoodIds specAmounts == 0

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
  -- Psy-target effects; unreachable for EVM sources but the shared Core Ops
  -- define them, so the matcher must stay exhaustive.
  | .emitEvent _ payload => #[payload]
  | .externalCall _ args => args
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

private def transferBatchAbi : String :=
  "{\"type\":\"event\",\"name\":\"TransferBatch\",\"inputs\":[" ++
    "{\"name\":\"operator\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"from\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"to\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"ids\",\"type\":\"uint256[]\",\"indexed\":false}," ++
    "{\"name\":\"values\",\"type\":\"uint256[]\",\"indexed\":false}],\"anonymous\":false}"

/-- The ERC-1155 `TransferBatch` topic0 every indexer matches on. -/
private def transferBatchTopic : String :=
  "4a39dc06d4c0dbc64b70af90fd698a233a518aa5d07e595d983b8c0526c8f7fb"

#guard ProofForge.Crypto.Keccak.keccak256HexOfString
  "TransferBatch(address,address,address,uint256[],uint256[])" == transferBatchTopic

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

/-- The dynamic-array tails of every typed event under `ops`, one array per event. -/
private partial def sourceTypedTails (ops : Array ProofForge.Extract.IR.Op) :
    Array (Array (NativeFx.LogTail ProofForge.Extract.IR.Val)) :=
  ops.foldl (init := #[]) fun tails op =>
    let tails := match op with
      | .ext (.evm (.component (.nativeFx (.logTyped _ eventTails)))) => tails.push eventTails
      | _ => tails
    match op with
    | .ite _ _ _ yes no => tails ++ sourceTypedTails yes ++ sourceTypedTails no
    | .forBody _ body => tails ++ sourceTypedTails body
    | _ => tails

private partial def sourceErrorFrames (ops : Array ProofForge.Extract.IR.Op) :
    Array (ProofForge.Core.Ops.ErrorFrame ProofForge.Extract.IR.Val) :=
  ops.foldl (init := #[]) fun frames op =>
    let frames := match op with
      | .errorTyped frame => frames.push frame
      | _ => frames
    match op with
    | .ite _ _ _ yes no => frames ++ sourceErrorFrames yes ++ sourceErrorFrames no
    | .forBody _ body => frames ++ sourceErrorFrames body
    | _ => frames

/-- Constructors of the selector-only (fieldless) errors under `ops`. -/
private partial def sourceNamedErrors (ops : Array ProofForge.Extract.IR.Op) : Array String :=
  ops.foldl (init := #[]) fun names op =>
    let names := match op with
      | .errorNamed name => names.push name
      | _ => names
    match op with
    | .ite _ _ _ yes no => names ++ sourceNamedErrors yes ++ sourceNamedErrors no
    | .forBody _ body => names ++ sourceNamedErrors body
    | _ => names

/-- Field name, scalar, and limb count per argument of a typed error frame. -/
private def frameLimbs (frame : ProofForge.Core.Ops.ErrorFrame V) :
    Array (String × ProofForge.Core.Codec.Scalar × Nat) :=
  frame.args.map fun arg => (arg.name, arg.type, arg.parts.size)

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

/-- `safeTransferFrom(address,address,uint256,uint256,bytes)` answering the `Effect.thenTrue` bool. -/
private def safeTransferFromAbi : String :=
  "{\"type\":\"function\",\"name\":\"safeTransferFrom\",\"stateMutability\":\"nonpayable\"," ++
    "\"inputs\":[{\"name\":\"arg0\",\"type\":\"address\"},{\"name\":\"arg1\",\"type\":\"address\"}," ++
    "{\"name\":\"arg2\",\"type\":\"uint256\"},{\"name\":\"arg3\",\"type\":\"uint256\"}," ++
    "{\"name\":\"arg4\",\"type\":\"bytes\"}],\"outputs\":[{\"name\":\"\",\"type\":\"bool\"}]}"

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
      !abi.contains erc20TransferAbi do
    throwError s!"{evm.name} ABI lost ERC-1155 TransferSingle/ApprovalForAll:\n{abi}"
  let yul ←
    match Emit.emitYul evm with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless yul.contains s!"log4(0, 64, 0x{transferSingleTopic}" &&
      yul.contains s!"log3(0, 32, 0x{approvalForAllTopic}" do
    throwError s!"{evm.name} Yul omitted LOG4 TransferSingle or LOG3 ApprovalForAll"

/-- The bounded `balanceOfBatch` frame is one length leaf plus four elements of four limbs, its
ABI is `(address[],uint256[]) -> uint256[]`, and its Yul computes every element into a local
before the first frame word is stored (element code hashes map keys in low memory). -/
private def expectMultiTokenBatch (source : ProofForge.Extract.IR.Program) (evm : IR.Program) :
    CommandElabM Unit := do
  let ops ← methodOps source "balanceOfBatch"
  let returns := ops.filter fun
    | .returnU64 _ => true
    | _ => false
  unless returns.size == 1 + 4 * 4 do
    throwError s!"MultiToken.balanceOfBatch publishes {returns.size} leaves, expected 17"
  let abi ←
    match Emit.emitAbiChecked evm with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"balanceOfBatch\",\"stateMutability\":\"view\"" &&
      abi.contains "\"inputs\":[{\"name\":\"arg0\",\"type\":\"address[]\"},{\"name\":\"arg1\",\"type\":\"uint256[]\"}]" &&
      abi.contains "\"outputs\":[{\"name\":\"\",\"type\":\"uint256[]\"}]" do
    throwError s!"MultiToken.balanceOfBatch ABI diverged:\n{abi}"
  let yul ←
    match Emit.emitYul evm with
    | .ok yul => pure yul
    | .error reason => throwError reason
  let parts := yul.splitOn "mstore(0, 32)"
  unless parts.length == 2 && parts[0]!.contains "abi_ret_3_0 := " &&
      parts[1]!.contains "mstore(64, abi_ret_0_0)" &&
      parts[1]!.contains "mstore(160, abi_ret_3_0)" do
    throwError "MultiToken.balanceOfBatch Yul stored a frame word before computing every element"

/-- The bounded `safeBatchTransferFrom` carries one OZ-shaped `ERC1155InvalidArrayLength` frame, one
`ERC1155InsufficientBalance` frame per slot with the OZ field order, one selector-only
`DuplicateId`, and one `TransferBatch` whose two `uint256[]` tails read the entry's own arrays
(length leaf plus four slots of four limbs each). Its ABI is
`(address,address,uint256[],uint256[],bytes)` nonpayable, and its Yul reverts with the `cast sig`
selectors and the 4 + 4 * 32 byte geometry and logs LOG4 with the cursor as data length. -/
private def expectMultiTokenBatchTransfer (source : ProofForge.Extract.IR.Program)
    (evm : IR.Program) : CommandElabM Unit := do
  let ops ← methodOps source "safeBatchTransferFrom"
  let frames := sourceErrorFrames ops
  let named (constructor : String) := frames.filter (·.constructor == constructor)
  let lengths := named "ERC1155InvalidArrayLength"
  let shortfalls := named "ERC1155InsufficientBalance"
  unless frames.size == 5 && lengths.size == 1 && shortfalls.size == 4 do
    throwError s!"MultiToken.safeBatchTransferFrom carries {frames.size} typed error frames: \
      {frames.map (·.constructor)}"
  unless sourceNamedErrors ops == #["DuplicateId"] do
    throwError s!"MultiToken.safeBatchTransferFrom selector-only errors diverged: \
      {sourceNamedErrors ops}"
  unless lengths.all (frameLimbs · == #[("idsLength", .uint256, 4), ("valuesLength", .uint256, 4)]) do
    throwError s!"ERC1155InvalidArrayLength frame diverged: {repr (lengths.map frameLimbs)}"
  unless shortfalls.all (frameLimbs · ==
      #[("sender", .address20, 3), ("balance", .uint256, 4), ("needed", .uint256, 4),
        ("tokenId", .uint256, 4)]) do
    throwError s!"ERC1155InsufficientBalance frame diverged: {repr (shortfalls.map frameLimbs)}"
  let logs := sourceTypedFrames ops
  unless logs.size == 2 &&
      eventMatches logs[0]! "TransferSingle"
        #[("operator", true), ("from", true), ("to", true), ("id", false), ("value", false)] &&
      eventMatches logs[1]! "TransferBatch" #[("operator", true), ("from", true), ("to", true)] do
    throwError s!"MultiToken.safeBatchTransferFrom logs {logs.size} typed events, expected the OZ \
      TransferSingle-or-TransferBatch pair: {logs.map (·.constructor)}"
  let tails := sourceTypedTails ops
  let tailShape (tail : NativeFx.LogTail ProofForge.Extract.IR.Val) :=
    (tail.name, tail.elementType, tail.capacity, tail.elements.size)
  unless tails.size == 2 && tails[0]!.isEmpty && tails[1]!.map tailShape ==
      #[("ids", .uint256, 4, 16), ("values", .uint256, 4, 16)] do
    throwError s!"MultiToken.safeBatchTransferFrom TransferBatch tails diverged: {repr tails}"
  let argLeaf : ProofForge.Extract.IR.Val → Bool
    | .field (.arg _) _ => true
    | _ => false
  unless tails[1]!.all fun tail => argLeaf tail.length && tail.elements.all argLeaf do
    throwError s!"MultiToken.safeBatchTransferFrom TransferBatch tails are not argument leaves: \
      {repr tails}"
  let abi ←
    match Emit.emitAbiChecked evm with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains transferBatchAbi do
    throwError s!"MultiToken ABI lost TransferBatch:\n{abi}"
  unless abi.contains "\"name\":\"safeBatchTransferFrom\",\"stateMutability\":\"nonpayable\"" &&
      abi.contains ("\"inputs\":[{\"name\":\"arg0\",\"type\":\"address\"},{\"name\":\"arg1\",\"type\":\"address\"}," ++
        "{\"name\":\"arg2\",\"type\":\"uint256[]\"},{\"name\":\"arg3\",\"type\":\"uint256[]\"}," ++
        "{\"name\":\"arg4\",\"type\":\"bytes\"}]") &&
      abi.contains ("{\"type\":\"error\",\"name\":\"ERC1155InvalidArrayLength\",\"inputs\":[" ++
        "{\"name\":\"idsLength\",\"type\":\"uint256\"},{\"name\":\"valuesLength\",\"type\":\"uint256\"}]}") &&
      abi.contains ("{\"type\":\"error\",\"name\":\"ERC1155InsufficientBalance\",\"inputs\":[" ++
        "{\"name\":\"sender\",\"type\":\"address\"},{\"name\":\"balance\",\"type\":\"uint256\"}," ++
        "{\"name\":\"needed\",\"type\":\"uint256\"},{\"name\":\"tokenId\",\"type\":\"uint256\"}]}") do
    throwError s!"MultiToken.safeBatchTransferFrom ABI diverged:\n{abi}"
  unless ProofForge.Evm.Keccak.selector "ERC1155InvalidArrayLength" #["uint256", "uint256"] ==
      "5b059991" &&
      ProofForge.Evm.Keccak.selector "ERC1155InsufficientBalance"
        #["address", "uint256", "uint256", "uint256"] == "03dee4c5" do
    throwError "OZ ERC-1155 error selectors diverged from cast sig"
  let yul ←
    match Emit.emitYul evm with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless yul.contains "shl(224, 0x5b059991)" && yul.contains "shl(224, 0x03dee4c5)" &&
      yul.contains "revert(0, 132)" do
    throwError "MultiToken.safeBatchTransferFrom Yul omitted an OZ selector or the revert geometry"
  unless yul.contains s!"log4(0, pf_log_end, 0x{transferBatchTopic}" do
    throwError "MultiToken.safeBatchTransferFrom Yul omitted the LOG4 TransferBatch with a cursor length"
  let hookSelector := ProofForge.Evm.Keccak.selector "onERC1155BatchReceived"
    #["address", "address", "uint256[]", "uint256[]", "bytes"]
  unless hookSelector == "bc197c81" do
    throwError s!"onERC1155BatchReceived selector is {hookSelector}"
  let hookPlans := sourceOpenCalls ops
  unless hookPlans.size == 1 && hookPlans[0]!.name == "onERC1155BatchReceived" &&
      hookPlans[0]!.kind == .call && hookPlans[0]!.policy == .magicBytes4 hookSelector &&
      hookPlans[0]!.args.size == 5 &&
      hookPlans[0]!.args[2]!.type == .array 4 .uint256 &&
      hookPlans[0]!.args[3]!.type == .array 4 .uint256 &&
      hookPlans[0]!.args[4]!.type == .bytes 32 &&
      hookPlans[0]!.usesCursor && hookPlans[0]!.inSize == 164 &&
      hookPlans[0]!.abiTypes matches
        .ok #["address", "address", "uint256[]", "uint256[]", "bytes"] do
    throwError s!"MultiToken.safeBatchTransferFrom hook plan diverged: {repr hookPlans}"
  unless yul.contains "extcodesize(" &&
      yul.contains s!"shl(224, 0x{hookSelector}))) \{ revert(0, 0) }" do
    throwError "MultiToken.safeBatchTransferFrom Yul lost the receiver code-size guard or the magic equality gate"

/-- `safeTransferFrom` on an ERC-1155 consumer: the `TransferSingle` frame beside one CALL plan
whose magic is its own selector, five head words plus the 32-byte bounded `data` tail
(4 + 5 * 32 + 32 = 196 static calldata bytes), then the Yul code-size guard and magic gate. -/
private def expectSafeTransferFromHook (source : ProofForge.Extract.IR.Program)
    (evm : IR.Program) : CommandElabM Unit := do
  let safeOps ← methodOps source "safeTransferFrom"
  let safeFrames := sourceTypedFrames safeOps
  unless safeFrames.size == 1 &&
      eventMatches safeFrames[0]! "TransferSingle"
        #[("operator", true), ("from", true), ("to", true), ("id", false), ("value", false)] do
    throwError s!"{evm.name}.safeTransferFrom TransferSingle frame diverged: {repr safeFrames}"
  let hookSelector := ProofForge.Evm.Keccak.selector "onERC1155Received"
    #["address", "address", "uint256", "uint256", "bytes"]
  unless hookSelector == "f23a6e61" do
    throwError s!"onERC1155Received selector is {hookSelector}"
  let hookPlans := sourceOpenCalls safeOps
  unless hookPlans.size == 1 && hookPlans[0]!.name == "onERC1155Received" &&
      hookPlans[0]!.kind == .call && hookPlans[0]!.policy == .magicBytes4 hookSelector &&
      hookPlans[0]!.args.size == 5 &&
      hookPlans[0]!.args[0]!.name == "operator" && hookPlans[0]!.args[1]!.name == "from" &&
      hookPlans[0]!.args[2]!.name == "id" && hookPlans[0]!.args[3]!.name == "value" &&
      hookPlans[0]!.args[4]!.name == "data" &&
      hookPlans[0]!.args[4]!.type == .bytes 32 && hookPlans[0]!.inSize == 196 &&
      hookPlans[0]!.abiTypes matches
        .ok #["address", "address", "uint256", "uint256", "bytes"] do
    throwError s!"{evm.name}.safeTransferFrom hook plan diverged: {repr hookPlans}"
  let abi ←
    match Emit.emitAbiChecked evm with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains safeTransferFromAbi do
    throwError s!"{evm.name} ABI lost safeTransferFrom(address,address,uint256,uint256,bytes):\n{abi}"
  let yul ←
    match Emit.emitYul evm with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless yul.contains "extcodesize(" &&
      yul.contains s!"shl(224, 0x{hookSelector}))) \{ revert(0, 0) }" &&
      yul.contains "calldatacopy(" do
    throwError s!"{evm.name} Yul lost the receiver code-size guard, the magic equality gate, or the calldata copy"

private def expectMultiTokenEvents : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.MultiToken with
    | .ok source => pure source
    | .error reason => throwError reason
  let mintFrames := sourceTypedFrames (← methodOps source "mint")
  let operatorFrames := sourceTypedFrames (← methodOps source "setApprovalForAll")
  let transferFrames := sourceTypedFrames (← methodOps source "safeTransferFrom")
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
    throwError s!"MultiToken.safeTransferFrom TransferSingle frame diverged: {repr transferFrames}"
  unless burnFrames.size == 1 &&
      eventMatches burnFrames[0]! "TransferSingle"
        #[("operator", true), ("from", true), ("to", true), ("id", false), ("value", false)] do
    throwError s!"MultiToken.burn TransferSingle frame diverged: {repr burnFrames}"
  let evm ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  -- ERC-1155 has no `transferFrom`; the single transfer is `safeTransferFrom` with the hook.
  -- Packed-bytes calldatacopy is what lets this entry fit MultiToken under EIP-170.
  expectMethodNames evm
    #["mint", "burn", "setApprovalForAll", "safeTransferFrom", "balanceOf", "isApprovedForAll",
      "supportsInterface", "balanceOfBatch", "safeBatchTransferFrom"]
  expectTypedAbiYul evm
  expectMultiTokenBatch source evm
  expectMultiTokenBatchTransfer source evm
  expectSafeTransferFromHook source evm

private def expectCraftTokenEvents : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.CraftToken with
    | .ok source => pure source
    | .error reason => throwError reason
  let mintFrames := sourceTypedFrames (← methodOps source "mint")
  let operatorFrames := sourceTypedFrames (← methodOps source "setApprovalForAll")
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
  unless burnFrames.size == 1 &&
      eventMatches burnFrames[0]! "TransferSingle"
        #[("operator", true), ("from", true), ("to", true), ("id", false), ("value", false)] do
    throwError s!"CraftToken.burn TransferSingle frame diverged: {repr burnFrames}"
  let evm ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  -- ERC-1155 has no `transferFrom`; the single transfer is `safeTransferFrom` with the hook.
  expectMethodNames evm
    #["mint", "burn", "setApprovalForAll", "safeTransferFrom", "balanceOf", "supplyOf",
      "isApprovedForAll", "supportsInterface"]
  expectTypedAbiYul evm
  match Emit.emitAbiChecked evm with
  | .ok abi =>
      if abi.contains "TransferBatch" then
        throwError s!"CraftToken has no batch transfer yet its ABI names TransferBatch:\n{abi}"
  | .error reason => throwError reason
  expectSafeTransferFromHook source evm

private def expectErc1155 : CommandElabM Unit := do
  expectMultiTokenEvents
  expectCraftTokenEvents
  expectDigest `Examples.Evm.MultiToken "41d2adc0aff313ef"
  expectDigest `Examples.Evm.CraftToken "2ba8b59633a3bd11"
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
