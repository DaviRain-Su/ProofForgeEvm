import ProofForge
import ProofForge.Evm.OpenCall
import ProofForge.Evm.OpenCall.Emit
import ProofForge.Evm.CallResult
import ProofForge.Evm.CallResult.Emit
import Examples.Evm.EvmOpenCall
import Tests.EvmOpenCallMisuse
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
    { name := "to", type := .scalar .address20, parts := #[.lit 1, .lit 2, .lit 3] },
    { name := "amount", type := .scalar .uint256, parts := #[.lit 4, .lit 5, .lit 6, .lit 7] }
  ]
  target := #[lit, lit, lit]
  kind := .call
  policy := .canonicalTrueOrCodeBackedEmpty
}

private def echoPlan : OpenCall.Plan Ops.Val := {
  name := "echo"
  args := #[{ name := "n", type := .scalar .uint256, parts := #[.lit 9, lit, lit, lit] }]
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

/-- `sink(uint256,bytes)`: one head word for `tag`, one offset word for `data`, then the tail
(`length` limb followed by eight byte limbs). -/
private def bytesArg (name : String) (capacity : Nat) : OpenCall.Arg Ops.Val :=
  { name, type := .bytes capacity, parts := Array.replicate (1 + capacity) lit }

private def sinkPlan : OpenCall.Plan Ops.Val := {
  name := "sink"
  args := #[
    { name := "tag", type := .scalar .uint256, parts := #[.lit 7, lit, lit, lit] },
    bytesArg "data" 8
  ]
  target := #[lit, lit, lit]
  kind := .call
  policy := .contractSuccess
}

#guard OpenCall.maxBytesArgs == 1
#guard OpenCall.maxArrayArgs == 2
#guard OpenCall.maxDynamicArgs == 3
#guard (OpenCall.ArgType.bytes 8).limbCount == 9
#guard (OpenCall.ArgType.bytes 8).abiType matches .ok "bytes"
#guard (OpenCall.ArgType.bytes 8).canonical == "bytes8"
#guard (OpenCall.ArgType.bytes 65).supported
#guard !(OpenCall.ArgType.bytes 66).supported
#guard OpenCall.ArgType.supported (.bytes Codec.maxPackedBytesCapacity)
#guard (OpenCall.ArgType.string 8).limbCount == 9
#guard (OpenCall.ArgType.string 8).abiType matches .ok "string"
#guard (OpenCall.ArgType.string 8).canonical == "string8"
#guard (OpenCall.ArgType.string 65).supported
#guard !(OpenCall.ArgType.string 66).supported
#guard OpenCall.ArgType.supported (.string Codec.maxPackedBytesCapacity)
#guard (OpenCall.ArgType.string 8).isPacked
#guard (OpenCall.ArgType.string 8).validateUtf8
#guard !(OpenCall.ArgType.bytes 8).validateUtf8
#guard !(OpenCall.ArgType.bytes 8).isString
#guard (OpenCall.ArgType.array 4 .uint256).limbCount == 17
#guard (OpenCall.ArgType.array 4 .uint256).abiType matches .ok "uint256[]"
#guard (OpenCall.ArgType.array 4 .uint256).supported
#guard !(OpenCall.ArgType.array 16 .uint256).supported
#guard sinkPlan.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard sinkPlan.headBytes == 68
#guard sinkPlan.inSize == 100
#guard sinkPlan.abiTypes matches .ok #["uint256", "bytes"]
#guard
  match sinkPlan.selectorHex (·.wellFormed Ops.ValKind.arity) with
  | .ok sel => sel == Keccak.selector "sink" #["uint256", "bytes"]
  | .error _ => false
#guard (sinkPlan.canonical fun _ => "x").startsWith
  "ocall.call.ok.sink(x,x,x;tag:"
#guard (sinkPlan.canonical fun _ => "x").endsWith ",data:bytes8(x,x,x,x,x,x,x,x,x))"
-- A scalar-only plan spells its canonical string as before the bytes tail existed.
#guard (transferPlan.canonical fun _ => "x") ==
  s!"ocall.call.erc20.transfer(x,x,x;to:{repr ProofForge.Core.Codec.Scalar.address20}(x,x,x),amount:{repr ProofForge.Core.Codec.Scalar.uint256}(x,x,x,x))"

private def stringArgPlan (name : String) (capacity : Nat) : OpenCall.Arg Ops.Val :=
  { name, type := .string capacity, parts := Array.replicate (1 + capacity) lit }

private def labelPlan : OpenCall.Plan Ops.Val := {
  name := "label"
  args := #[stringArgPlan "text" 8]
  target := #[lit, lit, lit]
  kind := .call
  policy := .contractSuccess
}

#guard labelPlan.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard labelPlan.headBytes == 36
#guard labelPlan.inSize == 68
#guard labelPlan.abiTypes matches .ok #["string"]
#guard
  match labelPlan.selectorHex (·.wellFormed Ops.ValKind.arity) with
  | .ok sel => sel == Keccak.selector "label" #["string"] &&
      sel != Keccak.selector "label" #["bytes"]
  | .error _ => false
#guard (labelPlan.canonical fun _ => "x").endsWith ";text:string8(x,x,x,x,x,x,x,x,x))"

private def mixedPacked : OpenCall.Plan Ops.Val :=
  { sinkPlan with args := #[bytesArg "a" 4, stringArgPlan "b" 4] }
#guard !mixedPacked.wellFormed (·.wellFormed Ops.ValKind.arity)

private def twoTails : OpenCall.Plan Ops.Val :=
  { sinkPlan with args := #[bytesArg "a" 4, bytesArg "b" 4] }
private def wideTail : OpenCall.Plan Ops.Val :=
  { sinkPlan with args := #[bytesArg "data" 66] }
private def shortTail : OpenCall.Plan Ops.Val :=
  { sinkPlan with args := #[{ bytesArg "data" 8 with parts := Array.replicate 8 lit }] }
private def edgeTail : OpenCall.Plan Ops.Val :=
  { sinkPlan with args := #[bytesArg "data" 65] }

#guard !twoTails.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard !wideTail.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard !shortTail.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard edgeTail.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard edgeTail.inSize == 68

private def arrayArg (name : String) (capacity : Nat) : OpenCall.Arg Ops.Val :=
  { name, type := .array capacity .uint256,
    parts := Array.replicate (1 + capacity * 4) lit }

private def batchHookPlan : OpenCall.Plan Ops.Val := {
  name := "onERC1155BatchReceived"
  args := #[
    { name := "operator", type := .scalar .address20, parts := #[lit, lit, lit] },
    { name := "from", type := .scalar .address20, parts := #[lit, lit, lit] },
    arrayArg "ids" 4,
    arrayArg "values" 4,
    bytesArg "data" 32
  ]
  target := #[lit, lit, lit]
  kind := .call
  policy := .magicBytes4 "bc197c81"
}

#guard batchHookPlan.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard batchHookPlan.usesCursor
#guard batchHookPlan.headBytes == 164
#guard batchHookPlan.inSize == 164
#guard batchHookPlan.abiTypes matches
  .ok #["address", "address", "uint256[]", "uint256[]", "bytes"]
#guard
  match batchHookPlan.selectorHex (·.wellFormed Ops.ValKind.arity) with
  | .ok sel => sel == "bc197c81" &&
      sel == Keccak.selector "onERC1155BatchReceived"
        #["address", "address", "uint256[]", "uint256[]", "bytes"]
  | .error _ => false

private def threeArrays : OpenCall.Plan Ops.Val :=
  { batchHookPlan with args := #[arrayArg "a" 1, arrayArg "b" 1, arrayArg "c" 1] }
#guard !threeArrays.wellFormed (·.wellFormed Ops.ValKind.arity)

private def badName : OpenCall.Plan Ops.Val := { pingPlan with name := "" }
private def nineArgs : OpenCall.Plan Ops.Val :=
  { pingPlan with
    args := (List.range 9).toArray.map fun i =>
      { name := s!"a{i}", type := .scalar .uint64, parts := #[lit] } }
private def staticValue : OpenCall.Plan Ops.Val :=
  { echoPlan with valueParts := #[lit, lit, lit, lit] }

#guard !badName.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard !nineArgs.wellFormed (·.wellFormed Ops.ValKind.arity)
#guard !staticValue.wellFormed (·.wellFormed Ops.ValKind.arity)

private def echoQuery : OpenCall.Query := {
  name := "echo"
  argTypes := #[.scalar .uint256]
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

/-- `calldataHash(bytes)` read: target limbs, then the tail's length and eight byte limbs. -/
private def hashQuery : OpenCall.Query :=
  OpenCall.StaticShape.word.query "calldataHash" #[.bytes 8]
private def hashOperands : Array Ops.Val := #[lit, lit, lit] ++ Array.replicate 9 lit

#guard hashQuery.wellFormed
#guard hashQuery.arity == 12
#guard !(OpenCall.StaticShape.word.query "two" #[.bytes 4, .bytes 4]).wellFormed
#guard !(OpenCall.StaticShape.word.query "wide" #[.bytes 66]).wellFormed
#guard
  match hashQuery.toPlan hashOperands with
  | some plan =>
      plan.args.size == 1 && plan.args[0]!.type == .bytes 8 &&
        plan.args[0]!.parts.size == 9 && plan.inSize == 68
  | none => false
#guard (hashQuery.toPlan (hashOperands.pop)).isNone

-- Every STATICCALL read shape is a well-formed query whose limbs fit one ABI word.
#guard OpenCall.StaticShape.all.size == 6
#guard OpenCall.StaticShape.all.all fun shape =>
  (shape.query "read" #[.scalar .address20]).wellFormed &&
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
#guard OpenCall.policyCanon (.tryMagicBytes4 "1626ba7e") == "trymagic1626ba7e"
#guard (CallResult.Request.staticTryMagic 100 "1626ba7e").wellFormed
#guard ({ name := "isValidSignature"
          argTypes := #[.scalar (.fixedBytes 32), .bytes 65]
          kind := .staticcall
          policy := .tryMagicBytes4 "1626ba7e" } : OpenCall.Query).wellFormed
#guard (OpenCall.StaticShape.word.query "echo" #[.scalar .uint256]) == echoQuery
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

-- A `bytes` argument: the head holds its offset (64 = two head words), the tail holds the
-- runtime length then only the first `length` bytes over a zeroed region, and the call sends
-- the static 100 bytes plus the padded payload. Fresh names: tok v0, length v1, padded v2, ok v3.
#guard
  match OpenCall.Emit.emitCall mockOpenCtx (.invoke sinkPlan) 0 with
  | .ok (txt, _, 4) =>
      txt.contains s!"mstore(0, shl(224, 0x{Keccak.selector "sink" #["uint256", "bytes"]}))" &&
        txt.contains "  mstore(36, 64)\n" &&
        txt.contains "  let v1 := 0\n  if gt(v1, 8) { revert(0, 0) }\n  mstore(68, v1)\n  mstore(100, 0)\n" &&
        txt.contains "  if gt(v1, 0) { mstore8(100, 0) }\n" &&
        txt.contains "  if gt(v1, 7) { mstore8(107, 0) }\n" &&
        !txt.contains "mstore8(108," &&
        txt.contains "  let v2 := and(add(v1, 31), not(31))\n" &&
        txt.contains "let v3 := call(gas(), v0, 0, 0, add(100, v2), 0, 0)\n" &&
        txt.contains "if and(iszero(returndatasize()), iszero(extcodesize(v0)))"
  | _ => false

-- A 63-byte capacity zeroes two payload words; the head offset is one word when `bytes` is the
-- only argument.
#guard
  match OpenCall.Emit.emitCall mockOpenCtx (.invoke edgeTail) 0 with
  | .ok (txt, _, _) =>
      txt.contains "  mstore(4, 32)\n" && txt.contains "  mstore(36, v1)\n" &&
        txt.contains "  mstore(68, 0)\n  mstore(100, 0)\n" &&
        txt.contains "  if gt(v1, 62) { mstore8(130, 0) }\n" &&
        txt.contains "call(gas(), v0, 0, 0, add(68, v2), 0, 0)"
  | .error _ => false

-- A `bytes` argument whose limbs are exactly one packed-bytes entry parameter (the length word
-- then its capacity byte words, here words 2..10) is copied from calldata in one
-- `calldatacopy` of the padded length; the context names the payload offset. Any other limb
-- shape (a literal above, a computed byte) keeps the per-byte stores.
private def frameTail : OpenCall.Plan Ops.Val :=
  { sinkPlan with args := #[
      { name := "tag", type := .scalar .uint256, parts := #[.lit 7, lit, lit, lit] },
      { name := "data", type := .bytes 8, parts := (Array.range 9).map fun i => .arg (2 + i) }
    ] }
private def frameCtx : OpenCall.Emit.Context Nat :=
  { mockOpenCtx with
    calldataBytes := fun parts =>
      if parts == frameTail.args[1]!.parts then some "abi_bytes2"
      else none }
#guard
  match OpenCall.Emit.emitCall frameCtx (.invoke frameTail) 0 with
  | .ok (txt, _, 4) =>
      txt.contains "  mstore(36, 64)\n" &&
        txt.contains "  let v1 := 0\n  if gt(v1, 8) { revert(0, 0) }\n  mstore(68, v1)\n" &&
        txt.contains "  let v2 := and(add(v1, 31), not(31))\n  calldatacopy(100, abi_bytes2, v2)\n" &&
        !txt.contains "mstore8(" && !txt.contains "mstore(100, 0)" &&
        txt.contains "let v3 := call(gas(), v0, 0, 0, add(100, v2), 0, 0)\n"
  | _ => false
-- The same limbs under a context that does not know them stay on the per-byte path.
#guard
  match OpenCall.Emit.emitCall mockOpenCtx (.invoke frameTail) 0 with
  | .ok (txt, _, _) => txt.contains "  if gt(v1, 7) { mstore8(107, 0) }\n" && !txt.contains "calldatacopy("
  | .error _ => false

-- Every operand is materialized before the first calldata store. An operand whose prelude runs
-- its own call through scratch memory (a read passed as an argument) lands ahead of the target
-- check, the selector, and every head word, so it cannot overwrite them. Here `.lit 9` stands
-- for such an operand: echoPlan's first limb and depositPlan's first value limb.
private def preludeCtx : OpenCall.Emit.Context Nat :=
  { mockOpenCtx with
    materialize := fun value st =>
      match value with
      | .lit 9 => .ok (s!"  let p{st} := mload(0)\n", s!"p{st}", st + 1)
      | _ => .ok ("", "0", st) }
#guard
  match OpenCall.Emit.emitCall preludeCtx (.invoke echoPlan) 0 with
  | .ok (txt, _, _) =>
      txt.startsWith "  let p0 := mload(0)\n  if shr(32, 0) { revert(0, 0) }\n" &&
        txt.contains "  mstore(4, or(or(p0, shl(64, 0)), or(shl(128, 0), shl(192, 0))))\n" &&
        txt.contains "staticcall(gas(), v1, 0, 36, 0, 32)"
  | .error _ => false
#guard
  match OpenCall.Emit.emitCall preludeCtx
      (.invoke { depositPlan with valueParts := #[.lit 9, lit, lit, lit] }) 0 with
  | .ok (txt, _, _) =>
      txt.startsWith "  let p0 := mload(0)\n  if shr(32, 0) { revert(0, 0) }\n" &&
        txt.contains "  let v2 := or(or(p0, shl(64, 0)), or(shl(128, 0), shl(192, 0)))\n" &&
        txt.contains "call(gas(), v1, v2, 0, 4, 0, 0)"
  | .error _ => false

-- A STATICCALL read with a `bytes` argument rebuilds the same tail from flattened operands and
-- still binds the exact-one-word result.
#guard
  match OpenCall.Emit.emitQuery mockOpenCtx hashQuery hashOperands 0 with
  | .ok (txt, name, _) =>
      txt.contains s!"mstore(0, shl(224, 0x{Keccak.selector "calldataHash" #["bytes"]}))" &&
        txt.contains "  mstore(4, 32)\n" &&
        txt.contains "  mstore(36, v1)\n" &&
        txt.contains "let v3 := staticcall(gas(), v0, 0, add(68, v2), 0, 32)\n" &&
        txt.contains "if iszero(eq(returndatasize(), 32)) { revert(0, 0) }" &&
        txt.contains "let v4 := mload(0)\n" &&
        name == "v5"
  | .error _ => false

-- Plans without a tail keep the literal calldata size.
#guard
  match CallResult.Emit.emitBound mockCallResultCtx (.successOnly 4) "tok" none 0 with
  | .ok (txt, _, _) => txt.contains "call(gas(), tok, 0, 0, 4, 0, 0)"
  | .error _ => false
#guard
  match CallResult.Emit.emitBound mockCallResultCtx (.successOnly 36) "tok" none 0 (some "pad") with
  | .ok (txt, _, _) => txt.contains "call(gas(), tok, 0, 0, add(36, pad), 0, 0)"
  | .error _ => false

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
#guard Registry.digestOf "EvmOpenCall" == some "31027ffbd5535bb0"
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

private def extractInferred (env : Environment) (name : Name) :
    Except String ProofForge.Extract.IR.Method := do
  ProofForge.Extract.extractMethod env (← ProofForge.Extract.inferKind env name) name

private def expectUnsupported (env : Environment) (name : Name) (fragment : String) :
    CommandElabM Unit := do
  match extractInferred env name with
  | .ok _ => throwError s!"{name}: unsupported open-call unexpectedly extracted"
  | .error reason =>
      unless reason.contains fragment do
        throwError s!"{name}: wrong fail-closed reason: {reason}"

namespace Unsupported
open ProofForge.Core.Value (BoundedBytes BoundedString)

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

inductive TwoTails where
  | pair (a : BoundedBytes 4) (b : BoundedBytes 4)

def twoBytesArgs (target : Address) (a b : BoundedBytes 4) : UInt64 :=
  OpenCall.call target (TwoTails.pair a b)

inductive BytesAndString where
  | pair (a : BoundedBytes 4) (b : BoundedString 4)

def bytesAndString (target : Address) (a : BoundedBytes 4) (b : BoundedString 4) : UInt64 :=
  OpenCall.call target (BytesAndString.pair a b)

inductive WideTail where
  | wide (data : BoundedBytes 66)

def wideBytesArg (target : Address) (data : BoundedBytes 66) : UInt64 :=
  OpenCall.call target (WideTail.wide data)

end Unsupported

/-! The carrier's homes stay compiled, each with its CALL plan kept: the entry's result word,
the `effect` of `Effect.thenTrue` (and so of `Effect.abort` and `Effect.ensure`), and a `let`
whose binder reaches the result word. -/
namespace CarrierWord

def asBool (s : Examples.Evm.EvmOpenCall.State) (target : Address) :
    Except Examples.Evm.EvmOpenCall.Error (Examples.Evm.EvmOpenCall.State × Bool) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ s with dummy := 0 }, Effect.thenTrue (OpenCall.callSuccess target Remote.ping))
  else
    .error .overflow

def ensured (s : Examples.Evm.EvmOpenCall.State) (target : Address) :
    Except Examples.Evm.EvmOpenCall.Error (Examples.Evm.EvmOpenCall.State × Bool) :=
  Effect.ensure (s.flag == 0) s (OpenCall.callSuccess target Remote.ping)
    (fun _ => .ok ({ s with flag := 1 }, true))

def named (s : Examples.Evm.EvmOpenCall.State) (target : Address) :
    Except Examples.Evm.EvmOpenCall.Error (Examples.Evm.EvmOpenCall.State × Bool) :=
  let sent := Effect.thenTrue (OpenCall.callSuccess target Remote.ping)
  if s.flag == 0 then
    .ok ({ s with flag := 1 }, sent)
  else
    .error .overflow

end CarrierWord

private def expectCallKept (env : Environment) (name : Name) : CommandElabM Unit := do
  match extractInferred env name with
  | .error reason => throwError s!"{name}: carrier word unexpectedly refused: {reason}"
  | .ok method =>
      let plans := sourceOpenCalls method.ops
      unless plans.size == 1 && plans[0]!.name == "ping" && plans[0]!.kind == .call do
        throwError s!"{name} lost its ping CALL: {repr plans}"

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
  let some sink := source.methods.find? (·.ixName == "sinkBytes")
    | throwError "open-call example lost sinkBytes"
  let some _hash := source.methods.find? (·.ixName == "hashBytes")
    | throwError "open-call example lost hashBytes"
  let some label := source.methods.find? (·.ixName == "sinkString")
    | throwError "open-call example lost sinkString"
  let some _hashString := source.methods.find? (·.ixName == "hashString")
    | throwError "open-call example lost hashString"
  let some badUtf8 := source.methods.find? (·.ixName == "sinkBadUtf8")
    | throwError "open-call example lost sinkBadUtf8"
  let some hook := source.methods.find? (·.ixName == "notifyReceiver")
    | throwError "open-call example lost notifyReceiver"
  let some batchHook := source.methods.find? (·.ixName == "notifyBatchReceiver")
    | throwError "open-call example lost notifyBatchReceiver"
  let pingPlans := sourceOpenCalls ping.ops
  let storedPlans := sourceOpenCalls stored.ops
  let xferPlans := sourceOpenCalls xfer.ops
  let payPlans := sourceOpenCalls pay.ops
  let markPlans := sourceOpenCalls mark.ops
  let sinkPlans := sourceOpenCalls sink.ops
  let labelPlans := sourceOpenCalls label.ops
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
  -- The bytes field decodes as the one tail: an offset head word, then length plus eight
  -- byte limbs, with the static calldata size counting the length word.
  unless sinkPlans.size == 1 && sinkPlans[0]!.name == "sink" &&
      sinkPlans[0]!.kind == .call && sinkPlans[0]!.policy == .contractSuccess &&
      sinkPlans[0]!.args.size == 2 &&
      sinkPlans[0]!.args[0]!.type == .scalar .uint256 &&
      sinkPlans[0]!.args[1]!.name == "data" && sinkPlans[0]!.args[1]!.type == .bytes 8 &&
      sinkPlans[0]!.args[1]!.parts.size == 9 &&
      sinkPlans[0]!.inSize == 100 && sinkPlans[0]!.abiTypes matches .ok #["uint256", "bytes"] do
    throwError s!"sinkBytes plan diverged: {repr sinkPlans}"
  unless labelPlans.size == 1 && labelPlans[0]!.name == "label" &&
      labelPlans[0]!.kind == .call && labelPlans[0]!.policy == .contractSuccess &&
      labelPlans[0]!.args.size == 1 &&
      labelPlans[0]!.args[0]!.name == "text" && labelPlans[0]!.args[0]!.type == .string 8 &&
      labelPlans[0]!.args[0]!.type.validateUtf8 &&
      labelPlans[0]!.args[0]!.parts.size == 9 &&
      labelPlans[0]!.inSize == 68 && labelPlans[0]!.abiTypes matches .ok #["string"] do
    throwError s!"sinkString plan diverged: {repr labelPlans}"
  let badPlans := sourceOpenCalls badUtf8.ops
  unless badPlans.size == 1 && badPlans[0]!.name == "label" &&
      badPlans[0]!.kind == .call && badPlans[0]!.policy == .contractSuccess &&
      badPlans[0]!.args.size == 1 &&
      badPlans[0]!.args[0]!.type == .string 8 &&
      badPlans[0]!.args[0]!.type.validateUtf8 &&
      badPlans[0]!.args[0]!.parts ==
        #[.lit 2, .lit 0xc0, .lit 0x80, .lit 0, .lit 0, .lit 0, .lit 0, .lit 0, .lit 0] &&
      badPlans[0]!.abiTypes matches .ok #["string"] do
    throwError s!"sinkBadUtf8 plan diverged: {repr badPlans}"
  -- The hook's magic is the plan's own selector, computed from the constructor, never written
  -- by the author.
  let hookPlans := sourceOpenCalls hook.ops
  let hookSelector := ProofForge.Evm.Keccak.selector "onERC721Received"
    #["address", "address", "uint256", "bytes"]
  unless hookSelector == "150b7a02" do
    throwError s!"onERC721Received selector is {hookSelector}"
  unless hookPlans.size == 1 && hookPlans[0]!.name == "onERC721Received" &&
      hookPlans[0]!.kind == .call && hookPlans[0]!.policy == .magicBytes4 hookSelector &&
      hookPlans[0]!.args.size == 4 && hookPlans[0]!.args[3]!.type == .bytes 8 &&
      hookPlans[0]!.policy.copiedWordCount == 1 &&
      hookPlans[0]!.policy.wordKinds == #[.bytes4] do
    throwError s!"notifyReceiver plan diverged: {repr hookPlans}"
  let batchPlans := sourceOpenCalls batchHook.ops
  let batchSelector := ProofForge.Evm.Keccak.selector "onERC1155BatchReceived"
    #["address", "address", "uint256[]", "uint256[]", "bytes"]
  unless batchSelector == "bc197c81" do
    throwError s!"onERC1155BatchReceived selector is {batchSelector}"
  unless batchPlans.size == 1 && batchPlans[0]!.name == "onERC1155BatchReceived" &&
      batchPlans[0]!.kind == .call && batchPlans[0]!.policy == .magicBytes4 batchSelector &&
      batchPlans[0]!.args.size == 5 &&
      batchPlans[0]!.args[2]!.type == .array 4 .uint256 &&
      batchPlans[0]!.args[3]!.type == .array 4 .uint256 &&
      batchPlans[0]!.args[4]!.type == .bytes 8 &&
      batchPlans[0]!.usesCursor && batchPlans[0]!.inSize == 164 do
    throwError s!"notifyBatchReceiver plan diverged: {repr batchPlans}"

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
  unless yul.contains s!"shl(224, 0x{hookSelector}))) \{ revert(0, 0) }" do
    throwError "notifyReceiver Yul lost the magic equality gate"
  unless yul.contains s!"shl(224, 0x{batchSelector}))) \{ revert(0, 0) }" do
    throwError "notifyBatchReceiver Yul lost the magic equality gate"

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
  expectLimbs "hashBytes" .word
  expectLimbs "hashString" .word
  -- Both bytes paths send the canonical size: the static head plus the padded runtime length.
  unless yul.contains s!"shl(224, 0x{ProofForge.Evm.Keccak.selector "sink" #["uint256", "bytes"]})" &&
      yul.contains s!"shl(224, 0x{ProofForge.Evm.Keccak.selector "calldataHash" #["bytes"]})" &&
      yul.contains "mstore(36, 64)" && yul.contains ", 0, 0, add(100, " &&
      yul.contains "mstore(4, 32)" && yul.contains "staticcall(gas(), v0, 0, add(68, " &&
      yul.contains ":= and(add(" && yul.contains ", 31), not(31))" do
    throwError "open-call Yul omitted the bytes tail offset, size, or selector"
  unless yul.contains s!"shl(224, 0x{ProofForge.Evm.Keccak.selector "label" #["string"]})" &&
      yul.contains s!"shl(224, 0x{ProofForge.Evm.Keccak.selector "stringHash" #["string"]})" &&
      !yul.contains s!"shl(224, 0x{ProofForge.Evm.Keccak.selector "label" #["bytes"]})" &&
      yul.contains "let oc_utf8_need0 := 0" &&
      yul.contains "if oc_utf8_need0 { revert(0, 0) }" do
    throwError "open-call Yul omitted the string selector, used the bytes selector, or lost the UTF-8 guard"
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
  expectUnsupported env ``Unsupported.twoBytesArgs "at most one bytes or string argument"
  expectUnsupported env ``Unsupported.bytesAndString "at most one bytes or string argument"
  expectUnsupported env ``Unsupported.wideBytesArg "exceeds the bounded bytes capacity"

  -- A read in value position keeps the computation around it: the Bool read is the `ite`
  -- condition, the UInt256 read an operand of `ge256`, the Address read an operand of `eq20`,
  -- the inner read the outer read's argument. With the query scan descending into operator
  -- arguments, `covers` and `ownedBy` returned the read's limbs without the comparison.
  -- The canonical form is `evm|name|slots|ctor|entry/entry/…`; an indexed op prints a `/` of its
  -- own, so a split piece that does not open a new entry belongs to the previous one.
  let entryList := ((ProofForge.Evm.IR.canonical evm).splitOn "|").getLast?.getD ""
  let entries := (entryList.splitOn "/").foldl (init := (#[] : Array String)) fun acc piece =>
    if acc.isEmpty || ["view:", "mut:", "pay:"].any (fun tag => piece.startsWith tag) then
      acc.push piece
    else acc.modify (acc.size - 1) (· ++ "/" ++ piece)
  let expectCanon (ixName : String) (fragments : List String) : CommandElabM Unit := do
    let some entry := entries.find? fun segment => (segment.splitOn ":")[1]? == some ixName
      | throwError s!"EVM open-call example lost {ixName}"
    for fragment in fragments do
      unless entry.contains fragment do
        throwError s!"{ixName} canonical IR lost `{fragment}`:\n{entry}"
  let target := "f.w0(a0),f.w1(a0),f.w2(a0)"
  let isOn := s!"ocallq.0.0.ocall.static.bool.isOn({target};)"
  let balanceOfLimb (limb : Nat) : String :=
    s!"ocallq.0.{limb}.ocall.static.word1.balanceOf({target};a0:ProofForge.Core.Codec.Scalar.address 20(f.w0(a1),f.w1(a1),f.w2(a1)))"
  let ownerOfLimb (limb : Nat) : String :=
    s!"ocallq.0.{limb}.ocall.static.typed[a20].ownerOf({target};)"
  expectCanon "pingIfOn" [s!"ite.eq({isOn},l1,[ocall.call.ok.ping({target};)],[])"]
  expectCanon "echoIfOn"
    [s!"ite.eq({isOn},l1,[retu(ocallq.0.0.ocall.static.word1.echo({target};",
     "],[retu(l0);retu(l0);retu(l0);retu(l0)])"]
  expectCanon "covers"
    [":r1:1:[retu(ext.ProofForge.Evm.Ops.ValKind.ge256(" ++ balanceOfLimb 0 ++ "," ++
      balanceOfLimb 1 ++ "," ++ balanceOfLimb 2 ++ "," ++ balanceOfLimb 3 ++
      ",f.w0(a2),f.w1(a2),f.w2(a2),f.w3(a2)))]"]
  expectCanon "ownedBy"
    [":r1:1:[retu(ext.ProofForge.Evm.Ops.ValKind.eq20(" ++ ownerOfLimb 0 ++ "," ++
      ownerOfLimb 1 ++ "," ++ ownerOfLimb 2 ++ ",f.w0(a1),f.w1(a1),f.w2(a1)))]"]
  expectCanon "echoBalance"
    [s!"retu(ocallq.0.0.ocall.static.word1.echo({target};a0:ProofForge.Core.Codec.Scalar.uint 256(" ++
      balanceOfLimb 0 ++ "," ++ balanceOfLimb 1 ++ "," ++ balanceOfLimb 2 ++ "," ++
      balanceOfLimb 3 ++ ")))",
     s!"retu(ocallq.0.3.ocall.static.word1.echo({target};"]
  -- A CALL carrier anywhere but the result word is refused; the carrier in its homes keeps
  -- its plan.
  expectUnsupported env ``Tests.EvmOpenCallMisuse.compared "CALL carrier"
  expectUnsupported env ``Tests.EvmOpenCallMisuse.isZero "CALL carrier"
  expectUnsupported env ``Tests.EvmOpenCallMisuse.plusOne "CALL carrier"
  expectUnsupported env ``Tests.EvmOpenCallMisuse.stored "CALL carrier"
  expectUnsupported env ``Tests.EvmOpenCallMisuse.gated "CALL carrier"
  expectUnsupported env ``Tests.EvmOpenCallMisuse.readArg "CALL carrier"
  expectUnsupported env ``Tests.EvmOpenCallMisuse.callArg "CALL carrier"
  expectUnsupported env ``Tests.EvmOpenCallMisuse.valueCompared "CALL carrier"
  expectUnsupported env ``Tests.EvmOpenCallMisuse.thenTrueGated "CALL carrier"
  expectUnsupported env ``Tests.EvmOpenCallMisuse.thenTrueCompared "CALL carrier"
  expectUnsupported env ``Tests.EvmOpenCallMisuse.letDropped "CALL carrier"
  expectUnsupported env ``Tests.EvmOpenCallMisuse.letGuarded "CALL carrier"
  expectUnsupported env ``Tests.EvmOpenCallMisuse.magicCompared "CALL carrier"
  expectCallKept env ``CarrierWord.asBool
  expectCallKept env ``CarrierWord.ensured
  expectCallKept env ``CarrierWord.named

  logInfo s!"EvmOpenCall digest: {ProofForge.Evm.IR.digestHex evm}"

#pf_guard_evm_open_call_source

end Tests.EvmOpenCallSpec
