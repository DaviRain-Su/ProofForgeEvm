import ProofForge.Evm.Codec

namespace ProofForge.Evm.LogError

/-!
Target-local typed plan for EVM event-log and custom-error data (EVM-RT-2b).

This module is the plan layer of the shared LOG / custom-error policy. It names the memory
geometry that used to be inlined per effect site in `Evm.NativeFx.Emit` (and duplicated by
permit in `Evm.ClosedCall.Emit`):

- `LogPlan` — one LOG0..4 emission: the already-materialized ABI data words stored at
  `memory[wordOffset i)` (data always starts at memory offset 0) and the already-materialized
  topic words in order. `topicCount` names the `log0` … `log4` opcode and is bounded at
  `maxTopics = 4`; the static data payload is bounded at `maxLogDataWords = 4` words (128
  bytes). At most `maxLogTails = 2` bounded dynamic-array tails (`LogTailPlan`) follow the
  static words: the head then ends with one offset word per tail, and each tail publishes its
  runtime `length` word plus the first `length` of its `capacity` element words, so the data
  section is the standard ABI encoding of `(static..., T[]...)` and its byte length is a
  runtime value.
- `ErrorPlan` — one ABI custom-error revert: the 4-byte `selector` (8 lowercase hex
  characters) stored left-aligned at `memory[0..3]`, the already-materialized ABI argument
  words stored at `memory[argOffset i)`, and the total revert length
  `revertBytes = 4 + 32 · |args|`, bounded at `maxErrorArgs = 4` words.

Plans consume already-materialized Yul words; they never materialize operands, allocate fresh
names, or open opcodes beyond the `log0..4` / `revert` pair. Closed semantic names (event
signatures such as `Transfer(address,address,uint256)`, error names such as
`Insufficient(uint256,uint256)`) stay owned by `Evm.NativeFx` / `Evm.ClosedCall`; this layer
validates shape only and fails closed on any shape it does not name. It is not a source API
for arbitrary event signatures or error selectors, and validating LOG0/2/4 shapes here does
not expose them to source contracts. `Evm.LogError.Emit` is the sole interpreter.
-/

/-- Bytes in one ABI word. -/
def abiWordBytes : Nat := 32

/-- Bytes in one ABI error selector. -/
def selectorBytes : Nat := 4

/-- Hardware bound on LOG topic count (LOG0..LOG4). -/
def maxTopics : Nat := 4

/-- Bound on the static LOG data payload: at most four ABI words (128 bytes) at memory offset 0. -/
def maxLogDataWords : Nat := 4

/-- Bound on the bounded dynamic-array tails of one LOG data section. `TransferBatch(ids, values)`
carries two. -/
def maxLogTails : Nat := 2

/-- Bound on custom-error ABI argument words. -/
def maxErrorArgs : Nat := 4

/-- One bounded dynamic-array tail of a LOG data section: the already-materialized runtime element
count and the already-materialized element words, one ABI word per slot. The wire form is
`length ‖ element₀ ‖ … ‖ element₍length₋₁₎` at the offset its head word names; the slots past
`length` are never written. -/
structure LogTailPlan where
  length : String
  elements : Array String
  deriving BEq, Repr, Inhabited

/-- Compile-time slot count of one tail. -/
def LogTailPlan.capacity (tail : LogTailPlan) : Nat := tail.elements.size

/-- A tail has at least one slot, and its `length ‖ elements` frame is no larger than the
bounded-array local frame the codec accepts, so an event never publishes a bounded array an
entry could not carry. -/
def tailCapacityWellFormed (capacity : Nat) : Bool :=
  0 < capacity && 1 + capacity ≤ Codec.maxBoundedArrayLocalWords

def LogTailPlan.wellFormed (tail : LogTailPlan) : Bool :=
  tailCapacityWellFormed tail.capacity

/-- Typed plan for one LOG0..4 emission. `data` holds already-materialized static ABI words stored
at `memory[wordOffset i)`; `topics` holds the already-materialized topic words in order (topic 0
is the event signature hash for named events); `tails` holds the bounded dynamic arrays whose
offset words follow the static words in the head. -/
structure LogPlan where
  data : Array String := #[]
  topics : Array String := #[]
  tails : Array LogTailPlan := #[]
  deriving BEq, Repr, Inhabited

/-- Memory offset of ABI data word `wordIndex`; data always starts at offset 0. -/
def LogPlan.wordOffset (wordIndex : Nat) : Nat := abiWordBytes * wordIndex

/-- Topic count naming the `log0` … `log4` opcode. -/
def LogPlan.topicCount (plan : LogPlan) : Nat := plan.topics.size

/-- Byte length of the head at memory offset 0: the static words plus one offset word per tail.
Without tails this is the whole payload; with tails the payload ends at a runtime cursor. -/
def LogPlan.dataBytes (plan : LogPlan) : Nat :=
  abiWordBytes * (plan.data.size + plan.tails.size)

/-- Memory offset of the head word that names where tail `tailIndex` starts. -/
def LogPlan.tailOffsetWord (plan : LogPlan) (tailIndex : Nat) : Nat :=
  LogPlan.wordOffset (plan.data.size + tailIndex)

/-- Fail-closed shape gate: at most `maxTopics` topics, at most `maxLogDataWords` static data
words, and at most `maxLogTails` well-formed tails. -/
def LogPlan.wellFormed (plan : LogPlan) : Bool :=
  plan.topicCount ≤ maxTopics && plan.data.size ≤ maxLogDataWords &&
    plan.tails.size ≤ maxLogTails && plan.tails.all (·.wellFormed)

/-- Typed plan for one ABI custom-error revert. `selector` is the 4-byte error selector as 8
lowercase hex characters; `args` holds the already-materialized ABI argument words in order. -/
structure ErrorPlan where
  selector : String
  args : Array String := #[]
  deriving BEq, Repr, Inhabited

/-- Memory offset of ABI argument word `argIndex`; argument data starts after the selector. -/
def ErrorPlan.argOffset (argIndex : Nat) : Nat := selectorBytes + abiWordBytes * argIndex

/-- Total revert byte length: selector plus ABI argument words. -/
def ErrorPlan.revertBytes (plan : ErrorPlan) : Nat :=
  selectorBytes + abiWordBytes * plan.args.size

private def isLowerHexDigit (c : Char) : Bool :=
  ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')

/-- Fail-closed shape gate: the selector is exactly 4 bytes of lowercase hex and argument
words stay within `maxErrorArgs`. -/
def ErrorPlan.wellFormed (plan : ErrorPlan) : Bool :=
  plan.selector.length == 2 * selectorBytes && plan.selector.all isLowerHexDigit &&
    plan.args.size ≤ maxErrorArgs

end ProofForge.Evm.LogError
