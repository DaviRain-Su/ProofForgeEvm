import ProofForge.Evm.LogError

namespace ProofForge.Evm.LogError.Emit

/-!
Sole interpreter for the typed LOG0..4 / custom-error plans (EVM-RT-2b).

`emitLog` is the only spelling of EVM event-log emission:

1. the static ABI data words at `memory[wordOffset i)` (data always starts at offset 0), then
2. for a plan with tails, one Yul block that walks a byte cursor `pf_log_end` from the end of
   the head: per tail it stores the cursor into the tail's head offset word, reverts when the
   runtime length exceeds the capacity, stores the length, stores each slot under an
   `if gt(length, slot)` guard, and advances the cursor by `(length + 1) · 32`, then
3. the `log0` … `log4` opcode named by `LogPlan.topicCount`, with data byte length
   `LogPlan.dataBytes` (or the cursor) and the topic words in plan order.

The cursor is block-scoped so two tail plans in one Yul scope never redeclare it, and the
interpreter still allocates no fresh names.

`emitRevert` is the only spelling of ABI custom-error reverts:

1. the 4-byte selector left-aligned at `memory[0..3]` via `shl(224, ..)`,
2. the ABI argument words at `memory[argOffset i)`, then
3. `revert(0, revertBytes)`.

Plans carry already-materialized Yul words, so the interpreter allocates no fresh names and
threads no emitter state; the context is indentation only, which keeps branch-scoped emission
(permit's nested gates) byte-exact with the previous inline spellings. Malformed plans (more
than 4 topics, oversized data, a selector that is not exactly 4 bytes of lowercase hex,
oversized argument lists) fail closed with an `extract/unsupported` error instead of emitting.
-/

private def nl : String := "\n"

/-- Minimal emission context shared by component emitters: indentation only. Plans consume
already-materialized words, so no fresh-name or materialization state is required. -/
structure Context where
  indent : String

private def cursor : String := "pf_log_end"

/-- Emit one validated LOG0..4 plan: static data words at `memory[0, dataBytes)`, the tails at
the cursor, then the `logN` opcode named by the topic count. -/
def emitLog (context : Context) (plan : LogPlan) : Except String String := do
  if !plan.wellFormed then
    throw "extract/unsupported: evm log plan shape"
  let indent := context.indent
  let invoke (dataBytes : String) : String :=
    plan.topics.foldl (init := "log" ++ toString plan.topicCount ++ "(0, " ++ dataBytes)
      (fun acc topic => acc ++ ", " ++ topic) ++ ")" ++ nl
  let mut txt := ""
  for i in [0:plan.data.size] do
    txt := txt ++ indent ++ "mstore(" ++ toString (LogPlan.wordOffset i) ++ ", " ++
      plan.data[i]! ++ ")" ++ nl
  if plan.tails.isEmpty then
    return txt ++ indent ++ invoke (toString plan.dataBytes)
  let inner := indent ++ "  "
  txt := txt ++ indent ++ "{" ++ nl ++
    inner ++ "let " ++ cursor ++ " := " ++ toString plan.dataBytes ++ nl
  for tailIndex in [0:plan.tails.size] do
    let tail := plan.tails[tailIndex]!
    txt := txt ++
      inner ++ "mstore(" ++ toString (plan.tailOffsetWord tailIndex) ++ ", " ++ cursor ++ ")" ++
        nl ++
      inner ++ "if gt(" ++ tail.length ++ ", " ++ toString tail.capacity ++ ") { revert(0, 0) }" ++
        nl ++
      inner ++ "mstore(" ++ cursor ++ ", " ++ tail.length ++ ")" ++ nl
    for slot in [0:tail.capacity] do
      txt := txt ++ inner ++ "if gt(" ++ tail.length ++ ", " ++ toString slot ++ ") { mstore(add(" ++
        cursor ++ ", " ++ toString (abiWordBytes * (slot + 1)) ++ "), " ++ tail.elements[slot]! ++
        ") }" ++ nl
    txt := txt ++ inner ++ cursor ++ " := add(" ++ cursor ++ ", mul(add(" ++ tail.length ++
      ", 1), " ++ toString abiWordBytes ++ "))" ++ nl
  return txt ++ inner ++ invoke cursor ++ indent ++ "}" ++ nl

/-- Emit one validated custom-error plan: selector at `memory[0..3]`, argument words at
`memory[argOffset i)`, then `revert(0, revertBytes)`. -/
def emitRevert (context : Context) (plan : ErrorPlan) : Except String String := do
  if !plan.wellFormed then
    throw "extract/unsupported: evm error plan shape"
  let indent := context.indent
  let mut txt := indent ++ "mstore(0, shl(224, 0x" ++ plan.selector ++ "))" ++ nl
  for i in [0:plan.args.size] do
    txt := txt ++ indent ++ "mstore(" ++ toString (ErrorPlan.argOffset i) ++ ", " ++
      plan.args[i]! ++ ")" ++ nl
  return txt ++ indent ++ "revert(0, " ++ toString plan.revertBytes ++ ")" ++ nl

end ProofForge.Evm.LogError.Emit
