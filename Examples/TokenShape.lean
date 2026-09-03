import ProofForge.Attr

/-!
# Shared TokenShape (N15)

Minimal **transfer-shaped** UInt64 ledger — the conceptual subset that lowers from one Lean
source (mirroring `Examples.Counter`).

This is **not** ERC-20 wire: no `approve` / allowance (approve fixtures stay separate).
The digest is pinned in `Tests/TokenShapeSpec` and `ProofForge.Evm.Registry`.
-/

namespace Examples.TokenShape

structure State where
  balance : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

def u64Max : UInt64 := ~~~(0 : UInt64)

@[pf_entry]
def init (initial : UInt64) : State :=
  { balance := initial }

@[pf_entry]
def get (s : State) : UInt64 :=
  s.balance

/-- Credit `amount` into the single balance (checked add). -/
@[pf_entry]
def credit (s : State) (amount : UInt64) : Except Error (State × UInt64) :=
  if s.balance ≤ u64Max - amount then
    let next := s.balance + amount
    .ok ({ balance := next }, next)
  else
    .error .overflow

/-- Debit `amount` from the single balance (checked sub). Transfer-shaped mutual of `credit`. -/
@[pf_entry]
def debit (s : State) (amount : UInt64) : Except Error (State × UInt64) :=
  if amount ≤ s.balance then
    let next := s.balance - amount
    .ok ({ balance := next }, next)
  else
    .error .overflow

theorem credit_overflow_not_ok
    (s : State) (a : UInt64)
    (h : credit s a = .error .overflow) :
    ¬ ∃ t r, credit s a = .ok (t, r) := by
  intro ⟨t, r, hok⟩
  have : Except.error Error.overflow = Except.ok (t, r) := h.symm.trans hok
  cases this

theorem debit_underflow_not_ok
    (s : State) (a : UInt64)
    (h : debit s a = .error .overflow) :
    ¬ ∃ t r, debit s a = .ok (t, r) := by
  intro ⟨t, r, hok⟩
  have : Except.error Error.overflow = Except.ok (t, r) := h.symm.trans hok
  cases this

end Examples.TokenShape
