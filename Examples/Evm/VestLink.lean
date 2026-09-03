import ProofForge.Evm.Sdk

/-!
Single-beneficiary native-ETH vesting consumer. Constructor immutables are the beneficiary,
`start`, and `duration`; a `released` counter tracks payouts and an ordered storage lock protects
the native-ETH call. There is no ERC-20 token map, beneficiary rotation, or schedule mutation.
Invalid configuration (zero beneficiary or overflowing `start + duration`) fails closed to zero
views and a no-op `release`.

Schedule math is spelled inline at this boundary so extract can emit linear vesting; SDK helpers
supply gates and the typed event only.
-/

namespace Examples.Evm.VestLink
open ProofForge.Evm.Sdk

structure State where
  released : UInt256
  guard : UInt64
  deriving Repr, DecidableEq, Inhabited

structure Handles where
  guard : Storage.Static.Handle UInt64

@[pf_inline] def declared : Storage.Static.Allocated Handles :=
  let released := Storage.Static.Layout.root.uint256 "released"
  let guard := released.next.uint64 "guard"
  { handle := { guard := guard.handle }, next := guard.next }

inductive Error where
  | overflow
  | reentrantCall
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_entry]
def init (_beneficiary : Address) (_start _duration : UInt64) : State :=
  { released := UInt256.zero, guard := Reentrancy.notEntered }

@[pf_entry]
def beneficiary (_s : State) : Address :=
  if Vesting.canSchedule Immutable.address Immutable.u64 Immutable.u64b then
    Immutable.address
  else
    Address.zero

@[pf_entry]
def start (_s : State) : UInt256 :=
  if Vesting.canSchedule Immutable.address Immutable.u64 Immutable.u64b then
    ⟨Immutable.u64, 0, 0, 0⟩
  else
    UInt256.zero

@[pf_entry]
def duration (_s : State) : UInt256 :=
  if Vesting.canSchedule Immutable.address Immutable.u64 Immutable.u64b then
    ⟨Immutable.u64b, 0, 0, 0⟩
  else
    UInt256.zero

@[pf_entry]
def endTime (_s : State) : UInt256 :=
  if Vesting.canSchedule Immutable.address Immutable.u64 Immutable.u64b then
    ⟨Vesting.endAt Immutable.u64 Immutable.u64b, 0, 0, 0⟩
  else
    UInt256.zero

@[pf_entry]
def releasedOf (s : State) : UInt256 :=
  if Vesting.canSchedule Immutable.address Immutable.u64 Immutable.u64b then
    s.released
  else
    UInt256.zero

@[pf_entry]
def releasable (s : State) : UInt256 :=
  if Vesting.canSchedule Immutable.address Immutable.u64 Immutable.u64b then
    if Context.timestamp < Immutable.u64 then
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
  if Vesting.canSchedule Immutable.address Immutable.u64 Immutable.u64b then
    if !Vesting.wellFormedDuration Immutable.u64 Immutable.u64b then
      UInt256.zero
    else if timestamp < Immutable.u64 then
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

/-- Release at most the currently releasable native ETH to the immutable beneficiary. The
parameter permits a partial payout; an over-release reverts with `Insufficient`. The ordered
guard is visible before the external call and restored afterwards. -/
@[pf_entry]
def release (s : State) (payout : UInt256) : Except Error (State × UInt64) :=
  if Vesting.canSchedule Immutable.address Immutable.u64 Immutable.u64b then
    if Reentrancy.canEnter s.guard then
      if Context.timestamp < Immutable.u64 then
        if UInt256.le payout UInt256.zero then
          let _ := Reentrancy.enter declared.handle.guard
          let _ := Ether.send Immutable.address payout
          let _ := Reentrancy.leave declared.handle.guard
          .ok ({ released := UInt256.add s.released payout, guard := Reentrancy.notEntered },
            Vesting.Log.etherReleased payout)
        else
          .ok (s, Revert.insufficient UInt256.zero payout)
      else if Context.timestamp ≥ Vesting.endAt Immutable.u64 Immutable.u64b then
        let available := UInt256.sub (UInt256.add Context.selfBalance s.released) s.released
        if UInt256.le payout available then
          let _ := Reentrancy.enter declared.handle.guard
          let _ := Ether.send Immutable.address payout
          let _ := Reentrancy.leave declared.handle.guard
          .ok ({ released := UInt256.add s.released payout, guard := Reentrancy.notEntered },
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
          let _ := Ether.send Immutable.address payout
          let _ := Reentrancy.leave declared.handle.guard
          .ok ({ released := UInt256.add s.released payout, guard := Reentrancy.notEntered },
            Vesting.Log.etherReleased payout)
        else
          .ok (s, Revert.insufficient available payout)
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
