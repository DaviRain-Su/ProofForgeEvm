import ProofForge.Evm.CallResult

namespace ProofForge.Evm.CallResult.Emit

/-!
Emitter interpreter for the typed call-result contract (EVM-RT-2a, S2).

`emitBound` is the sole spelling of the closed external-call result gates. `emit` wraps it
and projects the historical first-word `Option String` carrier so ClosedCall / Precompile
consumers keep their existing output and fresh-name order.

1. the `call`/`staticcall` instruction itself, with calldata at `memory[0, inSize)`, extended by
   the caller's bound padded tail length when the plan carries a `bytes` argument, and
   returndata copied to `memory[0, retBound)` (`retBound ≤ maxRetBytes`);
2. the fail-closed success gate. Default `FailMode.revert0` is `if iszero(ok) { revert(0, 0) }`,
   byte-identical with pre-S2 ClosedCall Yul. Opt-in `FailMode.bubble` forwards callee revert
   data instead;
3. the policy tail:
   - `canonicalTrueOrCodeBackedEmpty` binds `rds := returndatasize()`, accepts exactly one word
     only when it equals canonical ABI `true`, and accepts empty data only when the target still
     has runtime code after the call;
   - `exactWord` reverts unless `returndatasize() = 32` and binds the returned word;
   - `contractSuccess` never copies or consumes returndata, but an empty result requires runtime
     code at the target after the call;
   - `exactWords n` / `words kinds` / `strictBool` / `magicBytes4` compare `returndatasize()`
     with the full expected static frame, bind each copied word, and validate declared
     bool/address/`bytes4`/magic constraints.

Malformed requests (oversized plans, invalid magic selectors, msg.value on a STATICCALL, a
missing or unexpected value expression) fail closed with an `extract/unsupported` error instead
of emitting. Fresh-name allocation order (`ok`, then the policy temporaries) is part of the
contract so consumers observe no naming drift.
-/

private def nl : String := "\n"
private def revert0 : String := "revert(0, 0)"
private def abiWordSize : String := toString CallResult.abiWordBytes

/-- Bound Yul names for decoded returndata words, in declaration order. Empty when the policy
does not bind words (`canonicalTrueOrCodeBackedEmpty`, `contractSuccess`). -/
structure Bound where
  names : Array String := #[]
  deriving BEq, Repr, Inhabited

/-- Historical first-word carrier. `none` when the policy binds no words. -/
def Bound.word (bound : Bound) : Option String :=
  bound.names[0]?

/-- Minimal emission context shared by component emitters: fresh Yul names and indentation. -/
structure Context (σ : Type) where
  fresh : σ → String × σ
  indent : String

/-- Call-failure body. Policy tails always keep `revert(0, 0)`. -/
private def failStmt : CallResult.FailMode → String
  | .revert0 => revert0
  | .bubble => "returndatacopy(0, 0, returndatasize()) revert(0, returndatasize())"

/-- Canonicality gate for one already-bound word. Unconstrained `uint256` emits nothing. -/
private def wordGate (indent name : String) : CallResult.WordKind → String
  | .uint256 => ""
  | .boolean => indent ++ "if gt(" ++ name ++ ", 1) { " ++ revert0 ++ " }" ++ nl
  | .address20 => indent ++ "if shr(160, " ++ name ++ ") { " ++ revert0 ++ " }" ++ nl
  | .bytes4 => indent ++ "if shl(32, " ++ name ++ ") { " ++ revert0 ++ " }" ++ nl

/-- Exact-size compare, then bind and validate each word. Fresh-name order is left-to-right. -/
private def emitExactWords (context : Context σ) (indent : String) (st : σ)
    (kinds : Array CallResult.WordKind) : String × Bound × σ :=
  Id.run do
    let mut st := st
    let mut names : Array String := #[]
    let mut txt :=
      indent ++ "if iszero(eq(returndatasize(), " ++
        toString (CallResult.abiWordBytes * kinds.size) ++ ")) { " ++ revert0 ++ " }" ++ nl
    for i in [0:kinds.size] do
      let (name, st') := context.fresh st
      st := st'
      names := names.push name
      txt :=
        txt ++ indent ++ "let " ++ name ++ " := mload(" ++
          toString (CallResult.abiWordBytes * i) ++ ")" ++ nl ++
          wordGate indent name kinds[i]!
    return (txt, { names }, st)

/-- Emit one closed external call and its typed fail-closed result gates, binding every
decoded word. `target` is the already-materialized callee word; `value` is the msg.value
expression and must be present exactly when `request.value` holds. `inSizeTail` is the
already-bound padded byte count of a dynamic calldata tail, added to the static
`request.inSize` when present. -/
def emitBound (context : Context σ) (request : CallResult.Request) (target : String)
    (value : Option String) (st : σ) (inSizeTail : Option String := none) :
    Except String (String × Bound × σ) := do
  if !(request.wellFormed) then
    throw "extract/unsupported: evm call-result request shape"
  if request.value != value.isSome then
    throw "extract/unsupported: evm call-result value shape"
  let indent := context.indent
  let (ok, st1) := context.fresh st
  let inSize := match inSizeTail with
    | none => toString request.inSize
    | some tail => "add(" ++ toString request.inSize ++ ", " ++ tail ++ ")"
  let invoke := match request.kind, value with
    | .call, some val =>
        "call(gas(), " ++ target ++ ", " ++ val ++ ", 0, " ++ inSize ++
          ", 0, " ++ toString request.retBound ++ ")"
    | .call, none =>
        "call(gas(), " ++ target ++ ", 0, 0, " ++ inSize ++
          ", 0, " ++ toString request.retBound ++ ")"
    | .staticcall, _ =>
        "staticcall(gas(), " ++ target ++ ", 0, " ++ inSize ++
          ", 0, " ++ toString request.retBound ++ ")"
  let head :=
    indent ++ "let " ++ ok ++ " := " ++ invoke ++ nl ++
    indent ++ "if iszero(" ++ ok ++ ") { " ++ failStmt request.fail ++ " }" ++ nl
  match request.policy with
  | .contractSuccess =>
      return (head ++
        indent ++ "if and(iszero(returndatasize()), iszero(extcodesize(" ++ target ++ "))) { " ++
          revert0 ++ " }" ++ nl, {}, st1)
  | .exactWord =>
      let (word, st2) := context.fresh st1
      return (head ++
        indent ++ "if iszero(eq(returndatasize(), " ++ abiWordSize ++ ")) { " ++
          revert0 ++ " }" ++ nl ++
        indent ++ "let " ++ word ++ " := mload(0)" ++ nl, { names := #[word] }, st2)
  | .canonicalTrueOrCodeBackedEmpty =>
      let (rds, st2) := context.fresh st1
      return (head ++
        indent ++ "let " ++ rds ++ " := returndatasize()" ++ nl ++
        indent ++ "switch " ++ rds ++ nl ++
        indent ++ "case 0 { if iszero(extcodesize(" ++ target ++ ")) { " ++ revert0 ++ " } }" ++ nl ++
        indent ++ "case " ++ abiWordSize ++ " { if iszero(eq(mload(0), 1)) { " ++ revert0 ++
          " } }" ++ nl ++
        indent ++ "default { " ++ revert0 ++ " }" ++ nl, {}, st2)
  | .exactWords n =>
      let (tail, bound, st2) := emitExactWords context indent st1 (Array.replicate n .uint256)
      return (head ++ tail, bound, st2)
  | .strictBool =>
      let (tail, bound, st2) := emitExactWords context indent st1 #[.boolean]
      return (head ++ tail, bound, st2)
  | .magicBytes4 selector =>
      let (tail, bound, st2) := emitExactWords context indent st1 #[.bytes4]
      let some name := bound.word
        | throw "extract/unsupported: evm call-result missing word"
      -- Equality to the left-aligned magic already implies canonical `bytes4`; keep the
      -- explicit low-28-zero gate so `WordKind.bytes4` has one spelling.
      return (head ++ tail ++
        indent ++ "if iszero(eq(" ++ name ++ ", shl(224, 0x" ++ selector ++ "))) { " ++
          revert0 ++ " }" ++ nl, bound, st2)
  | .words kinds =>
      let (tail, bound, st2) := emitExactWords context indent st1 kinds
      return (head ++ tail, bound, st2)

/-- Yul for source limb `limb` of the bound word `src`. A canonical address word yields the
little-endian byte limbs `pf_store_addr20` consumes (bytes 12..19, 20..27, 28..31 of the word);
any other word yields numeric 64-bit limbs from bit `64 * limb`. -/
def wordLimb (kind : CallResult.WordKind) (src : String) (limb : Nat) : String :=
  match kind with
  | .address20 =>
      let rec orBytes (index remaining : Nat) (acc : String) : String :=
        match remaining with
        | 0 => acc
        | count + 1 =>
            let byteExpr := "byte(" ++ toString (12 + 8 * limb + index) ++ ", " ++ src ++ ")"
            let next :=
              if index == 0 then byteExpr
              else "or(" ++ acc ++ ", shl(" ++ toString (8 * index) ++ ", " ++ byteExpr ++ "))"
            orBytes (index + 1) count next
      orBytes 0 (if limb == 2 then 4 else 8) "0"
  | .uint256 | .boolean | .bytes4 =>
      "and(shr(" ++ toString (64 * limb) ++ ", " ++ src ++ "), 0xffffffffffffffff)"

/-- Compatibility wrapper: same Yul and fresh-name order as `emitBound`, projecting the
historical first-word `Option String` carrier for ClosedCall / Precompile consumers. -/
def emit (context : Context σ) (request : CallResult.Request) (target : String)
    (value : Option String) (st : σ) : Except String (String × Option String × σ) := do
  let (txt, bound, st') ← emitBound context request target value st
  return (txt, bound.word, st')

end ProofForge.Evm.CallResult.Emit
