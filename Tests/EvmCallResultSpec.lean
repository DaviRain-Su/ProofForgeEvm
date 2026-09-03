import ProofForge
import ProofForge.Evm.CallResult
import ProofForge.Evm.CallResult.Emit
import Examples.Evm.Vault
import Examples.Evm.Token

namespace Tests.EvmCallResultSpec

open ProofForge.Evm
open Lean Elab Command

/-! Focused gates for the EVM-RT-2a typed call-result contract: plan-layer shape gates,
byte-exact emission goldens for each policy, S2 multiword / typed-decode / fail-mode
policies, fail-closed emission errors, and ClosedCall / Component consumer regression
(including the existing Vault and Token structural gates). Existing ClosedCall digests
must stay pinned. -/

-- Plan layer: established policies keep returndata bounded to one 32-byte word.
#guard CallResult.Policy.retBound .canonicalTrueOrCodeBackedEmpty == 32
#guard CallResult.Policy.retBound .exactWord == 32
#guard CallResult.Policy.retBound .contractSuccess == 0
#guard [CallResult.Policy.canonicalTrueOrCodeBackedEmpty, .exactWord, .contractSuccess].all
  (fun p => Nat.ble (CallResult.Policy.retBound p) 32)
#guard CallResult.maxResultWords == 4
#guard CallResult.maxRetBytes == 128

-- S2 plan layer: exactWords / strictBool / magicBytes4 / words stay within the explicit max.
#guard CallResult.Policy.retBound (.exactWords 1) == 32
#guard CallResult.Policy.retBound (.exactWords 2) == 64
#guard CallResult.Policy.retBound (.exactWords 4) == 128
#guard CallResult.Policy.retBound .strictBool == 32
#guard CallResult.Policy.retBound (.magicBytes4 "1626ba7e") == 32
#guard CallResult.Policy.retBound (.words #[.address20, .boolean]) == 64
#guard CallResult.Policy.wellFormed (.exactWords 1)
#guard CallResult.Policy.wellFormed (.exactWords 4)
#guard !CallResult.Policy.wellFormed (.exactWords 0)
#guard !CallResult.Policy.wellFormed (.exactWords 5)
#guard CallResult.Policy.wellFormed .strictBool
#guard CallResult.Policy.wellFormed (.magicBytes4 "1626ba7e")
#guard !CallResult.Policy.wellFormed (.magicBytes4 "1626BA7E")
#guard !CallResult.Policy.wellFormed (.magicBytes4 "1626ba")
#guard !CallResult.Policy.wellFormed (.magicBytes4 "gggggggg")
#guard CallResult.Policy.wellFormed (.words #[.uint256, .boolean, .address20, .bytes4])
#guard !CallResult.Policy.wellFormed (.words #[])
#guard !CallResult.Policy.wellFormed
  (.words #[.uint256, .uint256, .uint256, .uint256, .uint256])
#guard (CallResult.Request.staticWords 36 2).wellFormed
#guard (CallResult.Request.staticBool 4).wellFormed
#guard (CallResult.Request.staticMagic 36 "150b7a02").wellFormed
#guard (CallResult.Request.staticTyped 36 #[.address20, .uint256]).wellFormed
#guard !(CallResult.Request.staticWords 36 0).wellFormed
#guard !(CallResult.Request.staticWords 36 5).wellFormed
#guard !({ kind := .staticcall, inSize := 36, policy := .exactWords 2, value := true } :
    CallResult.Request).wellFormed
#guard CallResult.Policy.wordKinds (.exactWords 2) == #[.uint256, .uint256]
#guard CallResult.Policy.wordKinds .strictBool == #[.boolean]
#guard CallResult.Policy.wordKinds (.magicBytes4 "1626ba7e") == #[.bytes4]

-- Plan layer: established constructors are well-formed; msg.value on a STATICCALL is not.
#guard (CallResult.Request.erc20Mutation 68).wellFormed
#guard (CallResult.Request.erc20Mutation 100).wellFormed
#guard (CallResult.Request.erc20Mutation 228).wellFormed
#guard (CallResult.Request.staticWord 36).wellFormed
#guard (CallResult.Request.staticWord 68).wellFormed
#guard (CallResult.Request.successOnly 4 true).wellFormed
#guard (CallResult.Request.successOnly 260).wellFormed
#guard !({ kind := .staticcall, inSize := 36, policy := .exactWord, value := true } :
    CallResult.Request).wellFormed
#guard (CallResult.Request.erc20Mutation 68).retBound == 32
#guard (CallResult.Request.successOnly 292).retBound == 0
#guard ProofForge.Evm.Sdk.Effect.thenTrue 0

private def mockCtx : CallResult.Emit.Context Nat :=
  { fresh := fun st => (s!"v{st}", st + 1), indent := "  " }

-- Emission golden: safe ERC-20 compatibility rule (CALL success + canonical true, or empty data
-- from a target that still has runtime code after the call), byte-exact.
#guard
  match CallResult.Emit.emit mockCtx (.erc20Mutation 68) "tok" none 0 with
  | .error _ => false
  | .ok (txt, word, st) =>
      txt ==
        "  let v0 := call(gas(), tok, 0, 0, 68, 0, 32)\n" ++
        "  if iszero(v0) { revert(0, 0) }\n" ++
        "  let v1 := returndatasize()\n" ++
        "  switch v1\n" ++
        "  case 0 { if iszero(extcodesize(tok)) { revert(0, 0) } }\n" ++
        "  case 32 { if iszero(eq(mload(0), 1)) { revert(0, 0) } }\n" ++
        "  default { revert(0, 0) }\n" &&
        word == none && st == 2

-- Emission golden: exact-one-word STATICCALL read, byte-exact; the word is bound.
#guard
  match CallResult.Emit.emit mockCtx (.staticWord 36) "tok" none 0 with
  | .error _ => false
  | .ok (txt, word, st) =>
      txt ==
        "  let v0 := staticcall(gas(), tok, 0, 36, 0, 32)\n" ++
        "  if iszero(v0) { revert(0, 0) }\n" ++
        "  if iszero(eq(returndatasize(), 32)) { revert(0, 0) }\n" ++
        "  let v1 := mload(0)\n" &&
        word == some "v1" && st == 2

-- Emission golden: contract-success CALL carrying msg.value; returndata is not copied or
-- consumed, and an empty result is accepted only for a target with runtime code.
#guard
  match CallResult.Emit.emit mockCtx (.successOnly 4 true) "tok" (some "amt") 0 with
  | .error _ => false
  | .ok (txt, word, st) =>
      txt ==
        "  let v0 := call(gas(), tok, amt, 0, 4, 0, 0)\n" ++
        "  if iszero(v0) { revert(0, 0) }\n" ++
        "  if and(iszero(returndatasize()), iszero(extcodesize(tok))) { revert(0, 0) }\n" &&
        word == none && st == 1

-- Fail closed at emission: unexpected or missing msg.value expression.
#guard
  match CallResult.Emit.emit mockCtx (.erc20Mutation 68) "tok" (some "amt") 0 with
  | .error reason => reason.contains "value shape"
  | .ok _ => false
#guard
  match CallResult.Emit.emit mockCtx (.successOnly 4 true) "tok" none 0 with
  | .error reason => reason.contains "value shape"
  | .ok _ => false

-- Fail closed at emission: msg.value on a STATICCALL request is not well-formed.
#guard
  match CallResult.Emit.emit mockCtx
      { kind := .staticcall, inSize := 36, policy := .exactWord, value := true }
      "tok" (some "amt") 0 with
  | .error reason => reason.contains "request shape"
  | .ok _ => false

private def mockClosedCtx : ClosedCall.Emit.Context Nat :=
  { materialize := fun _ st => .ok ("", "0", st)
    fresh := fun st => (s!"v{st}", st + 1)
    rememberWide := fun st _ _ => st
    lookupWide := fun _ _ => none
    valKey := fun _ => ""
    indent := "  " }

private def lit : Ops.Val := .lit 0

private def explicitResultAfterEffect : IR.Program :=
  {
    name := "ExplicitResultAfterEffect"
    slots := #[{ name := "dummy", index := 0, width := 8 }]
    constructor := {
      kind := .init
      name := "Tests.ExplicitResultAfterEffect.init"
      ixName := "initialize"
      paramCount := 1
      paramWidths := #[8]
      ops := #[.returnState (.lit 0)]
    }
    entries := #[{
      kind := .increment
      name := "Tests.ExplicitResultAfterEffect.mutate"
      ixName := "mutate"
      selector := ProofForge.Evm.Keccak.selectorOfWidths "mutate" #[]
      retTypes := #[.boolean]
      retSchema := .scalar .boolean
      ops := #[
        .component (.nativeFx (.log "Result" (.lit 7))),
        .returnU64 (.lit 1)
      ]
    }]
  }

-- An explicit terminator wins over the preceding component's numeric effect carrier.
#guard
  match Emit.emitYul explicitResultAfterEffect with
  | .error _ => false
  | .ok yul =>
      yul.contains "pf_last := 0x7" && yul.contains "mstore(0, 0x1)" &&
        !yul.contains "mstore(0, pf_last)"

-- ClosedCall mutation consumes the shared contract: the emitted transfer contains exactly the
-- fragment the shared interpreter produces at the same state.
#guard
  match CallResult.Emit.emit mockCtx (.erc20Mutation 68) "v0" none 1,
        ClosedCall.Emit.emitCall mockClosedCtx (.transfer lit lit lit lit lit lit lit) 0 with
  | .ok (fragment, _, _), .ok (txt, _, st) => txt.contains fragment && st == 3
  | _, _ => false

-- ClosedCall query consumes the shared contract: balance256 contains the exact-one-word
-- STATICCALL fragment and exposes the bound word through the limb selector.
#guard
  match CallResult.Emit.emit mockCtx (.staticWord 36) "v0" none 1,
        ClosedCall.Emit.emitQuery mockClosedCtx (.balance256 0) #[lit, lit, lit] 0 with
  | .ok (fragment, _, _), .ok (txt, _, _) =>
      txt.contains fragment && txt.contains "and(shr(0, v2), 0xffffffffffffffff)"
  | _, _ => false

-- Component bridge still routes closed calls into the shared contract.
#guard
  match Component.Emit.emitCall
      { materialize := fun _ st => .ok ("", "0", st)
        fresh := fun st => (s!"v{st}", st + 1)
        rememberWide := fun st _ _ => st
        lookupWide := fun _ _ => none
        valKey := fun _ => ""
        indent := "  " }
      (.closedCall (.transfer lit lit lit lit lit lit lit) : Component.Call Ops.Val) 0 with
  | .error _ => false
  | .ok (txt, _, _) =>
      txt.contains " := call(gas(), " && txt.contains " := returndatasize()" &&
        txt.contains "case 0 { if iszero(extcodesize(" &&
        txt.contains "case 32 { if iszero(eq(mload(0), 1)) { revert(0, 0) } }"

-- Existing consumer regression: Vault and Token keep the shared gate spellings.
#guard
  match Emit.emitYul ProofForge.Evm.Golden.extractedVault with
  | .error _ => false
  | .ok yul =>
      yul.contains " := call(gas(), " &&
        yul.contains " := staticcall(gas(), " &&
        yul.contains " := returndatasize()" &&
        yul.contains "case 0 { if iszero(extcodesize(" &&
        yul.contains "case 32 { if iszero(eq(mload(0), 1)) { revert(0, 0) } }" &&
        yul.contains "if iszero(eq(returndatasize(), 32)) { revert(0, 0) }"

#guard
  match Emit.emitYul ProofForge.Evm.Golden.extractedToken with
  | .error _ => false
  | .ok yul =>
      yul.contains "staticcall(gas(), 1," &&
        !yul.contains " := returndatasize()"

/- The live Token extraction must retain the explicit Boolean result rather than reusing the
numeric carrier of the final event or storage effect. This is the source-to-IR regression that
keeps ERC-20 success words canonical for every transfer amount. -/
elab "#pf_guard_evm_token_bool_results" : command => do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.Token with
    | .ok source => pure source
    | .error reason => throwError reason
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let canonicalBool : Ops.Val → Bool
    | .select .ne (.bitOr _ (.lit 1)) (.lit 0) (.lit 1) (.lit 0) => true
    | _ => false
  let rec hasCanonicalReturn (fuel : Nat) (ops : Array IR.Op) : Bool :=
    match fuel with
    | 0 => false
    | fuel' + 1 => ops.any fun
        | .returnU64 value => canonicalBool value
        | .ite _ _ _ thn els =>
            hasCanonicalReturn fuel' thn || hasCanonicalReturn fuel' els
        | .forBody _ body => hasCanonicalReturn fuel' body
        | _ => false
  for name in #["approve", "transfer", "transferFrom"] do
    let some method := program.entries.find? (·.ixName == name)
      | throwError s!"missing Token {name} entry"
    unless method.retTypes == #[.boolean] && method.retSchema == .scalar .boolean &&
        hasCanonicalReturn 32 method.ops do
      throwError s!"Token {name} did not retain a canonical Boolean result"

#pf_guard_evm_token_bool_results

-- S2: exactWords 1 is byte-identical to exactWord (same size gate, same first-word bind).
#guard
  match CallResult.Emit.emit mockCtx (.staticWord 36) "tok" none 0,
        CallResult.Emit.emit mockCtx (.staticWords 36 1) "tok" none 0 with
  | .ok (a, wa, sa), .ok (b, wb, sb) => a == b && wa == wb && sa == sb
  | _, _ => false

-- S2: exactWords 2 copies 64 bytes, binds both words, fresh-name order ok then w0 then w1.
#guard
  match CallResult.Emit.emitBound mockCtx (.staticWords 36 2) "tok" none 0 with
  | .error _ => false
  | .ok (txt, bound, st) =>
      txt ==
        "  let v0 := staticcall(gas(), tok, 0, 36, 0, 64)\n" ++
        "  if iszero(v0) { revert(0, 0) }\n" ++
        "  if iszero(eq(returndatasize(), 64)) { revert(0, 0) }\n" ++
        "  let v1 := mload(0)\n" ++
        "  let v2 := mload(32)\n" &&
        bound.names == #["v1", "v2"] && bound.word == some "v1" && st == 3

-- S2: strictBool is exact 32 bytes plus the canonical 0/1 gate.
#guard
  match CallResult.Emit.emitBound mockCtx (.staticBool 4) "tok" none 0 with
  | .error _ => false
  | .ok (txt, bound, st) =>
      txt ==
        "  let v0 := staticcall(gas(), tok, 0, 4, 0, 32)\n" ++
        "  if iszero(v0) { revert(0, 0) }\n" ++
        "  if iszero(eq(returndatasize(), 32)) { revert(0, 0) }\n" ++
        "  let v1 := mload(0)\n" ++
        "  if gt(v1, 1) { revert(0, 0) }\n" &&
        bound.names == #["v1"] && st == 2

-- S2: magicBytes4 is exact 32 bytes, canonical bytes4, and equality to the left-aligned selector.
#guard
  match CallResult.Emit.emitBound mockCtx (.staticMagic 36 "1626ba7e") "tok" none 0 with
  | .error _ => false
  | .ok (txt, bound, st) =>
      txt ==
        "  let v0 := staticcall(gas(), tok, 0, 36, 0, 32)\n" ++
        "  if iszero(v0) { revert(0, 0) }\n" ++
        "  if iszero(eq(returndatasize(), 32)) { revert(0, 0) }\n" ++
        "  let v1 := mload(0)\n" ++
        "  if shl(32, v1) { revert(0, 0) }\n" ++
        "  if iszero(eq(v1, shl(224, 0x1626ba7e))) { revert(0, 0) }\n" &&
        bound.names == #["v1"] && st == 2

-- S2: typed words validate address (high 12 zero) then bool (0 or 1).
#guard
  match CallResult.Emit.emitBound mockCtx
      (.staticTyped 36 #[.address20, .boolean]) "tok" none 0 with
  | .error _ => false
  | .ok (txt, bound, st) =>
      txt ==
        "  let v0 := staticcall(gas(), tok, 0, 36, 0, 64)\n" ++
        "  if iszero(v0) { revert(0, 0) }\n" ++
        "  if iszero(eq(returndatasize(), 64)) { revert(0, 0) }\n" ++
        "  let v1 := mload(0)\n" ++
        "  if shr(160, v1) { revert(0, 0) }\n" ++
        "  let v2 := mload(32)\n" ++
        "  if gt(v2, 1) { revert(0, 0) }\n" &&
        bound.names == #["v1", "v2"] && st == 3

-- S2: default FailMode.revert0 is byte-identical to an explicit revert0 request.
#guard
  match CallResult.Emit.emit mockCtx (.erc20Mutation 68) "tok" none 0,
        CallResult.Emit.emit mockCtx
          { kind := .call, inSize := 68, policy := .canonicalTrueOrCodeBackedEmpty,
            fail := .revert0 }
          "tok" none 0 with
  | .ok (a, _, _), .ok (b, _, _) => a == b
  | _, _ => false

-- S2: bubble replaces only the call-failure body; policy tails stay revert(0, 0).
#guard
  match CallResult.Emit.emit mockCtx
      { kind := .staticcall, inSize := 36, policy := .exactWord, fail := .bubble }
      "tok" none 0 with
  | .error _ => false
  | .ok (txt, word, st) =>
      txt ==
        "  let v0 := staticcall(gas(), tok, 0, 36, 0, 32)\n" ++
        "  if iszero(v0) { returndatacopy(0, 0, returndatasize()) revert(0, returndatasize()) }\n" ++
        "  if iszero(eq(returndatasize(), 32)) { revert(0, 0) }\n" ++
        "  let v1 := mload(0)\n" &&
        word == some "v1" && st == 2

#guard
  match CallResult.Emit.emit mockCtx
      { kind := .call, inSize := 68, policy := .canonicalTrueOrCodeBackedEmpty,
        fail := .bubble }
      "tok" none 0 with
  | .error _ => false
  | .ok (txt, word, _) =>
      txt.startsWith
        ("  let v0 := call(gas(), tok, 0, 0, 68, 0, 32)\n" ++
          "  if iszero(v0) { returndatacopy(0, 0, returndatasize()) revert(0, returndatasize()) }\n") &&
        txt.contains "default { revert(0, 0) }" &&
        !txt.contains "default { returndatacopy" &&
        word == none

-- S2 fail closed: oversized / empty / malformed magic never emit.
#guard
  match CallResult.Emit.emit mockCtx (.staticWords 36 5) "tok" none 0 with
  | .error reason => reason.contains "request shape"
  | .ok _ => false
#guard
  match CallResult.Emit.emit mockCtx (.staticWords 36 0) "tok" none 0 with
  | .error reason => reason.contains "request shape"
  | .ok _ => false
#guard
  match CallResult.Emit.emit mockCtx (.staticMagic 36 "1626BA7E") "tok" none 0 with
  | .error reason => reason.contains "request shape"
  | .ok _ => false
#guard
  match CallResult.Emit.emitBound mockCtx (.staticTyped 36 #[]) "tok" none 0 with
  | .error reason => reason.contains "request shape"
  | .ok _ => false

-- emit wraps emitBound: first-word carrier matches Bound.word.
#guard
  match CallResult.Emit.emit mockCtx (.staticWords 36 2) "tok" none 0,
        CallResult.Emit.emitBound mockCtx (.staticWords 36 2) "tok" none 0 with
  | .ok (a, wa, sa), .ok (b, bound, sb) =>
      a == b && wa == bound.word && sa == sb && bound.names.size == 2
  | _, _ => false

-- Consumer component/IR identity is preserved (registry digests).
#guard IR.digestHex ProofForge.Evm.Golden.extractedVault == "a3ea1b5b2a69c0e3"
#guard IR.digestHex ProofForge.Evm.Golden.extractedToken == "59f8696f9b0e06db"
#guard Registry.digestOf "Vault" == some "bb2f93cb28d7501"
#guard Registry.digestOf "Token" == some "7d01d10202d87dd3"

end Tests.EvmCallResultSpec
