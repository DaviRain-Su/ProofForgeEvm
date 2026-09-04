import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.SignerLink

/-!
Phase 3 signer check: `Sdk.Ierc1271.checkSignature` is OZ `SignatureChecker`'s ERC-1271 half
over `OpenCall.callMagic`. `checkNow` is the combined `isValidSignatureNow` gate: code takes
that CALL, no code splits the 65-byte `r ‖ s ‖ v` through `packLane` / `Ecdsa.recover`.
`SignerLink.requireSigner` stays the 1271-only consumer; `requireNow` is the combined one.
The live matrix lives in `runtime-tests/evm/anvil_signerlink.sh`.
-/

namespace Tests.EvmIerc1271Spec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open ProofForge.Core.Value
open Lean Elab Command

private def emptySignature : BoundedBytes 65 :=
  { length := 0, values := Vector.replicate 65 0 }

private def filledSignature (byte : UInt8) : BoundedBytes 65 :=
  { length := 65, values := Vector.replicate 65 byte }

-- The host stub answers 0 for every open CALL; the check is a sequencing carrier, not a Bool.
#guard Ierc1271.checkSignature ⟨1, 2, 3⟩ ⟨4, 5, 6, 7⟩ emptySignature == 0
#guard Ierc1271.packLane 0x11 0x11 0x11 0x11 0x11 0x11 0x11 0x11 == 0x1111111111111111
#guard (Ierc1271.rWord (filledSignature 0x11)).w0 == 0x1111111111111111
#guard (Ierc1271.sWord (filledSignature 0x22)).w0 == 0x2222222222222222
#guard Ierc1271.vByte (filledSignature 27) == 27
#guard Ierc1271.vByte (filledSignature 0) == 27
#guard Ierc1271.vByte (filledSignature 1) == 28
-- Host EXTCODESIZE is 0 and evmEq20 is true, so a 65-byte frame takes the EOA success arm.
#guard Ierc1271.checkNow ⟨1, 2, 3⟩ ⟨4, 5, 6, 7⟩ (filledSignature 27) == 0
-- Host revertUnauthorized is 0; length != 65 still selects that arm.
#guard Ierc1271.checkNow ⟨1, 2, 3⟩ ⟨4, 5, 6, 7⟩ emptySignature == 0

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
  expectMethodNames evm #["requireSigner", "requireNow", "accepted"]
  let abi ←
    match Emit.emitAbiChecked evm with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"requireSigner\"" && abi.contains "\"name\":\"requireNow\"" &&
      abi.contains "\"type\":\"bytes\"" && abi.contains "\"type\":\"bytes32\"" do
    throwError s!"SignerLink ABI lost requireSigner/requireNow(address,bytes32,bytes):\n{abi}"
  let nowPlans := sourceOpenCalls (← methodOps source "requireNow")
  unless nowPlans.size == 1 && nowPlans[0]!.name == "isValidSignature" &&
      nowPlans[0]!.kind == .call && nowPlans[0]!.policy == .magicBytes4 magic &&
      nowPlans[0]!.args.size == 2 && nowPlans[0]!.inSize == 100 do
    throwError s!"SignerLink.requireNow plan diverged: {repr nowPlans}"
  let yul ←
    match Emit.emitYul evm with
    | .ok yul => pure yul
    | .error reason => throwError reason
  -- requireSigner still has no code-size branch. requireNow adds EXTCODESIZE, a length-65
  -- guard, and the closed ecrecover STATICCALL for the EOA arm.
  unless yul.contains s!"shl(224, 0x{magic}))) \{ revert(0, 0) }" &&
      yul.contains "extcodesize(" &&
      yul.contains " := staticcall(gas(), 1, 0, 128, 0, 32)\n" do
    throwError "SignerLink Yul lost the magic gate, the code-size branch, or ecrecover"
  -- The signature stays in calldata on the 1271 CALL: 65 byte locals and 65 guarded `mstore8`s
  -- cost 3.5 KB of runtime code, one `calldatacopy` of the padded length costs a few opcodes.
  unless yul.contains "let abi_bytes2 := add(add(4, abi_data0), 32)\n" &&
      !yul.contains "let arg3 := 0\n" && !yul.contains "arg3 := byte(0, calldataload" &&
      yul.contains "calldatacopy(100, abi_bytes2, " && !yul.contains "mstore8(1" do
    throwError "SignerLink Yul materializes the signature per byte instead of copying calldata"
  unless IR.digestHex evm == "48768ba3013eb87" do
    throwError s!"SignerLink digest drifted: {IR.digestHex evm}"
  logInfo m!"signerlink: digest={IR.digestHex evm} plan-ok abi-ok"

elab "#pf_guard_evm_ierc1271" : command => expectSignerLink

#pf_guard_evm_ierc1271

#pf_evm_build Examples.Evm.SignerLink

end Tests.EvmIerc1271Spec
