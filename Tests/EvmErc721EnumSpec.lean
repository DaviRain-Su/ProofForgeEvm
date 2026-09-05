import ProofForge
import ProofForge.Evm.Commands
import ProofForge.Evm.Emit
import Examples.Evm.Gallery

/-!
Bounded IERC721Enumerable profile: UInt64 ids, capacity 4, Gallery consumer.
Live mint/transfer/burn/swap-remove matrices live in `runtime-tests/evm/anvil_gallery.sh`.
-/

namespace Tests.EvmErc721EnumSpec

open ProofForge.Evm
open ProofForge.Evm.Sdk
open Lean Elab Command

#guard Erc721.Enum.capU64 == 4
#guard Erc721.Enum.canEnumerate ⟨0, 0, 0, 0⟩
#guard Erc721.Enum.canEnumerate ⟨1, 0, 0, 0⟩
#guard !Erc721.Enum.canEnumerate ⟨0, 1, 0, 0⟩
#guard !Erc721.Enum.canEnumerate ⟨0, 0, 1, 0⟩
#guard !Erc721.Enum.canEnumerate ⟨1, 0, 0, 1⟩
#guard Erc721.Enum.wideId 7 == (⟨7, 0, 0, 0⟩ : UInt256)
#guard Erc721.Enum.narrowId ⟨7, 0, 0, 0⟩ == 7
#guard Erc721.Enum.idAddr 7 == (⟨7, 0, 0⟩ : Address)
#guard Erc721.Enum.indexKey 0 == (⟨0, 0, 0⟩ : Address)
#guard Erc721.Enum.idAddr 7 == Erc721.tokenKey (Erc721.Enum.wideId 7)
#guard Erc165.erc721Enumerable == (⟨0x639d0e78, 0, 0, 0⟩ : Bytes4)

#guard Examples.Evm.Gallery.declared.handle.set.wellFormed
#guard Examples.Evm.Gallery.declared.handle.set.values.baseSlot == 0
#guard Examples.Evm.Gallery.declared.handle.set.count.slot? == some 4
#guard Examples.Evm.Gallery.layout.nextSlot == 5
#guard Examples.Evm.Gallery.owners.base == 0
#guard Examples.Evm.Gallery.approvals.base == 1
#guard Examples.Evm.Gallery.balances.base == 2
#guard Examples.Evm.Gallery.allIndex.base == 3
#guard Examples.Evm.Gallery.ownedAt.base == 4
#guard Examples.Evm.Gallery.ownedIndex.base == 5

#guard Registry.digestOf "Gallery" == some "9fdfc61d00414718"

private def expectGallery : CommandElabM Unit := do
  let env ← getEnv
  let source ←
    match ProofForge.Extract.extractModuleIR env `Examples.Evm.Gallery with
    | .ok source => pure source
    | .error reason => throwError reason
  for ixName in #[
      "totalSupply", "tokenByIndex", "tokenOfOwnerByIndex", "ownerOf", "balanceOf",
      "mint", "transferFrom", "burn", "supportsInterface"
    ] do
    unless source.methods.any (·.ixName == ixName) do
      throwError s!"Gallery is missing {ixName}"
  let program ←
    match IR.fromExtracted source with
    | .ok program => pure program
    | .error reason => throwError reason
  let abi ←
    match Emit.emitAbiChecked program with
    | .ok abi => pure abi
    | .error reason => throwError reason
  unless abi.contains "\"name\":\"totalSupply\"" &&
      abi.contains "\"name\":\"tokenByIndex\"" &&
      abi.contains "\"name\":\"tokenOfOwnerByIndex\"" &&
      abi.contains "\"name\":\"Transfer\"" do
    throwError s!"Gallery ABI lost enumerable surface:\n{abi}"
  unless program.entries.any (fun e =>
      e.ixName == "tokenByIndex" &&
        e.selector == ProofForge.Crypto.Keccak.selector "tokenByIndex" #["uint256"]) do
    throwError "Gallery tokenByIndex selector drifted"
  unless program.entries.any (fun e =>
      e.ixName == "tokenOfOwnerByIndex" &&
        e.selector == ProofForge.Crypto.Keccak.selector "tokenOfOwnerByIndex"
          #["address", "uint256"]) do
    throwError "Gallery tokenOfOwnerByIndex selector drifted"
  unless IR.digestHex program == "9fdfc61d00414718" do
    throwError s!"Gallery digest drifted: {IR.digestHex program}"
  logInfo m!"gallery: digest={IR.digestHex program} abi-ok"

elab "#pf_guard_evm_erc721_enum" : command => expectGallery

#pf_guard_evm_erc721_enum

#pf_evm_build Examples.Evm.Gallery

end Tests.EvmErc721EnumSpec
