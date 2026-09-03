import ProofForge
import ProofForge.Evm.LogError
import ProofForge.Evm.LogError.Emit
import ProofForge.Extract.LegacyGolden
import ProofForge.Evm.Commands
import Examples.Evm.EvmTypedEvents

/-!
S1a: target-local typed events. Core owns `EventArg`/`EventFrame` (mirroring typed errors, plus
`indexed`); EVM lowers `NativeFx.Call.logTyped` to the existing `LogPlan` (≤4 topics, ≤4 data
words) and emits ABI JSON without rewriting Transfer/Approval bytes.
-/

namespace Tests.EvmTypedEventSpec

open ProofForge.Evm

private def lit : Ops.Val := .lit 0

private def transferFrame : ProofForge.Core.Ops.EventFrame Ops.Val := {
  constructor := "Transfer"
  args := #[
    { name := "from", type := .address20, parts := #[.lit 0, .lit 1, .lit 2], indexed := true },
    { name := "to", type := .address20, parts := #[.lit 3, .lit 4, .lit 5], indexed := true },
    { name := "value", type := .uint256, parts := #[.lit 6, .lit 7, .lit 8, .lit 9] }
  ]
}

private def approvalFrame : ProofForge.Core.Ops.EventFrame Ops.Val := {
  constructor := "Approval"
  args := #[
    { name := "owner", type := .address20, parts := #[.lit 0, .lit 1, .lit 2], indexed := true },
    { name := "spender", type := .address20, parts := #[.lit 3, .lit 4, .lit 5], indexed := true },
    { name := "value", type := .uint256, parts := #[.lit 6, .lit 7, .lit 8, .lit 9] }
  ]
}

private def tippedFrame : ProofForge.Core.Ops.EventFrame Ops.Val := {
  constructor := "Tipped"
  args := #[{ name := "amt", type := .uint64, parts := #[.lit 9] }]
}

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

#guard transferFrame.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard approvalFrame.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard tippedFrame.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard transferFrame.indexedCount == 2
#guard transferFrame.dataCount == 1
#guard transferFrame.values == #[.lit 0, .lit 1, .lit 2, .lit 3, .lit 4, .lit 5,
  .lit 6, .lit 7, .lit 8, .lit 9]
#guard (transferFrame.mapValues fun _ => (.lit 11 : Ops.Val)).values.all (· == .lit 11)

#guard NativeFx.Call.wellFormed (·.wellFormed Ops.ValKind.arity) (.logTyped transferFrame)
#guard NativeFx.Call.wellFormed (·.wellFormed Ops.ValKind.arity) (.logTyped approvalFrame)
#guard NativeFx.Call.wellFormed (·.wellFormed Ops.ValKind.arity) (.logTyped tippedFrame)

#guard !(ProofForge.Core.Ops.EventFrame.wellFormed
  (·.wellFormed Ops.ValKind.arity)
  ({ transferFrame with constructor := "" } :
    ProofForge.Core.Ops.EventFrame Ops.Val))
#guard !(ProofForge.Core.Ops.EventFrame.wellFormed
  (·.wellFormed Ops.ValKind.arity)
  ({ transferFrame with args := transferFrame.args.push transferFrame.args[0]! } :
    ProofForge.Core.Ops.EventFrame Ops.Val))

private def fourIndexed : ProofForge.Core.Ops.EventFrame Ops.Val := {
  constructor := "TooManyTopics"
  args := #[
    { name := "a", type := .uint64, parts := #[.lit 1], indexed := true },
    { name := "b", type := .uint64, parts := #[.lit 2], indexed := true },
    { name := "c", type := .uint64, parts := #[.lit 3], indexed := true },
    { name := "d", type := .uint64, parts := #[.lit 4], indexed := true }
  ]
}

private def fiveData : ProofForge.Core.Ops.EventFrame Ops.Val := {
  constructor := "TooMuchData"
  args := #[
    { name := "a", type := .uint64, parts := #[.lit 1] },
    { name := "b", type := .uint64, parts := #[.lit 2] },
    { name := "c", type := .uint64, parts := #[.lit 3] },
    { name := "d", type := .uint64, parts := #[.lit 4] },
    { name := "e", type := .uint64, parts := #[.lit 5] }
  ]
}

#guard fourIndexed.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard fiveData.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard fourIndexed.indexedCount + 1 > LogError.maxTopics
#guard fiveData.dataCount > LogError.maxLogDataWords
#guard !NativeFx.Call.wellFormed (·.wellFormed Ops.ValKind.arity) (.logTyped fourIndexed)
#guard !NativeFx.Call.wellFormed (·.wellFormed Ops.ValKind.arity) (.logTyped fiveData)

-- Closed EVM type vocabulary: Core-well-formed scalars without a one-word EVM carrier
-- (`uint96` spans two limbs but is not whole 64-bit limbs; `address32`) fail before Yul.
private def uint96Frame : ProofForge.Core.Ops.EventFrame Ops.Val := {
  constructor := "Wide"
  args := #[{ name := "x", type := .uint 96, parts := #[.lit 1, .lit 2] }]
}

private def address32Frame : ProofForge.Core.Ops.EventFrame Ops.Val := {
  constructor := "Bad"
  args := #[{ name := "a", type := .address32, parts := #[.lit 1, .lit 2, .lit 3, .lit 4] }]
}

private def boolFrame : ProofForge.Core.Ops.EventFrame Ops.Val := {
  constructor := "Flag"
  args := #[{ name := "on", type := .boolean, parts := #[.lit 1] }]
}

private def bytes32Frame : ProofForge.Core.Ops.EventFrame Ops.Val := {
  constructor := "Digest"
  args := #[{ name := "h", type := .bytes32, parts := #[.lit 1, .lit 2, .lit 3, .lit 4],
              indexed := true }]
}

private def emptyFrame : ProofForge.Core.Ops.EventFrame Ops.Val := {
  constructor := "Ping", args := #[] }

#guard uint96Frame.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard address32Frame.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard !NativeFx.Call.wellFormed (·.wellFormed Ops.ValKind.arity) (.logTyped uint96Frame)
#guard !NativeFx.Call.wellFormed (·.wellFormed Ops.ValKind.arity) (.logTyped address32Frame)
#guard NativeFx.Call.wellFormed (·.wellFormed Ops.ValKind.arity) (.logTyped boolFrame)
#guard NativeFx.Call.wellFormed (·.wellFormed Ops.ValKind.arity) (.logTyped bytes32Frame)
#guard NativeFx.Call.wellFormed (·.wellFormed Ops.ValKind.arity) (.logTyped emptyFrame)
#guard
  match NativeFx.Call.logTypedAbiTypes (·.wellFormed Ops.ValKind.arity) transferFrame with
  | .ok types => types == #["address", "address", "uint256"]
  | .error _ => false
#guard
  match NativeFx.Call.logTypedAbiTypes (·.wellFormed Ops.ValKind.arity) uint96Frame with
  | .error reason => reason.contains "typed event"
  | .ok _ => false

#guard Keccak.signature "Transfer" #["address", "address", "uint256"] ==
  "Transfer(address,address,uint256)"
#guard Keccak.signature "Approval" #["address", "address", "uint256"] ==
  "Approval(address,address,uint256)"
#guard Keccak.signature "Tipped" #["uint64"] == "Tipped(uint64)"

private def transferTopic0 : String :=
  Keccak.keccak256HexOfString "Transfer(address,address,uint256)"
private def approvalTopic0 : String :=
  Keccak.keccak256HexOfString "Approval(address,address,uint256)"
private def tippedTopic0 : String :=
  Keccak.keccak256HexOfString "Tipped(uint64)"

#guard transferTopic0 != approvalTopic0
#guard transferTopic0 != tippedTopic0

private def mockNativeCtx : NativeFx.Emit.Context Nat :=
  { materialize := fun _ st => .ok ("", "0", st)
    fresh := fun st => (s!"v{st}", st + 1)
    indent := "  " }

private def mockLogCtx : LogError.Emit.Context := { indent := "  " }

-- Closed Transfer256 ABI bytes stay the spelling `eventAbi` already emits.
#guard
  match Emit.emitAbi ProofForge.Evm.Golden.extractedToken with
  | abi => abi.contains transferAbi && abi.contains approvalAbi

-- `logTyped` Transfer lowers to the same LOG3 plan as the closed Transfer256 helper.
#guard
  match LogError.Emit.emitLog mockLogCtx
        { data := #["v2"]
          topics := #["0x" ++ transferTopic0, "v0", "v1"] },
        NativeFx.Emit.emitCall mockNativeCtx (.logTyped transferFrame) 0,
        NativeFx.Emit.emitCall mockNativeCtx
          (.logTransfer256 lit lit lit lit lit lit lit lit lit lit) 0 with
  | .ok fragment, .ok (typedTxt, _, typedSt), .ok (closedTxt, _, closedSt) =>
      typedTxt.endsWith fragment && closedTxt.endsWith fragment &&
        typedTxt.contains s!"log3(0, 32, 0x{transferTopic0}" &&
        typedSt == closedSt
  | _, _, _ => false

#guard
  match NativeFx.Emit.emitCall mockNativeCtx (.logTyped approvalFrame) 0 with
  | .error _ => false
  | .ok (txt, _, _) => txt.contains s!"log3(0, 32, 0x{approvalTopic0}"

#guard
  match NativeFx.Emit.emitCall mockNativeCtx (.logTyped tippedFrame) 0 with
  | .error _ => false
  | .ok (txt, _, _) =>
      txt == s!"  mstore(0, 0)\n  log1(0, 32, 0x{tippedTopic0})\n"

#guard
  match NativeFx.Emit.emitCall mockNativeCtx (.logTyped fourIndexed) 0 with
  | .error reason => reason.contains "typed event"
  | .ok _ => false

-- Emission never silently drops limbs: unsupported carriers fail, not truncate.
#guard
  match NativeFx.Emit.emitCall mockNativeCtx (.logTyped uint96Frame) 0 with
  | .error reason => reason.contains "typed event"
  | .ok _ => false

-- Signature-only event: zero data words, LOG1 with `(0, 0)` geometry.
#guard
  match NativeFx.Emit.emitCall mockNativeCtx (.logTyped emptyFrame) 0 with
  | .error _ => false
  | .ok (txt, _, st) =>
      txt == s!"  log1(0, 0, 0x{Keccak.keccak256HexOfString "Ping()"})\n" && st == 0

-- Indexed bytes32 packs through the fixed-bytes helper into a fresh topic word.
#guard
  match NativeFx.Emit.emitCall mockNativeCtx (.logTyped bytes32Frame) 0 with
  | .error _ => false
  | .ok (txt, _, st) =>
      txt.contains "pf_store_fixed_bytes(0, 0, 0, 0, 0, 32)" &&
        txt.contains s!"log2(0, 0, 0x{Keccak.keccak256HexOfString "Digest(bytes32)"}, v0)" &&
        st == 1

private def spliceTyped (p : IR.Program) (frame : ProofForge.Core.Ops.EventFrame Ops.Val) :
    Option IR.Program :=
  match p.entries.find? (·.ixName == "get") with
  | none => none
  | some get =>
      some { p with entries := #[{ get with
        ops := #[.component (.nativeFx (.logTyped frame)), .returnU64 (.lit 0)] }] }

#guard
  match IR.fromProgram ProofForge.Golden.extractedCounter with
  | .error _ => false
  | .ok base =>
      match spliceTyped base transferFrame, spliceTyped base approvalFrame,
          spliceTyped base tippedFrame with
      | some transferProg, some approvalProg, some tippedProg =>
          match Emit.emitAbiChecked transferProg, Emit.emitYul transferProg,
              Emit.emitAbiChecked approvalProg, Emit.emitYul approvalProg,
              Emit.emitAbiChecked tippedProg, Emit.emitYul tippedProg with
          | .ok transferAbiJson, .ok transferYul,
              .ok approvalAbiJson, .ok approvalYul,
              .ok tippedAbiJson, .ok tippedYul =>
              transferAbiJson.contains transferAbi &&
                approvalAbiJson.contains approvalAbi &&
                transferYul.contains s!"0x{transferTopic0}" &&
                approvalYul.contains s!"0x{approvalTopic0}" &&
                tippedYul.contains s!"0x{tippedTopic0}" &&
                tippedAbiJson.contains
                  "{\"type\":\"event\",\"name\":\"Tipped\",\"inputs\":[{\"name\":\"amt\",\"type\":\"uint64\",\"indexed\":false}],\"anonymous\":false}" &&
                !transferAbiJson.contains
                  "{\"name\":\"amt\",\"type\":\"uint64\",\"indexed\":false}"
          | _, _, _, _, _, _ => false
      | _, _, _ => false

-- ABI identity is the topic0 signature. Same signature with different indexed flags or names
-- is a conflict; identical frames dedupe to one declaration even across entries / nested `ite`.
private def transferReindexed : ProofForge.Core.Ops.EventFrame Ops.Val := {
  constructor := "Transfer"
  args := #[
    { name := "from", type := .address20, parts := #[.lit 0, .lit 1, .lit 2] },
    { name := "to", type := .address20, parts := #[.lit 3, .lit 4, .lit 5] },
    { name := "value", type := .uint256, parts := #[.lit 6, .lit 7, .lit 8, .lit 9],
      indexed := true }
  ]
}

private def transferRenamed : ProofForge.Core.Ops.EventFrame Ops.Val := {
  constructor := "Transfer"
  args := #[
    { name := "src", type := .address20, parts := #[.lit 0, .lit 1, .lit 2], indexed := true },
    { name := "to", type := .address20, parts := #[.lit 3, .lit 4, .lit 5], indexed := true },
    { name := "value", type := .uint256, parts := #[.lit 6, .lit 7, .lit 8, .lit 9] }
  ]
}

private def tippedRenamed : ProofForge.Core.Ops.EventFrame Ops.Val := {
  constructor := "Tipped"
  args := #[{ name := "value", type := .uint64, parts := #[.lit 9] }]
}

private def spliceOps (p : IR.Program) (ops : Array IR.Op) : Option IR.Program :=
  match p.entries.find? (·.ixName == "get") with
  | none => none
  | some get => some { p with entries := #[{ get with ops := ops.push (.returnU64 (.lit 0)) }] }

private def logTypedOp (frame : ProofForge.Core.Ops.EventFrame Ops.Val) : IR.Op :=
  .component (.nativeFx (.logTyped frame))

private def abiOf (p : IR.Program) (ops : Array IR.Op) : Except String String :=
  match spliceOps p ops with
  | none => .error "no get entry"
  | some prog => Emit.emitAbiChecked prog

private def countOccurrences (haystack needle : String) : Nat :=
  (haystack.splitOn needle).length - 1

#guard
  match IR.fromProgram ProofForge.Golden.extractedCounter with
  | .error _ => false
  | .ok base =>
      let conflictIndexed := abiOf base #[logTypedOp transferFrame, logTypedOp transferReindexed]
      let conflictNames := abiOf base #[logTypedOp transferFrame, logTypedOp transferRenamed]
      let dedupNested := abiOf base #[
        logTypedOp transferFrame,
        .ite .eq (.lit 0) (.lit 0) #[logTypedOp transferFrame] #[.forBody 1 #[logTypedOp transferFrame]]]
      let closedSame := abiOf base #[
        .component (.nativeFx (.logTransfer256 lit lit lit lit lit lit lit lit lit lit)),
        logTypedOp transferFrame,
        .component (.nativeFx (.log "Tipped" lit)),
        logTypedOp tippedFrame]
      let closedConflict := abiOf base #[
        .component (.nativeFx (.log "Tipped" lit)),
        logTypedOp tippedRenamed]
      (match conflictIndexed with
        | .error reason => reason.contains "conflicting typed event"
        | .ok _ => false) &&
      (match conflictNames with
        | .error reason => reason.contains "conflicting typed event"
        | .ok _ => false) &&
      (match dedupNested with
        | .ok abi => countOccurrences abi transferAbi == 1
        | .error _ => false) &&
      (match closedSame with
        | .ok abi => countOccurrences abi transferAbi == 1 &&
            countOccurrences abi "\"name\":\"Tipped\"" == 1
        | .error _ => false) &&
      (match closedConflict with
        | .error reason => reason.contains "conflicts with closed event"
        | .ok _ => false)

-- Registry / golden digests for existing programs stay pinned (no closed-union spelling change).
#guard Registry.digestOf "Token" == some "7d01d10202d87dd3"
#guard Registry.digestOf "EvmTypedErrors" == some "499001a31fb4d9e7"
#guard Registry.digestOf "EvmTypedEvents" == some "0"
#guard Registry.digestOf "Counter" == some "254202356ee921d6"
#guard IR.digestHex ProofForge.Evm.Golden.extractedToken == "59f8696f9b0e06db"
#guard IR.digestHex ProofForge.Evm.Golden.extractedVault == "a3ea1b5b2a69c0e3"
#guard
  match IR.fromProgram ProofForge.Golden.extractedCounter with
  | .ok p => IR.digestHex p == "254202356ee921d6"
  | .error _ => false

open Lean Elab Command
open ProofForge.Evm.Sdk
open Examples.Evm.EvmTypedEvents

#guard Event.emit (Notice.Ticked 3) == 0
#guard (Event.indexed (⟨1, 2, 3⟩ : Address)).value == ⟨1, 2, 3⟩

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

private partial def evmTypedFrames (ops : Array ProofForge.Evm.IR.Op) :
    Array (ProofForge.Core.Ops.EventFrame ProofForge.Evm.Ops.Val) :=
  ops.foldl (init := #[]) fun frames op =>
    let frames := match op with
      | .component (.nativeFx (.logTyped frame)) => frames.push frame
      | _ => frames
    match op with
    | .ite _ _ _ yes no => frames ++ evmTypedFrames yes ++ evmTypedFrames no
    | .forBody _ body => frames ++ evmTypedFrames body
    | _ => frames

private def eventMatches (frame : ProofForge.Core.Ops.EventFrame V)
    (constructor : String) (fields : Array (String × Bool)) : Bool :=
  frame.constructor == constructor &&
    frame.args.size == fields.size &&
    (List.zip frame.args.toList fields.toList).all fun
      | (arg, (name, indexed)) => arg.name == name && arg.indexed == indexed

private def expectUnsupported (env : Environment) (name : Name) (fragment : String) :
    CommandElabM Unit := do
  match ProofForge.Extract.extractMethod env .get name with
  | .ok _ => throwError s!"{name}: unsupported typed event unexpectedly extracted"
  | .error reason =>
      unless reason.contains fragment do
        throwError s!"{name}: wrong fail-closed reason: {reason}"

namespace Unsupported

inductive OptionEvent where
  | wide (value : Option UInt64)

def optionField (value : Option UInt64) : UInt64 :=
  Event.emit (OptionEvent.wide value)

inductive FourIndexed where
  | many (a b c d : Event.Indexed UInt64)

def fifthTopic (value : UInt64) : UInt64 :=
  Event.emit (FourIndexed.many (Event.indexed value) (Event.indexed value)
    (Event.indexed value) (Event.indexed value))

inductive AnonymousEvent where
  | hidden (_ : UInt64)

def anonymous (value : UInt64) : UInt64 :=
  Event.emit (AnonymousEvent.hidden value)

inductive ImplicitEvent where
  | hidden {code : UInt64}

def implicitField (value : UInt64) : UInt64 :=
  Event.emit (ImplicitEvent.hidden (code := value))

inductive TippedAmt where
  | Tipped (amt : UInt64)

inductive TippedValue where
  | Tipped (value : UInt64)

def conflict (left right : UInt64) : UInt64 :=
  Event.emit (TippedAmt.Tipped left) ||| Event.emit (TippedValue.Tipped right)

end Unsupported

elab "#pf_guard_evm_typed_event_source" : command => do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.EvmTypedEvents with
    | .ok source => pure source
    | .error reason => throwError reason
  let some sourceTransfer := source.methods.find? (·.ixName == "transfer")
    | throwError "typed-event example lost transfer"
  let some sourceFlag := source.methods.find? (·.ixName == "setFlag")
    | throwError "typed-event example lost setFlag"
  let some sourcePulse := source.methods.find? (·.ixName == "pulse")
    | throwError "typed-event example lost pulse"
  let transferFrames := sourceTypedFrames sourceTransfer.ops
  let flagFrames := sourceTypedFrames sourceFlag.ops
  let pulseFrames := sourceTypedFrames sourcePulse.ops
  unless transferFrames.size == 1 &&
      eventMatches transferFrames[0]! "Transferred"
        #[("from", true), ("to", true), ("value", false)] &&
      transferFrames[0]!.args[2]!.type == .uint256 do
    throwError s!"source Transferred frame diverged: {repr transferFrames}"
  unless flagFrames.size == 1 &&
      eventMatches flagFrames[0]! "Flagged" #[("ok", false)] &&
      flagFrames[0]!.args[0]!.type == .boolean do
    throwError s!"source Flagged frame diverged: {repr flagFrames}"
  unless pulseFrames.size == 2 &&
      pulseFrames.all (eventMatches · "Ticked" #[("n", false)]) do
    throwError s!"source Ticked frames diverged: {repr pulseFrames}"

  let evm ←
    match ProofForge.Evm.IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let some transfer := evm.entries.find? (·.ixName == "transfer")
    | throwError "EVM typed-event example lost transfer"
  let some setFlag := evm.entries.find? (·.ixName == "setFlag")
    | throwError "EVM typed-event example lost setFlag"
  let some pulse := evm.entries.find? (·.ixName == "pulse")
    | throwError "EVM typed-event example lost pulse"
  unless (evmTypedFrames transfer.ops).size == 1 &&
      (evmTypedFrames setFlag.ops).size == 1 &&
      (evmTypedFrames pulse.ops).size == 2 do
    throwError "EVM lowering lost typed event frames"

  let abi ←
    match ProofForge.Evm.Emit.emitAbiChecked evm with
    | .ok abi => pure abi
    | .error reason => throwError reason
  let transferredAbi := "{\"type\":\"event\",\"name\":\"Transferred\",\"inputs\":[" ++
    "{\"name\":\"from\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"to\",\"type\":\"address\",\"indexed\":true}," ++
    "{\"name\":\"value\",\"type\":\"uint256\",\"indexed\":false}],\"anonymous\":false}"
  let flaggedAbi := "{\"type\":\"event\",\"name\":\"Flagged\",\"inputs\":[" ++
    "{\"name\":\"ok\",\"type\":\"bool\",\"indexed\":false}],\"anonymous\":false}"
  let tickedAbi := "{\"type\":\"event\",\"name\":\"Ticked\",\"inputs\":[" ++
    "{\"name\":\"n\",\"type\":\"uint64\",\"indexed\":false}],\"anonymous\":false}"
  unless abi.contains transferredAbi && abi.contains flaggedAbi && abi.contains tickedAbi &&
      countOccurrences abi tickedAbi == 1 do
    throwError s!"typed-event ABI metadata diverged:\n{abi}"

  let yul ←
    match ProofForge.Evm.Emit.emitYul evm with
    | .ok yul => pure yul
    | .error reason => throwError reason
  let transferredTopic :=
    ProofForge.Crypto.Keccak.keccak256HexOfString "Transferred(address,address,uint256)"
  let flaggedTopic := ProofForge.Crypto.Keccak.keccak256HexOfString "Flagged(bool)"
  let tickedTopic := ProofForge.Crypto.Keccak.keccak256HexOfString "Ticked(uint64)"
  unless yul.contains s!"0x{transferredTopic}" && yul.contains "log3(" &&
      yul.contains s!"0x{flaggedTopic}" && yul.contains s!"0x{tickedTopic}" do
    throwError "typed-event Yul omitted topic0 or LOG geometry"

  expectUnsupported env ``Unsupported.optionField "closed EVM scalar"
  expectUnsupported env ``Unsupported.fifthTopic "malformed typed event"
  expectUnsupported env ``Unsupported.anonymous "explicitly named"
  expectUnsupported env ``Unsupported.implicitField "explicitly named"
  match ProofForge.Extract.extractMethod env .get ``Unsupported.conflict with
  | .error reason => throwError s!"conflict unexpectedly failed extract: {reason}"
  | .ok method =>
      let frames := sourceTypedFrames method.ops
      unless frames.size == 2 &&
          frames.any (eventMatches · "Tipped" #[("amt", false)]) &&
          frames.any (eventMatches · "Tipped" #[("value", false)]) do
        throwError s!"conflict frames diverged: {repr frames}"

  logInfo s!"EvmTypedEvents digest: {ProofForge.Evm.IR.digestHex evm}"

#pf_guard_evm_typed_event_source

end Tests.EvmTypedEventSpec
