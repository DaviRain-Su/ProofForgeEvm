import ProofForge.Evm.Ops
import ProofForge.Evm.IR
import ProofForge.Core.Target
import ProofForge.Extract.LegacyAdapter
import ProofForge.Extract.LegacyGolden

namespace Tests.TargetOpsSpec

private def validEvmValue : ProofForge.Evm.Ops.Val :=
  ProofForge.Evm.Ops.mapGetU64 ProofForge.Evm.Ops.self (.lit 7)

private def invalidEvmValue : ProofForge.Evm.Ops.Val :=
  .ext (.component (.hashedMap .getU64)) #[ProofForge.Evm.Ops.self]

#guard validEvmValue.wellFormed ProofForge.Evm.Ops.ValKind.arity
#guard !invalidEvmValue.wellFormed ProofForge.Evm.Ops.ValKind.arity

private def validEvmOp : ProofForge.Evm.Ops.Op :=
  .ext (.component (.nativeFx (.sendEth (.lit 1) (.lit 2) (.lit 3) validEvmValue)))

#guard validEvmOp.wellFormed

#guard
  match ProofForge.Extract.IR.ofLegacyOps
      #[.evmDeposit ProofForge.Ops.Val.evmCallValue] with
  | .ok source =>
    match ProofForge.Evm.IR.projectExtractedOps source with
    | .ok evm => evm.all ProofForge.Evm.Ops.Op.wellFormed
    | .error _ => false
  | .error _ => false

/-- A synthetic future backend with no accepted source extensions. -/
private inductive CoreOnlyValKind where
  | reserved
  deriving BEq

private inductive CoreOnlyOpExt (V : Type) where
  | reserved

private def coreOnlyCfgDialect :
    ProofForge.Core.CFG.Dialect CoreOnlyValKind CoreOnlyOpExt where
  mapValues := fun _ payload => match payload with | .reserved => .reserved
  values := fun payload => match payload with | .reserved => #[]
  payloadEq := fun left right =>
    match left, right with
    | .reserved, .reserved => true

private def coreOnlyOpWellFormed :
    ProofForge.Core.Ops.Op CoreOnlyValKind CoreOnlyOpExt → Bool :=
  ProofForge.Core.Ops.Op.wellFormed (fun _ => 0)
    (fun _ _ => true) (fun _ => false)

private def coreOnlyRegistration :
    ProofForge.Core.Target.Registration
      ProofForge.Extract.IR.ValKind ProofForge.Extract.IR.OpExt
      CoreOnlyValKind CoreOnlyOpExt where
  name := "CoreOnly"
  projectValExt := fun _ => throw "core-only target rejects source value extensions"
  projectOpExt := fun _ _ => throw "core-only target rejects source effect extensions"
  valArity := fun _ => 0
  opWellFormed := coreOnlyOpWellFormed
  cfgDialect := coreOnlyCfgDialect

private def coreOnlySource : ProofForge.Extract.IR.Program :=
  { name := "CoreOnly"
    slots := #[]
    schema := {}
    methods := #[{
      kind := .get
      name := "CoreOnly.choose"
      ixName := "choose"
      paramCount := 1
      ops := #[
        .letLocal 0 (.addU64 (.arg 0) (.lit 1)),
        .ite .ne (.local 0) (.lit 0)
          #[.returnU64 (.local 0)] #[.returnU64 (.lit 0)]
      ]
    }] }

#guard
  match ProofForge.Core.Target.projectProgram coreOnlyRegistration coreOnlySource with
  | .ok program =>
      program.methods.size == 1 &&
        match program.methods[0]!.ops with
        | #[.letLocal 0 (.addU64 (.arg 0) (.lit 1)),
            .ite .ne (.local 0) (.lit 0)
              #[.returnU64 (.local 0)] #[.returnU64 (.lit 0)]] => true
        | _ => false
  | .error _ => false

#guard
  let source : ProofForge.Extract.IR.Program :=
    { coreOnlySource with methods := #[{
        kind := .get
        name := "CoreOnly.foreign"
        ixName := "foreign"
        ops := #[.returnU64 (.ext (.evm .timestamp) #[])]
      }] }
  match ProofForge.Core.Target.projectProgram coreOnlyRegistration source with
  | .error _ => true
  | .ok _ => false

private def legacyOpsRoundTrip (ops : Array ProofForge.Ops.Op) : Bool :=
  match ProofForge.Extract.IR.ofLegacyOps ops with
  | .ok extensible =>
      extensible.all ProofForge.Extract.IR.Op.wellFormed &&
        match ProofForge.Extract.IR.toLegacyOps extensible with
        | .ok restored => restored == ops
        | .error _ => false
  | .error _ => false

#guard ProofForge.Golden.programs.all fun program =>
  program.methods.all fun method => legacyOpsRoundTrip method.ops

#guard ProofForge.Golden.programs.all fun program =>
  match ProofForge.Extract.IR.ofLegacyProgram program >>= ProofForge.Extract.IR.toLegacyProgram with
  | .ok restored => restored == program
  | .error _ => false

private def coreSchema : ProofForge.Core.Schema :=
  { rootType := "CoreCounter.State"
    leaves := #[{
      place := { steps := #[.field "CoreCounter.State" 0 "value"] }
      name := "value"
      ty := .uint 64
    }] }

private def coreProgram : ProofForge.Extract.IR.Program :=
  let schema := coreSchema
  { name := "CoreCounter"
    slots := ProofForge.Core.IR.slotsOfSchema schema
    schema
    methods := #[
      { kind := .init, name := "init", ixName := "initialize" },
      { kind := .increment, name := "tick", ixName := "tick" },
      { kind := .get, name := "get", ixName := "get" }
    ] }

#guard ProofForge.Core.IR.schemaMatchesSlots coreProgram
#guard ProofForge.Core.IR.isProgramShape coreProgram

private def genericEvaluation : Except String ProofForge.Extract.IR.Evaluation :=
  let slot : ProofForge.Extract.IR.Val := .ext (.evm .timestamp) #[]
  let ops : Array ProofForge.Extract.IR.Op :=
    #[.storeField "value" slot, .okState slot]
  ProofForge.Core.evaluate coreSchema ops

#guard
  match genericEvaluation with
  | .ok evaluation =>
      evaluation.explicit && evaluation.events.size == 2 &&
        evaluation.commits.size == 1 && evaluation.commits[0]!.writes.isEmpty
  | .error _ => false

end Tests.TargetOpsSpec
