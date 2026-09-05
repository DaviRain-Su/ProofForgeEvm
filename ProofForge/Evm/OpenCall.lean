import ProofForge.Core.Ops
import ProofForge.Evm.CallResult
import ProofForge.Evm.Codec
import ProofForge.Evm.Keccak

namespace ProofForge.Evm.OpenCall

/-!
Typed external CALL sibling of `ClosedCall` (S3). “Open” means the target address may be a
typed source value; the call contract stays static and compiler-checked:

- CALL or STATICCALL;
- compile-time function name and fixed ABI schema: one head word per argument, plus at most
  two bounded dynamic-array tails and one packed `bytes` or `string` tail;
- typed argument limbs and optional typed CALL value;
- one `CallResult.Policy`;
- `externalCall` (and `sendsValue` when msg.value is present).

Calldata is assembled by the emitter. The source API never accepts an arbitrary bytes payload,
selector string, return buffer length, or opcode. A `bytes` argument is a `BoundedBytes`
source value whose capacity is fixed at compile time; a `string` argument is a `BoundedString`
with the same limb frame, published as ABI `string`. An array argument is a `BoundedVec`
over a closed scalar. Runtime lengths decide tail sizes. A plan with only scalars, or with
one packed tail and no array, keeps compile-time tail offsets. A plan that carries an array
walks a byte cursor so later tails can follow a runtime-length prefix. `delegatecall`,
CREATE/CREATE2, and proxy dispatch are not variants. `NativeFx.sendEth` stays a separate
zero-calldata primitive.
-/

/-- Fail-closed calldata bound: selector plus at most eight ABI head words. -/
def maxArgWords : Nat := 8

/-- At most one packed `bytes` or `string` argument per plan. Alone, its tail offset stays a
compile-time constant. -/
def maxBytesArgs : Nat := 1

/-- At most two bounded-array arguments per plan: `onERC1155BatchReceived` carries `ids` and
`values`. -/
def maxArrayArgs : Nat := 2

/-- At most three dynamic arguments per plan: two arrays plus one `bytes` tail. -/
def maxDynamicArgs : Nat := 3

/-- Closed EVM argument vocabulary: the same one-word carriers typed events already admit. -/
def argScalarSupported (type : Core.Codec.Scalar) : Bool :=
  Codec.isNarrowIntegerCarrier type || Codec.isWideIntegerCarrier type ||
    Codec.isAddressCarrier type || Codec.isFixedBytesCarrier type

/-- One ABI parameter type: a closed one-word scalar, a `bytes` or `string` tail bounded by
`capacity`, or a dynamic array of a closed scalar with compile-time slot count `capacity`. -/
inductive ArgType where
  | scalar (type : Core.Codec.Scalar)
  | bytes (capacity : Nat)
  | string (capacity : Nat)
  | array (capacity : Nat) (element : Core.Codec.Scalar)
  deriving BEq, Repr, Inhabited

def ArgType.isDynamic : ArgType → Bool
  | .scalar _ => false
  | .bytes _ | .string _ | .array .. => true

def ArgType.isBytes : ArgType → Bool
  | .bytes _ => true
  | _ => false

def ArgType.isString : ArgType → Bool
  | .string _ => true
  | _ => false

/-- Packed ABI `bytes` and `string` share one tail slot and the same limb frame. -/
def ArgType.isPacked : ArgType → Bool
  | .bytes _ | .string _ => true
  | _ => false

def ArgType.isArray : ArgType → Bool
  | .array .. => true
  | _ => false

/-- Source limbs the argument carries: the scalar's limbs; the runtime length followed by one
byte limb per slot of capacity, the frame `BoundedBytes` already has on the entry side; or the
runtime length followed by every slot's scalar limbs, the frame `BoundedVec` already has. -/
def ArgType.limbCount : ArgType → Nat
  | .scalar type => Codec.limbCount type
  | .bytes capacity | .string capacity => 1 + capacity
  | .array capacity element => 1 + capacity * Codec.limbCount element

def ArgType.abiType : ArgType → Except String String
  | .scalar type => Codec.abiType type
  | .bytes _ => pure "bytes"
  | .string _ => pure "string"
  | .array _ element => return (← Codec.abiType element) ++ "[]"

/-- A packed `bytes` / `string` capacity is bounded by the same packed-bytes ceiling the entry
decoder admits, so every `BoundedBytes` or `BoundedString` an entry can receive can be forwarded.
An array's source frame is bounded by the same local-word ceiling a `BoundedVec` entry already
admits. -/
def ArgType.supported : ArgType → Bool
  | .scalar type => argScalarSupported type
  | .bytes capacity | .string capacity => capacity ≤ Codec.maxPackedBytesCapacity
  | .array capacity element =>
      argScalarSupported element && 0 < capacity &&
        1 + capacity * Codec.limbCount element ≤ Codec.maxBoundedArrayLocalWords

def ArgType.canonical : ArgType → String
  | .scalar type => toString (repr type)
  | .bytes capacity => s!"bytes{capacity}"
  | .string capacity => s!"string{capacity}"
  | .array capacity element => s!"{repr element}[{capacity}]"

/-- Transitive effects for one typed open CALL. -/
structure EffectSummary where
  externalCall : Bool := false
  sendsValue : Bool := false
  deriving BEq, Repr, Inhabited

/-- One ABI argument: declaration-order name, parameter type, and source limbs (little-endian
scalar limbs; `length` followed by `capacity` byte limbs for packed `bytes` / `string`;
`length` followed by every slot's scalar limbs for an array). -/
structure Arg (V : Type) where
  name : String
  type : ArgType
  parts : Array V
  deriving BEq, Repr, Inhabited

def Arg.mapValues (mapValue : α → β) (arg : Arg α) : Arg β :=
  { arg with parts := arg.parts.map mapValue }

def Arg.mapValuesM [Monad m] (mapValue : α → m β) (arg : Arg α) : m (Arg β) := do
  return { arg with parts := ← arg.parts.mapM mapValue }

/-- Compile-time ABI contract plus typed operands for one open CALL/STATICCALL. -/
structure Plan (V : Type) where
  name : String
  args : Array (Arg V)
  target : Array V
  kind : CallResult.Kind
  policy : CallResult.Policy
  valueParts : Array V := #[]
  deriving BEq, Repr, Inhabited

def Plan.mapValues (mapValue : α → β) (plan : Plan α) : Plan β :=
  { name := plan.name
    args := plan.args.map (·.mapValues mapValue)
    target := plan.target.map mapValue
    kind := plan.kind
    policy := plan.policy
    valueParts := plan.valueParts.map mapValue }

def Plan.mapValuesM [Monad m] (mapValue : α → m β) (plan : Plan α) : m (Plan β) := do
  return {
    name := plan.name
    args := ← plan.args.mapM (·.mapValuesM mapValue)
    target := ← plan.target.mapM mapValue
    kind := plan.kind
    policy := plan.policy
    valueParts := ← plan.valueParts.mapM mapValue }

def Plan.values (plan : Plan V) : Array V :=
  plan.target ++ plan.args.flatMap (·.parts) ++ plan.valueParts

def Plan.sendsValue (plan : Plan V) : Bool :=
  !plan.valueParts.isEmpty

/-- The packed `bytes` / `string` arguments in declaration order; at most `maxBytesArgs` when
well-formed. -/
def Plan.bytesArgs (plan : Plan V) : Array (Arg V) :=
  plan.args.filter (·.type.isPacked)

/-- The bounded-array arguments in declaration order; at most `maxArrayArgs` when well-formed. -/
def Plan.arrayArgs (plan : Plan V) : Array (Arg V) :=
  plan.args.filter (·.type.isArray)

/-- Dynamic arguments in declaration order; at most `maxDynamicArgs` when well-formed. -/
def Plan.dynamicArgs (plan : Plan V) : Array (Arg V) :=
  plan.args.filter (·.type.isDynamic)

/-- True when a tail offset depends on a previous tail's runtime length, so emission walks a
cursor instead of storing a compile-time offset. -/
def Plan.usesCursor (plan : Plan V) : Bool :=
  !plan.arrayArgs.isEmpty

/-- Byte length of the head: selector plus one word per argument (a value or a tail offset). The
first tail starts here. -/
def Plan.headBytes (plan : Plan V) : Nat :=
  CallResult.selectorBytes + CallResult.abiWordBytes * plan.args.size

/-- Compile-time calldata bytes: the head plus one length word per packed tail when there is
no array. An array plan's tails are sized at emission from runtime lengths, so this is only
the head; `CallResult.Emit.emitBound` takes the cursor as the full `inSize`. The padded
payload of a lone packed tail is added at emission from its runtime length. -/
def Plan.inSize (plan : Plan V) : Nat :=
  if plan.usesCursor then plan.headBytes
  else plan.headBytes + CallResult.abiWordBytes * plan.bytesArgs.size

def Plan.request (plan : Plan V) : CallResult.Request :=
  { kind := plan.kind
    inSize := plan.inSize
    policy := plan.policy
    value := plan.sendsValue }

/-- Solidity-style identifier: non-empty, starts with a letter, then alphanumerics/`_`. -/
def isIdent (s : String) : Bool :=
  !s.isEmpty && s.front.isAlpha && s.all (fun c => c.isAlphanum || c == '_')

def Arg.wellFormed (valueWellFormed : V → Bool) (arg : Arg V) : Bool :=
  isIdent arg.name && arg.type.supported &&
    arg.parts.size == arg.type.limbCount && arg.parts.all valueWellFormed

def Plan.wellFormed (valueWellFormed : V → Bool) (plan : Plan V) : Bool :=
  let names := plan.args.toList.map (·.name)
  isIdent plan.name && plan.args.size ≤ maxArgWords &&
    plan.bytesArgs.size ≤ maxBytesArgs &&
    plan.arrayArgs.size ≤ maxArrayArgs &&
    plan.dynamicArgs.size ≤ maxDynamicArgs &&
    names.length == names.eraseDups.length &&
    plan.args.all (Arg.wellFormed valueWellFormed) &&
    plan.target.size == 3 && plan.target.all valueWellFormed &&
    (plan.valueParts.isEmpty || plan.valueParts.size == 4) &&
    plan.valueParts.all valueWellFormed &&
    plan.request.wellFormed

def Plan.abiTypes (plan : Plan V) : Except String (Array String) :=
  plan.args.mapM (·.type.abiType)

/-- Keccak selector of `name(type1,type2,...)`. Fails closed on a malformed plan. -/
def Plan.selectorHex (valueWellFormed : V → Bool) (plan : Plan V) : Except String String := do
  unless plan.wellFormed valueWellFormed do
    throw "extract/unsupported: malformed open-call plan"
  pure (Keccak.selector plan.name (← plan.abiTypes))

def policyCanon : CallResult.Policy → String
  | .canonicalTrueOrCodeBackedEmpty => "erc20"
  | .exactWord => "word1"
  | .contractSuccess => "ok"
  | .exactWords n => s!"word{n}"
  | .strictBool => "bool"
  | .magicBytes4 sel => s!"magic{sel}"
  | .tryMagicBytes4 sel => s!"trymagic{sel}"
  | .words kinds =>
      "typed[" ++
        String.intercalate "," (kinds.toList.map fun
          | .uint256 => "u256"
          | .boolean => "b"
          | .address20 => "a20"
          | .bytes4 => "b4") ++ "]"

def kindCanon : CallResult.Kind → String
  | .call => "call"
  | .staticcall => "static"

def Plan.canonical (renderValue : V → String) (plan : Plan V) : String :=
  let args := plan.args.toList.map fun arg =>
    s!"{arg.name}:{arg.type.canonical}({String.intercalate "," (arg.parts.map renderValue).toList})"
  let target := String.intercalate "," (plan.target.map renderValue).toList
  let value :=
    if plan.valueParts.isEmpty then ""
    else s!",v({String.intercalate "," (plan.valueParts.map renderValue).toList})"
  s!"ocall.{kindCanon plan.kind}.{policyCanon plan.policy}.{plan.name}({target};{String.intercalate "," args}{value})"

/-- Effect-producing open CALL. The numeric carrier is dummy; returndata stays in `CallResult`. -/
inductive Call (V : Type) where
  | invoke (plan : Plan V)
  deriving BEq, Repr, Inhabited

def Call.mapValues (mapValue : α → β) : Call α → Call β
  | .invoke plan => .invoke (plan.mapValues mapValue)

def Call.mapValuesM [Monad m] (mapValue : α → m β) : Call α → m (Call β)
  | .invoke plan => return .invoke (← plan.mapValuesM mapValue)

def Call.values : Call V → Array V
  | .invoke plan => plan.values

def Call.anyValue (predicate : V → Bool) (call : Call V) : Bool :=
  call.values.any predicate

def Call.allValues (predicate : V → Bool) (call : Call V) : Bool :=
  call.values.all predicate

def Call.effects : Call V → EffectSummary
  | .invoke plan => { externalCall := true, sendsValue := plan.sendsValue }

def Call.wellFormed (valueWellFormed : V → Bool) : Call V → Bool
  | .invoke plan => plan.wellFormed valueWellFormed

def Call.canonical (renderValue : V → String) : Call V → String
  | .invoke plan => plan.canonical renderValue

/-- Value-producing open CALL/STATICCALL. `word` selects a bound ABI word; `limb` a UInt64 leaf. -/
structure Query where
  name : String
  argTypes : Array ArgType
  kind : CallResult.Kind := .staticcall
  policy : CallResult.Policy := .exactWord
  hasValue : Bool := false
  word : Nat := 0
  limb : Nat := 0
  deriving BEq, Repr, Inhabited

def Query.argLimbCount (query : Query) : Nat :=
  query.argTypes.foldl (init := 0) fun acc ty => acc + ty.limbCount

def Query.arity (query : Query) : Nat :=
  3 + query.argLimbCount + (if query.hasValue then 4 else 0)

def Query.copiedWordCount (query : Query) : Nat :=
  query.policy.copiedWordCount

def Query.effects (_query : Query) : EffectSummary :=
  { externalCall := true }

/-- Rebuild a `Plan` from query metadata and flattened operands
(`target₃ ++ arg-limbs… ++ value₄?`). -/
def Query.toPlan (query : Query) (operands : Array V) : Option (Plan V) := Id.run do
  unless operands.size == query.arity do return none
  let target := operands.extract 0 3
  let mut rest := operands.extract 3 operands.size
  let mut args : Array (Arg V) := #[]
  for i in [0:query.argTypes.size] do
    let ty := query.argTypes[i]!
    let n := ty.limbCount
    if rest.size < n then return none
    args := args.push { name := s!"a{i}", type := ty, parts := rest.extract 0 n }
    rest := rest.extract n rest.size
  let valueParts := if query.hasValue then rest else #[]
  if query.hasValue && valueParts.size != 4 then return none
  if !query.hasValue && !rest.isEmpty then return none
  some {
    name := query.name
    args
    target
    kind := query.kind
    policy := query.policy
    valueParts
  }

/-- Source limbs the bound word `word` yields; zero when the policy binds no such word. -/
def Query.limbCount (query : Query) : Nat :=
  ((query.policy.wordKinds[query.word]?).map (·.limbCount)).getD 0

def Query.wellFormed (query : Query) : Bool :=
  isIdent query.name && query.argTypes.size ≤ maxArgWords &&
    query.argTypes.all ArgType.supported &&
    (query.argTypes.filter ArgType.isPacked).size ≤ maxBytesArgs &&
    (query.argTypes.filter ArgType.isArray).size ≤ maxArrayArgs &&
    (query.argTypes.filter ArgType.isDynamic).size ≤ maxDynamicArgs &&
    query.policy.wellFormed &&
    query.copiedWordCount ≥ 1 &&
    query.word < query.copiedWordCount &&
    query.limb < query.limbCount &&
    (!query.hasValue || query.kind == .call)

def Query.canonical (renderValue : V → String) (operands : Array V) (query : Query) : String :=
  match query.toPlan operands with
  | some plan =>
      s!"ocallq.{query.word}.{query.limb}." ++ plan.canonical renderValue
  | none =>
      s!"invalid-ocallq-{query.word}-{query.limb}-{operands.size}"

/-- Result shape of one typed STATICCALL read as the source language sees it. Each shape names
the `CallResult.Policy` that gates the returndata frame and how many `UInt64` limbs of word 0
the extractor binds. Multiword shapes hand the source the first word; every word is still
size-gated. -/
inductive StaticShape where
  | word
  | words2
  | words3
  | words4
  | bool
  | address
  deriving BEq, Repr, Inhabited, DecidableEq

def StaticShape.all : Array StaticShape :=
  #[.word, .words2, .words3, .words4, .bool, .address]

def StaticShape.policy : StaticShape → CallResult.Policy
  | .word => .exactWord
  | .words2 => .exactWords 2
  | .words3 => .exactWords 3
  | .words4 => .exactWords 4
  | .bool => .strictBool
  | .address => .words #[.address20]

/-- Limbs of word 0 handed to the source carrier: four for `UInt256`, three for `Addr20`, one
for `Bool`. -/
def StaticShape.limbCount (shape : StaticShape) : Nat :=
  ((shape.policy.wordKinds[0]?).map (·.limbCount)).getD 0

/-- Query for limb 0 of word 0 under this shape; the extractor rebinds `limb` per carrier limb. -/
def StaticShape.query (shape : StaticShape) (name : String) (argTypes : Array ArgType) : Query :=
  { name, argTypes, kind := .staticcall, policy := shape.policy }

end ProofForge.Evm.OpenCall
