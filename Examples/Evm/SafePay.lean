import ProofForge.Evm.Sdk

/-!
Fail-closed ERC-20 consumer. The SDK owns the closed CALL recipes, zero-address gates, and
checked increase/decrease/force-approve policy. This contract does not implement a token
ledger: it moves another token's balances through typed helpers, never raw calldata.
-/

namespace Examples.Evm.SafePay
open ProofForge.Evm.Sdk

structure State where
  dummy : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[reducible, pf_inline] private def hold (s : State) : State :=
  { dummy := s.dummy }

@[pf_entry]
def init (_seed : UInt64) : State :=
  { dummy := 0 }

/-- Closed ERC-20 `balanceOf(address(this))`. -/
@[pf_entry]
def held (_s : State) (token : Address) : UInt256 :=
  ERC20.balanceOfSelf token

/-- Closed ERC-20 `allowance(address(this), spender)`. -/
@[pf_entry]
def allowed (_s : State) (token spender : Address) : UInt256 :=
  SafeErc20.allowanceOfSelf token spender

/-- Fail-closed `transfer` with an explicit zero-destination gate. -/
@[pf_entry]
def pull (s : State) (token dest : Address) (amt : UInt256) :
    Except Error (State × UInt64) :=
  Effect.ensureCode (SafeErc20.canSend dest) (hold s) Revert.zeroAddress fun _ =>
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := 0 }, SafeErc20.transfer token dest amt)
  else
    .error .overflow

/-- Fail-closed `approve` with an explicit zero-spender gate. -/
@[pf_entry]
def grant (s : State) (token spender : Address) (amt : UInt256) :
    Except Error (State × UInt64) :=
  Effect.ensureCode (SafeErc20.canSend spender) (hold s) Revert.zeroAddress fun _ =>
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := 0 }, SafeErc20.approve token spender amt)
  else
    .error .overflow

/-- Fail-closed `transferFrom` with an explicit zero-destination gate. -/
@[pf_entry]
def take (s : State) (token owner dest : Address) (amt : UInt256) :
    Except Error (State × UInt64) :=
  Effect.ensureCode (SafeErc20.canSend dest) (hold s) Revert.zeroAddress fun _ =>
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := 0 }, SafeErc20.transferFrom token owner dest amt)
  else
    .error .overflow

/-- Read-modify-write increase of this contract's allowance. Wraparound is a hard overflow. -/
@[pf_entry]
def bump (s : State) (token spender : Address) (added : UInt256) :
    Except Error (State × UInt64) :=
  Effect.ensureCode (SafeErc20.canSend spender) (hold s) Revert.zeroAddress fun _ =>
  if SafeErc20.canIncrease (SafeErc20.allowanceOfSelf token spender) added then
    .ok ({ dummy := 0 }, SafeErc20.increaseAllowance token spender added)
  else
    .error .overflow

/-- Read-modify-write decrease of this contract's allowance. Underflow is a hard overflow. -/
@[pf_entry]
def drop (s : State) (token spender : Address) (subtracted : UInt256) :
    Except Error (State × UInt64) :=
  Effect.ensureCode (SafeErc20.canSend spender) (hold s) Revert.zeroAddress fun _ =>
  if SafeErc20.canDecrease (SafeErc20.allowanceOfSelf token spender) subtracted then
    .ok ({ dummy := 0 }, SafeErc20.decreaseAllowance token spender subtracted)
  else
    .error .overflow

/-- USDT-safe approve: zero then `amt`. -/
@[pf_entry]
def force (s : State) (token spender : Address) (amt : UInt256) :
    Except Error (State × UInt64) :=
  Effect.ensureCode (SafeErc20.canSend spender) (hold s) Revert.zeroAddress fun _ =>
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := 0 }, SafeErc20.forceApprove token spender amt)
  else
    .error .overflow

end Examples.Evm.SafePay
