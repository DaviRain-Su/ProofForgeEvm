import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.Collectible
import Examples.Evm.Badge
import Examples.Evm.MultiToken
import Examples.Evm.CraftToken

/-!
W1 ERC-165 gate. The SDK comparison is bounded to four `UInt64` carrier limbs and each adopted
example must expose a Solidity-shaped `supportsInterface(bytes4) -> bool` view in its ABI.
Live calldata/return decoding is covered by the corresponding Anvil scripts.
-/

namespace Tests.EvmErc165Spec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard Erc165.equal Erc165.erc165 Erc165.erc165
#guard Erc165.equal Erc165.erc721 Erc165.erc721
#guard Erc165.equal Erc165.erc1155 Erc165.erc1155
#guard Erc165.supportsToken Erc165.erc165 Erc165.erc721
#guard Erc165.supportsToken Erc165.erc721 Erc165.erc721

private partial def valueContainsBytes4Equality : IR.Val → Bool
  | .arg _ | .local _ | .lit _ | .loopIx => false
  | .field base _ | .bitNot base => valueContainsBytes4Equality base
  | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
  | .shiftL lhs rhs | .shiftR lhs rhs
  | .addU64 lhs rhs | .subU64 lhs rhs | .mulU64 lhs rhs
  | .divU64 lhs rhs | .modU64 lhs rhs =>
      valueContainsBytes4Equality lhs || valueContainsBytes4Equality rhs
  | .indexGet base _ idx _ _ =>
      valueContainsBytes4Equality base || valueContainsBytes4Equality idx
  | .select _ lhs rhs thn els =>
      valueContainsBytes4Equality lhs || valueContainsBytes4Equality rhs ||
        valueContainsBytes4Equality thn || valueContainsBytes4Equality els
  | .ext (.evm (.component (.wideWord .eqBytes4))) operands => operands.size == 2
  | .ext _ operands => operands.any valueContainsBytes4Equality

private def expectErc165Abi (moduleName : Name) : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env moduleName with
    | .ok source => pure source
    | .error reason => throwError reason
  let some method := source.methods.find? (·.ixName == "supportsInterface")
    | throwError s!"{moduleName} is missing supportsInterface"
  unless method.paramTypes == #[.fixedBytes 4] && method.retTypes == #[.boolean] do
    throwError s!"{moduleName}.supportsInterface lost its bytes4/bool source boundary"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"supportsInterface\"" &&
      abi.contains "\"name\":\"arg0\",\"type\":\"bytes4\"" &&
      abi.contains "\"type\":\"bool\"" do
    throwError s!"{moduleName} ABI lost supportsInterface(bytes4) -> bool:\n{abi}"
  let supportOps := (program.entries.find? (·.ixName == "supportsInterface")).get!.ops
  unless supportOps.size > 0 && (program.entries.map (·.ixName)).contains "supportsInterface" do
    throwError s!"{moduleName}.supportsInterface did not lower to EVM operations"
  unless supportOps.any fun
      | .returnU64 value => valueContainsBytes4Equality value
      | _ => false do
    throwError s!"{moduleName}.supportsInterface did not use the closed bytes4 equality leaf"

private def expectErc165 : CommandElabM Unit := do
  expectErc165Abi `Examples.Evm.Collectible
  expectErc165Abi `Examples.Evm.Badge
  expectErc165Abi `Examples.Evm.MultiToken
  expectErc165Abi `Examples.Evm.CraftToken

elab "#pf_guard_evm_erc165" : command => expectErc165

#pf_guard_evm_erc165

#pf_evm_build Examples.Evm.Collectible
#pf_evm_build Examples.Evm.Badge
#pf_evm_build Examples.Evm.MultiToken
#pf_evm_build Examples.Evm.CraftToken

end Tests.EvmErc165Spec
