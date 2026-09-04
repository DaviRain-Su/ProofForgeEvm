import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.SignerLink

/-!
Phase 3 signer check: `Sdk.Ierc1271.checkSignature` is OZ `SignatureChecker`'s ERC-1271 half
over `OpenCall.callMagic`. The contract signer must answer `isValidSignature(bytes32,bytes)`
with its own selector `0x1626ba7e`; the 65-byte signature is one ECDSA `r ‖ s ‖ v` and rides
the bounded `bytes` tail at its runtime length. `SignerLink` is the consumer. The live matrix
against a Solidity wallet lives in `runtime-tests/evm/anvil_signerlink.sh`.
-/

namespace Tests.EvmIerc1271Spec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open ProofForge.Core.Value
open Lean Elab Command

private def emptySignature : BoundedBytes 65 :=
  { length := 0, values := Vector.replicate 65 0 }

-- The host stub answers 0 for every open CALL; the check is a sequencing carrier, not a Bool.
#guard Ierc1271.checkSignature ⟨1, 2, 3⟩ ⟨4, 5, 6, 7⟩ emptySignature == 0

#guard Codec.maxPackedBytesCapacity == 65

private partial def sourceOpenCalls (ops : Array ProofForge.Extract.IR.Op) :
    Array (OpenCall.Plan ProofForge.Extract.IR.Val) :=
  ops.foldl (init := #[]) fun acc op =>
    let acc := match op with
      | .ext (.evm (.component (.openCall (.invoke plan)))) => acc.push plan
      | _ => acc
    match op with
    | .ite _ _ _ yes no => acc ++ sourceOpenCalls yes ++ sourceOpenCalls no
    | .forBody _ body => acc ++ sourceOpenCalls body
    | _ => acc

private def methodOps (source : ProofForge.Extract.IR.Program) (name : String) :
    CommandElabM (Array ProofForge.Extract.IR.Op) := do
  let some method := source.methods.find? (·.ixName == name)
    | throwError s!"method {name} missing"
  return method.ops

private def expectMethodNames (program : IR.Program) (names : Array String) :
    CommandElabM Unit := do
  let got := program.entries.map (·.ixName)
  unless got.size == names.size && names.all (got.contains ·) && got.all (names.contains ·) do
    throwError s!"{program.name} method ABI diverged: {got}"

private def expectSignerLink : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.SignerLink with
    | .ok source => pure source
    | .error reason => throwError reason
  let magic := ProofForge.Evm.Keccak.selector "isValidSignature" #["bytes32", "bytes"]
  unless magic == "1626ba7e" do
    throwError s!"isValidSignature selector is {magic}"
  -- One CALL plan whose magic is its own selector: two head words (the hash and the tail
  -- offset) plus the length word, 4 + 2 * 32 + 32 = 100 static calldata bytes; the padded
  -- signature is added at its runtime length.
  let plans := sourceOpenCalls (← methodOps source "requireSigner")
  unless plans.size == 1 && plans[0]!.name == "isValidSignature" &&
      plans[0]!.kind == .call && plans[0]!.policy == .magicBytes4 magic &&
      plans[0]!.args.size == 2 &&
      plans[0]!.args[0]!.name == "hash" && plans[0]!.args[0]!.type == .scalar (.fixedBytes 32) &&
      plans[0]!.args[1]!.name == "signature" && plans[0]!.args[1]!.type == .bytes 65 &&
      plans[0]!.inSize == 100 &&
      plans[0]!.abiTypes matches .ok #["bytes32", "bytes"] do
    throwError s!"SignerLink.requireSigner plan diverged: {repr plans}"
  let evm ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  expectMethodNames evm #["requireSigner", "accepted"]
  let abi ←
    match Emit.emitAbiChecked evm with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"requireSigner\"" && abi.contains "\"type\":\"bytes\"" &&
      abi.contains "\"type\":\"bytes32\"" do
    throwError s!"SignerLink ABI lost requireSigner(address,bytes32,bytes):\n{abi}"
  let yul ←
    match Emit.emitYul evm with
    | .ok yul => pure yul
    | .error reason => throwError reason
  -- A signer without code answers an empty frame, which the magic policy already refuses, so
  -- the check has no code-size branch; any answer other than the left-aligned selector reverts.
  unless yul.contains s!"shl(224, 0x{magic}))) \{ revert(0, 0) }" && !yul.contains "extcodesize(" do
    throwError "SignerLink Yul lost the magic equality gate or grew a code-size guard"
  logInfo m!"signerlink: digest={IR.digestHex evm} plan-ok abi-ok"

elab "#pf_guard_evm_ierc1271" : command => expectSignerLink

#pf_guard_evm_ierc1271

end Tests.EvmIerc1271Spec
