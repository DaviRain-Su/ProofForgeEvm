import ProofForge.Evm.Sdk.Payments

namespace ProofForge.Evm.Sdk.SafeErc20

/-!
# EVM SDK fail-closed ERC-20 consumer helpers

OpenZeppelin-shaped wrappers around the existing closed ERC-20 CALL recipes. Applications never
supply raw calldata, a selector string, a return buffer, or an opcode. Each mutation still goes
through `CallResult`'s fail-closed compatibility policy (CALL success plus canonical `true` or
code-backed empty returndata). False, noncanonical, and EOA-empty returns revert.

Zero-address gates are explicit application policy, not part of the closed CALL. Increase and
decrease helpers read `allowance(address(this), spender)` then `approve` the next value; they do
not open a second interpreter. `forceApprove` uses the USDT two-step (zero, then value) because
a failed CALL cannot be caught and retried.
-/

/-- Destination/spender must be nonzero. Zero is refused by the caller, not by the closed CALL. -/
@[pf_inline] def canSend (destination : Address) : Bool :=
  !Address.isZero destination

/-- Closed `transfer`; empty or canonical nonzero return data succeeds. -/
@[pf_inline] def transfer (token destination : Address) (amount : UInt256) : UInt64 :=
  ERC20.transfer token destination amount

/-- Closed `approve`; empty or canonical nonzero return data succeeds. -/
@[pf_inline] def approve (token spender : Address) (amount : UInt256) : UInt64 :=
  ERC20.approve token spender amount

/-- Closed `transferFrom`; empty or canonical nonzero return data succeeds. -/
@[pf_inline] def transferFrom (token owner destination : Address) (amount : UInt256) : UInt64 :=
  ERC20.transferFrom token owner destination amount

/-- Current allowance of `address(this)` to `spender`. -/
@[pf_inline] def allowanceOfSelf (token spender : Address) : UInt256 :=
  ERC20.allowance token Context.self spender

/-- Unsigned add of `current` and `added` does not wrap. -/
@[pf_inline] def canIncrease (current added : UInt256) : Bool :=
  UInt256.ge (UInt256.add current added) current

@[pf_inline] def nextIncrease (current added : UInt256) : UInt256 :=
  UInt256.add current added

/-- Read-modify-write increase of this contract's allowance. Precondition:
`canSend spender && canIncrease (allowanceOfSelf token spender) added`. -/
@[pf_inline] def increaseAllowance (token spender : Address) (added : UInt256) : UInt64 :=
  ERC20.approve token spender (nextIncrease (allowanceOfSelf token spender) added)

/-- `current` covers `subtracted`. -/
@[pf_inline] def canDecrease (current subtracted : UInt256) : Bool :=
  UInt256.ge current subtracted

@[pf_inline] def nextDecrease (current subtracted : UInt256) : UInt256 :=
  UInt256.sub current subtracted

/-- Read-modify-write decrease of this contract's allowance. Precondition:
`canSend spender && canDecrease (allowanceOfSelf token spender) subtracted`. -/
@[pf_inline] def decreaseAllowance (token spender : Address) (subtracted : UInt256) : UInt64 :=
  ERC20.approve token spender (nextDecrease (allowanceOfSelf token spender) subtracted)

/-- USDT-safe approve: write zero, then `amount`. Always two closed CALLs so a nonzero-to-nonzero
token cannot trap a single `approve`. Precondition: `canSend spender`. -/
@[pf_inline] def forceApprove (token spender : Address) (amount : UInt256) : UInt64 :=
  ERC20.approve token spender UInt256.zero ||| ERC20.approve token spender amount

section Proofs

theorem transfer_eq (token destination : Address) (amount : UInt256) :
    transfer token destination amount = ERC20.transfer token destination amount := rfl

theorem approve_eq (token spender : Address) (amount : UInt256) :
    approve token spender amount = ERC20.approve token spender amount := rfl

theorem transferFrom_eq (token owner destination : Address) (amount : UInt256) :
    transferFrom token owner destination amount
      = ERC20.transferFrom token owner destination amount := rfl

theorem allowanceOfSelf_eq (token spender : Address) :
    allowanceOfSelf token spender = ERC20.allowance token Context.self spender := rfl

theorem forceApprove_eq (token spender : Address) (amount : UInt256) :
    forceApprove token spender amount
      = (ERC20.approve token spender UInt256.zero ||| ERC20.approve token spender amount) := rfl

end Proofs

end ProofForge.Evm.Sdk.SafeErc20
