import ProofForge.Evm.Sdk

/-!
Native-ETH vesting consumer. Constructor stores the beneficiary and cliff duration, and bakes
`start` / `duration` as immutables. `released` tracks payouts and an ordered storage lock
protects the native-ETH call. `transferOwnership` is one-step Ownable rotation of that stored
beneficiary. `release()` pays the currently releasable amount (OZ ABI). `release(uint256)` still
permits a partial payout. The ERC-20 `released[token]` map lives on `Vest20Link`. There is no
arbitrary schedule mutation.

Invalid configuration (zero beneficiary, overflowing `start + duration`, or
`cliffDuration > duration`) fails closed to zero views and a no-op `release`. Before the cliff,
`vestedAmount` is 0 even when `timestamp ≥ start`. After the cliff the linear formula still uses
`timestamp - start`.

Schedule math is spelled inline at this boundary so extract can emit linear vesting; SDK helpers
supply gates and the typed event only.
-/

namespace Examples.Evm.VestLink
open ProofForge.Evm.Sdk

structure State where
  owner : Address
  cliffDuration : UInt64
  released : UInt256
  guard : UInt64
  deriving Repr, DecidableEq, Inhabited

structure Handles where
  guard : Storage.Static.Handle UInt64

@[pf_inline] def declared : Storage.Static.Allocated Handles :=
  let owner := Storage.Static.Layout.root.address "owner"
  let cliffDuration := owner.next.uint64 "cliffDuration"
  let released := cliffDuration.next.uint256 "released"
  let guard := released.next.uint64 "guard"
  { handle := { guard := guard.handle }, next := guard.next }

inductive Error where
  | overflow
  | reentrantCall
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_entry]
def init (beneficiary : Address) (_start _duration cliffDuration : UInt64) : State :=
  { owner := beneficiary, cliffDuration := cliffDuration, released := UInt256.zero,
    guard := Reentrancy.notEntered }

@[pf_entry]
def beneficiary (s : State) : Address :=
  if Vesting.canSchedule s.owner Immutable.u64 Immutable.u64b s.cliffDuration then
    s.owner
  else
    Address.zero

@[pf_entry]
def owner (s : State) : Address :=
  s.owner

@[pf_entry]
def start (s : State) : UInt256 :=
  if Vesting.canSchedule s.owner Immutable.u64 Immutable.u64b s.cliffDuration then
    ⟨Immutable.u64, 0, 0, 0⟩
  else
    UInt256.zero

@[pf_entry]
def duration (s : State) : UInt256 :=
  if Vesting.canSchedule s.owner Immutable.u64 Immutable.u64b s.cliffDuration then
    ⟨Immutable.u64b, 0, 0, 0⟩
  else
    UInt256.zero

@[pf_entry]
def cliff (s : State) : UInt256 :=
  if Vesting.canSchedule s.owner Immutable.u64 Immutable.u64b s.cliffDuration then
    ⟨Vesting.cliffAt Immutable.u64 Immutable.u64b s.cliffDuration, 0, 0, 0⟩
  else
    UInt256.zero

@[pf_entry]
def endTime (s : State) : UInt256 :=
  if Vesting.canSchedule s.owner Immutable.u64 Immutable.u64b s.cliffDuration then
    ⟨Vesting.endAt Immutable.u64 Immutable.u64b, 0, 0, 0⟩
  else
    UInt256.zero

@[pf_entry]
def releasedOf (s : State) : UInt256 :=
  if Vesting.canSchedule s.owner Immutable.u64 Immutable.u64b s.cliffDuration then
    s.released
  else
    UInt256.zero

@[pf_entry]
def releasable (s : State) : UInt256 :=
  if Vesting.canSchedule s.owner Immutable.u64 Immutable.u64b s.cliffDuration then
    if Context.timestamp < Vesting.cliffAt Immutable.u64 Immutable.u64b s.cliffDuration then
      UInt256.zero
    else if Context.timestamp ≥ Vesting.endAt Immutable.u64 Immutable.u64b then
      UInt256.sub (UInt256.add Context.selfBalance s.released) s.released
    else
      UInt256.sub
        (UInt256.div
          (UInt256.mul (UInt256.add Context.selfBalance s.released)
            ⟨Context.timestamp - Immutable.u64, 0, 0, 0⟩)
          ⟨Immutable.u64b, 0, 0, 0⟩)
        s.released
  else
    UInt256.zero

@[pf_entry]
def vestedAmount (s : State) (timestamp : UInt64) : UInt256 :=
  if Vesting.canSchedule s.owner Immutable.u64 Immutable.u64b s.cliffDuration then
    if timestamp < Vesting.cliffAt Immutable.u64 Immutable.u64b s.cliffDuration then
      UInt256.zero
    else if timestamp ≥ Vesting.endAt Immutable.u64 Immutable.u64b then
      UInt256.add Context.selfBalance s.released
    else
      UInt256.div
        (UInt256.mul (UInt256.add Context.selfBalance s.released)
          ⟨timestamp - Immutable.u64, 0, 0, 0⟩)
        ⟨Immutable.u64b, 0, 0, 0⟩
  else
    UInt256.zero

/-- One-step Ownable rotation of the stored beneficiary. Zero `newOwner` reverts
`ZeroAddress`. Non-owner reverts `Unauthorized(caller)`. Success emits
`OwnershipTransferred(previous, newOwner)`. -/
@[pf_entry]
def transferOwnership (s : State) (newOwner : Address) : Except Error (State × UInt64) :=
  if Access.requireOwner s.owner then
    if Address.isZero newOwner then
      .ok (s, Revert.zeroAddress)
    else
      .ok ({ s with owner := newOwner }, Ownable.Log.ownershipTransferred s.owner newOwner)
  else
    .ok (s, Access.ownerViolation)

/-- Release at most the currently releasable native ETH to the stored beneficiary. The
parameter permits a partial payout; an over-release reverts with `Insufficient`. The ordered
guard is visible before the external call and restored afterwards. -/
@[pf_entry]
def release (s : State) (payout : UInt256) : Except Error (State × UInt64) :=
  if Vesting.canSchedule s.owner Immutable.u64 Immutable.u64b s.cliffDuration then
    if Reentrancy.canEnter s.guard then
      if Context.timestamp < Vesting.cliffAt Immutable.u64 Immutable.u64b s.cliffDuration then
        if UInt256.le payout UInt256.zero then
          let _ := Reentrancy.enter declared.handle.guard
          let _ := Ether.send s.owner payout
          let _ := Reentrancy.leave declared.handle.guard
          .ok (({ s with released := UInt256.add s.released payout, guard := Reentrancy.notEntered }),
            Vesting.Log.etherReleased payout)
        else
          .ok (s, Revert.insufficient UInt256.zero payout)
      else if Context.timestamp ≥ Vesting.endAt Immutable.u64 Immutable.u64b then
        let available := UInt256.sub (UInt256.add Context.selfBalance s.released) s.released
        if UInt256.le payout available then
          let _ := Reentrancy.enter declared.handle.guard
          let _ := Ether.send s.owner payout
          let _ := Reentrancy.leave declared.handle.guard
          .ok (({ s with released := UInt256.add s.released payout, guard := Reentrancy.notEntered }),
            Vesting.Log.etherReleased payout)
        else
          .ok (s, Revert.insufficient available payout)
      else
        let available :=
          UInt256.sub
            (UInt256.div
              (UInt256.mul (UInt256.add Context.selfBalance s.released)
                ⟨Context.timestamp - Immutable.u64, 0, 0, 0⟩)
              ⟨Immutable.u64b, 0, 0, 0⟩)
            s.released
        if UInt256.le payout available then
          let _ := Reentrancy.enter declared.handle.guard
          let _ := Ether.send s.owner payout
          let _ := Reentrancy.leave declared.handle.guard
          .ok (({ s with released := UInt256.add s.released payout, guard := Reentrancy.notEntered }),
            Vesting.Log.etherReleased payout)
        else
          .ok (s, Revert.insufficient available payout)
    else
      .error .reentrantCall
  else
    .ok (s, 0)

/-- Pay the currently releasable native ETH. ABI name `release()` (OZ `VestingWallet.release()`).
A zero payout still logs `EtherReleased(0)` and sends 0. -/
@[pf_entry]
def release__all (s : State) : Except Error (State × UInt64) :=
  if Vesting.canSchedule s.owner Immutable.u64 Immutable.u64b s.cliffDuration then
    if Reentrancy.canEnter s.guard then
      if Context.timestamp < Vesting.cliffAt Immutable.u64 Immutable.u64b s.cliffDuration then
        let _ := Reentrancy.enter declared.handle.guard
        let _ := Ether.send s.owner UInt256.zero
        let _ := Reentrancy.leave declared.handle.guard
        .ok (({ s with guard := Reentrancy.notEntered }),
          Vesting.Log.etherReleased UInt256.zero)
      else if Context.timestamp ≥ Vesting.endAt Immutable.u64 Immutable.u64b then
        let available := UInt256.sub (UInt256.add Context.selfBalance s.released) s.released
        let _ := Reentrancy.enter declared.handle.guard
        let _ := Ether.send s.owner available
        let _ := Reentrancy.leave declared.handle.guard
        .ok (({ s with released := UInt256.add s.released available, guard := Reentrancy.notEntered }),
          Vesting.Log.etherReleased available)
      else
        let available :=
          UInt256.sub
            (UInt256.div
              (UInt256.mul (UInt256.add Context.selfBalance s.released)
                ⟨Context.timestamp - Immutable.u64, 0, 0, 0⟩)
              ⟨Immutable.u64b, 0, 0, 0⟩)
            s.released
        let _ := Reentrancy.enter declared.handle.guard
        let _ := Ether.send s.owner available
        let _ := Reentrancy.leave declared.handle.guard
        .ok (({ s with released := UInt256.add s.released available, guard := Reentrancy.notEntered }),
          Vesting.Log.etherReleased available)
    else
      .error .reentrantCall
  else
    .ok (s, 0)

/-- Payable receive: accept native ETH into the vesting wallet. -/
@[pf_entry]
def receive (s : State) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok (s, Ether.receive)
  else
    .error .overflow

end Examples.Evm.VestLink
