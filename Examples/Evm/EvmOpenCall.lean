import ProofForge.Evm.Sdk

/-!
S3 source consumer of typed external CALL. Constructor name + fields are the ABI contract;
the target may be a parameter or a stored `Address`. No raw calldata, selector string,
return-buffer length, or opcode is accepted. Reentrancy is application-visible.
-/

namespace Examples.Evm.EvmOpenCall
open ProofForge.Evm.Sdk

structure State where
  dummy : UInt64
  flag : UInt64
  target : Address
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

/-- Approved remote ABI for this example. Each constructor is one function. -/
inductive Remote where
  | ping
  | transfer (to : Address) (amount : UInt256)
  | echo (n : UInt256)
  | getPair
  | deposit
  deriving Repr, DecidableEq, Inhabited

@[pf_entry]
def init (_seed : UInt64) : State :=
  { dummy := 0, flag := 0, target := ⟨0, 0, 0⟩ }

@[pf_entry]
def flagOf (s : State) : UInt64 :=
  s.flag

@[pf_entry]
def targetOf (s : State) : Address :=
  s.target

@[pf_entry]
def setTarget (s : State) (target : Address) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ s with dummy := 0, target }, 1)
  else
    .error .overflow

/-- Parameter-supplied target, contract-success policy. -/
@[pf_entry]
def pingTarget (_s : State) (target : Address) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := 0, flag := _s.flag, target := _s.target },
      OpenCall.callSuccess target Remote.ping)
  else
    .error .overflow

/-- State-supplied target. -/
@[pf_entry]
def pingStored (s : State) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ s with dummy := 0 }, OpenCall.callSuccess s.target Remote.ping)
  else
    .error .overflow

/-- ERC-20-shaped `transfer(address,uint256)` via typed OpenCall (compatibility policy). -/
@[pf_entry]
def openTransfer (_s : State) (token dest : Address) (amt : UInt256) :
    Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := 0, flag := _s.flag, target := _s.target },
      OpenCall.call token (Remote.transfer dest amt))
  else
    .error .overflow

/-- Exact-one-word STATICCALL. `n = 0` is reserved by the Anvil mock for a malformed
two-word return that must fail closed. -/
@[pf_entry]
def readEcho (_s : State) (target : Address) (n : UInt256) : UInt256 :=
  OpenCall.staticWord target (Remote.echo n)

/-- Exact-two-word STATICCALL. The source carrier is the first word; both words are gated. -/
@[pf_entry]
def readPair (_s : State) (target : Address) : UInt256 :=
  OpenCall.staticWords2 target Remote.getPair

/-- Payable CALL value. `Ether.accept` makes the entry payable; OpenCall forwards the value. -/
@[pf_entry]
def payTarget (_s : State) (target : Address) (amt : UInt256) :
    Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := Ether.accept amt, flag := _s.flag, target := _s.target },
      OpenCall.callValue target amt Remote.deposit)
  else
    .error .overflow

/-- Same-transition storage write + CALL. Extract emits the CALL before the `flag` store,
so a callee that staticcalls `flagOf()` observes the pre-state. -/
@[pf_entry]
def markThenPing (s : State) (target : Address) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ s with dummy := 0, flag := 1 }, OpenCall.callSuccess target Remote.ping)
  else
    .error .overflow

end Examples.Evm.EvmOpenCall
