import ProofForge.Evm.Sdk

/-!
ERC-20 vesting consumer. Constructor stores the beneficiary and cliff duration, and bakes
`start` / `duration` as immutables. Each token's paid-out amount lives in a hashed address map.
`release(address)` pays the currently releasable amount through `SafeErc20.transfer`, matching
OpenZeppelin `release(address token)`. `transferOwnership` is one-step Ownable rotation of the
stored beneficiary. Native-ETH `release()` / `release(uint256)` stay on `VestLink`. There is no
arbitrary schedule mutation. A zero beneficiary reverts `OwnableInvalidOwner(address)` in the
constructor. The success path emits
`OwnershipTransferred(address(0), beneficiary)`. Before
the cliff, `vestedAmount` is 0. After the cliff the linear formula still uses `timestamp - start`.

Schedule math is spelled inline at this boundary so extract can emit linear vesting. SDK helpers
supply gates and the typed event only.
-/

namespace Examples.Evm.Vest20Link
open ProofForge.Evm.Sdk

structure State where
  owner : Address
  cliffDuration : UInt64
  dummy : UInt64
  guard : UInt64
  deriving Repr, DecidableEq, Inhabited

structure Handles where
  guard : Storage.Static.Handle UInt64

@[pf_inline] def declared : Storage.Static.Allocated Handles :=
  let owner := Storage.Static.Layout.root.address "owner"
  let cliffDuration := owner.next.uint64 "cliffDuration"
  let dummy := cliffDuration.next.uint64 "dummy"
  let guard := dummy.next.uint64 "guard"
  { handle := { guard := guard.handle }, next := guard.next }

@[pf_inline] def released : Storage.AddressMap256 :=
  Storage.Layout.root.addressMap256.handle

inductive Error where
  | overflow
  | reentrantCall
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_entry]
def init (beneficiary : Address) (_start _duration cliffDuration : UInt64) : State :=
  let _ :=
    if Address.isZero beneficiary then
      Revert.ownableInvalidOwner beneficiary
    else
      Ownable.Log.constructorTransferred beneficiary
  { owner := beneficiary, cliffDuration := cliffDuration, dummy := 0, guard := Reentrancy.notEntered }

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
def releasedOf (s : State) (token : Address) : UInt256 :=
  if Vesting.canSchedule s.owner Immutable.u64 Immutable.u64b s.cliffDuration then
    if Vesting.wellFormedToken token then
      released.get token
    else
      UInt256.zero
  else
    UInt256.zero

@[pf_entry]
def releasable (s : State) (token : Address) : UInt256 :=
  if Vesting.canSchedule s.owner Immutable.u64 Immutable.u64b s.cliffDuration then
    if Vesting.wellFormedToken token then
      if Context.timestamp < Vesting.cliffAt Immutable.u64 Immutable.u64b s.cliffDuration then
        UInt256.zero
      else if Context.timestamp ≥ Vesting.endAt Immutable.u64 Immutable.u64b then
        let paid := released.get token
        let held := ERC20.balanceOfSelf token
        if UInt256.ge (UInt256.add held paid) paid then
          UInt256.sub (UInt256.add held paid) paid
        else
          UInt256.zero
      else
        let paid := released.get token
        let held := ERC20.balanceOfSelf token
        let vested :=
          UInt256.div
            (UInt256.mul (UInt256.add held paid)
              ⟨Context.timestamp - Immutable.u64, 0, 0, 0⟩)
            ⟨Immutable.u64b, 0, 0, 0⟩
        if UInt256.ge vested paid then UInt256.sub vested paid else UInt256.zero
    else
      UInt256.zero
  else
    UInt256.zero

@[pf_entry]
def vestedAmount (s : State) (token : Address) (timestamp : UInt64) : UInt256 :=
  if Vesting.canSchedule s.owner Immutable.u64 Immutable.u64b s.cliffDuration then
    if Vesting.wellFormedToken token then
      if timestamp < Vesting.cliffAt Immutable.u64 Immutable.u64b s.cliffDuration then
        UInt256.zero
      else if timestamp ≥ Vesting.endAt Immutable.u64 Immutable.u64b then
        UInt256.add (ERC20.balanceOfSelf token) (released.get token)
      else
        UInt256.div
          (UInt256.mul (UInt256.add (ERC20.balanceOfSelf token) (released.get token))
            ⟨timestamp - Immutable.u64, 0, 0, 0⟩)
          ⟨Immutable.u64b, 0, 0, 0⟩
    else
      UInt256.zero
  else
    UInt256.zero

/-- One-step Ownable rotation of the stored beneficiary. Zero `newOwner` reverts
`OwnableInvalidOwner(newOwner)`. Non-owner reverts `Unauthorized(caller)`. Success emits
`OwnershipTransferred(previous, newOwner)`. -/
@[pf_entry]
def transferOwnership (s : State) (newOwner : Address) : Except Error (State × UInt64) :=
  if Access.requireOwner s.owner then
    if Address.isZero newOwner then
      .ok (s, Revert.ownableInvalidOwner newOwner)
    else
      .ok ({ s with owner := newOwner }, Ownable.Log.ownershipTransferred s.owner newOwner)
  else
    .ok (s, Access.ownerViolation)

/-- Pay the currently releasable ERC-20 amount to the stored beneficiary. A zero token
reverts `ZeroAddress`. An over-capacity `released + payout` is a hard overflow. The ordered
guard is visible before the external call and restored afterwards. -/
@[pf_entry]
def release (s : State) (token : Address) : Except Error (State × UInt64) :=
  if Vesting.canSchedule s.owner Immutable.u64 Immutable.u64b s.cliffDuration then
    if Vesting.wellFormedToken token then
      if Reentrancy.canEnter s.guard then
        if Context.timestamp < Vesting.cliffAt Immutable.u64 Immutable.u64b s.cliffDuration then
          let paid := released.get token
          let _ := Reentrancy.enter declared.handle.guard
          let _ := SafeErc20.transfer token s.owner UInt256.zero
          let _ := Reentrancy.leave declared.handle.guard
          .ok ({ owner := s.owner, cliffDuration := s.cliffDuration,
                 dummy := released.put token paid,
                 guard := Reentrancy.notEntered },
            Vesting.TokenLog.erc20Released token UInt256.zero)
        else if Context.timestamp ≥ Vesting.endAt Immutable.u64 Immutable.u64b then
          let paid := released.get token
          let held := ERC20.balanceOfSelf token
          if UInt256.ge (UInt256.add held paid) paid then
            let payout := UInt256.sub (UInt256.add held paid) paid
            if UInt256.ge (UInt256.add paid payout) paid then
              let _ := Reentrancy.enter declared.handle.guard
              let _ := SafeErc20.transfer token s.owner payout
              let _ := Reentrancy.leave declared.handle.guard
              .ok ({ owner := s.owner, cliffDuration := s.cliffDuration,
                     dummy := released.put token (UInt256.add paid payout),
                     guard := Reentrancy.notEntered },
                Vesting.TokenLog.erc20Released token payout)
            else
              .error .overflow
          else
            .error .overflow
        else
          let paid := released.get token
          let held := ERC20.balanceOfSelf token
          let vested :=
            UInt256.div
              (UInt256.mul (UInt256.add held paid)
                ⟨Context.timestamp - Immutable.u64, 0, 0, 0⟩)
              ⟨Immutable.u64b, 0, 0, 0⟩
          if UInt256.ge vested paid then
            let payout := UInt256.sub vested paid
            if UInt256.ge (UInt256.add paid payout) paid then
              let _ := Reentrancy.enter declared.handle.guard
              let _ := SafeErc20.transfer token s.owner payout
              let _ := Reentrancy.leave declared.handle.guard
              .ok ({ owner := s.owner, cliffDuration := s.cliffDuration,
                     dummy := released.put token (UInt256.add paid payout),
                     guard := Reentrancy.notEntered },
                Vesting.TokenLog.erc20Released token payout)
            else
              .error .overflow
          else
            let _ := Reentrancy.enter declared.handle.guard
            let _ := SafeErc20.transfer token s.owner UInt256.zero
            let _ := Reentrancy.leave declared.handle.guard
            .ok ({ owner := s.owner, cliffDuration := s.cliffDuration,
                   dummy := released.put token paid,
                   guard := Reentrancy.notEntered },
              Vesting.TokenLog.erc20Released token UInt256.zero)
      else
        .error .reentrantCall
    else
      .ok (s, Revert.zeroAddress)
  else
    .ok (s, 0)

end Examples.Evm.Vest20Link
