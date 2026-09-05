import ProofForge.Evm.Codec

namespace ProofForge.Evm.Codec.Emit

private def nl : String := "\n"
private def revert0 : String := "revert(0, 0)"

/-- Limb `word` of an ABI address word `src` as the inline byte shuffle: Addr20 is three
little-endian limbs over address bytes `8*word ..`, which sit at bytes 12..31 of the word. -/
def addrLimbChain (src : String) (word : Nat) : String :=
  let rec orBytes (i : Nat) (n : Nat) (acc : String) : String :=
    match n with
    | 0 => acc
    | n' + 1 =>
      let b := "byte(" ++ toString (12 + 8 * word + i) ++ ", " ++ src ++ ")"
      let next :=
        if i == 0 then b
        else "or(" ++ acc ++ ", shl(" ++ toString (8 * i) ++ ", " ++ b ++ "))"
      orBytes (i + 1) n' next
  let count := if word == 2 then 4 else 8
  orBytes 0 count "0"

/-- Limb `word` of the address word `src`, as a call to the runtime helper. Every keyed map
read, topic and comparison re-derives the limbs of the same few words, and the inline shuffle
is twenty-two nested opcodes solc neither shares across dispatcher cases nor keeps shallow on
the stack; the helper body is the one copy. -/
def packAddrWord (src : String) (word : Nat) : String :=
  s!"pf_addr_w{word}({src})"

/-- The word three address limbs came from, when they are `packAddrWord` of one source word
(or all zero). Packing such limbs back into an ABI word is the identity on that word. -/
def addrWordOfLimbs (w0 w1 w2 : String) : Option String :=
  if w0 == "0" && w1 == "0" && w2 == "0" then some "0"
  else
    let head := "pf_addr_w0("
    if w0.startsWith head && w0.endsWith ")" then
      let src := ((w0.drop head.length).dropEnd 1).toString
      if w1 == packAddrWord src 1 && w2 == packAddrWord src 2 then some src else none
    else none

/-- Runtime limb helpers, one per limb, each the shuffle `addrLimbChain` spells. -/
def renderAddrLimbHelpers (indent : String) : String :=
  String.join <| (List.range 3).map fun word =>
    indent ++ s!"function pf_addr_w{word}(x) -> r \{" ++ nl ++
    indent ++ "  r := " ++ addrLimbChain "x" word ++ nl ++
    indent ++ "}" ++ nl

/-- Bind `word` to the ABI address word of three limbs: the source word itself when the limbs
were taken from one, otherwise the runtime byte shuffle through scratch memory. -/
def bindAddrWord (indent word w0 w1 w2 : String) : String :=
  match addrWordOfLimbs w0 w1 w2 with
  | some src => indent ++ "let " ++ word ++ " := " ++ src ++ nl
  | none =>
      indent ++ "mstore(0, 0)" ++ nl ++
      indent ++ "pf_store_addr20(0, " ++ w0 ++ ", " ++ w1 ++ ", " ++ w2 ++ ")" ++ nl ++
      indent ++ "let " ++ word ++ " := mload(0)" ++ nl

/-- Little-endian 64-bit limb `word` of a 256-bit ABI/storage word. -/
def packU256Word (src : String) (word : Nat) : String :=
  "and(shr(" ++ toString (64 * word) ++ ", " ++ src ++ "), 0xffffffffffffffff)"

/-- The word four limbs came from, when they are `packU256Word` 0..3 of one source word (or
all zero), so packing them back is the identity on that word. -/
def u256WordOfLimbs (w0 w1 w2 w3 : String) : Option String :=
  if w0 == "0" && w1 == "0" && w2 == "0" && w3 == "0" then some "0"
  else
    let head := "and(shr(0, "
    let tail := "), 0xffffffffffffffff)"
    if w0.startsWith head && w0.endsWith tail && w0.length > head.length + tail.length then
      let src := ((w0.drop head.length).dropEnd tail.length).toString
      if w1 == packU256Word src 1 && w2 == packU256Word src 2 && w3 == packU256Word src 3
      then some src else none
    else none

/-- A 256-bit word from four little-endian limbs. Limbs that were just split from one word
name that word again instead of rebuilding it (seven nested opcodes solc keeps on the stack
next to every live argument of the method). -/
def packU256 (w0 w1 w2 w3 : String) : String :=
  match u256WordOfLimbs w0 w1 w2 w3 with
  | some src => src
  | none =>
      "or(or(" ++ w0 ++ ", shl(64, " ++ w1 ++ ")), or(shl(128, " ++ w2 ++ "), shl(192, " ++
        w3 ++ ")))"

/-- Render canonical padding/range checks for one standard-ABI word. -/
def renderWordGuard (indent name : String) (type : Core.Codec.Scalar) :
    Except String String := do
  match ← Codec.wordGuard type with
  | .fullWord => return ""
  | .boolean =>
      return indent ++ "if gt(" ++ name ++ ", 1) { " ++ revert0 ++ " }" ++ nl
  | .unsignedMax bits =>
      return indent ++ "if gt(" ++ name ++ ", " ++ Codec.byteMask (bits / 8) ++
        ") { " ++ revert0 ++ " }" ++ nl
  | .address160 =>
      return indent ++ "if gt(" ++ name ++ ", " ++ Codec.byteMask 20 ++
        ") { " ++ revert0 ++ " }" ++ nl
  | .fixedBytesLeftPadded bytes =>
      return indent ++ "if and(" ++ name ++ ", " ++ Codec.byteMask (32 - bytes) ++
        ") { " ++ revert0 ++ " }" ++ nl

/-- Render one fixed tagged-frame canonicality policy over caller-supplied expressions. Input and
output adapters share this bounded policy interpreter, but retain separate plans and state. -/
private def renderTaggedFrameGuards (indent tag : String) (payloadWords : Nat)
    (payloadAt : Nat → String) (activePayloadWords : Array Nat) : Except String String := do
  unless !activePayloadWords.isEmpty && activePayloadWords.all (· ≤ payloadWords) do
    throw "evm/codec: malformed tagged tuple v1 guard"
  let mut out := indent ++ "if iszero(lt(" ++ tag ++ ", " ++
    toString activePayloadWords.size ++ ")) { " ++ revert0 ++ " }" ++ nl
  for variant in [0:activePayloadWords.size] do
    let active := activePayloadWords[variant]!
    for lane in [active:payloadWords] do
      out := out ++ indent ++ "if and(eq(" ++ tag ++ ", " ++ toString variant ++
        "), " ++ payloadAt lane ++ ") { " ++ revert0 ++ " }" ++ nl
  return out

/-- Interpret fixed Tagged Tuple v1 guards from the input codec plan. This is independent of
contract Ops and storage: it only constrains already decoded input locals. -/
def renderTaggedGuards (indent argPrefix : String)
    (plans : Array Codec.AbiInputPlan) : Except String String := do
  let mut out := ""
  let mut base := 0
  for plan in plans do
    for guard in plan.taggedGuards do
      unless guard.tagWord < plan.wordCount &&
          guard.payloadStart + guard.payloadWords ≤ plan.wordCount do
        throw "evm/codec: malformed tagged tuple v1 guard"
      let tag := argPrefix ++ toString (base + guard.tagWord)
      out := out ++ (← renderTaggedFrameGuards indent tag guard.payloadWords
        (fun lane => argPrefix ++ toString (base + guard.payloadStart + lane))
        guard.activePayloadWords)
    base := base + plan.wordCount
  return out

/-- Render one strict Unicode-scalar UTF-8 scanner over a target-owned byte accessor. Input
calldata, OpenCall string tails, and output memory supply different accessors without duplicating
the validation policy. -/
def renderUtf8Guard (namePrefix indent lengthName : String)
    (byteAt : String → String) (index : Nat) : String :=
  let i := namePrefix ++ "i" ++ toString index
  let need := namePrefix ++ "need" ++ toString index
  let min := namePrefix ++ "min" ++ toString index
  let max := namePrefix ++ "max" ++ toString index
  let byte := namePrefix ++ "byte" ++ toString index
  indent ++ "let " ++ i ++ " := 0" ++ nl ++
  indent ++ "let " ++ need ++ " := 0" ++ nl ++
  indent ++ "let " ++ min ++ " := 128" ++ nl ++
  indent ++ "let " ++ max ++ " := 191" ++ nl ++
  indent ++ "for { } lt(" ++ i ++ ", " ++ lengthName ++ ") { " ++ i ++
    " := add(" ++ i ++ ", 1) } {" ++ nl ++
  indent ++ "  let " ++ byte ++ " := " ++ byteAt i ++ nl ++
  indent ++ "  switch " ++ need ++ nl ++
  indent ++ "  case 0 {" ++ nl ++
  indent ++ "    if gt(" ++ byte ++ ", 127) {" ++ nl ++
  indent ++ "      if or(lt(" ++ byte ++ ", 194), gt(" ++ byte ++ ", 244)) { " ++
    revert0 ++ " }" ++ nl ++
  indent ++ "      if lt(" ++ byte ++ ", 224) { " ++ need ++ " := 1 }" ++ nl ++
  indent ++ "      if and(gt(" ++ byte ++ ", 223), lt(" ++ byte ++ ", 240)) {" ++ nl ++
  indent ++ "        " ++ need ++ " := 2" ++ nl ++
  indent ++ "        if eq(" ++ byte ++ ", 224) { " ++ min ++ " := 160 }" ++ nl ++
  indent ++ "        if eq(" ++ byte ++ ", 237) { " ++ max ++ " := 159 }" ++ nl ++
  indent ++ "      }" ++ nl ++
  indent ++ "      if gt(" ++ byte ++ ", 239) {" ++ nl ++
  indent ++ "        " ++ need ++ " := 3" ++ nl ++
  indent ++ "        if eq(" ++ byte ++ ", 240) { " ++ min ++ " := 144 }" ++ nl ++
  indent ++ "        if eq(" ++ byte ++ ", 244) { " ++ max ++ " := 143 }" ++ nl ++
  indent ++ "      }" ++ nl ++
  indent ++ "    }" ++ nl ++
  indent ++ "  }" ++ nl ++
  indent ++ "  default {" ++ nl ++
  indent ++ "    if or(lt(" ++ byte ++ ", " ++ min ++ "), gt(" ++ byte ++ ", " ++
    max ++ ")) { " ++ revert0 ++ " }" ++ nl ++
  indent ++ "    " ++ need ++ " := sub(" ++ need ++ ", 1)" ++ nl ++
  indent ++ "    " ++ min ++ " := 128" ++ nl ++
  indent ++ "    " ++ max ++ " := 191" ++ nl ++
  indent ++ "  }" ++ nl ++
  indent ++ "}" ++ nl ++
  indent ++ "if " ++ need ++ " { " ++ revert0 ++ " }" ++ nl

/-- A packed `bytes` / `string` entry parameter stays in calldata. The decoder binds its length
to the local `arg{lengthWord}` and its payload offset to `abi_bytes{lengthWord}`; the
`capacity` byte words that follow the length in the local frame are never bound. Binding them
cost one local plus one guarded load per byte at the entry and one guarded store per byte at
every forward, about 3.5 KB of runtime code for a 65-byte signature. -/
structure PackedBytesFrame where
  lengthWord : Nat
  capacity : Nat
  deriving Repr, BEq

namespace PackedBytesFrame

def dataName (frame : PackedBytesFrame) : String :=
  "abi_bytes" ++ toString frame.lengthWord

def holdsByte (frame : PackedBytesFrame) (word : Nat) : Bool :=
  frame.lengthWord < word && word ≤ frame.lengthWord + frame.capacity

/-- Byte word `word` read in place. The decoder proved the padding zero, but another dynamic
tail may follow the padded payload, so a slot at or past the length reads as zero by the guard
rather than by position. -/
def byteExpr (frame : PackedBytesFrame) (word : Nat) : String :=
  let slot := toString (word - frame.lengthWord - 1)
  "mul(lt(" ++ slot ++ ", arg" ++ toString frame.lengthWord ++ "), byte(0, calldataload(add(" ++
    frame.dataName ++ ", " ++ slot ++ "))))"

end PackedBytesFrame

/-- The packed-bytes frames of an entry, in plan order over the local frame. -/
def packedBytesFrames (plans : Array Codec.AbiInputPlan) : Array PackedBytesFrame := Id.run do
  let mut frames : Array PackedBytesFrame := #[]
  let mut localWord := 0
  for plan in plans do
    if let some bytes := plan.packedBytes then
      frames := frames.push { lengthWord := localWord, capacity := bytes.capacity }
    localWord := localWord + plan.wordCount
  return frames

/-- Interpret EVM input plans into one fixed local frame. Static values load from the top-level
head. Dynamic plans require canonical contiguous tails, cap their runtime length, zero inactive
array locals, and validate packed bytes or every active array word before contract CFG
execution. Packed bytes bind only their length and payload offset (`PackedBytesFrame`). -/
def renderEntryArgs (plans : Array Codec.AbiInputPlan)
    (paramTypes : Array Core.Codec.Scalar) : Except String String := do
  let localWords := plans.foldl (init := 0) fun count plan => count + plan.wordCount
  unless localWords == paramTypes.size do
    throw "evm/codec: input plan local frame does not match parameter metadata"
  let headWords := plans.foldl (init := 0) fun count plan => count + plan.headWordCount
  let headBytes := headWords * 32
  let hasDynamic := plans.any (·.dynamic.isSome)
  let mut out := ""
  if hasDynamic then
    out := out ++
      "        if lt(calldatasize(), " ++ toString (4 + headBytes) ++ ") { " ++
        revert0 ++ " }" ++ nl ++
      "        let abi_size := sub(calldatasize(), 4)" ++ nl ++
      "        let abi_tail := " ++ toString headBytes ++ nl
  else
    out := out ++
      "        if iszero(eq(calldatasize(), " ++ toString (4 + headBytes) ++ ")) { " ++
        revert0 ++ " }" ++ nl
  let mut headWord := 0
  let mut localWord := 0
  let mut dynamicIndex := 0
  for plan in plans do
    match plan.dynamic with
    | none =>
        for i in [0:plan.wordCount] do
          let localIndex := localWord + i
          out := out ++
            "        let arg" ++ toString localIndex ++ " := calldataload(" ++
              toString (4 + (headWord + i) * 32) ++ ")" ++ nl
          let some type := paramTypes[localIndex]?
            | throw s!"evm/codec: missing entry parameter metadata at {localIndex}"
          out := out ++ (← renderWordGuard "        " ("arg" ++ toString localIndex) type)
        headWord := headWord + plan.wordCount
        localWord := localWord + plan.wordCount
    | some (.boundedArray array) =>
        let elementWords := array.elementWords.size
        unless 0 < elementWords &&
            plan.wordCount == 1 + array.capacity * elementWords &&
            plan.words[0]? == some .uint32 do
          throw "evm/codec: malformed bounded array v1 input plan"
        let dataName := "abi_data" ++ toString dynamicIndex
        let lengthName := "arg" ++ toString localWord
        out := out ++
          "        if iszero(eq(calldataload(" ++ toString (4 + headWord * 32) ++
            "), abi_tail)) { " ++ revert0 ++ " }" ++ nl ++
          "        let " ++ dataName ++ " := abi_tail" ++ nl ++
          "        if gt(add(" ++ dataName ++ ", 32), abi_size) { " ++ revert0 ++ " }" ++ nl ++
          "        let " ++ lengthName ++ " := calldataload(add(4, " ++ dataName ++ "))" ++ nl ++
          "        if gt(" ++ lengthName ++ ", " ++ toString array.capacity ++ ") { " ++
            revert0 ++ " }" ++ nl
        for i in [1:plan.wordCount] do
          out := out ++ "        let arg" ++ toString (localWord + i) ++ " := 0" ++ nl
        let elementBytes := elementWords * 32
        out := out ++
          "        abi_tail := add(abi_tail, add(32, mul(" ++ lengthName ++ ", " ++
            toString elementBytes ++ ")))" ++ nl ++
          "        if gt(abi_tail, abi_size) { " ++ revert0 ++ " }" ++ nl
        for elementIndex in [0:array.capacity] do
          out := out ++ "        if gt(" ++ lengthName ++ ", " ++ toString elementIndex ++
            ") {" ++ nl
          for wordIndex in [0:elementWords] do
            let relative := 1 + elementIndex * elementWords + wordIndex
            let localIndex := localWord + relative
            let dataOffset := 32 + (elementIndex * elementWords + wordIndex) * 32
            out := out ++
              "          arg" ++ toString localIndex ++ " := calldataload(add(add(4, " ++
                dataName ++ "), " ++ toString dataOffset ++ "))" ++ nl
            let some type := paramTypes[localIndex]?
              | throw s!"evm/codec: missing bounded element metadata at {localIndex}"
            out := out ++ (← renderWordGuard "          " ("arg" ++ toString localIndex) type)
          out := out ++ "        }" ++ nl
        headWord := headWord + 1
        localWord := localWord + plan.wordCount
        dynamicIndex := dynamicIndex + 1
    | some (.packedBytes bytes) =>
        unless plan.wordCount == 1 + bytes.capacity && plan.words[0]? == some .uint32 &&
            plan.words.extract 1 plan.wordCount == Array.replicate bytes.capacity .uint8 do
          throw "evm/codec: malformed packed bytes v1 input plan"
        let dataName := "abi_data" ++ toString dynamicIndex
        let lengthName := "arg" ++ toString localWord
        let payloadName := PackedBytesFrame.dataName { lengthWord := localWord, capacity := bytes.capacity }
        let paddedName := "abi_padded" ++ toString dynamicIndex
        let paddingIndex := "abi_padding_i" ++ toString dynamicIndex
        out := out ++
          "        if iszero(eq(calldataload(" ++ toString (4 + headWord * 32) ++
            "), abi_tail)) { " ++ revert0 ++ " }" ++ nl ++
          "        let " ++ dataName ++ " := abi_tail" ++ nl ++
          "        if gt(add(" ++ dataName ++ ", 32), abi_size) { " ++ revert0 ++ " }" ++ nl ++
          "        let " ++ lengthName ++ " := calldataload(add(4, " ++ dataName ++ "))" ++ nl ++
          "        if gt(" ++ lengthName ++ ", " ++ toString bytes.capacity ++ ") { " ++
            revert0 ++ " }" ++ nl ++
          "        let " ++ payloadName ++ " := add(add(4, " ++ dataName ++ "), 32)" ++ nl ++
          "        let " ++ paddedName ++ " := and(add(" ++ lengthName ++
            ", 31), not(31))" ++ nl ++
          "        abi_tail := add(abi_tail, add(32, " ++ paddedName ++ "))" ++ nl ++
          "        if gt(abi_tail, abi_size) { " ++ revert0 ++ " }" ++ nl ++
          "        for { let " ++ paddingIndex ++ " := " ++ lengthName ++ " } lt(" ++
            paddingIndex ++ ", " ++ paddedName ++ ") { " ++ paddingIndex ++ " := add(" ++
            paddingIndex ++ ", 1) } {" ++ nl ++
          "          if byte(0, calldataload(add(" ++ payloadName ++ ", " ++ paddingIndex ++
            "))) { " ++ revert0 ++ " }" ++ nl ++
          "        }" ++ nl
        if bytes.validateUtf8 then
          out := out ++ renderUtf8Guard "abi_utf8_" "        " lengthName (fun i =>
            "byte(0, calldataload(add(" ++ payloadName ++ ", " ++ i ++ ")))"
          ) dynamicIndex
        headWord := headWord + 1
        localWord := localWord + plan.wordCount
        dynamicIndex := dynamicIndex + 1
  if hasDynamic then
    out := out ++ "        if iszero(eq(abi_size, abi_tail)) { " ++ revert0 ++ " }" ++ nl
  return out

/-- Generic bridge from the target codec interpreter to the main CFG value materializer. ABI
output policy stays in this module; the main emitter supplies only source-value evaluation. -/
structure ReturnContext (Value State : Type) where
  indent : String
  materialize : String → Value → State → Except String (String × String × State)

/-- Pack Extract source limbs back into one ABI word for a dynamic array element. -/
private def packElementWord (type : Core.Codec.Scalar) (limbs : Array String) : Except String String := do
  let expected := limbCount type
  unless limbs.size == expected && expected ≠ 0 do
    throw "evm/codec: malformed wide element limb frame"
  if expected == 1 then
    return limbs[0]!
  if isWideIntegerCarrier type then
    let a0 := limbs[0]!
    let a1 := (limbs[1]?).getD "0"
    let a2 := (limbs[2]?).getD "0"
    let a3 := (limbs[3]?).getD "0"
    return "or(or(" ++ a0 ++ ", shl(64, " ++ a1 ++ ")), or(shl(128, " ++ a2 ++
      "), shl(192, " ++ a3 ++ ")))"
  if isAddressCarrier type then
    unless limbs.size == 3 do
      throw "evm/codec: address element requires three source limbs"
    -- Little-endian 20-byte address in the low 20 bytes of the ABI word (matches pf_store_addr20).
    return "or(or(" ++ limbs[0]! ++ ", shl(64, " ++ limbs[1]! ++ ")), shl(128, and(" ++
      limbs[2]! ++ ", 0xffffffff)))"
  if isFixedBytesCarrier type then
    let a0 := limbs[0]!
    let a1 := (limbs[1]?).getD "0"
    let a2 := (limbs[2]?).getD "0"
    let a3 := (limbs[3]?).getD "0"
    return "or(or(" ++ a0 ++ ", shl(64, " ++ a1 ++ ")), or(shl(128, " ++ a2 ++
      "), shl(192, " ++ a3 ++ ")))"
  throw "evm/codec: unsupported wide element carrier for dynamic return"

/-- Interpret one bounded dynamic output plan. The fixed source frame is never returned directly:
the encoder emits the canonical ABI offset/length header and only the active array or byte prefix.
Wide one-ABI-word elements and constructed multi-word static elements are packed from the Extract
limb frame; nested dynamics remain outside this plan. -/
def renderDynamicReturn [Inhabited Value] (context : ReturnContext Value State)
    (plan : DynamicOutputPlan) (values : Array Value) (state : State) :
    Except String (String × State) := do
  let indent := context.indent
  unless values.size == plan.sourceWords.size do
    throw s!"evm/codec: dynamic result has {values.size} source parts, expected {plan.sourceWords.size}"
  let (lengthPre, length, state0) ← context.materialize indent values[0]! state
  let mut state := state0
  let mut out := lengthPre
  let header :=
    indent ++ "mstore(0, 32)" ++ nl ++
    indent ++ "mstore(32, " ++ length ++ ")" ++ nl
  match plan with
  | .boundedArray array =>
      unless !array.elementWords.isEmpty do
        throw "evm/codec: malformed bounded array output plan"
      let abiWordsPerElement := array.elementWords.size
      let sourceLimbsPerElement := elementSourceLimbCount array.elementWords
      out := out ++ indent ++ "if gt(" ++ length ++ ", " ++ toString array.capacity ++
        ") { " ++ revert0 ++ " }" ++ nl
      -- Every element is computed into a local before the first frame word is stored. Element
      -- code may use low memory as scratch (a hashed-map key hash), which the frame would share.
      let mut stores : Array String := #[]
      for i in [0:array.capacity] do
        let mut block := ""
        let base := 1 + i * sourceLimbsPerElement
        let mut limbOffset := 0
        for wordIndex in [0:abiWordsPerElement] do
          let type := array.elementWords[wordIndex]!
          let nLimbs := limbCount type
          let slot := s!"abi_ret_{i}_{wordIndex}"
          let memOffset := 64 + (i * abiWordsPerElement + wordIndex) * 32
          let guard := indent ++ "if gt(" ++ length ++ ", " ++ toString i ++ ") { "
          let mut limbExprs : Array String := #[]
          for _ in [0:nLimbs] do
            let (pre, value, next) ←
              context.materialize (indent ++ "  ") values[base + limbOffset]! state
            state := next
            limbOffset := limbOffset + 1
            block := block ++ pre
            limbExprs := limbExprs.push value
          if isAddressCarrier type && nLimbs == 3 then
            for limb in [0:3] do
              out := out ++ indent ++ "let " ++ slot ++ "_" ++ toString limb ++ " := 0" ++ nl
              block := block ++ indent ++ "  " ++ slot ++ "_" ++ toString limb ++ " := " ++
                limbExprs[limb]! ++ nl
            stores := stores.push (guard ++ "pf_store_addr20(" ++ toString memOffset ++ ", " ++
              slot ++ "_0, " ++ slot ++ "_1, " ++ slot ++ "_2) }" ++ nl)
          else
            let packed ← packElementWord type limbExprs
            out := out ++ indent ++ "let " ++ slot ++ " := 0" ++ nl
            block := block ++ indent ++ "  " ++ slot ++ " := " ++ packed ++ nl
            stores := stores.push (guard ++ "mstore(" ++ toString memOffset ++ ", " ++ slot ++
              ") }" ++ nl)
        out := out ++ indent ++ "if gt(" ++ length ++ ", " ++ toString i ++ ") {" ++ nl ++
          block ++ indent ++ "}" ++ nl
      out := out ++ header
      for store in stores do
        out := out ++ store
      out := out ++ indent ++ "return(0, add(64, mul(" ++ length ++ ", " ++
        toString (abiWordsPerElement * 32) ++ ")))" ++ nl
  | .packedBytes bytes =>
      out := out ++ header ++ indent ++ "if gt(" ++ length ++ ", " ++ toString bytes.capacity ++
        ") { " ++ revert0 ++ " }" ++ nl
      for word in [0:(bytes.capacity + 31) / 32] do
        out := out ++ indent ++ "mstore(" ++ toString (64 + word * 32) ++ ", 0)" ++ nl
      for i in [0:bytes.capacity] do
        out := out ++ indent ++ "if gt(" ++ length ++ ", " ++ toString i ++ ") {" ++ nl
        let (pre, value, next) ←
          context.materialize (indent ++ "  ") values[1 + i]! state
        state := next
        out := out ++ pre ++ indent ++ "  mstore8(" ++ toString (64 + i) ++
          ", " ++ value ++ ")" ++ nl ++ indent ++ "}" ++ nl
      if bytes.validateUtf8 then
        out := out ++ renderUtf8Guard "abi_ret_utf8_" indent length
          (fun i => "byte(0, mload(add(64, " ++ i ++ ")))") 0
      let padded := "abi_ret_padded"
      out := out ++ indent ++ "let " ++ padded ++ " := and(add(" ++ length ++
        ", 31), not(31))" ++ nl ++
        indent ++ "return(0, add(64, " ++ padded ++ "))" ++ nl
  return (out, state)

/-- Rebuild one fixed Tagged Tuple v1 result from the shared `tag,payload...` source frame. The
output plan has no input offsets or decoded guard state; tag range and inactive-zero lanes are
checked again immediately before publishing returndata. -/
def renderTaggedTupleReturn [Inhabited Value] (context : ReturnContext Value State)
    (plan : TaggedTupleOutputPlan) (values : Array Value) (state : State) :
    Except String (String × State) := do
  let indent := context.indent
  unless !plan.words.isEmpty && values.size == plan.words.size &&
      plan.words.size == 1 + plan.activePayloadWords.foldl (init := 0) max &&
      (plan.words[0]! == .boolean || plan.words[0]! == .uint8) &&
      (plan.words.extract 1 plan.words.size |>.all fun type => limbCount type == 1) do
    throw "evm/codec: malformed tagged tuple output plan"
  let mut out := ""
  let mut state := state
  let mut names : Array String := #[]
  for i in [0:values.size] do
    let name := if i == 0 then "abi_ret_tag" else "abi_ret_p" ++ toString (i - 1)
    let (pre, expression, next) ← context.materialize indent values[i]! state
    out := out ++ pre ++ indent ++ "let " ++ name ++ " := " ++ expression ++ nl
    state := next
    names := names.push name
  out := out ++ (← renderWordGuard indent names[0]! plan.words[0]!)
  for i in [1:plan.words.size] do
    let type := plan.words[i]!
    unless isFixedBytesCarrier type do
      out := out ++ (← renderWordGuard indent names[i]! type)
  out := out ++ (← renderTaggedFrameGuards indent names[0]! (plan.words.size - 1)
    (fun lane => names[lane + 1]!) plan.activePayloadWords)
  for i in [0:plan.words.size] do
    let offset := i * 32
    let type := plan.words[i]!
    if isFixedBytesCarrier type then
      out := out ++ indent ++ "pf_store_fixed_bytes(" ++ toString offset ++ ", " ++
        names[i]! ++ ", 0, 0, 0, " ++ toString type.byteWidth ++ ")" ++ nl
    else
      out := out ++ indent ++ "mstore(" ++ toString offset ++ ", " ++ names[i]! ++ ")" ++ nl
  return (out ++ indent ++ "return(0, " ++ toString (plan.words.size * 32) ++ ")" ++ nl,
    state)

/-- Interpret the single target-owned ABI output sum. Adding an output shape extends this adapter
boundary rather than the main EVM operation emitter. -/
def renderReturn [Inhabited Value] (context : ReturnContext Value State)
    (plan : OutputPlan) (values : Array Value) (state : State) :
    Except String (String × State) :=
  match plan with
  | .dynamic dynamic => renderDynamicReturn context dynamic values state
  | .taggedTuple tagged => renderTaggedTupleReturn context tagged values state

end ProofForge.Evm.Codec.Emit
