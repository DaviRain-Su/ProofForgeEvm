import ProofForge.Evm.WideWord
import ProofForge.Evm.Ops
import ProofForge.Evm.Codec.Emit
import ProofForge.Evm.CallResult.Emit
import ProofForge.Evm.Precompile.Emit

namespace ProofForge.Evm.WideWord.Emit

private def nl : String := "\n"
private def u64MaxYul : String := "0xffffffffffffffff"
private def revert0 : String := "revert(0, 0)"

private def packU256 (w0 w1 w2 w3 : String) : String :=
  Codec.Emit.packU256 w0 w1 w2 w3

private def packU256Word (src : String) (word : Nat) : String :=
  Codec.Emit.packU256Word src word

/-- Shared with hashed-map emission so the main emitter can pass one context record. -/
structure Context (σ : Type) where
  materialize : Ops.Val → σ → Except String (String × String × σ)
  fresh : σ → String × σ
  rememberWide : σ → String → String → σ
  lookupWide : σ → String → Option String
  valKey : Ops.Val → String
  indent : String

private def compareExpr (comparison : WideWord.Comparison) (left right : String) : String :=
  match comparison with
  | .eq => "eq(" ++ left ++ ", " ++ right ++ ")"
  | .lt => "lt(" ++ left ++ ", " ++ right ++ ")"
  | .le => "iszero(gt(" ++ left ++ ", " ++ right ++ "))"
  | .gt => "gt(" ++ left ++ ", " ++ right ++ ")"
  | .ge => "iszero(lt(" ++ left ++ ", " ++ right ++ "))"

private def emitCompare256 (context : Context σ) (comparison : WideWord.Comparison)
    (a0 a1 a2 a3 b0 b1 b2 b3 : Ops.Val) (st : σ) :
    Except String (String × String × σ) := do
  let indent := context.indent
  let (p0, x0, s0) ← context.materialize a0 st
  let (p1, x1, s1) ← context.materialize a1 s0
  let (p2, x2, s2) ← context.materialize a2 s1
  let (p3, x3, s3) ← context.materialize a3 s2
  let (q0, y0, t0) ← context.materialize b0 s3
  let (q1, y1, t1) ← context.materialize b1 t0
  let (q2, y2, t2) ← context.materialize b2 t1
  let (q3, y3, t3) ← context.materialize b3 t2
  let (av, t4) := context.fresh t3
  let (bv, t5) := context.fresh t4
  let (nm, t6) := context.fresh t5
  let txt := p0 ++ p1 ++ p2 ++ p3 ++ q0 ++ q1 ++ q2 ++ q3 ++
    indent ++ "let " ++ av ++ " := " ++ packU256 x0 x1 x2 x3 ++ nl ++
    indent ++ "let " ++ bv ++ " := " ++ packU256 y0 y1 y2 y3 ++ nl ++
    indent ++ "let " ++ nm ++ " := " ++ compareExpr comparison av bv ++ nl
  return (txt, nm, t6)

private def emitEq20 (context : Context σ)
    (a0 a1 a2 b0 b1 b2 : Ops.Val) (st : σ) :
    Except String (String × String × σ) := do
  let indent := context.indent
  let (p0, x0, s0) ← context.materialize a0 st
  let (p1, x1, s1) ← context.materialize a1 s0
  let (p2, x2, s2) ← context.materialize a2 s1
  let (q0, y0, t0) ← context.materialize b0 s2
  let (q1, y1, t1) ← context.materialize b1 t0
  let (q2, y2, t2) ← context.materialize b2 t1
  let (av, t3) := context.fresh t2
  let (bv, t4) := context.fresh t3
  let (nm, t5) := context.fresh t4
  let txt := p0 ++ p1 ++ p2 ++ q0 ++ q1 ++ q2 ++
    Codec.Emit.bindAddrWord indent av x0 x1 x2 ++
    Codec.Emit.bindAddrWord indent bv y0 y1 y2 ++
    indent ++ "let " ++ nm ++ " := eq(" ++ av ++ ", " ++ bv ++ ")" ++ nl
  return (txt, nm, t5)

/-- Compare the canonical left-aligned ABI words produced for two `bytes4` values. -/
private def emitEqBytes4 (context : Context σ) (left right : Ops.Val) (st : σ) :
    Except String (String × String × σ) := do
  let indent := context.indent
  let (leftPrefix, leftValue, st1) ← context.materialize left st
  let (rightPrefix, rightValue, st2) ← context.materialize right st1
  let (name, st3) := context.fresh st2
  return (leftPrefix ++ rightPrefix ++
    indent ++ "let " ++ name ++ " := eq(" ++ leftValue ++ ", " ++ rightValue ++ ")" ++ nl,
    name, st3)

private def bitwiseExpr (operation : WideWord.Bitwise) (left right : String) : String :=
  match operation with
  | .and => "and(" ++ left ++ ", " ++ right ++ ")"
  | .or => "or(" ++ left ++ ", " ++ right ++ ")"
  | .xor => "xor(" ++ left ++ ", " ++ right ++ ")"

private def emitPackedBinary256 (context : Context σ) (cacheIdentity : String)
    (operation : String → String → String) (rejectZeroRight : Bool) (limb : Nat)
    (a0 a1 a2 a3 b0 b1 b2 b3 : Ops.Val) (st : σ) :
    Except String (String × String × σ) := do
  let indent := context.indent
  let (p0, x0, s0) ← context.materialize a0 st
  let (p1, x1, s1) ← context.materialize a1 s0
  let (p2, x2, s2) ← context.materialize a2 s1
  let (p3, x3, s3) ← context.materialize a3 s2
  let (q0, y0, t0) ← context.materialize b0 s3
  let (q1, y1, t1) ← context.materialize b1 t0
  let (q2, y2, t2) ← context.materialize b2 t1
  let (q3, y3, t3) ← context.materialize b3 t2
  let cacheKey :=
    cacheIdentity ++ "|" ++ context.valKey a0 ++ "|" ++
      context.valKey a1 ++ "|" ++ context.valKey a2 ++ "|" ++ context.valKey a3 ++ "|" ++
      context.valKey b0 ++ "|" ++ context.valKey b1 ++ "|" ++ context.valKey b2 ++ "|" ++
      context.valKey b3
  let pre := p0 ++ p1 ++ p2 ++ p3 ++ q0 ++ q1 ++ q2 ++ q3
  match context.lookupWide t3 cacheKey with
  | some rv =>
      let (nm, t4) := context.fresh t3
      return (pre ++ indent ++ "let " ++ nm ++ " := " ++ packU256Word rv limb ++ nl, nm, t4)
  | none =>
      let (av, t4) := context.fresh t3
      let (bv, t5) := context.fresh t4
      let (rv, t6) := context.fresh t5
      let (nm, t7) := context.fresh (context.rememberWide t6 cacheKey rv)
      let txt := pre ++
        indent ++ "let " ++ av ++ " := " ++ packU256 x0 x1 x2 x3 ++ nl ++
        indent ++ "let " ++ bv ++ " := " ++ packU256 y0 y1 y2 y3 ++ nl ++
        (if rejectZeroRight then indent ++ "if iszero(" ++ bv ++ ") { " ++ revert0 ++ " }" ++ nl
          else "") ++
        indent ++ "let " ++ rv ++ " := " ++ operation av bv ++ nl ++
        indent ++ "let " ++ nm ++ " := " ++ packU256Word rv limb ++ nl
      return (txt, nm, t7)

private def emitBitwise256 (context : Context σ) (operation : WideWord.Bitwise) (limb : Nat)
    (a0 a1 a2 a3 b0 b1 b2 b3 : Ops.Val) (st : σ) :
    Except String (String × String × σ) :=
  emitPackedBinary256 context ("bitwise256|" ++ toString (repr operation))
    (bitwiseExpr operation) false limb a0 a1 a2 a3 b0 b1 b2 b3 st

private def emitCheckedDivMod256 (context : Context σ) (operation : WideWord.Division) (limb : Nat)
    (a0 a1 a2 a3 b0 b1 b2 b3 : Ops.Val) (st : σ) :
    Except String (String × String × σ) :=
  let expr :=
    match operation with
    | .quotient => fun left right => "div(" ++ left ++ ", " ++ right ++ ")"
    | .remainder => fun left right => "mod(" ++ left ++ ", " ++ right ++ ")"
  emitPackedBinary256 context ("checkedDivMod256|" ++ toString (repr operation)) expr true limb
    a0 a1 a2 a3 b0 b1 b2 b3 st

private def emitNot256 (context : Context σ) (limb : Nat)
    (a0 a1 a2 a3 : Ops.Val) (st : σ) : Except String (String × String × σ) := do
  let indent := context.indent
  let (p0, x0, s0) ← context.materialize a0 st
  let (p1, x1, s1) ← context.materialize a1 s0
  let (p2, x2, s2) ← context.materialize a2 s1
  let (p3, x3, s3) ← context.materialize a3 s2
  let cacheKey :=
    "not256|" ++ context.valKey a0 ++ "|" ++ context.valKey a1 ++ "|" ++
      context.valKey a2 ++ "|" ++ context.valKey a3
  let pre := p0 ++ p1 ++ p2 ++ p3
  match context.lookupWide s3 cacheKey with
  | some rv =>
      let (nm, s4) := context.fresh s3
      return (pre ++ indent ++ "let " ++ nm ++ " := " ++ packU256Word rv limb ++ nl, nm, s4)
  | none =>
      let (av, s4) := context.fresh s3
      let (rv, s5) := context.fresh s4
      let (nm, s6) := context.fresh (context.rememberWide s5 cacheKey rv)
      let txt := pre ++
        indent ++ "let " ++ av ++ " := " ++ packU256 x0 x1 x2 x3 ++ nl ++
        indent ++ "let " ++ rv ++ " := not(" ++ av ++ ")" ++ nl ++
        indent ++ "let " ++ nm ++ " := " ++ packU256Word rv limb ++ nl
      return (txt, nm, s6)

private def emitShift256 (context : Context σ) (direction : WideWord.Shift) (limb : Nat)
    (a0 a1 a2 a3 amount : Ops.Val) (st : σ) : Except String (String × String × σ) := do
  let indent := context.indent
  let (p0, x0, s0) ← context.materialize a0 st
  let (p1, x1, s1) ← context.materialize a1 s0
  let (p2, x2, s2) ← context.materialize a2 s1
  let (p3, x3, s3) ← context.materialize a3 s2
  let (pb, bits, s4) ← context.materialize amount s3
  let cacheKey :=
    "shift256|" ++ toString (repr direction) ++ "|" ++ context.valKey a0 ++ "|" ++
      context.valKey a1 ++ "|" ++ context.valKey a2 ++ "|" ++ context.valKey a3 ++ "|" ++
      context.valKey amount
  let pre := p0 ++ p1 ++ p2 ++ p3 ++ pb
  match context.lookupWide s4 cacheKey with
  | some rv =>
      let (nm, s5) := context.fresh s4
      return (pre ++ indent ++ "let " ++ nm ++ " := " ++ packU256Word rv limb ++ nl, nm, s5)
  | none =>
      let (av, s5) := context.fresh s4
      let (rv, s6) := context.fresh s5
      let (nm, s7) := context.fresh (context.rememberWide s6 cacheKey rv)
      let shift :=
        match direction with
        | .left => "shl(" ++ bits ++ ", " ++ av ++ ")"
        | .right => "shr(" ++ bits ++ ", " ++ av ++ ")"
      let txt := pre ++
        indent ++ "let " ++ av ++ " := " ++ packU256 x0 x1 x2 x3 ++ nl ++
        indent ++ "let " ++ rv ++ " := " ++ shift ++ nl ++
        indent ++ "let " ++ nm ++ " := " ++ packU256Word rv limb ++ nl
      return (txt, nm, s7)

private def emitArith256 (context : Context σ) (op limb : Nat)
    (a0 a1 a2 a3 b0 b1 b2 b3 : Ops.Val) (st : σ) :
    Except String (String × String × σ) := do
  let indent := context.indent
  let (p0, x0, s0) ← context.materialize a0 st
  let (p1, x1, s1) ← context.materialize a1 s0
  let (p2, x2, s2) ← context.materialize a2 s1
  let (p3, x3, s3) ← context.materialize a3 s2
  let (q0, y0, t0) ← context.materialize b0 s3
  let (q1, y1, t1) ← context.materialize b1 t0
  let (q2, y2, t2) ← context.materialize b2 t1
  let (q3, y3, t3) ← context.materialize b3 t2
  let cacheKey :=
    "arith256|" ++ toString op ++ "|" ++ context.valKey a0 ++ "|" ++ context.valKey a1 ++ "|" ++
      context.valKey a2 ++ "|" ++ context.valKey a3 ++ "|" ++ context.valKey b0 ++ "|" ++
      context.valKey b1 ++ "|" ++ context.valKey b2 ++ "|" ++ context.valKey b3
  match context.lookupWide t3 cacheKey with
  | some rv =>
      let (nm, t4) := context.fresh t3
      return (p0 ++ p1 ++ p2 ++ p3 ++ q0 ++ q1 ++ q2 ++ q3 ++
        indent ++ "let " ++ nm ++ " := " ++ packU256Word rv limb ++ nl, nm, t4)
  | none =>
      let (av, t4) := context.fresh t3
      let (bv, t5) := context.fresh t4
      let (rv, t6) := context.fresh t5
      let (nm, t7) := context.fresh (context.rememberWide t6 cacheKey rv)
      let packedA := packU256 x0 x1 x2 x3
      let packedB := packU256 y0 y1 y2 y3
      let overflow :=
        match op with
        | 0 => "lt(" ++ rv ++ ", " ++ av ++ ")"
        | 1 => "gt(" ++ bv ++ ", " ++ av ++ ")"
        | _ => "and(iszero(iszero(" ++ bv ++ ")), iszero(eq(" ++ av ++ ", div(" ++ rv ++ ", " ++ bv ++ "))))"
      let arith :=
        match op with
        | 0 => "add(" ++ av ++ ", " ++ bv ++ ")"
        | 1 => "sub(" ++ av ++ ", " ++ bv ++ ")"
        | _ => "mul(" ++ av ++ ", " ++ bv ++ ")"
      let txt := p0 ++ p1 ++ p2 ++ p3 ++ q0 ++ q1 ++ q2 ++ q3 ++
        indent ++ "let " ++ av ++ " := " ++ packedA ++ nl ++
        indent ++ "let " ++ bv ++ " := " ++ packedB ++ nl ++
        indent ++ "let " ++ rv ++ " := " ++ arith ++ nl ++
        indent ++ "if " ++ overflow ++ " { " ++ revert0 ++ " }" ++ nl ++
        indent ++ "let " ++ nm ++ " := " ++ packU256Word rv limb ++ nl
      return (txt, nm, t7)

private def emitKeccak256Pair32 (context : Context σ) (limb : Nat)
    (a0 a1 a2 a3 b0 b1 b2 b3 : Ops.Val) (st : σ) :
    Except String (String × String × σ) := do
  let indent := context.indent
  let (p0, x0, s0) ← context.materialize a0 st
  let (p1, x1, s1) ← context.materialize a1 s0
  let (p2, x2, s2) ← context.materialize a2 s1
  let (p3, x3, s3) ← context.materialize a3 s2
  let (q0, y0, t0) ← context.materialize b0 s3
  let (q1, y1, t1) ← context.materialize b1 t0
  let (q2, y2, t2) ← context.materialize b2 t1
  let (q3, y3, t3) ← context.materialize b3 t2
  let cacheKey :=
    "keccak256Pair32|" ++ context.valKey a0 ++ "|" ++ context.valKey a1 ++ "|" ++
      context.valKey a2 ++ "|" ++ context.valKey a3 ++ "|" ++ context.valKey b0 ++ "|" ++
      context.valKey b1 ++ "|" ++ context.valKey b2 ++ "|" ++ context.valKey b3
  match context.lookupWide t3 cacheKey with
  | some rv =>
      let (nm, t4) := context.fresh t3
      return (p0 ++ p1 ++ p2 ++ p3 ++ q0 ++ q1 ++ q2 ++ q3 ++
        indent ++ "let " ++ nm ++ " := " ++ packU256Word rv limb ++ nl, nm, t4)
  | none =>
      let (lv, t4) := context.fresh t3
      let (sv, t5) := context.fresh t4
      let (left, t6) := context.fresh t5
      let (right, t7) := context.fresh t6
      let (hash, t8) := context.fresh t7
      let (nm, t9) := context.fresh t8
      let txt := p0 ++ p1 ++ p2 ++ p3 ++ q0 ++ q1 ++ q2 ++ q3 ++
        indent ++ "pf_store_fixed_bytes(0, " ++ x0 ++ ", " ++ x1 ++ ", " ++ x2 ++ ", " ++ x3 ++ ", 32)" ++ nl ++
        indent ++ "pf_store_fixed_bytes(32, " ++ y0 ++ ", " ++ y1 ++ ", " ++ y2 ++ ", " ++ y3 ++ ", 32)" ++ nl ++
        indent ++ "let " ++ lv ++ " := mload(0)" ++ nl ++
        indent ++ "let " ++ sv ++ " := mload(32)" ++ nl ++
        indent ++ "let " ++ left ++ " := " ++ lv ++ nl ++
        indent ++ "let " ++ right ++ " := " ++ sv ++ nl ++
        indent ++ "if gt(" ++ left ++ ", " ++ right ++ ") {" ++ nl ++
        indent ++ "  " ++ left ++ " := " ++ sv ++ nl ++
        indent ++ "  " ++ right ++ " := " ++ lv ++ nl ++
        indent ++ "}" ++ nl ++
        indent ++ "mstore(0, " ++ left ++ ")" ++ nl ++
        indent ++ "mstore(32, " ++ right ++ ")" ++ nl ++
        indent ++ "let " ++ hash ++ " := keccak256(0, 64)" ++ nl ++
        indent ++ "let " ++ nm ++ " := " ++ packU256Word hash limb ++ nl
      return (txt, nm, context.rememberWide t9 hash cacheKey)

private def emitMerkleVerify256 (context : Context σ) (operands : Array Ops.Val) (st : σ) :
    Except String (String × String × σ) := do
  unless operands.size == 41 do
    throw s!"extract/unsupported: depth-8 Merkle verify arity {operands.size}"
  let indent := context.indent
  let mut text := ""
  let mut names : Array String := #[]
  let mut state := st
  for operand in operands do
    let (pre, name, next) ← context.materialize operand state
    text := text ++ pre
    names := names.push name
    state := next
  let (computed, s0) := context.fresh state
  let (rootv, s1) := context.fresh s0
  let (result, s2) := context.fresh s1
  state := s2
  text := text ++
    indent ++ "let " ++ computed ++ " := 0" ++ nl ++
    indent ++ "let " ++ result ++ " := 0" ++ nl ++
    indent ++ "if iszero(gt(" ++ names[0]! ++ ", 8)) {" ++ nl ++
    indent ++ "  pf_store_fixed_bytes(0, " ++ names[1]! ++ ", " ++ names[2]! ++
      ", " ++ names[3]! ++ ", " ++ names[4]! ++ ", 32)" ++ nl ++
    indent ++ "  " ++ computed ++ " := mload(0)" ++ nl
  for i in [0:8] do
    let base := 5 + 4 * i
    let (sibling, t0) := context.fresh state
    let (left, t1) := context.fresh t0
    let (right, t2) := context.fresh t1
    state := t2
    text := text ++
      indent ++ "  if gt(" ++ names[0]! ++ ", " ++ toString i ++ ") {" ++ nl ++
      indent ++ "    pf_store_fixed_bytes(32, " ++ names[base]! ++ ", " ++
        names[base + 1]! ++ ", " ++ names[base + 2]! ++ ", " ++ names[base + 3]! ++
        ", 32)" ++ nl ++
      indent ++ "    let " ++ sibling ++ " := mload(32)" ++ nl ++
      indent ++ "    let " ++ left ++ " := " ++ computed ++ nl ++
      indent ++ "    let " ++ right ++ " := " ++ sibling ++ nl ++
      indent ++ "    if gt(" ++ left ++ ", " ++ right ++ ") {" ++ nl ++
      indent ++ "      " ++ left ++ " := " ++ sibling ++ nl ++
      indent ++ "      " ++ right ++ " := " ++ computed ++ nl ++
      indent ++ "    }" ++ nl ++
      indent ++ "    mstore(0, " ++ left ++ ")" ++ nl ++
      indent ++ "    mstore(32, " ++ right ++ ")" ++ nl ++
      indent ++ "    " ++ computed ++ " := keccak256(0, 64)" ++ nl ++
      indent ++ "  }" ++ nl
  text := text ++
    indent ++ "  pf_store_fixed_bytes(64, " ++ names[37]! ++ ", " ++ names[38]! ++
      ", " ++ names[39]! ++ ", " ++ names[40]! ++ ", 32)" ++ nl ++
    indent ++ "  let " ++ rootv ++ " := mload(64)" ++ nl ++
    indent ++ "  " ++ result ++ " := eq(" ++ computed ++ ", " ++ rootv ++ ")" ++ nl ++
    indent ++ "}" ++ nl
  return (text, result, state)

private def packFixedBytesAt (indent : String) (off : Nat) (w0 w1 w2 w3 : String) : String :=
  indent ++ "pf_store_fixed_bytes(" ++ toString off ++ ", " ++ w0 ++ ", " ++ w1 ++
    ", " ++ w2 ++ ", " ++ w3 ++ ", 32)" ++ nl

private def precompileContext (context : Context σ) : Precompile.Emit.Context σ :=
  { fresh := context.fresh, indent := context.indent }

private def emitEcrecover20 (context : Context σ) (limb : Nat) (operands : Array Ops.Val)
    (st : σ) : Except String (String × String × σ) := do
  unless operands.size == 13 do
    throw s!"extract/unsupported: ecrecover arity {operands.size}"
  let cacheKey :=
    "ecrecover20|" ++ String.intercalate "|" (operands.map context.valKey).toList
  match context.lookupWide st cacheKey with
  | some packed =>
      let (name, next) := context.fresh st
      return (context.indent ++ "let " ++ name ++ " := " ++
        CallResult.Emit.wordLimb .address20 packed limb ++ nl, name, next)
  | none =>
    let indent := context.indent
    let mut text := ""
    let mut names : Array String := #[]
    let mut state := st
    for operand in operands do
      let (pre, name, next) ← context.materialize operand state
      text := text ++ pre
      names := names.push name
      state := next
    let (packed, s0) := context.fresh state
    let (result, s1) := context.fresh s0
    let (precompileTxt, signer, s2) ← Precompile.Emit.emit (precompileContext context)
      Precompile.Plan.ecrecover s1
    text := text ++
      packFixedBytesAt indent 0 names[0]! names[1]! names[2]! names[3]! ++
      indent ++ "mstore(32, " ++ names[4]! ++ ")" ++ nl ++
      packFixedBytesAt indent 64 names[5]! names[6]! names[7]! names[8]! ++
      packFixedBytesAt indent 96 names[9]! names[10]! names[11]! names[12]! ++
      precompileTxt ++
      indent ++ "let " ++ packed ++ " := " ++ signer ++ nl ++
      indent ++ "let " ++ result ++ " := " ++
        CallResult.Emit.wordLimb .address20 packed limb ++ nl
    return (text, result, context.rememberWide s2 cacheKey packed)

def emitQuery (context : Context σ) (query : WideWord.Query) (operands : Array Ops.Val)
    (st : σ) : Except String (String × String × σ) :=
  match query, operands.toList with
  | .ge256, [a0, a1, a2, a3, b0, b1, b2, b3] =>
      emitCompare256 context .ge a0 a1 a2 a3 b0 b1 b2 b3 st
  | .compare256 comparison, [a0, a1, a2, a3, b0, b1, b2, b3] =>
      emitCompare256 context comparison a0 a1 a2 a3 b0 b1 b2 b3 st
  | .eq20, [a0, a1, a2, b0, b1, b2] =>
      emitEq20 context a0 a1 a2 b0 b1 b2 st
  | .eqBytes4, [left, right] =>
      emitEqBytes4 context left right st
  | .bitwise256 operation limb, [a0, a1, a2, a3, b0, b1, b2, b3] =>
      emitBitwise256 context operation limb a0 a1 a2 a3 b0 b1 b2 b3 st
  | .not256 limb, [a0, a1, a2, a3] =>
      emitNot256 context limb a0 a1 a2 a3 st
  | .shift256 direction limb, [a0, a1, a2, a3, amount] =>
      emitShift256 context direction limb a0 a1 a2 a3 amount st
  | .checkedDivMod256 operation limb, [a0, a1, a2, a3, b0, b1, b2, b3] =>
      emitCheckedDivMod256 context operation limb a0 a1 a2 a3 b0 b1 b2 b3 st
  | .arith256 op limb, [a0, a1, a2, a3, b0, b1, b2, b3] =>
      emitArith256 context op limb a0 a1 a2 a3 b0 b1 b2 b3 st
  | .keccak256Pair32 limb, [a0, a1, a2, a3, b0, b1, b2, b3] =>
      emitKeccak256Pair32 context limb a0 a1 a2 a3 b0 b1 b2 b3 st
  | .merkleVerify256, operands =>
      emitMerkleVerify256 context operands.toArray st
  | .ecrecover20 limb, operands =>
      emitEcrecover20 context limb operands.toArray st
  | .eqBytes32, [a0, a1, a2, a3, b0, b1, b2, b3] =>
      emitCompare256 context .eq a0 a1 a2 a3 b0 b1 b2 b3 st
  | _, _ =>
      .error s!"extract/unsupported: evm wide-word query arity {operands.size}"

end ProofForge.Evm.WideWord.Emit
