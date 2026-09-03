import ProofForge
import ProofForge.Evm.Commands
import Examples.Evm.EvmChainGuard

namespace Tests.EvmChainGuardSpec

open Examples.Evm.EvmChainGuard

#guard (init 84532).dummy == 0
#guard get (init 84532) == 0
#guard expectedChainId (init 84532) == 0
#guard chainId (init 84532) == 0

-- Kernel stubs for `Context.chainId` and `Immutable.u64` are both 0, so the matching
-- branch is the only one #guard can observe. Mismatch is an Anvil / RPC gate.
#guard
  match ping (init 84532) with
  | .ok (st, ret) => st.dummy == 0 && ret == 0
  | .error _ => false

#guard
  match ping (init 84538453) with
  | .ok (st, ret) => get st == 0 && ret == 0
  | .error _ => false

#guard ProofForge.Evm.Registry.digestOf "EvmChainGuard" == some "ebef98a36a4b1cc5"

#pf_evm_build Examples.Evm.EvmChainGuard

end Tests.EvmChainGuardSpec
