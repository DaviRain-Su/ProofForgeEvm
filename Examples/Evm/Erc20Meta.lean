import ProofForge

namespace Examples.Evm.Erc20Meta
open ProofForge.Evm.Sdk
open ProofForge.Core.Value

/-!
# ERC-20 metadata profile (product surface)

Minimal ledger + **string** `name` / `symbol` ABI so external tools see ERC-20-shaped
metadata. This is intentionally smaller than `Examples.Evm.Token` (no pause / permit /
cap / non-standard `*Of` renames).

Honest limits:
- Not a full EIP-20 claim (no optional extensions; events only on transfer/approve paths).
- `BoundedString` capacity is compile-time; strings longer than the bound are out of scope.
- Kernel theorems here cover Lean defs only — not `.bin` / EVM refinement.
-/

structure State where
  dummy : UInt64
  supply : UInt256
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_inline] def balances : Fungible.Balances :=
  Storage.Layout.root.addressMap256.handle

@[pf_inline] def allowances : Fungible.Allowances :=
  Storage.Layout.root.addressMap256 |>.next |>.addressPairMap256 |>.handle

/-- Soft-abort state copy for `Effect.ensure` gates. -/
@[reducible, pf_inline] private def hold (s : State) : State :=
  { dummy := s.dummy, supply := s.supply }

@[pf_entry]
def init (_owner : Address) : State :=
  { dummy := 0, supply := UInt256.zero }

/-- UTF-8 `string` ABI (`name()`), not packed `bytes32`. -/
@[pf_entry]
def name (_s : State) : BoundedString 8 :=
  { length := 5, values := #v[0x54, 0x6f, 0x6b, 0x65, 0x6e, 0, 0, 0] }

/-- UTF-8 `string` ABI (`symbol()`). -/
@[pf_entry]
def symbol (_s : State) : BoundedString 4 :=
  { length := 2, values := #v[0x50, 0x46, 0, 0] }

@[pf_entry]
def decimals (_s : State) : UInt8 :=
  18

@[pf_entry]
def totalSupply (s : State) : UInt256 :=
  s.supply

@[pf_entry]
def balanceOf (_s : State) (who : Address) : UInt256 :=
  Fungible.Balances.balanceOf balances who

/-- Standard ERC-20 name `allowance` (not `allowanceOf`). -/
@[pf_entry]
def allowance (_s : State) (owner spender : Address) : UInt256 :=
  Fungible.Allowances.allowanceOf allowances owner spender

@[pf_entry]
def approve (s : State) (spender : Address) (amount : UInt256) :
    Except Error (State × Bool) :=
  Effect.ensure (!Address.isZero spender) (hold s) Revert.zeroAddress fun _ =>
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := Fungible.Allowances.approve allowances Context.caller spender amount,
           supply := s.supply },
      Effect.thenTrue (Event.approval Context.caller spender amount))
  else
    .error .overflow

@[pf_entry]
def transfer (s : State) (destination : Address) (amount : UInt256) :
    Except Error (State × Bool) :=
  Effect.ensure (!Address.isZero destination) (hold s) Revert.zeroAddress fun _ =>
  Effect.ensure (Fungible.Balances.canDebit balances Context.caller amount) (hold s)
      (Fungible.Balances.insufficient balances Context.caller amount) fun _ =>
  if Address.eq Context.caller destination ||
      Fungible.Balances.canCredit balances destination amount then
    let movement :=
      Fungible.Balances.transfer balances Context.caller destination amount
    .ok ({ dummy := movement, supply := s.supply },
      Effect.thenTrue (Event.transfer Context.caller destination amount))
  else
    .error .overflow

@[pf_entry]
def transferFrom (s : State) (owner destination : Address) (amount : UInt256) :
    Except Error (State × Bool) :=
  Effect.ensure (!Address.isZero destination) (hold s) Revert.zeroAddress fun _ =>
  Effect.ensure (Fungible.Allowances.canSpend allowances owner Context.caller amount)
      (hold s) (Fungible.Allowances.insufficient allowances owner Context.caller amount)
      fun _ =>
  Effect.ensure (Fungible.Balances.canDebit balances owner amount) (hold s)
      (Fungible.Balances.insufficient balances owner amount) fun _ =>
  if Address.eq owner destination ||
      Fungible.Balances.canCredit balances destination amount then
    let movement :=
      (Fungible.Balances.transfer balances owner destination amount) |||
      (Fungible.Allowances.spend allowances owner Context.caller amount)
    .ok ({ dummy := movement, supply := s.supply },
      Effect.thenTrue (Event.transfer owner destination amount))
  else
    .error .overflow

end Examples.Evm.Erc20Meta
