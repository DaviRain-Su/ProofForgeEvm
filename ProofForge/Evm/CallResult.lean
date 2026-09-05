namespace ProofForge.Evm.CallResult

/-!
Target-local typed result contract for one closed external call (EVM-RT-2a, S2).

This module is the plan layer of the shared call-result policy. It names the established
returndata gates that used to be inlined per call site in `Evm.ClosedCall.Emit`, plus the S2
bounded multiword / typed-decode policies:

- `Policy.canonicalTrueOrCodeBackedEmpty` — the safe ERC-20 mutation rule: the CALL must succeed;
  returndata is either exactly one canonical ABI `true` word, or empty while the target still has
  runtime code after the call;
- `Policy.exactWord` — an exact-one-word STATICCALL read: the call must succeed and returndata
  must be exactly one 32-byte word, which is handed to the caller;
- `Policy.contractSuccess` — the call must succeed; returndata is not copied or consumed, and an
  empty result is accepted only while the target still has runtime code after the call;
- `Policy.exactWords n` — exact `n` ABI words (`1 ≤ n ≤ maxResultWords`); each word is bound;
- `Policy.strictBool` — exact one word that is a canonical ABI bool (`0` or `1`);
- `Policy.magicBytes4` — exact one word equal to a left-aligned 4-byte magic selector;
- `Policy.tryMagicBytes4` — STATICCALL that answers canonical ABI `true` when the call
  succeeds with exactly one word equal to that same left-aligned magic, and canonical
  ABI `false` on any other outcome (failed call, wrong size, dirty low bytes, wrong
  word). It never reverts for a call-result reason. `FailMode` is ignored.
- `Policy.words kinds` — exact `|kinds|` words, each validated against its declared
  `uint256` / `bool` / `address` / `bytes4` constraint.

Copied returndata is bounded by `maxResultWords` ABI words (`maxRetBytes = 128`). Established
ERC-20 / success-only policies still copy at most one word. Calldata always starts at memory
offset 0, returndata is always copied to memory offset 0, and msg.value never rides a
STATICCALL. No policy opens arbitrary callee selection, delegatecall/create, or unbounded
returndata. `FailMode.revert0` is the default call-failure spelling (`revert(0, 0)`), so
existing ClosedCall Yul and digests stay stable; `FailMode.bubble` is opt-in.

`Evm.CallResult.Emit` is the sole interpreter; `Evm.ClosedCall.Emit` consumes it so all closed
ERC-20 / WETH / Uniswap / permit call sites share one gate spelling.
-/

/-- Opcode family of one closed external call. -/
inductive Kind where
  | call
  | staticcall
  deriving BEq, Repr, Inhabited

/-- Call-failure revert spelling. Policy tails (malformed size / non-canonical words) always
use `revert(0, 0)`: the callee succeeded, so there is nothing honest to bubble. -/
inductive FailMode where
  /-- Historical spelling: `revert(0, 0)`. Default, required for ClosedCall digest stability. -/
  | revert0
  /-- Forward the callee's revert data: `returndatacopy(0, 0, returndatasize()) revert(0, returndatasize())`.
  Opt-in only; the copy length is callee-controlled. -/
  | bubble
  deriving BEq, Repr, Inhabited

/-- Declared ABI word for typed returndata decode. Each kind occupies exactly one 32-byte word. -/
inductive WordKind where
  /-- Unconstrained 32-byte word (`uint256` / `bytes32`). -/
  | uint256
  /-- Canonical ABI bool: the word is `0` or `1`. -/
  | boolean
  /-- Canonical ABI address: the high 12 bytes are zero. -/
  | address20
  /-- Canonical ABI `bytes4`: the low 28 bytes are zero (left-aligned selector). -/
  | bytes4
  deriving BEq, Repr, Inhabited

/-- Source `UInt64` limbs one bound word yields: three little-endian limbs for a canonical
address (`Addr20`), one for a bool, four for any other word. -/
def WordKind.limbCount : WordKind → Nat
  | .address20 => 3
  | .boolean => 1
  | .uint256 | .bytes4 => 4

def abiWordBytes : Nat := 32

/-- Explicit S2 ceiling: at most four static ABI words (128 bytes), matching `LogError.maxLogDataWords`. -/
def maxResultWords : Nat := 4

def maxRetBytes : Nat := abiWordBytes * maxResultWords

/-- Bytes in one ABI `bytes4` selector. -/
def selectorBytes : Nat := 4

/-- Typed result contract applied to the returndata of one closed external call. -/
inductive Policy where
  /-- Safe ERC-20 compatibility rule: CALL must succeed; returndata is either exactly one word
  equal to canonical ABI `true` (`1`), or empty while the target has runtime code after the call.
  This rejects EOAs/nonexistent targets whose CALL otherwise reports success with empty data. -/
  | canonicalTrueOrCodeBackedEmpty
  /-- Exact-one-word read: the call must succeed and returndata must be exactly one 32-byte
  word; the word is bound for the caller. Any other length reverts. -/
  | exactWord
  /-- Contract success: the call must succeed and returndata is ignored. Empty returndata also
  requires runtime code at the target after the call, so an EOA cannot masquerade as a contract. -/
  | contractSuccess
  /-- Exact `n` ABI words. `n` is a compile-time constant in `1 ..= maxResultWords`. -/
  | exactWords (n : Nat)
  /-- Exact one canonical ABI bool word (`0` or `1`). Rejects every other length and every
  non-canonical truthy word. -/
  | strictBool
  /-- Exact one ABI `bytes4` word equal to the left-aligned 4-byte magic `selector`
  (8 lowercase hex characters). -/
  | magicBytes4 (selector : String)
  /-- Soft magic read: bind ABI bool `1` when the call succeeds with exactly one word equal
  to the left-aligned 4-byte magic `selector` (8 lowercase hex characters), else bind `0`.
  Does not revert on a failed call or a malformed frame. `FailMode` is ignored. -/
  | tryMagicBytes4 (selector : String)
  /-- Exact `|kinds|` ABI words, each validated against its declared scalar/address/bool/`bytes4`
  constraint. `kinds.size` is a compile-time constant in `1 ..= maxResultWords`. -/
  | words (kinds : Array WordKind)
  deriving BEq, Repr, Inhabited

private def isLowerHexDigit (c : Char) : Bool :=
  ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')

/-- Fail-closed policy shape: S2 plans stay within `maxResultWords`, and `magicBytes4` carries
exactly 4 bytes of lowercase hex. Established policies are always well-formed. -/
def Policy.wellFormed : Policy → Bool
  | .canonicalTrueOrCodeBackedEmpty | .exactWord | .contractSuccess | .strictBool => true
  | .exactWords n => 1 ≤ n && n ≤ maxResultWords
  | .magicBytes4 selector | .tryMagicBytes4 selector =>
      selector.length == 2 * selectorBytes && selector.all isLowerHexDigit
  | .words kinds =>
      1 ≤ kinds.size && kinds.size ≤ maxResultWords

/-- Number of ABI words this policy copies and (for exact/typed policies) binds. -/
def Policy.copiedWordCount : Policy → Nat
  | .canonicalTrueOrCodeBackedEmpty | .exactWord | .strictBool | .magicBytes4 _
    | .tryMagicBytes4 _ => 1
  | .contractSuccess => 0
  | .exactWords n => n
  | .words kinds => kinds.size

/-- Declared word kinds in declaration order. Empty when the policy does not bind typed words
(`canonicalTrueOrCodeBackedEmpty` / `contractSuccess`). `exactWord` / `exactWords` are
unconstrained `uint256` words. -/
def Policy.wordKinds : Policy → Array WordKind
  | .canonicalTrueOrCodeBackedEmpty | .contractSuccess => #[]
  | .exactWord => #[.uint256]
  | .exactWords n => Array.replicate n .uint256
  | .strictBool | .tryMagicBytes4 _ => #[.boolean]
  | .magicBytes4 _ => #[.bytes4]
  | .words kinds => kinds

/-- Bytes of returndata copied to memory offset 0. Bounded by `maxRetBytes`. -/
def Policy.retBound (policy : Policy) : Nat :=
  abiWordBytes * policy.copiedWordCount

/-- One closed external call together with its typed result contract. Calldata occupies
`memory[0, inSize)`; returndata is copied to `memory[0, retBound)`. `value` marks a CALL that
carries msg.value (the value expression is supplied at emission); it is never valid on a
STATICCALL. `fail` defaults to `revert0` so existing ClosedCall spellings stay byte-identical. -/
structure Request where
  kind : Kind
  inSize : Nat
  policy : Policy
  value : Bool := false
  fail : FailMode := .revert0
  deriving BEq, Repr, Inhabited

/-- Returndata bytes copied by this request. -/
def Request.retBound (request : Request) : Nat :=
  request.policy.retBound

/-- Fail-closed shape gate: the policy is well-formed, copied returndata stays within
`maxRetBytes`, and msg.value never rides a STATICCALL. -/
def Request.wellFormed (request : Request) : Bool :=
  request.policy.wellFormed && request.retBound ≤ maxRetBytes &&
    (!request.value || request.kind == .call)

/-- Safe ERC-20 compatibility rule: CALL must succeed and returndata is either exactly canonical
ABI `true`, or empty with runtime code still present at the target after the call. -/
def Request.erc20Mutation (inSize : Nat) : Request :=
  { kind := .call, inSize, policy := .canonicalTrueOrCodeBackedEmpty }

/-- Exact-one-word STATICCALL read: the call must succeed and returndata must be exactly one
32-byte word. -/
def Request.staticWord (inSize : Nat) : Request :=
  { kind := .staticcall, inSize, policy := .exactWord }

/-- Contract-success CALL: returndata is not copied or consumed; an empty result additionally
requires runtime code at the target after the call. -/
def Request.successOnly (inSize : Nat) (value : Bool := false) : Request :=
  { kind := .call, inSize, policy := .contractSuccess, value }

/-- Exact-`n`-word STATICCALL read. -/
def Request.staticWords (inSize n : Nat) : Request :=
  { kind := .staticcall, inSize, policy := .exactWords n }

/-- Exact canonical-bool STATICCALL read. -/
def Request.staticBool (inSize : Nat) : Request :=
  { kind := .staticcall, inSize, policy := .strictBool }

/-- Exact left-aligned `bytes4` magic STATICCALL read. -/
def Request.staticMagic (inSize : Nat) (selector : String) : Request :=
  { kind := .staticcall, inSize, policy := .magicBytes4 selector }

/-- Soft left-aligned `bytes4` magic STATICCALL read. Answers `1` on exact magic, else `0`. -/
def Request.staticTryMagic (inSize : Nat) (selector : String) : Request :=
  { kind := .staticcall, inSize, policy := .tryMagicBytes4 selector }

/-- Exact typed-word STATICCALL read. -/
def Request.staticTyped (inSize : Nat) (kinds : Array WordKind) : Request :=
  { kind := .staticcall, inSize, policy := .words kinds }

end ProofForge.Evm.CallResult
