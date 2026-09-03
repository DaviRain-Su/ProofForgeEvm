import ProofForge
import Examples.Evm.TwoStepCounter
import Examples.Evm.Credits

/-!
R5-004 focused suite: canonical pause flags, fail-closed predicates, compatibility aliases, and
two independent consumers. Existing Anvil suites own authorization, pause/unpause, blocked-call,
and storage-atomicity behavior; canonical registry digests ensure the SDK facade adds no target
operation or artifact-visible recipe.
-/

namespace Tests.EvmPausableSpec

open ProofForge.Evm.Sdk

#guard Pausable.running == 0
#guard Pausable.paused == 1
#guard Pausable.isRunning Pausable.running
#guard !Pausable.isRunning Pausable.paused
#guard !Pausable.isRunning 2
#guard Pausable.isPaused Pausable.paused
#guard !Pausable.isPaused Pausable.running
#guard !Pausable.isPaused 2
#guard Pausable.pause Pausable.running == Pausable.paused
#guard Pausable.pause Pausable.paused == Pausable.paused
#guard Pausable.unpause Pausable.paused == Pausable.running
#guard Pausable.unpause Pausable.running == Pausable.running
#guard Pausable.violation == 0
#guard Pausable.Log.paused ⟨1, 2, 3⟩ == 0
#guard Pausable.Log.unpaused ⟨1, 2, 3⟩ == 0
#guard Ownable.Log.ownershipTransferred ⟨1, 2, 3⟩ ⟨4, 5, 6⟩ == 0

-- Access keeps compatibility names while delegating pause semantics to the single owner.
#guard Access.runningFlag == Pausable.running
#guard Access.pausedFlag == Pausable.paused
#guard Access.requireRunning Pausable.running
#guard !Access.requireRunning Pausable.paused
#guard Access.runningViolation == Pausable.violation

open Examples.Evm.TwoStepCounter in
#guard (init ⟨1, 2, 3⟩).paused == Pausable.running

open Examples.Evm.Credits in
#guard (init ⟨1, 2, 3⟩).paused == Pausable.running

#guard ProofForge.Evm.Registry.digestOf "TwoStepCounter" == some "9e20eb417583ce6e"
#guard ProofForge.Evm.Registry.digestOf "Credits" == some "c2ceddddbf415d40"

end Tests.EvmPausableSpec
