import ProofForge.Evm.Sdk
import ProofForge.Core.Value

namespace Examples.Evm.Erc20Meta
open ProofForge.Evm.Sdk
open ProofForge.Core.Value

/-!
# ERC-20 metadata profile (product surface)

Minimal ledger + **string** `name` / `symbol` ABI so external tools see ERC-20-shaped
metadata. This is intentionally smaller than `Examples.Evm.Token` (no pause / cap /
packed `bytes32` metadata / non-standard `*Of` renames). Issuer EIP-2612 `permit`,
`DOMAIN_SEPARATOR`, and `nonces` use the closed Token/1 path (`Permit.authorize`).

Honest limits:
- Not a full EIP-20 claim (no pause, cap, or extension ecosystem; events only on
  transfer/approve/permit paths).
- `BoundedString` capacity is compile-time; strings longer than the bound are out of scope.
- Permit domain is the closed Token/1 name/version (nonce base 2, allowance base 1), not the
  string metadata views. The example name happens to be `Token`.
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

/-- Same hashed-map base as `emitPermit` (nonce base 2 after balances 0 and allowances 1). -/
@[pf_inline] def nonceStore : Storage.AddressMap256 :=
  Storage.Layout.root.addressMap256 |>.next |>.addressPairMap256 |>.next
    |>.addressMap256 |>.handle

/-- UTF-8 bytes for `Token` padded to the example name capacity. -/
@[pf_inline] def tokenName : BoundedString 8 :=
  { length := 5, values := #v[0x54, 0x6f, 0x6b, 0x65, 0x6e, 0, 0, 0] }

/-- UTF-8 bytes for `PF` padded to the example symbol capacity. -/
@[pf_inline] def tokenSymbol : BoundedString 4 :=
  { length := 2, values := #v[0x50, 0x46, 0, 0] }

/-- Soft-abort state copy for `Effect.ensure` gates. -/
@[reducible, pf_inline] private def hold (s : State) : State :=
  { dummy := s.dummy, supply := s.supply }

@[pf_entry]
def init (_owner : Address) : State :=
  { dummy := 0, supply := UInt256.zero }

/-- UTF-8 `string` ABI (`name()`), not packed `bytes32`. Fail closed when misconfigured. -/
@[pf_entry]
def name (_s : State) : BoundedString 8 :=
  { length := if Erc20Meta.canPublish tokenName tokenSymbol then 5 else 0
    values := #v[0x54, 0x6f, 0x6b, 0x65, 0x6e, 0, 0, 0] }

/-- UTF-8 `string` ABI (`symbol()`). Fail closed when misconfigured. -/
@[pf_entry]
def symbol (_s : State) : BoundedString 4 :=
  { length := if Erc20Meta.canPublish tokenName tokenSymbol then 2 else 0
    values := #v[0x50, 0x46, 0, 0] }

@[pf_entry]
def decimals (_s : State) : UInt8 :=
  18

@[pf_entry]
def totalSupply (s : State) : UInt256 :=
  s.supply

/-- Constructor immutable owner (see `init`). -/
@[pf_entry]
def ownerOf (_s : State) : Address :=
  Immutable.address

/-- Owner-only mint: credits `to` and increases `supply`. Non-owner → `Unauthorized(caller)`;
zero recipient → `ZeroAddress()`. Success emits canonical `Transfer(address(0), to, value)`. -/
@[pf_entry]
def mint (s : State) (to : Address) (value : UInt256) : Except Error (State × UInt64) :=
  Effect.ensureCode (Address.eqImmutable Context.caller) (hold s)
      (Revert.unauthorized Context.caller) fun _ =>
  Effect.ensureCode (!Address.isZero to) (hold s) Revert.zeroAddress fun _ =>
  if Fungible.Balances.canCredit balances to value then
    .ok ({ dummy := Fungible.Balances.credit balances to value,
           supply := UInt256.add s.supply value },
      Fungible.Log.transfer Address.zero to value)
  else
    .error .overflow

@[pf_entry]
def balanceOf (_s : State) (who : Address) : UInt256 :=
  Fungible.Balances.balanceOf balances who

/-- Standard ERC-20 name `allowance` (not `allowanceOf`). -/
@[pf_entry]
def allowance (_s : State) (owner spender : Address) : UInt256 :=
  Fungible.Allowances.allowanceOf allowances owner spender

/-- IERC2612 `nonces(address)`, not Token's `nonceOf`. -/
@[pf_entry]
def nonces (_s : State) (who : Address) : UInt256 :=
  Nonces.current nonceStore who

@[pf_entry]
def DOMAIN_SEPARATOR (_s : State) : Bytes32 :=
  Permit.domainSeparator

/-- Issuer EIP-2612 permit over the closed Token/1 domain. Sequential `Effect` is not needed;
the `0 ≠ 1` branch is the extractable closed-call carrier. -/
@[pf_entry]
def permit (s : State) (owner spender : Address) (value deadline : UInt256)
    (v : UInt8) (r signature : Bytes32) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok (hold s, Permit.authorize owner spender value deadline v r signature)
  else
    .error .overflow

@[pf_entry]
def approve (s : State) (spender : Address) (amount : UInt256) :
    Except Error (State × Bool) :=
  Effect.ensure (!Address.isZero spender) (hold s) Revert.zeroAddress fun _ =>
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := Fungible.Allowances.approve allowances Context.caller spender amount,
           supply := s.supply },
      Effect.thenTrue (Fungible.Log.approval Context.caller spender amount))
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
      Effect.thenTrue (Fungible.Log.transfer Context.caller destination amount))
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
      Effect.thenTrue (Fungible.Log.transfer owner destination amount))
  else
    .error .overflow

end Examples.Evm.Erc20Meta
