import ProofForge.Extract.IR
import ProofForge.Extract.LegacyIR

namespace ProofForge.Extract.IR

private def cmpOfLegacy : ProofForge.Ops.Cmp → Cmp
  | .eq => .eq
  | .ne => .ne
  | .lt => .lt
  | .le => .le
  | .gt => .gt
  | .ge => .ge

private def cmpToLegacy : Cmp → ProofForge.Ops.Cmp
  | .eq => .eq
  | .ne => .ne
  | .lt => .lt
  | .le => .le
  | .gt => .gt
  | .ge => .ge

/-- Lossless upgrade for callers that still own a legacy closed-union value. -/
partial def ofLegacyVal : ProofForge.Ops.Val → Val
  | .arg i => .arg i
  | .local i => .local i
  | .field base name => .field (ofLegacyVal base) name
  | .lit n => .lit n
  | .evmCaller => .ext (.evm .caller) #[]
  | .evmBlockNumber => .ext (.evm .blockNumber) #[]
  | .evmTimestamp => .ext (.evm .timestamp) #[]
  | .evmChainId => .ext (.evm .chainId) #[]
  | .evmSelf => .ext (.evm .self) #[]
  | .evmCallValue => .ext (.evm .callValue) #[]
  | .evmSelfBalance => .ext (.evm .selfBalance) #[]
  | .evmCallerW0 => .ext (.evm .callerW0) #[]
  | .evmCallerW1 => .ext (.evm .callerW1) #[]
  | .evmCallerW2 => .ext (.evm .callerW2) #[]
  | .evmSelfW0 => .ext (.evm .selfW0) #[]
  | .evmSelfW1 => .ext (.evm .selfW1) #[]
  | .evmSelfW2 => .ext (.evm .selfW2) #[]
  | .bitAnd lhs rhs => .bitAnd (ofLegacyVal lhs) (ofLegacyVal rhs)
  | .bitOr lhs rhs => .bitOr (ofLegacyVal lhs) (ofLegacyVal rhs)
  | .bitXor lhs rhs => .bitXor (ofLegacyVal lhs) (ofLegacyVal rhs)
  | .bitNot value => .bitNot (ofLegacyVal value)
  | .shiftL lhs rhs => .shiftL (ofLegacyVal lhs) (ofLegacyVal rhs)
  | .shiftR lhs rhs => .shiftR (ofLegacyVal lhs) (ofLegacyVal rhs)
  | .indexGet base name idx len elemOff =>
      .indexGet (ofLegacyVal base) name (ofLegacyVal idx) len elemOff
  | .loopIx => .loopIx
  | .select cmp lhs rhs thn els =>
      .select (cmpOfLegacy cmp) (ofLegacyVal lhs) (ofLegacyVal rhs)
        (ofLegacyVal thn) (ofLegacyVal els)
  | .addU64 lhs rhs => .addU64 (ofLegacyVal lhs) (ofLegacyVal rhs)
  | .subU64 lhs rhs => .subU64 (ofLegacyVal lhs) (ofLegacyVal rhs)
  | .mulU64 lhs rhs => .mulU64 (ofLegacyVal lhs) (ofLegacyVal rhs)
  | .divU64 lhs rhs => .divU64 (ofLegacyVal lhs) (ofLegacyVal rhs)
  | .modU64 lhs rhs => .modU64 (ofLegacyVal lhs) (ofLegacyVal rhs)
  | .mapGetU64 base key =>
      .ext (.evm (.component (.hashedMap .getU64)))
        #[ofLegacyVal base, ofLegacyVal key]
  | .mapGetAddr base w0 w1 w2 =>
      .ext (.evm (.component (.hashedMap .getAddr)))
        #[ofLegacyVal base, ofLegacyVal w0, ofLegacyVal w1, ofLegacyVal w2]
  | .mapGetPair base o0 o1 o2 s0 s1 s2 =>
      .ext (.evm (.component (.hashedMap .getPair)))
        #[ofLegacyVal base, ofLegacyVal o0, ofLegacyVal o1, ofLegacyVal o2,
          ofLegacyVal s0, ofLegacyVal s1, ofLegacyVal s2]
  | _ => panic! "extract/unsupported: svm-only legacy value"

private def malformedValue : Except String α :=
  .error "extract/ir: malformed target value operands"

partial def toLegacyVal : Val → Except String ProofForge.Ops.Val
  | .arg i => pure (.arg i)
  | .local i => pure (.local i)
  | .field base name => return .field (← toLegacyVal base) name
  | .lit n => pure (.lit n)
  | .bitAnd lhs rhs => return .bitAnd (← toLegacyVal lhs) (← toLegacyVal rhs)
  | .bitOr lhs rhs => return .bitOr (← toLegacyVal lhs) (← toLegacyVal rhs)
  | .bitXor lhs rhs => return .bitXor (← toLegacyVal lhs) (← toLegacyVal rhs)
  | .bitNot value => return .bitNot (← toLegacyVal value)
  | .shiftL lhs rhs => return .shiftL (← toLegacyVal lhs) (← toLegacyVal rhs)
  | .shiftR lhs rhs => return .shiftR (← toLegacyVal lhs) (← toLegacyVal rhs)
  | .indexGet base name idx len elemOff =>
      return .indexGet (← toLegacyVal base) name (← toLegacyVal idx) len elemOff
  | .loopIx => pure .loopIx
  | .select cmp lhs rhs thn els =>
      return .select (cmpToLegacy cmp) (← toLegacyVal lhs) (← toLegacyVal rhs)
        (← toLegacyVal thn) (← toLegacyVal els)
  | .addU64 lhs rhs => return .addU64 (← toLegacyVal lhs) (← toLegacyVal rhs)
  | .subU64 lhs rhs => return .subU64 (← toLegacyVal lhs) (← toLegacyVal rhs)
  | .mulU64 lhs rhs => return .mulU64 (← toLegacyVal lhs) (← toLegacyVal rhs)
  | .divU64 lhs rhs => return .divU64 (← toLegacyVal lhs) (← toLegacyVal rhs)
  | .modU64 lhs rhs => return .modU64 (← toLegacyVal lhs) (← toLegacyVal rhs)
  | .ext (.evm .caller) #[] => pure .evmCaller
  | .ext (.evm .blockNumber) #[] => pure .evmBlockNumber
  | .ext (.evm .timestamp) #[] => pure .evmTimestamp
  | .ext (.evm .chainId) #[] => pure .evmChainId
  | .ext (.evm .self) #[] => pure .evmSelf
  | .ext (.evm .callValue) #[] => pure .evmCallValue
  | .ext (.evm .selfBalance) #[] => pure .evmSelfBalance
  | .ext (.evm .callerW0) #[] => pure .evmCallerW0
  | .ext (.evm .callerW1) #[] => pure .evmCallerW1
  | .ext (.evm .callerW2) #[] => pure .evmCallerW2
  | .ext (.evm .selfW0) #[] => pure .evmSelfW0
  | .ext (.evm .selfW1) #[] => pure .evmSelfW1
  | .ext (.evm .selfW2) #[] => pure .evmSelfW2
  | .ext (.evm .immU64) #[] | .ext (.evm .immU64b) #[] =>
      throw "extract/unsupported: legacy adapter cannot represent immutable u64"
  | .ext (.evm .immW0) #[] | .ext (.evm .immW1) #[] | .ext (.evm .immW2) #[]
  | .ext (.evm .immX0) #[] | .ext (.evm .immX1) #[] | .ext (.evm .immX2) #[] =>
      throw "extract/unsupported: legacy adapter cannot represent immutable Addr20"
  | .ext (.evm (.component (.wideWord .eq20))) _ =>
      throw "extract/unsupported: legacy adapter cannot represent Addr20 equality"
  | .ext (.evm (.component (.hashedMap .getU64))) #[base, key] =>
      return .mapGetU64 (← toLegacyVal base) (← toLegacyVal key)
  | .ext (.evm (.component (.hashedMap .getAddr))) #[base, w0, w1, w2] =>
      return .mapGetAddr (← toLegacyVal base) (← toLegacyVal w0)
        (← toLegacyVal w1) (← toLegacyVal w2)
  | .ext (.evm (.component (.hashedMap .getPair))) #[base, o0, o1, o2, s0, s1, s2] =>
      return .mapGetPair (← toLegacyVal base) (← toLegacyVal o0) (← toLegacyVal o1)
        (← toLegacyVal o2) (← toLegacyVal s0) (← toLegacyVal s1) (← toLegacyVal s2)
  | .ext _ _ => malformedValue

partial def ofLegacyOp : ProofForge.Ops.Op → Except String Op
  | .letLocal i value => return .letLocal i (ofLegacyVal value)
  | .joinLocal i => return .joinLocal i
  | .setLocal i value => return .setLocal i (ofLegacyVal value)
  | .checkedAddU64 lhs rhs => return .checkedAddU64 (ofLegacyVal lhs) (ofLegacyVal rhs)
  | .checkedSubU64 lhs rhs => return .checkedSubU64 (ofLegacyVal lhs) (ofLegacyVal rhs)
  | .checkedMulU64 lhs rhs => return .checkedMulU64 (ofLegacyVal lhs) (ofLegacyVal rhs)
  | .checkedDivU64 lhs rhs => return .checkedDivU64 (ofLegacyVal lhs) (ofLegacyVal rhs)
  | .checkedModU64 lhs rhs => return .checkedModU64 (ofLegacyVal lhs) (ofLegacyVal rhs)
  | .ite cmp lhs rhs thn els => do
      return .ite (cmpOfLegacy cmp) (ofLegacyVal lhs) (ofLegacyVal rhs)
        (← thn.mapM ofLegacyOp) (← els.mapM ofLegacyOp)
  | .invoke _programIx _metas _data _seed _bump =>
      throw "extract/unsupported: svm-only legacy invoke"
  | .evmDeposit amount =>
      return .ext (.evm (.component (.nativeFx (.deposit (ofLegacyVal amount)))))
  | .evmSendEth w0 w1 w2 amount =>
      return .ext (.evm (.component (.nativeFx (.sendEth (ofLegacyVal w0) (ofLegacyVal w1)
        (ofLegacyVal w2) (ofLegacyVal amount)))))
  | .evmLog name amount =>
      return .ext (.evm (.component (.nativeFx (.log name (ofLegacyVal amount)))))
  | .forAccum n addend resultLocal => return .forAccum n (ofLegacyVal addend) resultLocal
  | .forBody n body => return .forBody n (← body.mapM ofLegacyOp)
  | .indexSet name idx value len elemOff =>
      return .indexSet name (ofLegacyVal idx) (ofLegacyVal value) len elemOff
  | .mapGetU64 base key =>
      return .ext (.evm (.component (.hashedMap (.getU64 (ofLegacyVal base) (ofLegacyVal key)))))
  | .mapSetU64 base key value =>
      return .ext (.evm (.component (.hashedMap (.setU64 (ofLegacyVal base) (ofLegacyVal key)
        (ofLegacyVal value)))))
  | .mapGetAddr base w0 w1 w2 =>
      return .ext (.evm (.component (.hashedMap (.getAddr (ofLegacyVal base) (ofLegacyVal w0)
        (ofLegacyVal w1) (ofLegacyVal w2)))))
  | .mapSetAddr base w0 w1 w2 value =>
      return .ext (.evm (.component (.hashedMap (.setAddr (ofLegacyVal base) (ofLegacyVal w0)
        (ofLegacyVal w1) (ofLegacyVal w2) (ofLegacyVal value)))))
  | .mapGetPair base o0 o1 o2 s0 s1 s2 =>
      return .ext (.evm (.component (.hashedMap (.getPair (ofLegacyVal base) (ofLegacyVal o0)
        (ofLegacyVal o1) (ofLegacyVal o2) (ofLegacyVal s0) (ofLegacyVal s1)
        (ofLegacyVal s2)))))
  | .mapSetPair base o0 o1 o2 s0 s1 s2 value =>
      return .ext (.evm (.component (.hashedMap (.setPair (ofLegacyVal base) (ofLegacyVal o0)
        (ofLegacyVal o1) (ofLegacyVal o2) (ofLegacyVal s0) (ofLegacyVal s1)
        (ofLegacyVal s2) (ofLegacyVal value)))))
  | .evmTokenTransfer tw0 tw1 tw2 dw0 dw1 dw2 amount =>
      return .ext (.evm (.component (.closedCall (.transfer (ofLegacyVal tw0) (ofLegacyVal tw1)
        (ofLegacyVal tw2) (ofLegacyVal dw0) (ofLegacyVal dw1) (ofLegacyVal dw2)
        (ofLegacyVal amount)))))
  | .evmTokenBalanceOfSelf tw0 tw1 tw2 =>
      return .ext (.evm (.component (.closedCall (.balanceOfSelf (ofLegacyVal tw0)
        (ofLegacyVal tw1) (ofLegacyVal tw2)))))
  | .storeField name value => return .storeField name (ofLegacyVal value)
  | .okState value => return .okState (ofLegacyVal value)
  | .errorOverflow => return .errorOverflow
  | .errorNamed name => return .errorNamed name
  | .returnU64 value => return .returnU64 (ofLegacyVal value)
  | .returnState value => return .returnState (ofLegacyVal value)

def ofLegacyOps (ops : Array ProofForge.Ops.Op) : Except String (Array Op) :=
  ops.mapM ofLegacyOp

partial def toLegacyOp : Op → Except String ProofForge.Ops.Op
  | .letLocal i value => return .letLocal i (← toLegacyVal value)
  | .joinLocal i => pure (.joinLocal i)
  | .setLocal i value => return .setLocal i (← toLegacyVal value)
  | .checkedAddU64 lhs rhs => return .checkedAddU64 (← toLegacyVal lhs) (← toLegacyVal rhs)
  | .checkedSubU64 lhs rhs => return .checkedSubU64 (← toLegacyVal lhs) (← toLegacyVal rhs)
  | .checkedMulU64 lhs rhs => return .checkedMulU64 (← toLegacyVal lhs) (← toLegacyVal rhs)
  | .checkedDivU64 lhs rhs => return .checkedDivU64 (← toLegacyVal lhs) (← toLegacyVal rhs)
  | .checkedModU64 lhs rhs => return .checkedModU64 (← toLegacyVal lhs) (← toLegacyVal rhs)
  | .ite cmp lhs rhs thn els =>
      return .ite (cmpToLegacy cmp) (← toLegacyVal lhs) (← toLegacyVal rhs)
        (← thn.mapM toLegacyOp) (← els.mapM toLegacyOp)
  | .forAccum n addend resultLocal =>
      return .forAccum n (← toLegacyVal addend) resultLocal
  | .forBody n body => return .forBody n (← body.mapM toLegacyOp)
  | .indexSetLeaf name _ _ _ leaf =>
      throw s!"extract/ir: unresolved vector leaf {name}.{leaf}"
  | .indexSet name idx value len elemOff =>
      return .indexSet name (← toLegacyVal idx) (← toLegacyVal value) len elemOff
  | .storeField name value => return .storeField name (← toLegacyVal value)
  | .okState value => return .okState (← toLegacyVal value)
  | .errorOverflow => pure .errorOverflow
  | .errorNamed name => pure (.errorNamed name)
  | .errorTyped _ =>
      throw "extract/unsupported: legacy adapter cannot represent parameterized source errors"
  | .returnU64 value => return .returnU64 (← toLegacyVal value)
  | .returnState value => return .returnState (← toLegacyVal value)
  | .ext (.evm (.component (.nativeFx (.deposit amount)))) =>
      return .evmDeposit (← toLegacyVal amount)
  | .ext (.evm (.component (.nativeFx (.deposit256 ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent 256-bit deposit"
  | .emitEvent .. | .externalCall .. =>
      throw "extract/unsupported: legacy adapter cannot represent Psy-target effects"
  | .ext (.evm (.component (.nativeFx (.sendEth w0 w1 w2 amount)))) =>
      return .evmSendEth (← toLegacyVal w0) (← toLegacyVal w1)
        (← toLegacyVal w2) (← toLegacyVal amount)
  | .ext (.evm (.component (.nativeFx (.sendEth256 ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent 256-bit sendEth"
  | .ext (.evm (.component (.nativeFx (.log name amount)))) =>
      return .evmLog name (← toLegacyVal amount)
  | .ext (.evm (.component (.nativeFx (.logTransfer256 ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent LOG3 Transfer"
  | .ext (.evm (.component (.nativeFx (.logApproval256 ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent LOG3 Approval"
  | .ext (.evm (.component (.nativeFx (.logTyped ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent typed events"
  | .ext (.evm (.component (.nativeFx (.revertInsufficient ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent parameterized Insufficient"
  | .ext (.evm (.component (.nativeFx (.revertUnauthorized ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent parameterized Unauthorized"
  | .ext (.evm (.component (.nativeFx (.revertOwnableInvalidOwner ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent OwnableInvalidOwner"
  | .ext (.evm (.component (.nativeFx (.revertOwnableUnauthorizedAccount ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent OwnableUnauthorizedAccount"
  | .ext (.evm (.component (.nativeFx .revertZeroAddress))) =>
      throw "extract/unsupported: legacy adapter cannot represent ZeroAddress"
  | .ext (.evm (.component (.nativeFx .revertPaused))) =>
      throw "extract/unsupported: legacy adapter cannot represent Paused"
  | .ext (.evm (.component (.nativeFx .revertCapExceeded))) =>
      throw "extract/unsupported: legacy adapter cannot represent CapExceeded"
  | .ext (.evm (.component (.nativeFx .receive))) =>
      throw "extract/unsupported: legacy adapter cannot represent receive"
  | .ext (.evm (.component (.hashedMap (.getU64 base key)))) =>
      return .mapGetU64 (← toLegacyVal base) (← toLegacyVal key)
  | .ext (.evm (.component (.hashedMap (.setU64 base key value)))) =>
      return .mapSetU64 (← toLegacyVal base) (← toLegacyVal key) (← toLegacyVal value)
  | .ext (.evm (.component (.hashedMap (.getAddr base w0 w1 w2)))) =>
      return .mapGetAddr (← toLegacyVal base) (← toLegacyVal w0)
        (← toLegacyVal w1) (← toLegacyVal w2)
  | .ext (.evm (.component (.hashedMap (.setAddr base w0 w1 w2 value)))) =>
      return .mapSetAddr (← toLegacyVal base) (← toLegacyVal w0)
        (← toLegacyVal w1) (← toLegacyVal w2) (← toLegacyVal value)
  | .ext (.evm (.component (.hashedMap (.getPair base o0 o1 o2 s0 s1 s2)))) =>
      return .mapGetPair (← toLegacyVal base) (← toLegacyVal o0) (← toLegacyVal o1)
        (← toLegacyVal o2) (← toLegacyVal s0) (← toLegacyVal s1) (← toLegacyVal s2)
  | .ext (.evm (.component (.hashedMap (.setPair base o0 o1 o2 s0 s1 s2 value)))) =>
      return .mapSetPair (← toLegacyVal base) (← toLegacyVal o0) (← toLegacyVal o1)
        (← toLegacyVal o2) (← toLegacyVal s0) (← toLegacyVal s1) (← toLegacyVal s2)
        (← toLegacyVal value)
  | .ext (.evm (.component (.closedCall (.transfer tw0 tw1 tw2 dw0 dw1 dw2 amount)))) =>
      return .evmTokenTransfer (← toLegacyVal tw0) (← toLegacyVal tw1) (← toLegacyVal tw2)
        (← toLegacyVal dw0) (← toLegacyVal dw1) (← toLegacyVal dw2)
        (← toLegacyVal amount)
  | .ext (.evm (.component (.hashedMap (.setAddr256 ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent 256-bit map writes"
  | .ext (.evm (.component (.hashedMap (.setPair256 ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent 256-bit pair-map writes"
  | .ext (.evm (.component (.closedCall (.transfer256 ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent 256-bit token transfer"
  | .ext (.evm (.component (.closedCall (.approve256 ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent ERC-20 approve"
  | .ext (.evm (.component (.closedCall (.transferFrom256 ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent ERC-20 transferFrom"
  | .ext (.evm (.component (.closedCall (.balanceOfSelf tw0 tw1 tw2)))) =>
      return .evmTokenBalanceOfSelf (← toLegacyVal tw0) (← toLegacyVal tw1)
        (← toLegacyVal tw2)
  | .ext (.evm (.component (.closedCall (.wethDeposit256 ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent WETH deposit"
  | .ext (.evm (.component (.closedCall (.wethWithdraw256 ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent WETH withdraw"
  | .ext (.evm (.component (.closedCall (.swapExact2 ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent Uniswap V2 swap"
  | .ext (.evm (.component (.closedCall (.swapExact3 ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent Uniswap V2 path-3 swap"
  | .ext (.evm (.component (.closedCall (.permit ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent EIP-2612 permit"
  | .ext (.evm (.component (.closedCall (.tokenPermit ..)))) =>
      throw "extract/unsupported: legacy adapter cannot represent external permit"
  | .ext (.evm (.component ..)) =>
      throw "extract/unsupported: legacy adapter cannot represent evm component"

def toLegacyOps (ops : Array Op) : Except String (Array ProofForge.Ops.Op) :=
  ops.mapM toLegacyOp

private def slotOfLegacy (slot : Legacy.Slot) : Core.IR.Slot :=
  { name := slot.name, width := slot.width, abi := slot.abi }

private def slotToLegacy (slot : Core.IR.Slot) : Legacy.Slot :=
  { name := slot.name, width := slot.width, abi := slot.abi }

private def methodOfLegacy (schema : Core.Schema) (method : Legacy.Method) :
    Except String Method := do
  let ops ← ofLegacyOps method.ops
  unless ops.all Op.wellFormed do
    throw s!"extract/ir: malformed target extension in {method.ixName}"
  let evaluation ←
    if schema.isEmpty then pure {}
    else Core.evaluate schema ops
  return {
    kind := method.kind
    name := method.name
    ixName := method.ixName
    paramCount := method.paramCount
    paramWidths := method.paramWidths
    retWidths := method.retWidths
    retCount := method.retCount
    sketch := method.sketch
    ops
    evaluation
  }

/-- Upgrade the complete compatibility program at the extractor boundary. -/
def ofLegacyProgram (program : Legacy.Program) : Except String Program := do
  return {
    name := program.name
    slots := program.slots.map slotOfLegacy
    schema := program.schema
    methods := ← program.methods.mapM (methodOfLegacy program.schema)
  }

private def methodToLegacy (schema : Core.Schema) (method : Method) :
    Except String Legacy.Method := do
  unless method.annotations.isEmpty do
    throw s!"extract/unsupported: legacy adapter cannot preserve annotations on {method.ixName}"
  let ops ← toLegacyOps method.ops
  let evaluation ←
    if schema.isEmpty then pure {}
    else Legacy.evaluate schema ops
  return {
    kind := method.kind
    name := method.name
    ixName := method.ixName
    paramCount := method.paramCount
    paramWidths := method.paramWidths
    retWidths := method.retWidths
    retCount := method.retCount
    sketch := method.sketch
    ops
    evaluation
  }

/-- Downgrade only at a compatibility boundary; malformed target operands fail explicitly. -/
def toLegacyProgram (program : Program) : Except String Legacy.Program := do
  return {
    name := program.name
    slots := program.slots.map slotToLegacy
    schema := program.schema
    methods := ← program.methods.mapM (methodToLegacy program.schema)
  }

end ProofForge.Extract.IR
