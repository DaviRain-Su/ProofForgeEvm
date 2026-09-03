import ProofForge
import ProofForge.Evm.LogError
import ProofForge.Evm.LogError.Emit
import ProofForge.Extract.LegacyGolden

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

-- Registry / golden digests for existing programs stay pinned (no closed-union spelling change).
#guard Registry.digestOf "Token" == some "7d01d10202d87dd3"
#guard Registry.digestOf "EvmTypedErrors" == some "499001a31fb4d9e7"
#guard Registry.digestOf "Counter" == some "254202356ee921d6"
#guard IR.digestHex ProofForge.Evm.Golden.extractedToken == "59f8696f9b0e06db"
#guard IR.digestHex ProofForge.Evm.Golden.extractedVault == "a3ea1b5b2a69c0e3"
#guard
  match IR.fromProgram ProofForge.Golden.extractedCounter with
  | .ok p => IR.digestHex p == "254202356ee921d6"
  | .error _ => false

end Tests.EvmTypedEventSpec
