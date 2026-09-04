import ProofForge.Evm.OpenCall
import ProofForge.Evm.CallResult.Emit
import ProofForge.Evm.Ops
import ProofForge.Evm.Codec
import ProofForge.Evm.Codec.Emit
import ProofForge.Evm.Keccak

namespace ProofForge.Evm.OpenCall.Emit

/-!
Emitter for typed open CALL/STATICCALL. Calldata is assembled from the plan; the result
gate is always `CallResult.Emit.emitBound`. This is not a third result-policy interpreter.
`NativeFx.sendEth` is not lowered through this module.
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

/-- Store one ABI argument word at `memory[offset, offset+32)`. -/
private def storeArg (context : Context σ) (offset : Nat) (arg : OpenCall.Arg Ops.Val)
    (st : σ) : Except String (String × σ) := do
  let indent := context.indent
  let (prelude, parts, st) ← materializeParts context arg.parts st
  if parts.isEmpty then
    throw "extract/unsupported: open-call argument has no limbs"
  if Codec.isAddressCarrier arg.type then
    return (prelude ++
      indent ++ "pf_store_addr20(" ++ toString offset ++ ", " ++ parts[0]! ++ ", " ++
        (parts[1]?).getD "0" ++ ", " ++ (parts[2]?).getD "0" ++ ")" ++ nl, st)
  else if Codec.isFixedBytesCarrier arg.type then
    return (prelude ++
      indent ++ "pf_store_fixed_bytes(" ++ toString offset ++ ", " ++
        (parts[0]?).getD "0" ++ ", " ++ (parts[1]?).getD "0" ++ ", " ++
        (parts[2]?).getD "0" ++ ", " ++ (parts[3]?).getD "0" ++ ", " ++
        toString arg.type.byteWidth ++ ")" ++ nl, st)
  else if Codec.isWideIntegerCarrier arg.type then
    let packed := packU256 (parts[0]!) ((parts[1]?).getD "0") ((parts[2]?).getD "0")
      ((parts[3]?).getD "0")
    return (prelude ++ indent ++ "mstore(" ++ toString offset ++ ", " ++ packed ++ ")" ++ nl, st)
  else if Codec.isNarrowIntegerCarrier arg.type && parts.size == 1 then
    return (prelude ++ indent ++ "mstore(" ++ toString offset ++ ", " ++ parts[0]! ++ ")" ++ nl, st)
  else
    throw "extract/unsupported: open-call argument type has no EVM word carrier"

private def planCacheKey (context : Context σ) (plan : OpenCall.Plan Ops.Val) (word : Nat) :
    String :=
  "ocall|" ++ plan.canonical context.valKey ++ "|w" ++ toString word

/-- Assemble calldata and apply the shared `CallResult` interpreter. -/
def emitPlan (context : Context σ) (plan : OpenCall.Plan Ops.Val) (st : σ) :
    Except String (String × CallResult.Emit.Bound × σ) := do
  unless plan.wellFormed (·.wellFormed Ops.ValKind.arity) do
    throw "extract/unsupported: malformed open-call plan"
  let selector ← plan.selectorHex (·.wellFormed Ops.ValKind.arity)
  let indent := context.indent
  if plan.target.size != 3 then
    throw "extract/unsupported: open-call target is not Addr20"
  let (p0, t0, s0) ← context.materialize plan.target[0]! st
  let (p1, t1, s1) ← context.materialize plan.target[1]! s0
  let (p2, t2, s2) ← context.materialize plan.target[2]! s1
  let (tok, s3) := context.fresh s2
  let mut txt := p0 ++ p1 ++ p2 ++
    indent ++ "if shr(32, " ++ t2 ++ ") { " ++ revert0 ++ " }" ++ nl ++
    indent ++ "mstore(0, 0)" ++ nl ++
    indent ++ "pf_store_addr20(0, " ++ t0 ++ ", " ++ t1 ++ ", " ++ t2 ++ ")" ++ nl ++
    indent ++ "let " ++ tok ++ " := mload(0)" ++ nl ++
    indent ++ "mstore(0, shl(224, 0x" ++ selector ++ "))" ++ nl
  let mut st := s3
  for i in [0:plan.args.size] do
    let (argTxt, st') ← storeArg context (CallResult.selectorBytes + CallResult.abiWordBytes * i)
      plan.args[i]! st
    txt := txt ++ argTxt
    st := st'
  let mut valueExpr : Option String := none
  if plan.sendsValue then
    if plan.valueParts.size != 4 then
      throw "extract/unsupported: open-call value is not UInt256"
    let (vp, parts, stV) ← materializeParts context plan.valueParts st
    let (amt, stA) := context.fresh stV
    txt := txt ++ vp ++ indent ++ "let " ++ amt ++ " := " ++
      packU256 (parts[0]!) ((parts[1]?).getD "0") ((parts[2]?).getD "0")
        ((parts[3]?).getD "0") ++ nl
    valueExpr := some amt
    st := stA
  let (callTxt, bound, st') ← CallResult.Emit.emitBound context.callResult
    plan.request tok valueExpr st
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
