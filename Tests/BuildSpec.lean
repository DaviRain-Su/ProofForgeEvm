import ProofForge
import ProofForge.Evm.Commands
import Examples.Counter
import Examples.Pair
import Examples.Flag
import Examples.Maybe
import Examples.Window
import Examples.Phase
import Examples.Evm.EvmCtx
import Examples.Evm.TipJar
import Examples.Lang
import Examples.Evm.Vault
import Examples.Evm.Ownable
import Examples.Evm.Token
import Examples.Evm.Capped

#pf_evm_build Examples.Counter

#pf_evm_build Examples.Pair

#pf_evm_build Examples.Flag

#pf_evm_build Examples.Maybe

#pf_evm_build Examples.Window

#pf_evm_build Examples.Phase

#pf_evm_build Examples.Evm.EvmCtx

#pf_evm_build Examples.Evm.TipJar

#pf_evm_build Examples.Lang

#pf_evm_build Examples.Evm.Vault

#pf_evm_build Examples.Evm.Ownable

#pf_evm_build Examples.Evm.Token

#pf_evm_build Examples.Evm.Capped

/--
error: extract/unsupported: no pf_entry
-/
#guard_msgs (error) in
#pf_evm_build Tests.Fixtures

#guard
  ProofForge.Extract.Legacy.digestHex ProofForge.Golden.extractedCounter ==
    ProofForge.Extract.Legacy.digestHex ProofForge.Golden.extractedCounter

#guard
  ProofForge.Extract.Legacy.digestHex ProofForge.Golden.extractedCounter !=
    ProofForge.Extract.Legacy.digestHex ProofForge.Golden.extractedPair

#guard
  let p := ProofForge.Golden.extractedPair
  let q : ProofForge.Extract.Legacy.Program :=
    { p with methods := p.methods.map fun m =>
        if m.ixName == "getLeft" then
          { m with ops := #[.returnU64 (.field (.arg 0) "right")] }
        else m }
  ProofForge.Extract.Legacy.digestHex p != ProofForge.Extract.Legacy.digestHex q
