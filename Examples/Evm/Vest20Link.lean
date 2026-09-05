import ProofForge.Evm.Sdk

/-!
Single-beneficiary ERC-20 vesting consumer. Constructor immutables are the beneficiary,
`start`, and `duration`. Each token's paid-out amount lives in a hashed address map.
`release(address)` pays the currently releasable amount through `SafeErc20.transfer`, matching
OpenZeppelin `release(address token)` (no payout argument). Native-ETH `release(uint256)` stays
on `VestLink`. There is no beneficiary rotation.

Schedule math is spelled inline at this boundary so extract can emit linear vesting. SDK helpers
supply gates and the typed event only.
-/

namespace Examples.Evm.Vest20Link
open ProofForge.Evm.Sdk

structure State where
  dummy : UInt64
  guard : UInt64
  deriving Repr, DecidableEq, Inhabited

structure Handles where
  guard : Storage.Static.Handle UInt64

@[pf_inline] def declared : Storage.Static.Allocated Handles :=
  let dummy := Storage.Static.Layout.root.uint64 "dummy"
  let guard := dummy.next.uint64 "guard"
  { handle := { guard := guard.handle }, next := guard.next }

@[pf_inline] def released : Storage.AddressMap256 :=
  Storage.Layout.root.addressMap256.handle

inductive Error where
  | overflow
  | reentrantCall
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_entry]
def init (_beneficiary : Address) (_start _duration : UInt64) : State :=
  { dummy := 0, guard := Reentrancy.notEntered }

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
def releasedOf (_s : State) (token : Address) : UInt256 :=
  if Vesting.canSchedule Immutable.address Immutable.u64 Immutable.u64b then
    if Vesting.wellFormedToken token then
      released.get token
    else
      UInt256.zero
  else
    UInt256.zero

@[pf_entry]
def releasable (_s : State) (token : Address) : UInt256 :=
  if Vesting.canSchedule Immutable.address Immutable.u64 Immutable.u64b then
    if Vesting.wellFormedToken token then
      if Context.timestamp < Immutable.u64 then
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
def vestedAmount (_s : State) (token : Address) (timestamp : UInt64) : UInt256 :=
  if Vesting.canSchedule Immutable.address Immutable.u64 Immutable.u64b then
    if Vesting.wellFormedToken token then
      if timestamp < Immutable.u64 then
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

/-- Pay the currently releasable ERC-20 amount to the immutable beneficiary. A zero token
reverts `ZeroAddress`. An over-capacity `released + payout` is a hard overflow. The ordered
guard is visible before the external call and restored afterwards. -/
@[pf_entry]
def release (s : State) (token : Address) : Except Error (State × UInt64) :=
  if Vesting.canSchedule Immutable.address Immutable.u64 Immutable.u64b then
    if Vesting.wellFormedToken token then
      if Reentrancy.canEnter s.guard then
        if Context.timestamp < Immutable.u64 then
          let paid := released.get token
          let _ := Reentrancy.enter declared.handle.guard
          let _ := SafeErc20.transfer token Immutable.address UInt256.zero
          let _ := Reentrancy.leave declared.handle.guard
          .ok ({ dummy := released.put token paid, guard := Reentrancy.notEntered },
            Vesting.TokenLog.erc20Released token UInt256.zero)
        else if Context.timestamp ≥ Vesting.endAt Immutable.u64 Immutable.u64b then
          let paid := released.get token
          let held := ERC20.balanceOfSelf token
          if UInt256.ge (UInt256.add held paid) paid then
            let payout := UInt256.sub (UInt256.add held paid) paid
            if UInt256.ge (UInt256.add paid payout) paid then
              let _ := Reentrancy.enter declared.handle.guard
              let _ := SafeErc20.transfer token Immutable.address payout
              let _ := Reentrancy.leave declared.handle.guard
              .ok ({ dummy := released.put token (UInt256.add paid payout),
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
              let _ := SafeErc20.transfer token Immutable.address payout
              let _ := Reentrancy.leave declared.handle.guard
              .ok ({ dummy := released.put token (UInt256.add paid payout),
                     guard := Reentrancy.notEntered },
                Vesting.TokenLog.erc20Released token payout)
            else
              .error .overflow
          else
            let _ := Reentrancy.enter declared.handle.guard
            let _ := SafeErc20.transfer token Immutable.address UInt256.zero
            let _ := Reentrancy.leave declared.handle.guard
            .ok ({ dummy := released.put token paid, guard := Reentrancy.notEntered },
              Vesting.TokenLog.erc20Released token UInt256.zero)
      else
        .error .reentrantCall
    else
      .ok (s, Revert.zeroAddress)
  else
    .ok (s, 0)

end Examples.Evm.Vest20Link
