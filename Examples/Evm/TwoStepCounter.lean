import ProofForge

namespace Examples.Evm.TwoStepCounter
open ProofForge.Evm.Sdk

/-!
EVM-SDK-1 consumer A: a counter guarded by `Access.requireOwner` /
`Pausable.isRunning` with two-step ownership transfer via `Access.Ownership`.

The owner is an explicit `Address` state field (mutable so `acceptOwnership` can rotate it), the
paused flag is an explicit `UInt8` state field, and `ownership` contains exactly one pending
address. All storage writes stay in this file. Successful `transferOwnership` emits Ownable2Step
`OwnershipTransferStarted`; successful `acceptOwnership` and `renounceOwnership` emit canonical
`OwnershipTransferred`; renunciation clears both owner and pending nominee. Successful `pause` /
`unpause` emit `Paused` / `Unpaused`. CREATE of a zero owner reverts `OwnableInvalidOwner(address)`.
The success path emits `OwnershipTransferred(address(0), owner)`. Nominate-zero on
`transferOwnership` reverts `OwnableInvalidOwner(address)`.
-/

def u64Max : UInt64 := ~~~(0 : UInt64)

/-- owner: stored so two-step transfer can rotate it. paused: 0 running, 1 paused. -/
structure State where
  owner : Address
  paused : UInt8
  count : UInt64
  ownership : Address
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_entry]
def init (owner : Address) : State :=
  let _ :=
    if Address.isZero owner then
      Revert.ownableInvalidOwner owner
    else
      Ownable.Log.constructorTransferred owner
  { owner, paused := Pausable.running, count := 0, ownership := Access.Ownership.none }

/-- Step 1 of ownership transfer: current owner nominates `candidate`.
    Non-owner → `OwnableUnauthorizedAccount(caller)`; zero candidate → `OwnableInvalidOwner(address)`.
    Success emits `OwnershipTransferStarted(owner, candidate)`. -/
@[pf_entry]
def transferOwnership (s : State) (candidate : Address) : Except Error (State × UInt64) :=
  if Access.requireOwner s.owner then
    if Address.isZero candidate then
      .ok (s, Revert.ownableInvalidOwner candidate)
    else
      .ok ({ s with ownership := Access.Ownership.nominate s.ownership candidate },
        Ownable.Log.ownershipTransferStarted s.owner candidate)
  else
    .ok (s, Access.ownerViolation)

/-- Cancel a pending nomination. Non-owner → `Unauthorized(caller)`. -/
@[pf_entry]
def cancelOwnership (s : State) (candidate : Address) : Except Error (State × UInt64) :=
  if Access.requireOwner s.owner then
    if Access.Ownership.isPending s.ownership candidate then
      .ok ({ s with ownership := Access.Ownership.cancel s.ownership }, 0)
    else
      .ok (s, 0)
  else
    .ok (s, Access.ownerViolation)

/-- Step 2: the nominee accepts. The owner-field write is explicit here; the SDK only
    consumes the nomination flag. Non-nominee → `Unauthorized(caller)`. Success emits
    `OwnershipTransferred(previousOwner, pending)`. The new owner is the stored nominee
    (equal to `caller` on this path) so Extract keeps the owner-field stores beside the log. -/
@[pf_entry]
def acceptOwnership (s : State) : Except Error (State × UInt64) :=
  if Access.Ownership.callerIsPending s.ownership then
    .ok ({ owner := s.ownership, paused := s.paused, count := s.count, ownership :=
      Access.Ownership.consume s.ownership },
      Ownable.Log.ownershipTransferred s.owner s.ownership)
  else
    .ok (s, Access.ownerViolation)

/-- Permanently remove the current owner and clear any pending nominee. Non-owner →
    `Unauthorized(caller)`. Success emits `OwnershipTransferred(previousOwner, address(0))`. -/
@[pf_entry]
def renounceOwnership (s : State) : Except Error (State × UInt64) :=
  if Access.requireOwner s.owner then
    .ok ({ s with owner := Address.zero, ownership := Access.Ownership.cancel s.ownership },
      Ownable.Log.ownershipTransferred s.owner Address.zero)
  else
    .ok (s, Access.ownerViolation)

/-- Owner-gated, pause-gated increment. Non-owner → `Unauthorized(caller)`;
    paused → `Paused()`; overflow → error, no state change. -/
@[pf_entry]
def bump (s : State) (delta : UInt64) : Except Error (State × UInt64) :=
  if Access.requireOwner s.owner then
    if Pausable.isRunning s.paused then
      if s.count ≤ u64Max - delta then
        let next := s.count + delta
        .ok ({ s with count := next }, next)
      else
        .error .overflow
    else
      .ok (s, Pausable.violation)
  else
    .ok (s, Access.ownerViolation)

/-- Owner-gated pause. Success emits `Paused(caller)`. -/
@[pf_entry]
def pause (s : State) : Except Error (State × UInt64) :=
  if Access.requireOwner s.owner then
    .ok ({ s with paused := Pausable.pause s.paused }, Pausable.Log.paused Context.caller)
  else
    .ok (s, Access.ownerViolation)

/-- Owner-gated unpause. Success emits `Unpaused(caller)`. -/
@[pf_entry]
def unpause (s : State) : Except Error (State × UInt64) :=
  if Access.requireOwner s.owner then
    .ok ({ s with paused := Pausable.unpause s.paused }, Pausable.Log.unpaused Context.caller)
  else
    .ok (s, Access.ownerViolation)

@[pf_entry]
def ownerOf (s : State) : Address :=
  s.owner

/-- Sole pending nominee; `Address.zero` when none is live. -/
@[pf_entry]
def pendingOwner (s : State) : Address :=
  s.ownership

@[pf_entry]
def pendingOf (_s : State) (who : Address) : UInt64 :=
  Access.Ownership.nominationOf _s.ownership who

@[pf_entry]
def pausedOf (s : State) : UInt8 :=
  s.paused

@[pf_entry]
def get (s : State) : UInt64 :=
  s.count

end Examples.Evm.TwoStepCounter