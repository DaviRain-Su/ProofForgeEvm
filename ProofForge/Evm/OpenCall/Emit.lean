import ProofForge.Evm.OpenCall
import ProofForge.Evm.CallResult.Emit
import ProofForge.Evm.Ops
import ProofForge.Evm.Codec
import ProofForge.Evm.Codec.Emit
import ProofForge.Evm.Keccak

namespace ProofForge.Evm.OpenCall.Emit

/-!
Emitter for typed open CALL/STATICCALL. Calldata is assembled from the plan at `memory[0, …)`:
selector, one head word per argument, then dynamic tails in declaration order. A plan with no
array keeps the historical geometry: at most one packed `bytes` or `string` tail (length word
and padded payload) whose offset is the compile-time head length. A plan with an array walks a
byte cursor so a later tail can follow a runtime-length prefix. The result gate is always
`CallResult.Emit.emitBound`, handed the tail's padded length or the cursor so the call sends
exactly the canonical calldata size. This is not a third result-policy interpreter.
`NativeFx.sendEth` is not lowered through this module.

Every operand is materialized before the first calldata word is stored. An operand that is
itself a read (`OpenCall.staticWord` as an argument) runs its own call through `memory[0, …)`,
and interleaving it with the stores would overwrite the selector and head words already written.
Array slots are packed into Yul locals in that same prelude, because packing an address or
fixed-bytes word uses `memory[0]` as scratch.
-/

private def nl : String := "\n"
private def revert0 : String := "revert(0, 0)"

private def packU256 (w0 w1 w2 w3 : String) : String :=
  Codec.Emit.packU256 w0 w1 w2 w3

structure Context (σ : Type) where
  materialize : Ops.Val → σ → Except String (String × String × σ)
  fresh : σ → String × σ
  rememberWide : σ → String → String → σ
  lookupWide : σ → String → Option String
  valKey : Ops.Val → String
  /-- The calldata payload offset when these limbs are one packed `bytes` entry parameter, so
  the tail is one `calldatacopy` instead of one store per byte. -/
  calldataBytes : Array Ops.Val → Option String := fun _ => none
  indent : String

private def Context.callResult (context : Context σ) : CallResult.Emit.Context σ :=
  { fresh := context.fresh, indent := context.indent }

private def materializeParts (context : Context σ) (parts : Array Ops.Val) (st : σ) :
    Except String (String × Array String × σ) := do
  let mut prelude := ""
  let mut exprs : Array String := #[]
  let mut st := st
  for part in parts do
    let (pre, expr, st') ← context.materialize part st
    prelude := prelude ++ pre
    exprs := exprs.push expr
    st := st'
  return (prelude, exprs, st)

/-- Store one ABI head word at `memory[offset, offset+32)` from an argument's materialized
limbs: the scalar value, or for a dynamic argument its tail offset, which is the head length
measured from the first argument word. Array plans do not use this for the offset word; they
write the cursor instead. -/
private def storeArg (indent : String) (offset headWords : Nat) (type : ArgType)
    (parts : Array String) : Except String String := do
  let .scalar type := type
    | return indent ++ "mstore(" ++ toString offset ++ ", " ++
        toString (CallResult.abiWordBytes * headWords) ++ ")" ++ nl
  if parts.isEmpty then
    throw "extract/unsupported: open-call argument has no limbs"
  if Codec.isAddressCarrier type then
    return indent ++ "pf_store_addr20(" ++ toString offset ++ ", " ++ parts[0]! ++ ", " ++
      (parts[1]?).getD "0" ++ ", " ++ (parts[2]?).getD "0" ++ ")" ++ nl
  else if Codec.isFixedBytesCarrier type then
    return indent ++ "pf_store_fixed_bytes(" ++ toString offset ++ ", " ++
      (parts[0]?).getD "0" ++ ", " ++ (parts[1]?).getD "0" ++ ", " ++
      (parts[2]?).getD "0" ++ ", " ++ (parts[3]?).getD "0" ++ ", " ++
      toString type.byteWidth ++ ")" ++ nl
  else if Codec.isWideIntegerCarrier type then
    let packed := packU256 (parts[0]!) ((parts[1]?).getD "0") ((parts[2]?).getD "0")
      ((parts[3]?).getD "0")
    return indent ++ "mstore(" ++ toString offset ++ ", " ++ packed ++ ")" ++ nl
  else if Codec.isNarrowIntegerCarrier type && parts.size == 1 then
    return indent ++ "mstore(" ++ toString offset ++ ", " ++ parts[0]! ++ ")" ++ nl
  else
    throw "extract/unsupported: open-call argument type has no EVM word carrier"

/-- Write the tail of one packed `bytes` / `string` argument at
`memory[tailAt, tailAt + 32 + ceil32(capacity))`: the runtime length, then the payload padded to
a word. Limbs that are exactly one packed-bytes entry parameter copy its padded payload from
calldata, whose padding the entry decoder proved zero. Any other limbs store only the first
`length` bytes over a zeroed region, so the calldata is canonical however the inactive source
slots read. Returns the Yul name bound to the padded payload length. -/
private def storeBytesTail (context : Context σ) (tailAt capacity : Nat) (limbs : Array Ops.Val)
    (parts : Array String) (st : σ) : Except String (String × String × σ) := do
  let indent := context.indent
  unless parts.size == 1 + capacity do
    throw "extract/unsupported: open-call bytes argument limbs do not match its capacity"
  let (len, st) := context.fresh st
  let dataAt := tailAt + CallResult.abiWordBytes
  let mut txt :=
    indent ++ "let " ++ len ++ " := " ++ parts[0]! ++ nl ++
    indent ++ "if gt(" ++ len ++ ", " ++ toString capacity ++ ") { " ++ revert0 ++ " }" ++ nl ++
    indent ++ "mstore(" ++ toString tailAt ++ ", " ++ len ++ ")" ++ nl
  let (padded, st) := context.fresh st
  let paddedLet :=
    indent ++ "let " ++ padded ++ " := and(add(" ++ len ++ ", 31), not(31))" ++ nl
  if let some payload := context.calldataBytes limbs then
    txt := txt ++ paddedLet ++
      indent ++ "calldatacopy(" ++ toString dataAt ++ ", " ++ payload ++ ", " ++ padded ++ ")" ++ nl
    return (txt, padded, st)
  for word in [0:(capacity + 31) / 32] do
    txt := txt ++ indent ++ "mstore(" ++ toString (dataAt + word * 32) ++ ", 0)" ++ nl
  for i in [0:capacity] do
    txt := txt ++
      indent ++ "if gt(" ++ len ++ ", " ++ toString i ++ ") { mstore8(" ++
        toString (dataAt + i) ++ ", " ++ parts[1 + i]! ++ ") }" ++ nl
  return (txt ++ paddedLet, padded, st)

/-- Bind one already-materialized scalar to an ABI word. Address and fixed-bytes packing may
use `memory[0]` as scratch, so this runs before the selector is stored. -/
private def bindArgWord (context : Context σ) (type : Core.Codec.Scalar) (parts : Array String)
    (st : σ) : Except String (String × String × σ) := do
  let indent := context.indent
  if parts.isEmpty then
    throw "extract/unsupported: open-call argument has no limbs"
  if Codec.isAddressCarrier type then
    let (word, st') := context.fresh st
    return (Codec.Emit.bindAddrWord indent word (parts[0]!) ((parts[1]?).getD "0")
      ((parts[2]?).getD "0"), word, st')
  else if Codec.isFixedBytesCarrier type then
    let (word, st') := context.fresh st
    let txt :=
      indent ++ "mstore(0, 0)" ++ nl ++
      indent ++ "pf_store_fixed_bytes(0, " ++ (parts[0]?).getD "0" ++ ", " ++
        (parts[1]?).getD "0" ++ ", " ++ (parts[2]?).getD "0" ++ ", " ++
        (parts[3]?).getD "0" ++ ", " ++ toString type.byteWidth ++ ")" ++ nl ++
      indent ++ "let " ++ word ++ " := mload(0)" ++ nl
    return (txt, word, st')
  else if Codec.isWideIntegerCarrier type then
    let (word, st') := context.fresh st
    let packed := packU256 (parts[0]!) ((parts[1]?).getD "0") ((parts[2]?).getD "0")
      ((parts[3]?).getD "0")
    return (indent ++ "let " ++ word ++ " := " ++ packed ++ nl, word, st')
  else if Codec.isNarrowIntegerCarrier type && parts.size == 1 then
    return ("", parts[0]!, st)
  else
    throw "extract/unsupported: open-call array element type has no EVM word carrier"

/-- Pack every slot of one array argument into ABI words. The length limb stays in `parts[0]`. -/
private def packArraySlots (context : Context σ) (element : Core.Codec.Scalar) (capacity : Nat)
    (parts : Array String) (st : σ) : Except String (String × Array String × σ) := do
  let limbs := Codec.limbCount element
  unless parts.size == 1 + capacity * limbs do
    throw "extract/unsupported: open-call array argument limbs do not match its capacity"
  let mut txt := ""
  let mut words : Array String := #[]
  let mut st := st
  for slot in [0:capacity] do
    let slotParts := parts.extract (1 + slot * limbs) (1 + (slot + 1) * limbs)
    let (pre, word, st') ← bindArgWord context element slotParts st
    txt := txt ++ pre
    words := words.push word
    st := st'
  return (txt, words, st)

/-- Write one `uint256[]`-shaped tail at the cursor and advance the cursor by
`(length + 1) · 32`. -/
private def storeArrayTailAt (indent cursor : String) (capacity : Nat) (len : String)
    (slots : Array String) : String := Id.run do
  let mut txt :=
    indent ++ "if gt(" ++ len ++ ", " ++ toString capacity ++ ") { " ++ revert0 ++ " }" ++ nl ++
    indent ++ "mstore(" ++ cursor ++ ", " ++ len ++ ")" ++ nl
  for slot in [0:capacity] do
    txt := txt ++ indent ++ "if gt(" ++ len ++ ", " ++ toString slot ++ ") { mstore(add(" ++
      cursor ++ ", " ++ toString (CallResult.abiWordBytes * (slot + 1)) ++ "), " ++
      slots[slot]! ++ ") }" ++ nl
  txt ++ indent ++ cursor ++ " := add(" ++ cursor ++ ", mul(add(" ++ len ++ ", 1), " ++
    toString CallResult.abiWordBytes ++ "))" ++ nl

/-- Write one `bytes` tail at the cursor and advance the cursor by `32 + ceil32(length)`. -/
private def storeBytesTailAt (context : Context σ) (cursor : String) (capacity : Nat)
    (limbs : Array Ops.Val) (parts : Array String) (st : σ) : Except String (String × σ) := do
  let indent := context.indent
  unless parts.size == 1 + capacity do
    throw "extract/unsupported: open-call bytes argument limbs do not match its capacity"
  let (len, st) := context.fresh st
  let mut txt :=
    indent ++ "let " ++ len ++ " := " ++ parts[0]! ++ nl ++
    indent ++ "if gt(" ++ len ++ ", " ++ toString capacity ++ ") { " ++ revert0 ++ " }" ++ nl ++
    indent ++ "mstore(" ++ cursor ++ ", " ++ len ++ ")" ++ nl
  let (padded, st) := context.fresh st
  let paddedLet :=
    indent ++ "let " ++ padded ++ " := and(add(" ++ len ++ ", 31), not(31))" ++ nl
  if let some payload := context.calldataBytes limbs then
    txt := txt ++ paddedLet ++
      indent ++ "calldatacopy(add(" ++ cursor ++ ", 32), " ++ payload ++ ", " ++ padded ++ ")" ++
        nl ++
      indent ++ cursor ++ " := add(" ++ cursor ++ ", add(32, " ++ padded ++ "))" ++ nl
    return (txt, st)
  for word in [0:(capacity + 31) / 32] do
    txt := txt ++ indent ++ "mstore(add(" ++ cursor ++ ", " ++
      toString (CallResult.abiWordBytes * (word + 1)) ++ "), 0)" ++ nl
  for i in [0:capacity] do
    txt := txt ++
      indent ++ "if gt(" ++ len ++ ", " ++ toString i ++ ") { mstore8(add(" ++ cursor ++
        ", " ++ toString (CallResult.abiWordBytes + i) ++ "), " ++ parts[1 + i]! ++ ") }" ++ nl
  return (txt ++ paddedLet ++ indent ++ cursor ++ " := add(" ++ cursor ++ ", add(32, " ++
    padded ++ "))" ++ nl, st)

private def planCacheKey (context : Context σ) (plan : OpenCall.Plan Ops.Val) (word : Nat) :
    String :=
  "ocall|" ++ plan.canonical context.valKey ++ "|w" ++ toString word

/-- Assemble calldata and apply the shared `CallResult` interpreter: materialize the target,
every argument's limbs, and the value, then store the selector, head, and tail. -/
def emitPlan (context : Context σ) (plan : OpenCall.Plan Ops.Val) (st : σ) :
    Except String (String × CallResult.Emit.Bound × σ) := do
  unless plan.wellFormed (·.wellFormed Ops.ValKind.arity) do
    throw "extract/unsupported: malformed open-call plan"
  let selector ← plan.selectorHex (·.wellFormed Ops.ValKind.arity)
  let indent := context.indent
  if plan.target.size != 3 then
    throw "extract/unsupported: open-call target is not Addr20"
  if plan.sendsValue && plan.valueParts.size != 4 then
    throw "extract/unsupported: open-call value is not UInt256"
  let (targetPre, target, st) ← materializeParts context plan.target st
  let mut txt := targetPre
  let mut st := st
  let mut args : Array (Array String) := #[]
  for arg in plan.args do
    let (pre, parts, st') ← materializeParts context arg.parts st
    txt := txt ++ pre
    args := args.push parts
    st := st'
  let (valuePre, value, st') ← materializeParts context plan.valueParts st
  txt := txt ++ valuePre
  st := st'
  let mut arraySlots : Array (Array String) := #[]
  if plan.usesCursor then
    for i in [0:plan.args.size] do
      match plan.args[i]!.type with
      | .array capacity element =>
          let (pre, words, st') ← packArraySlots context element capacity args[i]! st
          txt := txt ++ pre
          arraySlots := arraySlots.push words
          st := st'
      | _ =>
          arraySlots := arraySlots.push #[]
  let (tok, st') := context.fresh st
  st := st'
  txt := txt ++
    indent ++ "if shr(32, " ++ target[2]! ++ ") { " ++ revert0 ++ " }" ++ nl ++
    indent ++ "mstore(0, 0)" ++ nl ++
    indent ++ "pf_store_addr20(0, " ++ target[0]! ++ ", " ++ target[1]! ++ ", " ++
      target[2]! ++ ")" ++ nl ++
    indent ++ "let " ++ tok ++ " := mload(0)" ++ nl ++
    indent ++ "mstore(0, shl(224, 0x" ++ selector ++ "))" ++ nl
  let mut inSizeTail : Option String := none
  let mut inSizeExpr : Option String := none
  if !plan.usesCursor then
    for i in [0:plan.args.size] do
      txt := txt ++ (← storeArg indent (CallResult.selectorBytes + CallResult.abiWordBytes * i)
        plan.args.size plan.args[i]!.type args[i]!)
    if let some i := plan.args.findIdx? (·.type.isDynamic) then
      let capacity ←
        match plan.args[i]!.type with
        | .bytes n | .string n => pure n
        | _ => throw "extract/unsupported: open-call packed argument lost its capacity"
      let (tailTxt, padded, st') ←
        storeBytesTail context plan.headBytes capacity plan.args[i]!.parts args[i]! st
      txt := txt ++ tailTxt
      inSizeTail := some padded
      st := st'
  else
    let (cursor, st') := context.fresh st
    st := st'
    txt := txt ++ indent ++ "let " ++ cursor ++ " := " ++ toString plan.headBytes ++ nl
    for i in [0:plan.args.size] do
      let offset := CallResult.selectorBytes + CallResult.abiWordBytes * i
      match plan.args[i]!.type with
      | .scalar _ =>
          txt := txt ++ (← storeArg indent offset plan.args.size plan.args[i]!.type args[i]!)
      | .bytes capacity | .string capacity =>
          txt := txt ++ indent ++ "mstore(" ++ toString offset ++ ", sub(" ++ cursor ++
            ", 4))" ++ nl
          let (tailTxt, st') ←
            storeBytesTailAt context cursor capacity plan.args[i]!.parts args[i]! st
          txt := txt ++ tailTxt
          st := st'
      | .array capacity _ =>
          txt := txt ++ indent ++ "mstore(" ++ toString offset ++ ", sub(" ++ cursor ++
            ", 4))" ++ nl
          let (len, st') := context.fresh st
          st := st'
          txt := txt ++ indent ++ "let " ++ len ++ " := " ++ args[i]![0]! ++ nl
          txt := txt ++ storeArrayTailAt indent cursor capacity len arraySlots[i]!
    inSizeExpr := some cursor
  let mut valueExpr : Option String := none
  if plan.sendsValue then
    let (amt, st') := context.fresh st
    txt := txt ++ indent ++ "let " ++ amt ++ " := " ++
      packU256 (value[0]!) ((value[1]?).getD "0") ((value[2]?).getD "0")
        ((value[3]?).getD "0") ++ nl
    valueExpr := some amt
    st := st'
  let (callTxt, bound, st') ← CallResult.Emit.emitBound context.callResult
    plan.request tok valueExpr st inSizeTail inSizeExpr
  return (txt ++ callTxt, bound, st')

def emitCall (context : Context σ) (call : OpenCall.Call Ops.Val) (st : σ) :
    Except String (String × String × σ) := do
  match call with
  | .invoke plan =>
      let (txt, bound, st') ← emitPlan context plan st
      return (txt, bound.word.getD "0", st')

def emitQuery (context : Context σ) (query : OpenCall.Query) (operands : Array Ops.Val)
    (st : σ) : Except String (String × String × σ) := do
  unless query.wellFormed do
    throw "extract/unsupported: malformed open-call query"
  let some plan := query.toPlan operands
    | throw "extract/unsupported: open-call query arity"
  unless plan.wellFormed (·.wellFormed Ops.ValKind.arity) do
    throw "extract/unsupported: malformed open-call plan"
  let some kind := plan.policy.wordKinds[query.word]?
    | throw "extract/unsupported: open-call query missing result word"
  let limbOf (word : String) : String := CallResult.Emit.wordLimb kind word query.limb
  let cacheKey := planCacheKey context plan query.word
  match context.lookupWide st cacheKey with
  | some ret =>
      let (nm, st') := context.fresh st
      return (context.indent ++ "let " ++ nm ++ " := " ++ limbOf ret ++ nl, nm, st')
  | none =>
      let (txt, bound, st1) ← emitPlan context plan st
      let some word := bound.names[query.word]?
        | throw "extract/unsupported: open-call query missing result word"
      let st2 := context.rememberWide st1 cacheKey word
      let (nm, st3) := context.fresh st2
      return (txt ++ context.indent ++ "let " ++ nm ++ " := " ++ limbOf word ++ nl, nm, st3)

end ProofForge.Evm.OpenCall.Emit
