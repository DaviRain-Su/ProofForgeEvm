import ProofForge.Core.Ops
import ProofForge.Evm.CallResult
import ProofForge.Evm.Codec
import ProofForge.Evm.Keccak

namespace ProofForge.Evm.OpenCall

/-!
Typed external CALL sibling of `ClosedCall` (S3). “Open” means the target address may be a
typed source value; the call contract stays static and compiler-checked:

- CALL or STATICCALL;
- compile-time function name and fixed one-word-per-argument ABI schema;
- typed argument limbs and optional typed CALL value;
- one `CallResult.Policy`;
- `externalCall` (and `sendsValue` when msg.value is present).

Calldata is assembled by the emitter. The source API never accepts an arbitrary bytes payload,
selector string, return buffer length, or opcode. `delegatecall`, CREATE/CREATE2, and proxy
dispatch are not variants. `NativeFx.sendEth` stays a separate zero-calldata primitive.
-/

/-- Fail-closed calldata bound: selector plus at most eight static ABI words. -/
def maxArgWords : Nat := 8

/-- Transitive effects for one typed open CALL. -/
structure EffectSummary where
  externalCall : Bool := false
  sendsValue : Bool := false
  deriving BEq, Repr, Inhabited

/-- One ABI argument: declaration-order name, closed scalar type, little-endian source limbs. -/
structure Arg (V : Type) where
  name : String
  type : Core.Codec.Scalar
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

def Plan.inSize (plan : Plan V) : Nat :=
  CallResult.selectorBytes + CallResult.abiWordBytes * plan.args.size

def Plan.request (plan : Plan V) : CallResult.Request :=
  { kind := plan.kind
    inSize := plan.inSize
    policy := plan.policy
    value := plan.sendsValue }

/-- Solidity-style identifier: non-empty, starts with a letter, then alphanumerics/`_`. -/
def isIdent (s : String) : Bool :=
  !s.isEmpty && s.front.isAlpha && s.all (fun c => c.isAlphanum || c == '_')

/-- Closed EVM argument vocabulary: the same one-word carriers typed events already admit. -/
def argScalarSupported (type : Core.Codec.Scalar) : Bool :=
  Codec.isNarrowIntegerCarrier type || Codec.isWideIntegerCarrier type ||
    Codec.isAddressCarrier type || Codec.isFixedBytesCarrier type

def Arg.wellFormed (valueWellFormed : V → Bool) (arg : Arg V) : Bool :=
  isIdent arg.name && argScalarSupported arg.type &&
    arg.parts.size == Codec.limbCount arg.type && arg.parts.all valueWellFormed

def Plan.wellFormed (valueWellFormed : V → Bool) (plan : Plan V) : Bool :=
  let names := plan.args.toList.map (·.name)
  isIdent plan.name && plan.args.size ≤ maxArgWords &&
    names.length == names.eraseDups.length &&
    plan.args.all (Arg.wellFormed valueWellFormed) &&
    plan.target.size == 3 && plan.target.all valueWellFormed &&
    (plan.valueParts.isEmpty || plan.valueParts.size == 4) &&
    plan.valueParts.all valueWellFormed &&
    plan.request.wellFormed

def Plan.abiTypes (plan : Plan V) : Except String (Array String) :=
  plan.args.mapM fun arg => Codec.abiType arg.type

/-- Keccak selector of `name(type1,type2,...)`. Fails closed on a malformed plan. -/
def Plan.selectorHex (valueWellFormed : V → Bool) (plan : Plan V) : Except String String := do
  unless plan.wellFormed valueWellFormed do
    throw "extract/unsupported: malformed open-call plan"
  let types ← plan.args.mapM fun arg => Codec.abiType arg.type
  pure (Keccak.selector plan.name types)

def policyCanon : CallResult.Policy → String
  | .canonicalTrueOrCodeBackedEmpty => "erc20"
  | .exactWord => "word1"
  | .contractSuccess => "ok"
  | .exactWords n => s!"word{n}"
  | .strictBool => "bool"
  | .magicBytes4 sel => s!"magic{sel}"
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
    s!"{arg.name}:{repr arg.type}({String.intercalate "," (arg.parts.map renderValue).toList})"
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
  argTypes : Array Core.Codec.Scalar
  kind : CallResult.Kind := .staticcall
  policy : CallResult.Policy := .exactWord
  hasValue : Bool := false
  word : Nat := 0
  limb : Nat := 0
  deriving BEq, Repr, Inhabited

def Query.argLimbCount (query : Query) : Nat :=
  query.argTypes.foldl (init := 0) fun acc ty => acc + Codec.limbCount ty

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
    let n := Codec.limbCount ty
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

def Query.wellFormed (query : Query) : Bool :=
  isIdent query.name && query.argTypes.size ≤ maxArgWords &&
    query.argTypes.all argScalarSupported &&
    query.policy.wellFormed &&
    query.copiedWordCount ≥ 1 &&
    query.word < query.copiedWordCount &&
    query.limb ≤ 3 &&
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
def StaticShape.limbCount : StaticShape → Nat
  | .word | .words2 | .words3 | .words4 => 4
  | .address => 3
  | .bool => 1

/-- Query for limb 0 of word 0 under this shape; the extractor rebinds `limb` per carrier limb. -/
def StaticShape.query (shape : StaticShape) (name : String)
    (argTypes : Array Core.Codec.Scalar) : Query :=
  { name, argTypes, kind := .staticcall, policy := shape.policy }

end ProofForge.Evm.OpenCall
