import ProofForge.Core.Ops
import ProofForge.Evm.Codec
import ProofForge.Evm.LogError

namespace ProofForge.Evm.NativeFx

/-- Transitive effects for one native ETH / LOG / revert / receive call. -/
structure EffectSummary where
  logs : Bool := false
  externalCall : Bool := false
  payable : Bool := false
  receive : Bool := false
  deriving BEq, Repr, Inhabited

/-- One bounded dynamic-array field of a typed event. `name` and `elementType` are the ABI surface
(`ids : uint256[]`), `capacity` the slot count of the source `BoundedVec`, `length` its runtime
element count, and `elements` the `capacity · limbCount elementType` little-endian source limbs
of every slot in order. Core's `EventFrame` carries scalars only, so the EVM target owns this
shape: a dynamic field is never indexed and follows every scalar field of its event. -/
structure LogTail (V : Type) where
  name : String
  elementType : Core.Codec.Scalar
  capacity : Nat
  length : V
  elements : Array V
  deriving BEq, Repr, Inhabited

def LogTail.mapValues (mapValue : α → β) (tail : LogTail α) : LogTail β :=
  { tail with length := mapValue tail.length, elements := tail.elements.map mapValue }

def LogTail.mapValuesM [Monad m] (mapValue : α → m β) (tail : LogTail α) : m (LogTail β) := do
  return { tail with length := ← mapValue tail.length, elements := ← tail.elements.mapM mapValue }

/-- Length word first, then every slot's limbs in order. -/
def LogTail.values (tail : LogTail V) : Array V :=
  #[tail.length] ++ tail.elements

/-- Native ETH, LOG, revert, and receive effects. Dynamic operands stay in the Call. -/
inductive Call (V : Type) where
  | deposit (amount : V)
  | deposit256 (a0 a1 a2 a3 : V)
  | sendEth (w0 w1 w2 amount : V)
  | sendEth256 (w0 w1 w2 a0 a1 a2 a3 : V)
  | log (name : String) (amount : V)
  | logTransfer256 (f0 f1 f2 t0 t1 t2 a0 a1 a2 a3 : V)
  | logApproval256 (o0 o1 o2 s0 s1 s2 a0 a1 a2 a3 : V)
  /-- Typed event frame lowered to one `LogPlan` (topic0 + ≤3 indexed topics, ≤4 static data
  words, ≤2 bounded dynamic-array tails). -/
  | logTyped (frame : Core.Ops.EventFrame V) (tails : Array (LogTail V))
  | revertInsufficient (h0 h1 h2 h3 w0 w1 w2 w3 : V)
  | revertUnauthorized (w0 w1 w2 : V)
  | revertZeroAddress
  | revertPaused
  | revertCapExceeded
  | receive
  deriving BEq, Repr, Inhabited

def Call.mapValues (mapValue : α → β) : Call α → Call β
  | .deposit amount => .deposit (mapValue amount)
  | .deposit256 a0 a1 a2 a3 =>
      .deposit256 (mapValue a0) (mapValue a1) (mapValue a2) (mapValue a3)
  | .sendEth w0 w1 w2 amount =>
      .sendEth (mapValue w0) (mapValue w1) (mapValue w2) (mapValue amount)
  | .sendEth256 w0 w1 w2 a0 a1 a2 a3 =>
      .sendEth256 (mapValue w0) (mapValue w1) (mapValue w2)
        (mapValue a0) (mapValue a1) (mapValue a2) (mapValue a3)
  | .log name amount => .log name (mapValue amount)
  | .logTransfer256 f0 f1 f2 t0 t1 t2 a0 a1 a2 a3 =>
      .logTransfer256 (mapValue f0) (mapValue f1) (mapValue f2)
        (mapValue t0) (mapValue t1) (mapValue t2)
        (mapValue a0) (mapValue a1) (mapValue a2) (mapValue a3)
  | .logApproval256 o0 o1 o2 s0 s1 s2 a0 a1 a2 a3 =>
      .logApproval256 (mapValue o0) (mapValue o1) (mapValue o2)
        (mapValue s0) (mapValue s1) (mapValue s2)
        (mapValue a0) (mapValue a1) (mapValue a2) (mapValue a3)
  | .logTyped frame tails =>
      .logTyped (frame.mapValues mapValue) (tails.map (·.mapValues mapValue))
  | .revertInsufficient h0 h1 h2 h3 w0 w1 w2 w3 =>
      .revertInsufficient (mapValue h0) (mapValue h1) (mapValue h2) (mapValue h3)
        (mapValue w0) (mapValue w1) (mapValue w2) (mapValue w3)
  | .revertUnauthorized w0 w1 w2 =>
      .revertUnauthorized (mapValue w0) (mapValue w1) (mapValue w2)
  | .revertZeroAddress => .revertZeroAddress
  | .revertPaused => .revertPaused
  | .revertCapExceeded => .revertCapExceeded
  | .receive => .receive

def Call.mapValuesM [Monad m] (mapValue : α → m β) : Call α → m (Call β)
  | .deposit amount => return .deposit (← mapValue amount)
  | .deposit256 a0 a1 a2 a3 =>
      return .deposit256 (← mapValue a0) (← mapValue a1) (← mapValue a2) (← mapValue a3)
  | .sendEth w0 w1 w2 amount =>
      return .sendEth (← mapValue w0) (← mapValue w1) (← mapValue w2) (← mapValue amount)
  | .sendEth256 w0 w1 w2 a0 a1 a2 a3 =>
      return .sendEth256 (← mapValue w0) (← mapValue w1) (← mapValue w2)
        (← mapValue a0) (← mapValue a1) (← mapValue a2) (← mapValue a3)
  | .log name amount => return .log name (← mapValue amount)
  | .logTransfer256 f0 f1 f2 t0 t1 t2 a0 a1 a2 a3 =>
      return .logTransfer256 (← mapValue f0) (← mapValue f1) (← mapValue f2)
        (← mapValue t0) (← mapValue t1) (← mapValue t2)
        (← mapValue a0) (← mapValue a1) (← mapValue a2) (← mapValue a3)
  | .logApproval256 o0 o1 o2 s0 s1 s2 a0 a1 a2 a3 =>
      return .logApproval256 (← mapValue o0) (← mapValue o1) (← mapValue o2)
        (← mapValue s0) (← mapValue s1) (← mapValue s2)
        (← mapValue a0) (← mapValue a1) (← mapValue a2) (← mapValue a3)
  | .logTyped frame tails =>
      return .logTyped (← frame.mapValuesM mapValue) (← tails.mapM (·.mapValuesM mapValue))
  | .revertInsufficient h0 h1 h2 h3 w0 w1 w2 w3 =>
      return .revertInsufficient (← mapValue h0) (← mapValue h1) (← mapValue h2)
        (← mapValue h3) (← mapValue w0) (← mapValue w1) (← mapValue w2) (← mapValue w3)
  | .revertUnauthorized w0 w1 w2 =>
      return .revertUnauthorized (← mapValue w0) (← mapValue w1) (← mapValue w2)
  | .revertZeroAddress => pure .revertZeroAddress
  | .revertPaused => pure .revertPaused
  | .revertCapExceeded => pure .revertCapExceeded
  | .receive => pure .receive

def Call.values : Call V → Array V
  | .deposit amount | .log _ amount => #[amount]
  | .deposit256 a0 a1 a2 a3 => #[a0, a1, a2, a3]
  | .sendEth w0 w1 w2 amount => #[w0, w1, w2, amount]
  | .sendEth256 w0 w1 w2 a0 a1 a2 a3 => #[w0, w1, w2, a0, a1, a2, a3]
  | .logTransfer256 f0 f1 f2 t0 t1 t2 a0 a1 a2 a3 =>
      #[f0, f1, f2, t0, t1, t2, a0, a1, a2, a3]
  | .logApproval256 o0 o1 o2 s0 s1 s2 a0 a1 a2 a3 =>
      #[o0, o1, o2, s0, s1, s2, a0, a1, a2, a3]
  | .logTyped frame tails => frame.values ++ tails.flatMap (·.values)
  | .revertInsufficient h0 h1 h2 h3 w0 w1 w2 w3 =>
      #[h0, h1, h2, h3, w0, w1, w2, w3]
  | .revertUnauthorized w0 w1 w2 => #[w0, w1, w2]
  | .revertZeroAddress | .revertPaused | .revertCapExceeded | .receive => #[]

def Call.anyValue (predicate : V → Bool) (call : Call V) : Bool :=
  call.values.any predicate

def Call.allValues (predicate : V → Bool) (call : Call V) : Bool :=
  call.values.all predicate

def Call.effects : Call V → EffectSummary
  | .deposit _ | .deposit256 .. => { payable := true }
  | .sendEth .. | .sendEth256 .. => { externalCall := true }
  | .log .. | .logTransfer256 .. | .logApproval256 .. | .logTyped .. => { logs := true }
  | .revertInsufficient .. | .revertUnauthorized .. | .revertZeroAddress | .revertPaused
  | .revertCapExceeded => {}
  | .receive => { payable := true, receive := true }

/-- Closed EVM type vocabulary for one typed event field: exactly the static one-word ABI forms
the emitter can materialize from little-endian source limbs. `uint96`-style widths that are not
whole 64-bit limbs and non-20-byte addresses have no carrier and fail closed here, before Yul. -/
def eventScalarSupported (type : Core.Codec.Scalar) : Bool :=
  Codec.isNarrowIntegerCarrier type || Codec.isWideIntegerCarrier type ||
    Codec.isAddressCarrier type || Codec.isFixedBytesCarrier type

/-- Fail-closed shape gate for one dynamic-array field: a named, closed-scalar element type, a
slot count the `LogTailPlan` accepts, exactly `capacity · limbCount` element limbs, and
well-formed limb values. -/
def LogTail.wellFormed (valueWellFormed : V → Bool) (tail : LogTail V) : Bool :=
  !tail.name.isEmpty && eventScalarSupported tail.elementType &&
    LogError.tailCapacityWellFormed tail.capacity &&
    tail.elements.size == tail.capacity * Codec.limbCount tail.elementType &&
    valueWellFormed tail.length && tail.elements.all valueWellFormed

/-- Fail-closed shape gate for a typed event: generic frame invariant, the closed EVM type
vocabulary with exact limb counts, field names unique across scalars and tails, plus the EVM
`LogPlan` bounds (topic0 plus at most three indexed topics; at most four static data words; at
most two well-formed tails). -/
def Call.logTypedWellFormed (valueWellFormed : V → Bool)
    (frame : Core.Ops.EventFrame V) (tails : Array (LogTail V)) : Bool :=
  let names := frame.args.toList.map (·.name) ++ tails.toList.map (·.name)
  frame.wellFormed valueWellFormed &&
    frame.args.all (fun arg =>
      eventScalarSupported arg.type && arg.parts.size == Codec.limbCount arg.type) &&
    frame.indexedCount + 1 ≤ LogError.maxTopics &&
    frame.dataCount ≤ LogError.maxLogDataWords &&
    tails.size ≤ LogError.maxLogTails &&
    tails.all (·.wellFormed valueWellFormed) &&
    names.length == names.eraseDups.length

/-- ABI parameter types of a validated typed event, in declaration order: the scalar fields, then
each tail as `T[]`. This is the single owner consumed by both the Yul emitter (topic0 signature)
and the ABI JSON generator, so both artifacts derive from one descriptor. `indexed` is not part
of the keccak signature. -/
def Call.logTypedAbiTypes (valueWellFormed : V → Bool) (frame : Core.Ops.EventFrame V)
    (tails : Array (LogTail V)) : Except String (Array String) := do
  unless Call.logTypedWellFormed valueWellFormed frame tails do
    throw "extract/unsupported: malformed typed event frame"
  let scalars ← frame.args.mapM fun arg => Codec.abiType arg.type
  let arrays ← tails.mapM fun tail => return (← Codec.abiType tail.elementType) ++ "[]"
  return scalars ++ arrays

def Call.wellFormed (valueWellFormed : V → Bool) : Call V → Bool
  | .logTyped frame tails => Call.logTypedWellFormed valueWellFormed frame tails
  | call => call.allValues valueWellFormed

def Call.isDeposit : Call V → Bool
  | .deposit _ | .deposit256 .. => true
  | _ => false

def Call.isReceive : Call V → Bool
  | .receive => true
  | _ => false

def Call.emitsInsufficient : Call V → Bool
  | .revertInsufficient .. => true
  | _ => false

def Call.emitsUnauthorized : Call V → Bool
  | .revertUnauthorized .. => true
  | _ => false

def Call.emitsZeroAddress : Call V → Bool
  | .revertZeroAddress => true
  | _ => false

def Call.emitsPaused : Call V → Bool
  | .revertPaused => true
  | _ => false

def Call.emitsCapExceeded : Call V → Bool
  | .revertCapExceeded => true
  | _ => false

/-- Closed uint64 / Transfer256 / Approval256 names keep their existing ABI spelling. Typed
frames are collected separately so `eventAbi` cannot rewrite Transfer/Approval JSON. -/
def Call.logName : Call V → Option String
  | .log name _ => some name
  | .logTransfer256 .. => some "Transfer256"
  | .logApproval256 .. => some "Approval256"
  | .logTyped .. => none
  | _ => none

/-- Preserve the closed-union digest spelling (`edep` / `elog3.Transfer` / `err.ZeroAddress`). -/
def Call.canonical (renderValue : V → String) : Call V → String
  | .deposit v => s!"edep({renderValue v})"
  | .deposit256 a0 a1 a2 a3 =>
      s!"edep256({renderValue a0},{renderValue a1},{renderValue a2},{renderValue a3})"
  | .sendEth a b c d =>
      s!"esend({renderValue a},{renderValue b},{renderValue c},{renderValue d})"
  | .sendEth256 a b c d0 d1 d2 d3 =>
      s!"esend256({renderValue a},{renderValue b},{renderValue c},{renderValue d0},{renderValue d1},{renderValue d2},{renderValue d3})"
  | .log n v => s!"elog.{n}({renderValue v})"
  | .logTransfer256 f0 f1 f2 t0 t1 t2 a0 a1 a2 a3 =>
      s!"elog3.Transfer({renderValue f0},{renderValue f1},{renderValue f2},{renderValue t0},{renderValue t1},{renderValue t2},{renderValue a0},{renderValue a1},{renderValue a2},{renderValue a3})"
  | .logApproval256 o0 o1 o2 s0 s1 s2 a0 a1 a2 a3 =>
      s!"elog3.Approval({renderValue o0},{renderValue o1},{renderValue o2},{renderValue s0},{renderValue s1},{renderValue s2},{renderValue a0},{renderValue a1},{renderValue a2},{renderValue a3})"
  | .logTyped frame tails =>
      let args := frame.args.toList.map fun arg =>
        let tag := if arg.indexed then "i" else "d"
        s!"{arg.name}:{repr arg.type}:{tag}({String.intercalate "," (arg.parts.map renderValue).toList})"
      let arrays := tails.toList.map fun tail =>
        s!"{tail.name}:{repr tail.elementType}[{tail.capacity}]({renderValue tail.length};{String.intercalate "," (tail.elements.map renderValue).toList})"
      s!"elogT.{frame.constructor}({String.intercalate "," (args ++ arrays)})"
  | .revertInsufficient h0 h1 h2 h3 w0 w1 w2 w3 =>
      s!"err.Insufficient({renderValue h0},{renderValue h1},{renderValue h2},{renderValue h3},{renderValue w0},{renderValue w1},{renderValue w2},{renderValue w3})"
  | .revertUnauthorized w0 w1 w2 =>
      s!"err.Unauthorized({renderValue w0},{renderValue w1},{renderValue w2})"
  | .revertZeroAddress => "err.ZeroAddress"
  | .revertPaused => "err.Paused"
  | .revertCapExceeded => "err.CapExceeded"
  | .receive => "erecv"

end ProofForge.Evm.NativeFx
