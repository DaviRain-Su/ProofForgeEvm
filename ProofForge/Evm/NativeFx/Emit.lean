import ProofForge.Evm.NativeFx
import ProofForge.Evm.LogError.Emit
import ProofForge.Evm.Payable.Emit
import ProofForge.Evm.Ops
import ProofForge.Evm.Codec
import ProofForge.Evm.Codec.Emit
import ProofForge.Core.Ops
import ProofForge.Crypto.Keccak

namespace ProofForge.Evm.NativeFx.Emit

open ProofForge.Crypto

private def nl : String := "\n"
private def revert0 : String := "revert(0, 0)"

private def packU256 (w0 w1 w2 w3 : String) : String :=
  Codec.Emit.packU256 w0 w1 w2 w3

/-- Call the shared runtime helper that packs three little-endian Addr20 limbs into an
ABI address word at `memory[0..31]`. -/
private def packAddrMstore8 (indent w0 w1 w2 : String) : String :=
  indent ++ "pf_store_addr20(0, " ++ w0 ++ ", " ++ w1 ++ ", " ++ w2 ++ ")" ++ nl

structure Context (σ : Type) where
  materialize : Ops.Val → σ → Except String (String × String × σ)
  fresh : σ → String × σ
  indent : String

/-- Project the shared typed log/error emission context (EVM-RT-2b). Every LOG0..4 event and
custom-error revert below is emitted through `Evm.LogError.Emit`, so topic counts, data byte
lengths/offsets, selector placement, ABI argument word offsets, and revert lengths have
exactly one spelling; the closed semantic names stay here. -/
private def Context.logError (context : Context σ) : LogError.Emit.Context :=
  { indent := context.indent }

/-- Project the shared typed entry-value emission context (EVM-RT-2c). The exact CALLVALUE
deposit gate and the receive accept-any binding below are emitted through
`Evm.Payable.Emit`, so the payable guard spellings have exactly one owner; the closed
semantic names stay here. The native send CALL keeps its closed policy and does not
participate in the entry-value abstraction. -/
private def Context.payable (context : Context σ) : Payable.Emit.Context :=
  { indent := context.indent }

private def emitDeposit (context : Context σ) (amount : Ops.Val) (st : σ) :
    Except String (String × String × σ) := do
  let (pre, amt, st') ← context.materialize amount st
  let gate ← Payable.Emit.emitValueGate context.payable .exact (some amt)
  return (pre ++ gate, amt, st')

private def emitDeposit256 (context : Context σ) (a0 a1 a2 a3 : Ops.Val) (st : σ) :
    Except String (String × String × σ) := do
  let indent := context.indent
  let (p0, x0, s0) ← context.materialize a0 st
  let (p1, x1, s1) ← context.materialize a1 s0
  let (p2, x2, s2) ← context.materialize a2 s1
  let (p3, x3, s3) ← context.materialize a3 s2
  let (amt, s4) := context.fresh s3
  let gate ← Payable.Emit.emitValueGate context.payable .exact (some amt)
  let txt := p0 ++ p1 ++ p2 ++ p3 ++
    indent ++ "let " ++ amt ++ " := " ++ packU256 x0 x1 x2 x3 ++ nl ++ gate
  return (txt, x0, s4)

private def emitSendEth (context : Context σ) (w0 w1 w2 amount : Ops.Val) (st : σ) :
    Except String (String × String × σ) := do
  let indent := context.indent
  let (p0, a0, st0) ← context.materialize w0 st
  let (p1, a1, st1) ← context.materialize w1 st0
  let (p2, a2, st2) ← context.materialize w2 st1
  let (p3, amt, st3) ← context.materialize amount st2
  let (ok, st') := context.fresh st3
  let txt := p0 ++ p1 ++ p2 ++ p3 ++
    indent ++ "if shr(32, " ++ a2 ++ ") { " ++ revert0 ++ " }" ++ nl ++
    indent ++ "mstore(0, 0)" ++ nl ++
    packAddrMstore8 indent a0 a1 a2 ++
    indent ++ "let " ++ ok ++ " := call(gas(), mload(0), " ++ amt ++
      ", 0, 0, 0, 0)" ++ nl ++
    indent ++ "if iszero(" ++ ok ++ ") { " ++ revert0 ++ " }" ++ nl
  return (txt, amt, st')

private def emitSendEth256 (context : Context σ)
    (w0 w1 w2 a0 a1 a2 a3 : Ops.Val) (st : σ) :
    Except String (String × String × σ) := do
  let indent := context.indent
  let (p0, d0, s0) ← context.materialize w0 st
  let (p1, d1, s1) ← context.materialize w1 s0
  let (p2, d2, s2) ← context.materialize w2 s1
  let (q0, x0, s3) ← context.materialize a0 s2
  let (q1, x1, s4) ← context.materialize a1 s3
  let (q2, x2, s5) ← context.materialize a2 s4
  let (q3, x3, s6) ← context.materialize a3 s5
  let (amt, s7) := context.fresh s6
  let (ok, s8) := context.fresh s7
  let txt := p0 ++ p1 ++ p2 ++ q0 ++ q1 ++ q2 ++ q3 ++
    indent ++ "if shr(32, " ++ d2 ++ ") { " ++ revert0 ++ " }" ++ nl ++
    indent ++ "mstore(0, 0)" ++ nl ++
    packAddrMstore8 indent d0 d1 d2 ++
    indent ++ "let " ++ amt ++ " := " ++ packU256 x0 x1 x2 x3 ++ nl ++
    indent ++ "let " ++ ok ++ " := call(gas(), mload(0), " ++ amt ++
      ", 0, 0, 0, 0)" ++ nl ++
    indent ++ "if iszero(" ++ ok ++ ") { " ++ revert0 ++ " }" ++ nl
  return (txt, x0, s8)

private def emitLog (context : Context σ) (name : String) (amount : Ops.Val) (st : σ) :
    Except String (String × String × σ) := do
  let (pre, amt, st') ← context.materialize amount st
  let sigTopic := "0x" ++ Keccak.keccak256HexOfString (name ++ "(uint64)")
  let logTxt ← LogError.Emit.emitLog context.logError { data := #[amt], topics := #[sigTopic] }
  return (pre ++ logTxt, amt, st')

private def emitLogTransfer256 (context : Context σ)
    (f0 f1 f2 t0 t1 t2 a0 a1 a2 a3 : Ops.Val) (st : σ) :
    Except String (String × String × σ) := do
  let indent := context.indent
  let (p0, x0, s0) ← context.materialize f0 st
  let (p1, x1, s1) ← context.materialize f1 s0
  let (p2, x2, s2) ← context.materialize f2 s1
  let (q0, y0, s3) ← context.materialize t0 s2
  let (q1, y1, s4) ← context.materialize t1 s3
  let (q2, y2, s5) ← context.materialize t2 s4
  let (r0, z0, s6) ← context.materialize a0 s5
  let (r1, z1, s7) ← context.materialize a1 s6
  let (r2, z2, s8) ← context.materialize a2 s7
  let (r3, z3, s9) ← context.materialize a3 s8
  let (fromT, s10) := context.fresh s9
  let (toT, s11) := context.fresh s10
  let (amt, s12) := context.fresh s11
  let sigTopic := "0x" ++ Keccak.keccak256HexOfString "Transfer(address,address,uint256)"
  let logTxt ← LogError.Emit.emitLog context.logError
    { data := #[amt], topics := #[sigTopic, fromT, toT] }
  let txt := p0 ++ p1 ++ p2 ++ q0 ++ q1 ++ q2 ++ r0 ++ r1 ++ r2 ++ r3 ++
    Codec.Emit.bindAddrWord indent fromT x0 x1 x2 ++
    Codec.Emit.bindAddrWord indent toT y0 y1 y2 ++
    indent ++ "let " ++ amt ++ " := " ++ packU256 z0 z1 z2 z3 ++ nl ++
    logTxt
  return (txt, z0, s12)

/-- Pack one typed event or typed error field into a single ABI word. Addresses and fixed bytes
go through the shared memory helpers; wide integers use the little-endian `packU256` spelling;
narrow integers and booleans are already one word. Any other carrier fails closed. -/
def packAbiWord (context : Context σ) (type : Core.Codec.Scalar) (limbs : Array Ops.Val)
    (st : σ) : Except String (String × String × σ) := do
  let indent := context.indent
  let mut prelude := ""
  let mut parts : Array String := #[]
  let mut st := st
  for part in limbs do
    let (pre, expr, st') ← context.materialize part st
    prelude := prelude ++ pre
    parts := parts.push expr
    st := st'
  if parts.isEmpty then
    throw "extract/unsupported: typed field has no limbs"
  if Codec.isAddressCarrier type then
    let (word, st') := context.fresh st
    let txt := prelude ++ Codec.Emit.bindAddrWord indent word (parts[0]!)
      ((parts[1]?).getD "0") ((parts[2]?).getD "0")
    return (txt, word, st')
  else if Codec.isFixedBytesCarrier type then
    let (word, st') := context.fresh st
    let txt := prelude ++
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
    let txt := prelude ++ indent ++ "let " ++ word ++ " := " ++ packed ++ nl
    return (txt, word, st')
  else if Codec.isNarrowIntegerCarrier type && parts.size == 1 then
    return (prelude, parts[0]!, st)
  else
    throw "extract/unsupported: typed field type has no EVM word carrier"

/-- Pack one bounded dynamic-array field into a tail plan: the runtime length bound to a fresh
word (the plan reads it once per slot), then every slot packed by the same word packer the
scalar fields use. Slots past the runtime length are packed but never stored. -/
private def packLogTail (context : Context σ) (tail : NativeFx.LogTail Ops.Val) (st : σ) :
    Except String (String × LogError.LogTailPlan × σ) := do
  let indent := context.indent
  let (lengthPre, lengthExpr, st0) ← context.materialize tail.length st
  let (length, st1) := context.fresh st0
  let mut prelude := lengthPre ++ indent ++ "let " ++ length ++ " := " ++ lengthExpr ++ nl
  let mut elements : Array String := #[]
  let mut st := st1
  let limbs := Codec.limbCount tail.elementType
  for slot in [0:tail.capacity] do
    let (pre, word, st') ←
      packAbiWord context tail.elementType (tail.elements.extract (slot * limbs) ((slot + 1) * limbs)) st
    prelude := prelude ++ pre
    elements := elements.push word
    st := st'
  return (prelude, { length, elements }, st)

private def emitLogTyped (context : Context σ) (frame : Core.Ops.EventFrame Ops.Val)
    (tails : Array (NativeFx.LogTail Ops.Val)) (st : σ) :
    Except String (String × String × σ) := do
  let abiTypes ← NativeFx.Call.logTypedAbiTypes (·.wellFormed Ops.ValKind.arity) frame tails
  let mut prelude := ""
  let mut topics : Array String :=
    #["0x" ++ Keccak.keccak256HexOfString (Keccak.signature frame.constructor abiTypes)]
  let mut data : Array String := #[]
  let mut st := st
  let mut last : String := "0"
  for arg in frame.args do
    let (pre, word, st') ← packAbiWord context arg.type arg.parts st
    prelude := prelude ++ pre
    st := st'
    last := word
    if arg.indexed then
      topics := topics.push word
    else
      data := data.push word
  let mut tailPlans : Array LogError.LogTailPlan := #[]
  for tail in tails do
    let (pre, plan, st') ← packLogTail context tail st
    prelude := prelude ++ pre
    tailPlans := tailPlans.push plan
    st := st'
  let logTxt ← LogError.Emit.emitLog context.logError { data, topics, tails := tailPlans }
  return (prelude ++ logTxt, last, st)

private def emitLogApproval256 (context : Context σ)
    (o0 o1 o2 sp0 sp1 sp2 a0 a1 a2 a3 : Ops.Val) (st : σ) :
    Except String (String × String × σ) := do
  let indent := context.indent
  let (p0, x0, s0) ← context.materialize o0 st
  let (p1, x1, s1) ← context.materialize o1 s0
  let (p2, x2, s2) ← context.materialize o2 s1
  let (q0, y0, s3) ← context.materialize sp0 s2
  let (q1, y1, s4) ← context.materialize sp1 s3
  let (q2, y2, s5) ← context.materialize sp2 s4
  let (r0, z0, s6) ← context.materialize a0 s5
  let (r1, z1, s7) ← context.materialize a1 s6
  let (r2, z2, s8) ← context.materialize a2 s7
  let (r3, z3, s9) ← context.materialize a3 s8
  let (ownT, s10) := context.fresh s9
  let (spdT, s11) := context.fresh s10
  let (amt, s12) := context.fresh s11
  let sigTopic := "0x" ++ Keccak.keccak256HexOfString "Approval(address,address,uint256)"
  let logTxt ← LogError.Emit.emitLog context.logError
    { data := #[amt], topics := #[sigTopic, ownT, spdT] }
  let txt := p0 ++ p1 ++ p2 ++ q0 ++ q1 ++ q2 ++ r0 ++ r1 ++ r2 ++ r3 ++
    Codec.Emit.bindAddrWord indent ownT x0 x1 x2 ++
    Codec.Emit.bindAddrWord indent spdT y0 y1 y2 ++
    indent ++ "let " ++ amt ++ " := " ++ packU256 z0 z1 z2 z3 ++ nl ++
    logTxt
  return (txt, z0, s12)

private def emitRevertInsufficient (context : Context σ)
    (h0 h1 h2 h3 w0 w1 w2 w3 : Ops.Val) (st : σ) :
    Except String (String × String × σ) := do
  let (p0, x0, s0) ← context.materialize h0 st
  let (p1, x1, s1) ← context.materialize h1 s0
  let (p2, x2, s2) ← context.materialize h2 s1
  let (p3, x3, s3) ← context.materialize h3 s2
  let (q0, y0, s4) ← context.materialize w0 s3
  let (q1, y1, s5) ← context.materialize w1 s4
  let (q2, y2, s6) ← context.materialize w2 s5
  let (q3, y3, s7) ← context.materialize w3 s6
  let errTxt ← LogError.Emit.emitRevert context.logError
    { selector := Keccak.selector "Insufficient" #["uint256", "uint256"]
      args := #[packU256 x0 x1 x2 x3, packU256 y0 y1 y2 y3] }
  let txt := p0 ++ p1 ++ p2 ++ p3 ++ q0 ++ q1 ++ q2 ++ q3 ++ errTxt
  return (txt, x0, s7)

private def emitRevertUnauthorized (context : Context σ)
    (w0 w1 w2 : Ops.Val) (st : σ) : Except String (String × String × σ) := do
  let indent := context.indent
  let (p0, a0, s0) ← context.materialize w0 st
  let (p1, a1, s1) ← context.materialize w1 s0
  let (p2, a2, s2) ← context.materialize w2 s1
  let errTxt ← LogError.Emit.emitRevert context.logError
    { selector := Keccak.selector "Unauthorized" #["address"], args := #["pf_who"] }
  let txt := p0 ++ p1 ++ p2 ++ Codec.Emit.bindAddrWord indent "pf_who" a0 a1 a2 ++ errTxt
  return (txt, a0, s2)

private def emitRevertOwnableInvalidOwner (context : Context σ)
    (w0 w1 w2 : Ops.Val) (st : σ) : Except String (String × String × σ) := do
  let indent := context.indent
  let (p0, a0, s0) ← context.materialize w0 st
  let (p1, a1, s1) ← context.materialize w1 s0
  let (p2, a2, s2) ← context.materialize w2 s1
  let errTxt ← LogError.Emit.emitRevert context.logError
    { selector := Keccak.selector "OwnableInvalidOwner" #["address"], args := #["pf_owner"] }
  let txt := p0 ++ p1 ++ p2 ++ Codec.Emit.bindAddrWord indent "pf_owner" a0 a1 a2 ++ errTxt
  return (txt, a0, s2)

private def emitRevertOwnableUnauthorizedAccount (context : Context σ)
    (w0 w1 w2 : Ops.Val) (st : σ) : Except String (String × String × σ) := do
  let indent := context.indent
  let (p0, a0, s0) ← context.materialize w0 st
  let (p1, a1, s1) ← context.materialize w1 s0
  let (p2, a2, s2) ← context.materialize w2 s1
  let errTxt ← LogError.Emit.emitRevert context.logError
    { selector := Keccak.selector "OwnableUnauthorizedAccount" #["address"], args := #["pf_account"] }
  let txt := p0 ++ p1 ++ p2 ++ Codec.Emit.bindAddrWord indent "pf_account" a0 a1 a2 ++ errTxt
  return (txt, a0, s2)

private def emitRevertZeroAddress (context : Context σ) (st : σ) :
    Except String (String × String × σ) := do
  let txt ← LogError.Emit.emitRevert context.logError
    { selector := Keccak.selector "ZeroAddress" #[] }
  pure (txt, "0", st)

private def emitRevertPaused (context : Context σ) (st : σ) :
    Except String (String × String × σ) := do
  let txt ← LogError.Emit.emitRevert context.logError
    { selector := Keccak.selector "Paused" #[] }
  pure (txt, "0", st)

private def emitRevertCapExceeded (context : Context σ) (st : σ) :
    Except String (String × String × σ) := do
  let txt ← LogError.Emit.emitRevert context.logError
    { selector := Keccak.selector "CapExceeded" #[] }
  pure (txt, "0", st)

private def emitReceive (context : Context σ) (st : σ) :
    Except String (String × String × σ) := do
  let txt ← Payable.Emit.emitValueGate context.payable .acceptAny
  pure (txt, "pf_recv", st)

def emitCall (context : Context σ) (call : NativeFx.Call Ops.Val) (st : σ) :
    Except String (String × String × σ) :=
  match call with
  | .deposit amount => emitDeposit context amount st
  | .deposit256 a0 a1 a2 a3 => emitDeposit256 context a0 a1 a2 a3 st
  | .sendEth w0 w1 w2 amount => emitSendEth context w0 w1 w2 amount st
  | .sendEth256 w0 w1 w2 a0 a1 a2 a3 =>
      emitSendEth256 context w0 w1 w2 a0 a1 a2 a3 st
  | .log name amount => emitLog context name amount st
  | .logTransfer256 f0 f1 f2 t0 t1 t2 a0 a1 a2 a3 =>
      emitLogTransfer256 context f0 f1 f2 t0 t1 t2 a0 a1 a2 a3 st
  | .logApproval256 o0 o1 o2 s0 s1 s2 a0 a1 a2 a3 =>
      emitLogApproval256 context o0 o1 o2 s0 s1 s2 a0 a1 a2 a3 st
  | .logTyped frame tails => emitLogTyped context frame tails st
  | .revertInsufficient h0 h1 h2 h3 w0 w1 w2 w3 =>
      emitRevertInsufficient context h0 h1 h2 h3 w0 w1 w2 w3 st
  | .revertUnauthorized w0 w1 w2 => emitRevertUnauthorized context w0 w1 w2 st
  | .revertOwnableInvalidOwner w0 w1 w2 => emitRevertOwnableInvalidOwner context w0 w1 w2 st
  | .revertOwnableUnauthorizedAccount w0 w1 w2 =>
      emitRevertOwnableUnauthorizedAccount context w0 w1 w2 st
  | .revertZeroAddress => emitRevertZeroAddress context st
  | .revertPaused => emitRevertPaused context st
  | .revertCapExceeded => emitRevertCapExceeded context st
  | .receive => emitReceive context st

end ProofForge.Evm.NativeFx.Emit
