import Examples.Lang
import Tests.Fixtures

open Lean Elab Command

namespace Tests.LangSpec

open Examples.Lang

#guard (init 7).cells[0]! == 7
#guard get (init 7) == 7
#guard band (init 0) 0xf0 0x0f == 0
#guard bor (init 0) 0xf0 0x0f == 0xff
#guard bxor (init 0) 0xff 0x0f == 0xf0
#guard bnot (init 0) 0 == u64Max
#guard shl (init 0) 1 3 == 8
#guard shr (init 0) 8 3 == 1
#guard shl (init 0) 1 65 == 2
#guard shr (init 0) 8 67 == 1
#guard mask8 (init 0) 7 == 7
#guard wrap64 (init 0) == 3
#guard wrap64mix (init 0) == 0
#guard wrap64mix (init 3) == 3
#guard wrap64nest (init 0) == 3
#guard wrap64nest (init 3) == 6
#guard wrap64mul (init 0) == 0
#guard wrap64mul (init 3) == 0
#guard wrap64sub (init 0) == 0
#guard wrap64sub (init 1) == u64Max
#guard wrap64sub (init 3) == u64Max - 2
#guard wrap64sat (init 0) == 0
#guard wrap64sat (init 3) == 0
#guard Tests.Fixtures.getNarrowPrevious (Tests.Fixtures.initNarrow 7) 0 == 7
#guard
  match both (init 9) with
  | (a, b) => a == 9 && b == 0

#guard
  match ProofForge.Evm.IR.fromProgram ProofForge.Golden.extractedLang with
  | .error _ => false
  | .ok p =>
      match ProofForge.Evm.Emit.emitYul p with
      | .error _ => false
      | .ok yul =>
          yul.contains "and(" &&
            yul.contains "shl(and(" &&
            yul.contains "if gt(" &&
            yul.contains "for { let " &&
            yul.contains "sload(add(" &&
            yul.contains "sstore(add(" &&
            yul.contains "revert(0, 4)" &&
            yul.contains "return(0, 64)" &&
            yul.contains "if gt(arg0, 0xff)"

#guard
  match ProofForge.Evm.IR.fromProgram ProofForge.Golden.extractedLang with
  | .error _ => false
  | .ok p =>
      (p.entries.find? (·.ixName == "mask8")).map (·.paramWidths) == some #[1] &&
        (p.entries.find? (·.ixName == "both")).map (·.retCount) == some 2


elab "#pf_guard_narrow_vector_codegen" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgramIR env ``Tests.Fixtures.initNarrow
        ``Tests.Fixtures.setNarrow ``Tests.Fixtures.getNarrow with
    | .ok program => pure program
    | .error reason => throwError reason
  let evmProgram ←
    match ProofForge.Evm.IR.fromExtracted program with
    | .ok lowered => pure lowered
    | .error reason => throwError reason
  let evm ←
    match ProofForge.Evm.Emit.emitYul evmProgram with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless evm.contains "and(sload(add(" && evm.contains ", 0xff)" &&
      evm.contains "sstore(add(" do
    throwError "EVM indexed UInt8 leaves are not masked"

#pf_guard_narrow_vector_codegen

elab "#pf_guard_nat_sub_semantics" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgramIR env ``Tests.Fixtures.initNarrow
        ``Tests.Fixtures.setNarrow ``Tests.Fixtures.getNarrowPrevious with
    | .ok program => pure program
    | .error reason => throwError reason
  let evmProgram ←
    match ProofForge.Evm.IR.fromExtracted program with
    | .ok lowered => pure lowered
    | .error reason => throwError reason
  let evm ←
    match ProofForge.Evm.Emit.emitYul evmProgram with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless evm.contains "if iszero(lt(" && evm.contains "sub(" do
    throwError "EVM did not preserve saturating Nat.sub control flow"

#pf_guard_nat_sub_semantics

#guard ProofForge.Evm.Keccak.selector "mask8" #["uint8"] ==
  ProofForge.Evm.Keccak.selectorOfWidths "mask8" #[1]

elab "#pf_guard_uint64_ofnat_wrap" : command => do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Lang with
    | .ok source => pure source
    | .error reason => throwError reason
  let some wrap := source.methods.find? (·.ixName == "wrap64")
    | throwError "Lang lost wrap64"
  unless wrap.ops.any (fun
      | .returnU64 (.lit 3) => true
      | _ => false) do
    throwError "wrap64 did not fold 2^64+3 to 3"
  let evm ←
    match ProofForge.Evm.IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  unless (evm.entries.find? (·.ixName == "wrap64")).isSome do
    throwError "EVM Lang lost wrap64"
  let some mix := source.methods.find? (·.ixName == "wrap64mix")
    | throwError "Lang lost wrap64mix"
  unless mix.ops.any (fun
      | .returnU64 (.addU64 _ (.lit 0)) => true
      | .returnU64 (.addU64 (.lit 0) _) => true
      | _ => false) do
    throwError "wrap64mix did not add the wrapped 2^64 literal to a runtime cell"
  unless (evm.entries.find? (·.ixName == "wrap64mix")).isSome do
    throwError "EVM Lang lost wrap64mix"
  let some nest := source.methods.find? (·.ixName == "wrap64nest")
    | throwError "Lang lost wrap64nest"
  unless nest.ops.any (fun
      | .returnU64 (.addU64 (.addU64 _ (.lit 0)) (.lit 3)) => true
      | .returnU64 (.addU64 (.addU64 (.lit 0) _) (.lit 3)) => true
      | .returnU64 (.addU64 (.lit 3) (.addU64 _ (.lit 0))) => true
      | .returnU64 (.addU64 (.lit 3) (.addU64 (.lit 0) _)) => true
      | _ => false) do
    throwError "wrap64nest did not add 3 to a nested wrapped 2^64 runtime add"
  unless (evm.entries.find? (·.ixName == "wrap64nest")).isSome do
    throwError "EVM Lang lost wrap64nest"
  let some mul := source.methods.find? (·.ixName == "wrap64mul")
    | throwError "Lang lost wrap64mul"
  unless mul.ops.any (fun
      | .returnU64 (.mulU64 _ (.lit 0)) => true
      | .returnU64 (.mulU64 (.lit 0) _) => true
      | _ => false) do
    throwError "wrap64mul did not multiply a runtime cell by the wrapped 2^64 literal"
  unless (evm.entries.find? (·.ixName == "wrap64mul")).isSome do
    throwError "EVM Lang lost wrap64mul"
  let some sub := source.methods.find? (·.ixName == "wrap64sub")
    | throwError "Lang lost wrap64sub"
  unless sub.ops.any (fun
      | .returnU64 (.subU64 (.lit 0) _) => true
      | _ => false) do
    throwError "wrap64sub did not subtract a runtime cell from the wrapped 2^64 literal"
  unless (evm.entries.find? (·.ixName == "wrap64sub")).isSome do
    throwError "EVM Lang lost wrap64sub"
  let some sat := source.methods.find? (·.ixName == "wrap64sat")
    | throwError "Lang lost wrap64sat"
  unless sat.ops.any (fun
      | .returnU64 (.lit 0) => true
      | _ => false) do
    throwError "wrap64sat did not saturate runtime minus 2^64 to 0"
  unless (evm.entries.find? (·.ixName == "wrap64sat")).isSome do
    throwError "EVM Lang lost wrap64sat"
  let yul ←
    match ProofForge.Evm.Emit.emitYul evm with
    | .ok text => pure text
    | .error reason => throwError reason
  unless yul.contains "and(sub(0, sload(0)), 0xffffffffffffffff)" do
    throwError "wrap64sub did not emit masked wrapping 0 minus cells_0"
  if yul.contains "if lt(0, sload(0))" then
    throwError "wrap64sub still takes the checked-sub revert on a wrapped 2^64 minuend"

#pf_guard_uint64_ofnat_wrap

end Tests.LangSpec
