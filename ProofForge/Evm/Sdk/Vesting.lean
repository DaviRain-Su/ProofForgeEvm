import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.Vesting

/-!
# EVM SDK bounded single-beneficiary vesting schedule

Constructor-stored beneficiary plus immutables for `start` and `duration`, a linear vesting
curve over `Context.timestamp`, and typed `EtherReleased` / `ERC20Released` logs. Native-ETH
accounting is one `released` counter on `VestLink`. ERC-20 accounting is a hashed `token → paid`
map on `Vest20Link`. Consumers rotate the beneficiary with one-step `transferOwnership`
(Ownable `OwnershipTransferred`). There is no cliff or arbitrary schedule mutation. Consumers
must validate `canSchedule` before advertising schedule views or `release`.

Fail-closed gates:
- Zero beneficiary or overflowing `start + duration` should yield zero views and no release.
- `releasable` never underflows; zero duration behaves as a timelock at `start`.

Extract note: `pf_entry` schedule views must gate on `canSchedule` at the consumer boundary
(`if canSchedule then value else zero`). Do not route returns through parameterized SDK helpers;
use the predicates here and assemble results at the boundary.
-/

def u64Max : UInt64 := ~~~(0 : UInt64)

/-- True when the beneficiary address is nonzero. -/
@[pf_inline] def wellFormedBeneficiary (beneficiary : Address) : Bool :=
  !Address.isZero beneficiary

/-- True when an ERC-20 token address is nonzero. Zero is refused by the consumer, not by the
closed CALL. -/
@[pf_inline] def wellFormedToken (token : Address) : Bool :=
  !Address.isZero token

/-- True when `start + duration` fits in `UInt64`. Duration zero is always well-formed. -/
@[pf_inline] def wellFormedDuration (start duration : UInt64) : Bool :=
  duration == 0 || start ≤ u64Max - duration

/-- Schedule views and release may run only with a nonzero beneficiary and non-overflowing end. -/
@[pf_inline] def canSchedule (beneficiary : Address) (start duration : UInt64) : Bool :=
  wellFormedBeneficiary beneficiary && wellFormedDuration start duration

/-- End timestamp; zero when the duration gate fails. -/
@[pf_inline] def endAt (start duration : UInt64) : UInt64 :=
  if wellFormedDuration start duration then start + duration else 0

/-- OZ-style allocation: current balance plus already released wei. -/
@[pf_inline] def totalAllocation (balance released : UInt256) : UInt256 :=
  UInt256.add balance released

/-- Linear vesting amount at `timestamp`; zero when the schedule is ill-formed or before `start`. -/
@[pf_inline] def vestedAmount (totalAllocation : UInt256) (start duration timestamp : UInt64) : UInt256 :=
  if !wellFormedDuration start duration then
    UInt256.zero
  else if timestamp < start then
    UInt256.zero
  else if timestamp ≥ endAt start duration then
    totalAllocation
  else
    let elapsed : UInt256 := ⟨timestamp - start, 0, 0, 0⟩
    let span : UInt256 := ⟨duration, 0, 0, 0⟩
    UInt256.div (UInt256.mul totalAllocation elapsed) span

/-- Releasable wei at `timestamp`; zero when nothing has vested beyond `released`. -/
@[pf_inline] def releasable (totalAllocation released : UInt256) (start duration timestamp : UInt64) :
    UInt256 :=
  let vested := vestedAmount totalAllocation start duration timestamp
  if UInt256.ge vested released then UInt256.sub vested released else UInt256.zero

/-- Canonical OpenZeppelin `EtherReleased` typed event. -/
inductive Notice where
  | EtherReleased (amount : UInt256)
  deriving Repr, DecidableEq, Inhabited

namespace Log

/-- LOG1 `EtherReleased(uint256 amount)`. -/
@[pf_inline] def etherReleased (amount : UInt256) : UInt64 :=
  Event.emit (Notice.EtherReleased amount)

end Log

/-- Canonical OpenZeppelin `ERC20Released` typed event. -/
inductive TokenNotice where
  | ERC20Released (token : Event.Indexed Address) (amount : UInt256)
  deriving Repr, DecidableEq, Inhabited

namespace TokenLog

/-- LOG2 `ERC20Released(address indexed token, uint256 amount)`. -/
@[pf_inline] def erc20Released (token : Address) (amount : UInt256) : UInt64 :=
  Event.emit (TokenNotice.ERC20Released (Event.indexed token) amount)

end TokenLog

end ProofForge.Evm.Sdk.Vesting
