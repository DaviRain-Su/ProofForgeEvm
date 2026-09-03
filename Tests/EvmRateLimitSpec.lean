import ProofForge

/-!
W3 rate-limit SDK focused suite: pure decision helpers for the fixed-window counter profile.
-/

namespace Tests.EvmRateLimitSpec

open ProofForge.Evm.Sdk

def config : RateLimit.Config := { capacity := 10, window := 100 }

#guard RateLimit.FixedWindow.empty == ⟨0, 0⟩
#guard RateLimit.FixedWindow.effectiveWindow 0 == 1
#guard RateLimit.FixedWindow.effectiveWindow 60 == 60
#guard RateLimit.FixedWindow.canConsume config RateLimit.FixedWindow.empty 1000 0
#guard RateLimit.FixedWindow.available config RateLimit.FixedWindow.empty 1000 == 10
#guard RateLimit.FixedWindow.canConsume config RateLimit.FixedWindow.empty 1000 5
#guard RateLimit.FixedWindow.canConsume config RateLimit.FixedWindow.empty 1000 11 == false
#guard RateLimit.FixedWindow.used config ⟨7, 950⟩ 1000 == 7
#guard RateLimit.FixedWindow.used config ⟨7, 950⟩ 1051 == 0
#guard RateLimit.FixedWindow.consume config ⟨7, 950⟩ 1000 0 == ⟨7, 950⟩
#guard RateLimit.FixedWindow.consume config ⟨7, 950⟩ 1000 3 == ⟨10, 950⟩
#guard RateLimit.FixedWindow.consume config ⟨7, 950⟩ 1050 3 == ⟨3, 1050⟩

end Tests.EvmRateLimitSpec
