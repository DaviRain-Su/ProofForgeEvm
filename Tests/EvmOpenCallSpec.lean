import ProofForge
import ProofForge.Evm.OpenCall
import ProofForge.Evm.OpenCall.Emit
import ProofForge.Evm.CallResult
import ProofForge.Evm.CallResult.Emit
import Examples.Evm.EvmOpenCall
import Examples.Evm.TipJar

/-!
S3 typed external CALL: plan-layer bounds, CallResult-only result gates, extract/SDK path,
and existing digest/sendEth stability. OpenCall is a ClosedCall sibling, not a raw opcode hatch.
-/

namespace Tests.EvmOpenCallSpec

open ProofForge.Evm
open Lean Elab Command

private def lit : Ops.Val := .lit 0

private def pingPlan : OpenCall.Plan Ops.Val := {
  name := "ping"
  args := #[]
  target := #[lit, lit, lit]
  kind := .call
  policy := .contractSuccess
}

private def transferPlan : OpenCall.Plan Ops.Val := {
  name := "transfer"
  args := #[
    { name := "to", type := .address20, parts := #[.lit 1, .lit 2, .lit 3] },
    { name := "amount", type := .uint256, parts := #[.lit 4, .lit 5, .lit 6, .lit 7] }
  ]
  target := #[lit, lit, lit]
  kind := .call
  policy := .canonicalTrueOrCodeBackedEmpty
}

private def echoPlan : OpenCall.Plan Ops.Val := {
  name := "echo"
  args := #[{ name := "n", type := .uint256, parts := #[.lit 9, lit, lit, lit] }]
  target := #[lit, lit, lit]
  kind := .staticcall
  policy := .exactWord
}

private def pairPlan : OpenCall.Plan Ops.Val := {
  name := "getPair"
  args := #[]
  target := #[lit, lit, lit]
  kind := .staticcall
  policy := .exactWords 2
}

private def depositPlan : OpenCall.Plan Ops.Val := {
  name := "deposit"
  args := #[]
  target := #[lit, lit, lit]
  kind := .call
  policy := .contractSuccess
  valueParts := #[.lit 1, lit, lit, lit]
}

#guard OpenCall.maxArgWords == 8
#guard pingPlan.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard transferPlan.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard echoPlan.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard pairPlan.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard depositPlan.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard OpenCall.Call.wellFormed (·.wellFormed Ops.ValKind.arity) (.invoke pingPlan)
#guard OpenCall.Call.effects (.invoke depositPlan) ==
  { externalCall := true, sendsValue := true }
#guard OpenCall.Call.effects (.invoke pingPlan) ==
  { externalCall := true, sendsValue := false }
#guard
  match pingPlan.selectorHex (·.wellFormed Ops.ValKind.arity) with
  | .ok sel => sel == Keccak.selector "ping" #[]
  | .error _ => false
#guard
  match transferPlan.selectorHex (·.wellFormed Ops.ValKind.arity) with
  | .ok sel => sel == Keccak.selector "transfer" #["address", "uint256"]
  | .error _ => false

private def badName : OpenCall.Plan Ops.Val := { pingPlan with name := "" }
private def nineArgs : OpenCall.Plan Ops.Val :=
  { pingPlan with
    args := (List.range 9).toArray.map fun i =>
      { name := s!"a{i}", type := .uint64, parts := #[lit] } }
private def staticValue : OpenCall.Plan Ops.Val :=
  { echoPlan with valueParts := #[lit, lit, lit, lit] }

#guard !badName.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard !nineArgs.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard !staticValue.wellFormed (·.wellFormed Ops.ValKind.arity)

private def echoQuery : OpenCall.Query := {
  name := "echo"
  argTypes := #[.uint256]
  kind := .staticcall
  policy := .exactWord
  word := 0
  limb := 0
}

private def pairQuery : OpenCall.Query := {
  name := "getPair"
  argTypes := #[]
  kind := .staticcall
  policy := .exactWords 2
  word := 0
  limb := 0
}

#guard echoQuery.wellFormed
#guard pairQuery.wellFormed
#guard echoQuery.arity == 7
#guard pairQuery.arity == 3

-- Every STATICCALL read shape is a well-formed query whose limbs fit one ABI word.
#guard OpenCall.StaticShape.all.size == 6
#guard OpenCall.StaticShape.all.all fun shape =>
  (shape.query "read" #[.address20]).wellFormed &&
    1 ≤ shape.limbCount && shape.limbCount ≤ 4 &&
    shape.policy.copiedWordCount ≤ CallResult.maxResultWords
#guard OpenCall.StaticShape.word.policy == .exactWord
#guard OpenCall.StaticShape.words2.policy == .exactWords 2
#guard OpenCall.StaticShape.words3.policy == .exactWords 3
#guard OpenCall.StaticShape.words4.policy == .exactWords 4
#guard OpenCall.StaticShape.bool.policy == .strictBool
#guard OpenCall.StaticShape.address.policy == .words #[.address20]
#guard OpenCall.StaticShape.words4.limbCount == 4
#guard OpenCall.StaticShape.bool.limbCount == 1
#guard OpenCall.StaticShape.address.limbCount == 3
#guard (OpenCall.StaticShape.word.query "echo" #[.uint256]) == echoQuery
#guard (OpenCall.StaticShape.words2.query "getPair" #[]) == pairQuery

private def onQuery : OpenCall.Query := OpenCall.StaticShape.bool.query "isOn" #[]
private def ownerQuery : OpenCall.Query := OpenCall.StaticShape.address.query "ownerOf" #[]
private def tripleQuery : OpenCall.Query := OpenCall.StaticShape.words3.query "getTriple" #[]
private def quadQuery : OpenCall.Query := OpenCall.StaticShape.words4.query "getQuad" #[]

private def mockOpenCtx : OpenCall.Emit.Context Nat :=
  { materialize := fun _ st => .ok ("", "0", st)
    fresh := fun st => (s!"v{st}", st + 1)
    rememberWide := fun st _ _ => st
    lookupWide := fun _ _ => none
    valKey := fun _ => ""
    indent := "  " }

private def mockCallResultCtx : CallResult.Emit.Context Nat :=
  { fresh := fun st => (s!"v{st}", st + 1), indent := "  " }

-- OpenCall CALL consumes the shared interpreter (contract-success, empty calldata besides selector).
#guard
  match CallResult.Emit.emit mockCallResultCtx (.successOnly 4) "v0" none 1,
        OpenCall.Emit.emitCall mockOpenCtx (.invoke pingPlan) 0 with
  | .ok (fragment, _, _), .ok (txt, _, _) =>
      txt.contains fragment &&
        txt.contains "if shr(32, 0) { revert(0, 0) }" &&
        txt.contains s!"mstore(0, shl(224, 0x{Keccak.selector "ping" #[]}))" &&
        txt.contains "if and(iszero(returndatasize()), iszero(extcodesize("
  | _, _ => false

-- ERC-20 compatibility policy on a typed transfer; selector is ABI `transfer(address,uint256)`.
#guard
  match CallResult.Emit.emit mockCallResultCtx (.erc20Mutation 68) "v0" none 1,
        OpenCall.Emit.emitCall mockOpenCtx (.invoke transferPlan) 0 with
  | .ok (fragment, _, _), .ok (txt, _, _) =>
      txt.contains fragment &&
        txt.contains s!"mstore(0, shl(224, 0x{Keccak.selector "transfer" #["address", "uint256"]}))" &&
        txt.contains "pf_store_addr20(4," &&
        txt.contains "mstore(36,"
  | _, _ => false

-- Exact-one-word STATICCALL; malformed size is the shared `returndatasize() == 32` gate.
#guard
  match CallResult.Emit.emit mockCallResultCtx (.staticWord 36) "v0" none 1,
        OpenCall.Emit.emitQuery mockOpenCtx echoQuery
          #[lit, lit, lit, .lit 9, lit, lit, lit] 0 with
  | .ok (fragment, _, _), .ok (txt, _, _) =>
      txt.contains fragment &&
        txt.contains "if iszero(eq(returndatasize(), 32)) { revert(0, 0) }" &&
        txt.contains "and(shr(0, "
  | _, _ => false

-- Exact-two-word STATICCALL uses S2 `exactWords 2`.
#guard
  match CallResult.Emit.emit mockCallResultCtx (.staticWords 4 2) "v0" none 1,
        OpenCall.Emit.emitQuery mockOpenCtx pairQuery #[lit, lit, lit] 0 with
  | .ok (fragment, _, _), .ok (txt, _, _) =>
      txt.contains fragment &&
        txt.contains "if iszero(eq(returndatasize(), 64)) { revert(0, 0) }"
  | _, _ => false

-- Strict-bool STATICCALL: exact one word, then the canonical `0 | 1` gate.
#guard
  match CallResult.Emit.emit mockCallResultCtx (.staticBool 4) "v0" none 1,
        OpenCall.Emit.emitQuery mockOpenCtx onQuery #[lit, lit, lit] 0 with
  | .ok (fragment, _, _), .ok (txt, _, _) =>
      txt.contains fragment &&
        txt.contains "if iszero(eq(returndatasize(), 32)) { revert(0, 0) }" &&
        txt.contains ", 1) { revert(0, 0) }" &&
        txt.contains "if gt("
  | _, _ => false

-- Canonical-address STATICCALL: exact one word, high 12 bytes zero. The three source limbs are
-- Addr20's little-endian byte limbs (the layout `pf_store_addr20` writes), not numeric words.
#guard
  match CallResult.Emit.emit mockCallResultCtx (.staticTyped 4 #[.address20]) "v0" none 1,
        OpenCall.Emit.emitQuery mockOpenCtx ownerQuery #[lit, lit, lit] 0 with
  | .ok (fragment, _, _), .ok (txt, _, _) =>
      txt.contains fragment &&
        txt.contains "if shr(160, " &&
        txt.contains "byte(12, " && txt.contains "shl(56, byte(19, " &&
        !txt.contains "and(shr("
  | _, _ => false
#guard
  match OpenCall.Emit.emitQuery mockOpenCtx { ownerQuery with limb := 2 } #[lit, lit, lit] 0 with
  | .ok (txt, _, _) => txt.contains "byte(28, " && txt.contains "shl(24, byte(31, "
  | .error _ => false
#guard CallResult.Emit.wordLimb .address20 "w" 1 ==
  "or(or(or(or(or(or(or(byte(20, w), shl(8, byte(21, w))), shl(16, byte(22, w))), shl(24, byte(23, w))), shl(32, byte(24, w))), shl(40, byte(25, w))), shl(48, byte(26, w))), shl(56, byte(27, w)))"
#guard CallResult.Emit.wordLimb .uint256 "w" 3 == "and(shr(192, w), 0xffffffffffffffff)"
#guard CallResult.Emit.wordLimb .boolean "w" 0 == "and(shr(0, w), 0xffffffffffffffff)"

-- Limb indices are bounded by the bound word's kind, so a fourth address limb or a second
-- bool limb never reaches the emitter.
#guard CallResult.WordKind.address20.limbCount == 3
#guard CallResult.WordKind.boolean.limbCount == 1
#guard CallResult.WordKind.uint256.limbCount == 4
#guard ownerQuery.limbCount == 3 && onQuery.limbCount == 1 && quadQuery.limbCount == 4
#guard ({ ownerQuery with limb := 2 } : OpenCall.Query).wellFormed
#guard !({ ownerQuery with limb := 3 } : OpenCall.Query).wellFormed
#guard !({ onQuery with limb := 1 } : OpenCall.Query).wellFormed
#guard ({ quadQuery with limb := 3 } : OpenCall.Query).wellFormed
#guard !({ quadQuery with limb := 4 } : OpenCall.Query).wellFormed

-- Three- and four-word STATICCALL reads gate the full static frame.
#guard
  match CallResult.Emit.emit mockCallResultCtx (.staticWords 4 3) "v0" none 1,
        OpenCall.Emit.emitQuery mockOpenCtx tripleQuery #[lit, lit, lit] 0 with
  | .ok (fragment, _, _), .ok (txt, _, _) =>
      txt.contains fragment &&
        txt.contains "if iszero(eq(returndatasize(), 96)) { revert(0, 0) }"
  | _, _ => false
#guard
  match CallResult.Emit.emit mockCallResultCtx (.staticWords 4 4) "v0" none 1,
        OpenCall.Emit.emitQuery mockOpenCtx quadQuery #[lit, lit, lit] 0 with
  | .ok (fragment, _, _), .ok (txt, _, _) =>
      txt.contains fragment &&
        txt.contains "if iszero(eq(returndatasize(), 128)) { revert(0, 0) }"
  | _, _ => false

-- CALL value rides the shared success-only interpreter; NativeFx.sendEth is not this path.
#guard
  match CallResult.Emit.emit mockCallResultCtx (.successOnly 4 true) "v0" (some "v1") 2,
        OpenCall.Emit.emitCall mockOpenCtx (.invoke depositPlan) 0 with
  | .ok (fragment, _, _), .ok (txt, _, _) =>
      txt.contains fragment &&
        txt.contains "call(gas(), v0, v1, 0, 4, 0, 0)" &&
        txt.contains "if and(iszero(returndatasize()), iszero(extcodesize("
  | _, _ => false

-- Component bridge still routes open calls into the shared contract.
#guard
  match Component.Emit.emitCall
      { materialize := fun _ st => .ok ("", "0", st)
        fresh := fun st => (s!"v{st}", st + 1)
        rememberWide := fun st _ _ => st
        lookupWide := fun _ _ => none
        valKey := fun _ => ""
        indent := "  " }
      (.openCall (.invoke pingPlan) : Component.Call Ops.Val) 0 with
  | .error _ => false
  | .ok (txt, _, _) =>
      txt.contains " := call(gas(), " &&
        txt.contains "if and(iszero(returndatasize()), iszero(extcodesize("

-- Existing ClosedCall / TipJar sendEth stay on their own interpreters.
#guard Registry.digestOf "Token" == some "e25dfb4e1eaa54c"
#guard Registry.digestOf "Vault" == some "bb2f93cb28d7501"
#guard Registry.digestOf "EvmTypedEvents" == some "90bd573ddf9e2e49"
#guard Registry.digestOf "EvmOpenCall" == some "5223289d34513e5e"
#guard Registry.digestOf "TipJar" == some "33bcabf27f5b9523"
#guard
  match Emit.emitYul ProofForge.Evm.Golden.extractedTipJar with
  | .error _ => false
  | .ok yul =>
      yul.contains "call(gas(), mload(0)" &&
        yul.contains ", 0, 0, 0, 0)" &&
        !yul.contains "returndatasize()"
#guard
  match Emit.emitYul ProofForge.Evm.Golden.extractedVault with
  | .error _ => false
  | .ok yul =>
      yul.contains " := call(gas(), " &&
        yul.contains " := returndatasize()"

open ProofForge.Evm.Sdk
open Examples.Evm.EvmOpenCall

#guard OpenCall.call (⟨0, 0, 0⟩ : Address) Remote.ping == 0
#guard OpenCall.staticWord (⟨0, 0, 0⟩ : Address) (Remote.echo ⟨7, 0, 0, 0⟩) == ⟨0, 0, 0, 0⟩
#guard OpenCall.staticWords3 (⟨0, 0, 0⟩ : Address) Remote.getTriple == ⟨0, 0, 0, 0⟩
#guard OpenCall.staticWords4 (⟨0, 0, 0⟩ : Address) Remote.getQuad == ⟨0, 0, 0, 0⟩
#guard OpenCall.staticBool (⟨0, 0, 0⟩ : Address) Remote.isOn == false
#guard OpenCall.staticAddress (⟨0, 0, 0⟩ : Address) Remote.ownerOf == ⟨0, 0, 0⟩

#pf_evm_build Examples.Evm.EvmOpenCall

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

private def expectUnsupported (env : Environment) (name : Name) (fragment : String) :
    CommandElabM Unit := do
  match ProofForge.Extract.extractMethod env .get name with
  | .ok _ => throwError s!"{name}: unsupported open-call unexpectedly extracted"
  | .error reason =>
      unless reason.contains fragment do
        throwError s!"{name}: wrong fail-closed reason: {reason}"

namespace Unsupported

structure Payload where
  to : Address
  amount : UInt256

def structCall (target to : Address) (amount : UInt256) : UInt64 :=
  OpenCall.call target (Payload.mk to amount)

inductive OptionArg where
  | wide (value : Option UInt64)

def optionField (target : Address) (value : Option UInt64) : UInt64 :=
  OpenCall.call target (OptionArg.wide value)

inductive AnonymousArg where
  | hidden (_ : UInt64)

def anonymous (target : Address) (value : UInt64) : UInt64 :=
  OpenCall.call target (AnonymousArg.hidden value)

inductive TooMany where
  | many (a0 a1 a2 a3 a4 a5 a6 a7 a8 : UInt64)

def nineArgs (target : Address) (v : UInt64) : UInt64 :=
  OpenCall.call target (TooMany.many v v v v v v v v v)

end Unsupported

elab "#pf_guard_evm_open_call_source" : command => do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.EvmOpenCall with
    | .ok source => pure source
    | .error reason => throwError reason
  let some ping := source.methods.find? (·.ixName == "pingTarget")
    | throwError "open-call example lost pingTarget"
  let some stored := source.methods.find? (·.ixName == "pingStored")
    | throwError "open-call example lost pingStored"
  let some xfer := source.methods.find? (·.ixName == "openTransfer")
    | throwError "open-call example lost openTransfer"
  let some _echo := source.methods.find? (·.ixName == "readEcho")
    | throwError "open-call example lost readEcho"
  let some _pair := source.methods.find? (·.ixName == "readPair")
    | throwError "open-call example lost readPair"
  let some pay := source.methods.find? (·.ixName == "payTarget")
    | throwError "open-call example lost payTarget"
  let some mark := source.methods.find? (·.ixName == "markThenPing")
    | throwError "open-call example lost markThenPing"
  let pingPlans := sourceOpenCalls ping.ops
  let storedPlans := sourceOpenCalls stored.ops
  let xferPlans := sourceOpenCalls xfer.ops
  let payPlans := sourceOpenCalls pay.ops
  let markPlans := sourceOpenCalls mark.ops
  unless pingPlans.size == 1 && pingPlans[0]!.name == "ping" &&
      pingPlans[0]!.kind == .call &&
      pingPlans[0]!.policy == .contractSuccess &&
      pingPlans[0]!.args.isEmpty do
    throwError s!"pingTarget plan diverged: {repr pingPlans}"
  unless storedPlans.size == 1 && storedPlans[0]!.name == "ping" do
    throwError s!"pingStored plan diverged: {repr storedPlans}"
  unless xferPlans.size == 1 && xferPlans[0]!.name == "transfer" &&
      xferPlans[0]!.policy == .canonicalTrueOrCodeBackedEmpty &&
      xferPlans[0]!.args.size == 2 do
    throwError s!"openTransfer plan diverged: {repr xferPlans}"
  unless payPlans.size == 1 && payPlans[0]!.name == "deposit" &&
      payPlans[0]!.sendsValue do
    throwError s!"payTarget plan diverged: {repr payPlans}"
  unless markPlans.size == 1 && markPlans[0]!.name == "ping" do
    throwError s!"markThenPing plan diverged: {repr markPlans}"

  let evm ←
    match ProofForge.Evm.IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  unless (evm.entries.find? (·.ixName == "payTarget")).map (·.payable) == some true do
    throwError "payTarget must be payable"
  unless (evm.entries.find? (·.ixName == "pingTarget")).map (·.payable) == some false do
    throwError "pingTarget must not be payable"

  let yul ←
    match ProofForge.Evm.Emit.emitYul evm with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless yul.contains "staticcall(gas()," && yul.contains "call(gas()," &&
      yul.contains "if iszero(eq(returndatasize(), 32))" &&
      yul.contains "if iszero(eq(returndatasize(), 64))" &&
      yul.contains "if and(iszero(returndatasize()), iszero(extcodesize(" &&
      yul.contains s!"shl(224, 0x{ProofForge.Evm.Keccak.selector "ping" #[]})" &&
      yul.contains s!"shl(224, 0x{ProofForge.Evm.Keccak.selector "echo" #["uint256"]})" &&
      yul.contains s!"shl(224, 0x{ProofForge.Evm.Keccak.selector "getPair" #[]})" do
    throwError s!"open-call Yul omitted CALL/STATICCALL gates or selectors"

  -- Queries lower through Component.Query.openCall, not Call.invoke. Each read binds exactly
  -- the limbs its source carrier needs: four for `UInt256`, three for `Address`, one for `Bool`.
  let rec openQueryLimbs (fuel : Nat) (ops : Array ProofForge.Evm.IR.Op) : Nat :=
    match fuel with
    | 0 => 0
    | fuel' + 1 =>
      ops.foldl (init := 0) fun acc op =>
        acc + match op with
          | .returnU64 (.ext (.component (.openCall _)) _) => 1
          | .ite _ _ _ yes no => openQueryLimbs fuel' yes + openQueryLimbs fuel' no
          | .forBody _ body => openQueryLimbs fuel' body
          | _ => 0
  let expectLimbs (ixName : String) (shape : OpenCall.StaticShape) : CommandElabM Unit := do
    let some entry := evm.entries.find? (·.ixName == ixName)
      | throwError s!"EVM open-call example lost {ixName}"
    let limbs := openQueryLimbs 32 entry.ops
    unless limbs == shape.limbCount do
      throwError s!"{ixName} binds {limbs} open-call limbs, expected {shape.limbCount}"
  expectLimbs "readEcho" .word
  expectLimbs "readPair" .words2
  expectLimbs "readTriple" .words3
  expectLimbs "readQuad" .words4
  expectLimbs "readOn" .bool
  expectLimbs "readOwner" .address
  expectLimbs "readBalance" .word
  expectLimbs "readSupports" .bool
  unless yul.contains "if iszero(eq(returndatasize(), 96))" &&
      yul.contains "if iszero(eq(returndatasize(), 128))" &&
      yul.contains ", 1) { revert(0, 0) }" &&
      yul.contains "if shr(160, " &&
      yul.contains s!"shl(224, 0x{ProofForge.Evm.Keccak.selector "isOn" #[]})" &&
      yul.contains s!"shl(224, 0x{ProofForge.Evm.Keccak.selector "ownerOf" #[]})" &&
      yul.contains s!"shl(224, 0x{ProofForge.Evm.Keccak.selector "getTriple" #[]})" &&
      yul.contains s!"shl(224, 0x{ProofForge.Evm.Keccak.selector "getQuad" #[]})" &&
      yul.contains s!"shl(224, 0x{ProofForge.Evm.Keccak.selector "balanceOf" #["address"]})" &&
      yul.contains
        s!"shl(224, 0x{ProofForge.Evm.Keccak.selector "supportsInterface" #["bytes4"]})" do
    throwError "open-call Yul omitted a typed STATICCALL read gate or selector"

  expectUnsupported env ``Unsupported.structCall "inductive constructor"
  expectUnsupported env ``Unsupported.optionField "closed EVM scalar"
  expectUnsupported env ``Unsupported.anonymous "explicitly named"
  expectUnsupported env ``Unsupported.nineArgs "at most eight"

  logInfo s!"EvmOpenCall digest: {ProofForge.Evm.IR.digestHex evm}"

#pf_guard_evm_open_call_source

end Tests.EvmOpenCallSpec
