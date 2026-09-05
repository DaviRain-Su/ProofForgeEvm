import ProofForge.Evm.Sdk

/-!
Dual-asset vesting consumer. Constructor stores the beneficiary and cliff duration, and bakes
`start` / `duration` as immutables. Native ETH uses one `nativeReleased` counter. Each ERC-20
token's paid-out amount lives in a hashed address map. `release()` pays `releasable()` through
`Ether.send`. `release(address)` pays `releasable(token)` through `SafeErc20.transfer`.
`released()` and `released(address)` are the OZ paid-amount views (`released__eth` /
`released__token`; the hashed map stays `released`).
`transferOwnership` nominates a pending owner. `acceptOwnership` rotates the stored beneficiary.
VestLink stays the smaller ETH-only profile, including `release(uint256)`. There is no arbitrary
schedule mutation.
A zero beneficiary reverts `OwnableInvalidOwner(address)` in the constructor. The success path
emits `OwnershipTransferred(address(0), beneficiary)`. Before the cliff, `vestedAmount` is 0.
After the cliff the linear formula still uses `timestamp - start`.

Schedule math is spelled inline at this boundary so extract can emit linear vesting. SDK helpers
supply gates and the typed event only.
-/

namespace Examples.Evm.Vest20Link
open ProofForge.Evm.Sdk

structure State where
  owner : Address
  cliffDuration : UInt64
  nativeReleased : UInt256
  dummy : UInt64
  guard : UInt64
  ownership : Address
  deriving Repr, DecidableEq, Inhabited

structure Handles where
  guard : Storage.Static.Handle UInt64

@[pf_inline] def declared : Storage.Static.Allocated Handles :=
  let owner := Storage.Static.Layout.root.address "owner"
  let cliffDuration := owner.next.uint64 "cliffDuration"
  let nativeReleased := cliffDuration.next.uint256 "nativeReleased"
  let dummy := nativeReleased.next.uint64 "dummy"
  let guard := dummy.next.uint64 "guard"
  let ownership := guard.next.address "ownership"
  { handle := { guard := guard.handle }, next := ownership.next }

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
  { owner := beneficiary, cliffDuration := cliffDuration, nativeReleased := UInt256.zero,
    dummy := 0, guard := Reentrancy.notEntered, ownership := Access.Ownership.none }

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
def released__token (s : State) (token : Address) : UInt256 :=
  if Vesting.canSchedule s.owner Immutable.u64 Immutable.u64b s.cliffDuration then
    if Vesting.wellFormedToken token then
      released.get token
    else
      UInt256.zero
  else
    UInt256.zero

@[pf_entry]
def released__eth (s : State) : UInt256 :=
  if Vesting.canSchedule s.owner Immutable.u64 Immutable.u64b s.cliffDuration then
    s.nativeReleased
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
def releasable__eth (s : State) : UInt256 :=
  if Vesting.canSchedule s.owner Immutable.u64 Immutable.u64b s.cliffDuration then
    if Context.timestamp < Vesting.cliffAt Immutable.u64 Immutable.u64b s.cliffDuration then
      UInt256.zero
    else if Context.timestamp ≥ Vesting.endAt Immutable.u64 Immutable.u64b then
      UInt256.sub (UInt256.add Context.selfBalance s.nativeReleased) s.nativeReleased
    else
      UInt256.sub
        (UInt256.div
          (UInt256.mul (UInt256.add Context.selfBalance s.nativeReleased)
            ⟨Context.timestamp - Immutable.u64, 0, 0, 0⟩)
          ⟨Immutable.u64b, 0, 0, 0⟩)
        s.nativeReleased
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

@[pf_entry]
def vestedAmount__eth (s : State) (timestamp : UInt64) : UInt256 :=
  if Vesting.canSchedule s.owner Immutable.u64 Immutable.u64b s.cliffDuration then
    if timestamp < Vesting.cliffAt Immutable.u64 Immutable.u64b s.cliffDuration then
      UInt256.zero
    else if timestamp ≥ Vesting.endAt Immutable.u64 Immutable.u64b then
      UInt256.add Context.selfBalance s.nativeReleased
    else
      UInt256.div
        (UInt256.mul (UInt256.add Context.selfBalance s.nativeReleased)
          ⟨timestamp - Immutable.u64, 0, 0, 0⟩)
        ⟨Immutable.u64b, 0, 0, 0⟩
  else
    UInt256.zero

/-- Step 1 of Ownable2Step rotation. Zero `newOwner` nominates zero (OZ cancel).
Non-owner reverts `OwnableUnauthorizedAccount(caller)`. Success emits
`OwnershipTransferStarted(owner, newOwner)`. -/
@[pf_entry]
def transferOwnership (s : State) (newOwner : Address) : Except Error (State × UInt64) :=
  if Access.requireOwner s.owner then
    .ok ({ s with ownership := Access.Ownership.nominate s.ownership newOwner },
      Ownable.Log.ownershipTransferStarted s.owner newOwner)
  else
    .ok (s, Access.ownerViolation)

/-- Step 2. The nominee becomes the stored beneficiary. The owner-field write is explicit here
so Extract keeps the owner stores beside the log. Non-nominee reverts
`OwnableUnauthorizedAccount(caller)`. Success emits `OwnershipTransferred(previous, pending)`. -/
@[pf_entry]
def acceptOwnership (s : State) : Except Error (State × UInt64) :=
  if Access.Ownership.callerIsPending s.ownership then
    .ok ({ owner := s.ownership, cliffDuration := s.cliffDuration, nativeReleased :=
      s.nativeReleased, dummy := s.dummy, guard := s.guard, ownership :=
      Access.Ownership.consume s.ownership },
      Ownable.Log.ownershipTransferred s.owner s.ownership)
  else
    .ok (s, Access.ownerViolation)

@[pf_entry]
def pendingOwner (s : State) : Address :=
  s.ownership

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
        let available := UInt256.sub (UInt256.add Context.selfBalance s.nativeReleased) s.nativeReleased
        let _ := Reentrancy.enter declared.handle.guard
        let _ := Ether.send s.owner available
        let _ := Reentrancy.leave declared.handle.guard
        .ok (({ s with nativeReleased := UInt256.add s.nativeReleased available, guard := Reentrancy.notEntered }),
          Vesting.Log.etherReleased available)
      else
        let available :=
          UInt256.sub
            (UInt256.div
              (UInt256.mul (UInt256.add Context.selfBalance s.nativeReleased)
                ⟨Context.timestamp - Immutable.u64, 0, 0, 0⟩)
              ⟨Immutable.u64b, 0, 0, 0⟩)
            s.nativeReleased
        let _ := Reentrancy.enter declared.handle.guard
        let _ := Ether.send s.owner available
        let _ := Reentrancy.leave declared.handle.guard
        .ok (({ s with nativeReleased := UInt256.add s.nativeReleased available, guard := Reentrancy.notEntered }),
          Vesting.Log.etherReleased available)
    else
      .error .reentrantCall
  else
    .ok (s, 0)

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
                 nativeReleased := s.nativeReleased,
                 dummy := released.put token paid,
                 guard := Reentrancy.notEntered,
                 ownership := s.ownership },
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
                     nativeReleased := s.nativeReleased,
                     dummy := released.put token (UInt256.add paid payout),
                     guard := Reentrancy.notEntered,
                     ownership := s.ownership },
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
                     nativeReleased := s.nativeReleased,
                     dummy := released.put token (UInt256.add paid payout),
                     guard := Reentrancy.notEntered,
                     ownership := s.ownership },
                Vesting.TokenLog.erc20Released token payout)
            else
              .error .overflow
          else
            let _ := Reentrancy.enter declared.handle.guard
            let _ := SafeErc20.transfer token s.owner UInt256.zero
            let _ := Reentrancy.leave declared.handle.guard
            .ok ({ owner := s.owner, cliffDuration := s.cliffDuration,
                   nativeReleased := s.nativeReleased,
                   dummy := released.put token paid,
                   guard := Reentrancy.notEntered,
                   ownership := s.ownership },
              Vesting.TokenLog.erc20Released token UInt256.zero)
      else
        .error .reentrantCall
    else
      .ok (s, Revert.zeroAddress)
  else
    .ok (s, 0)

/-- Payable receive: accept native ETH into the vesting wallet. -/
@[pf_entry]
def receive (s : State) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok (s, Ether.receive)
  else
    .error .overflow

end Examples.Evm.Vest20Link
