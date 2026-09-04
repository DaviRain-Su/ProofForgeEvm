import ProofForge.Evm.Sdk

/-!
S3 source consumer of typed external CALL. Constructor name + fields are the ABI contract;
the target may be a parameter or a stored `Address`. A `BoundedBytes` field is the one
`bytes` argument a call may carry. No raw calldata, selector string, return-buffer length,
or opcode is accepted. Reentrancy is application-visible.
-/

namespace Examples.Evm.EvmOpenCall
open ProofForge.Evm.Sdk
open ProofForge.Core.Value (BoundedBytes)

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
  | isOn
  | ownerOf
  | getTriple
  | getQuad
  | balanceOf (who : Address)
  | supportsInterface (interfaceId : Bytes4)
  | sink (tag : UInt256) (data : BoundedBytes 8)
  | calldataHash (data : BoundedBytes 8)
  deriving Inhabited

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

/-- Exact-three-word STATICCALL. The Anvil mock can shrink or grow its frame to prove the
size gate. -/
@[pf_entry]
def readTriple (_s : State) (target : Address) : UInt256 :=
  OpenCall.staticWords3 target Remote.getTriple

/-- Exact-four-word STATICCALL, the `CallResult.maxResultWords` ceiling. -/
@[pf_entry]
def readQuad (_s : State) (target : Address) : UInt256 :=
  OpenCall.staticWords4 target Remote.getQuad

/-- Strict-bool STATICCALL. A callee word other than `0` or `1` fails closed. -/
@[pf_entry]
def readOn (_s : State) (target : Address) : Bool :=
  OpenCall.staticBool target Remote.isOn

/-- Canonical-address STATICCALL. A word with nonzero high 12 bytes fails closed. -/
@[pf_entry]
def readOwner (_s : State) (target : Address) : Address :=
  OpenCall.staticAddress target Remote.ownerOf

/-- ERC-20 `balanceOf(address)` read; `anvil_compose.sh` points it at a `pf`-compiled
`Erc20Meta`. -/
@[pf_entry]
def readBalance (_s : State) (token who : Address) : UInt256 :=
  OpenCall.staticWord token (Remote.balanceOf who)

/-- ERC-165 `supportsInterface(bytes4)` read; `anvil_compose.sh` points it at a `pf`-compiled
`Badge`. -/
@[pf_entry]
def readSupports (_s : State) (target : Address) (interfaceId : Bytes4) : Bool :=
  OpenCall.staticBool target (Remote.supportsInterface interfaceId)

/-- Bounded `bytes` argument through CALL: `sink(uint256,bytes)`. The Anvil mock records the
decoded length, the payload keccak, and the keccak of its whole calldata, which the gate
compares with `cast calldata`'s canonical encoding. -/
@[pf_entry]
def sinkBytes (_s : State) (target : Address) (tag : UInt256) (data : BoundedBytes 8) :
    Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := 0, flag := _s.flag, target := _s.target },
      OpenCall.callSuccess target (Remote.sink tag data))
  else
    .error .overflow

/-- Bounded `bytes` argument through STATICCALL: `calldataHash(bytes)` returns the keccak of
the calldata the callee received, one word the gate compares with `cast calldata`. -/
@[pf_entry]
def hashBytes (_s : State) (target : Address) (data : BoundedBytes 8) : UInt256 :=
  OpenCall.staticWord target (Remote.calldataHash data)

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
