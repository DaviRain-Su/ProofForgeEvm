import ProofForge.Evm.Sdk

namespace Examples.Evm.Auth3009Link
open ProofForge.Evm.Sdk

structure State where
  dummy : UInt64
  supply : UInt256
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_inline] def balances : Fungible.Balances :=
  Storage.Layout.root.addressMap256.handle

@[reducible, pf_inline] private def hold (s : State) : State :=
  { dummy := s.dummy, supply := s.supply }

@[pf_entry]
def init (_owner : Address) : State :=
  { dummy := 0, supply := UInt256.zero }

@[pf_entry]
def name (_s : State) : Bytes32 :=
  ⟨0, 0, 0, 0x6e656b6f54000000⟩

@[pf_entry]
def symbol (_s : State) : Bytes32 :=
  ⟨0, 0, 0, 0x4650000000000000⟩

@[pf_entry]
def decimals (_s : State) : UInt8 :=
  18

@[pf_entry]
def totalSupply (s : State) : UInt256 :=
  s.supply

@[pf_entry]
def DOMAIN_SEPARATOR (_s : State) : Bytes32 :=
  Erc3009.domainSeparator

@[pf_entry]
def balanceOf (_s : State) (who : Address) : UInt256 :=
  Fungible.Balances.balanceOf balances who

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
def transferWithAuthorization (s : State) (owner to : Address) (value validAfter validBefore : UInt256)
    (nonce : Bytes32) (v : UInt8) (r signature : Bytes32) : Except Error (State × UInt64) :=
  Effect.ensureCode (!Address.isZero to) (hold s) Revert.zeroAddress fun _ =>
  if (0 : UInt64) ≠ 1 then
    .ok (hold s,
      Erc3009.authorize owner to value validAfter validBefore nonce v r signature)
  else
    .error .overflow

@[pf_entry]
def receiveWithAuthorization (s : State) (owner to : Address) (value validAfter validBefore : UInt256)
    (nonce : Bytes32) (v : UInt8) (r signature : Bytes32) : Except Error (State × UInt64) :=
  Effect.ensureCode (!Address.isZero to) (hold s) Revert.zeroAddress fun _ =>
  if (0 : UInt64) ≠ 1 then
    .ok (hold s,
      Erc3009.receive owner to value validAfter validBefore nonce v r signature)
  else
    .error .overflow

@[pf_entry]
def cancelAuthorization (s : State) (authorizer : Address) (nonce : Bytes32)
    (v : UInt8) (r signature : Bytes32) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok (hold s, Erc3009.cancel authorizer nonce v r signature)
  else
    .error .overflow

end Examples.Evm.Auth3009Link
