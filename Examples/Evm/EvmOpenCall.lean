import ProofForge.Evm.Sdk

/-!
S3 source consumer of typed external CALL. Constructor name + fields are the ABI contract;
the target may be a parameter or a stored `Address`. A `BoundedBytes` field is the one
`bytes` argument a call may carry; a `BoundedString` field is the one `string` argument;
a `BoundedVec` field is one dynamic-array argument. One packed tail per plan. No raw
calldata, selector string, return-buffer length, or opcode is accepted. Reentrancy
is application-visible.
-/

namespace Examples.Evm.EvmOpenCall
open ProofForge.Evm.Sdk
open ProofForge.Core.Value (BoundedBytes BoundedString BoundedVec)

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
  | label (text : BoundedString 8)
  | stringHash (text : BoundedString 8)
  | onERC721Received (operator origin : Address) (tokenId : UInt256) (data : BoundedBytes 8)
  | onERC1155BatchReceived (operator origin : Address)
      (ids values : BoundedVec UInt256 4) (data : BoundedBytes 8)
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

/-- Source `{ data with length := 3 }` keeps the original slots and publishes ABI length 3.
Inactive source bytes must not appear in the packed tail. -/
@[pf_entry]
def sinkTrunc (_s : State) (target : Address) (tag : UInt256) (data : BoundedBytes 8) :
    Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := 0, flag := _s.flag, target := _s.target },
      OpenCall.callSuccess target (Remote.sink tag { data with length := 3 }))
  else
    .error .overflow

/-- Parameter `{ data with length := keep }`. `keep` is the published ABI length.
Emit reverts when `keep` is greater than capacity. -/
@[pf_entry]
def sinkKeep (_s : State) (target : Address) (tag : UInt256) (data : BoundedBytes 8)
    (keep : UInt32) :
    Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := 0, flag := _s.flag, target := _s.target },
      OpenCall.callSuccess target (Remote.sink tag { data with length := keep }))
  else
    .error .overflow

/-- `UInt32.ofNat` of a wider `UInt64`. Extract masks to 32 bits so Lean wrap and
the published ABI length match. -/
@[pf_entry]
def sinkWrap (_s : State) (target : Address) (tag : UInt256) (data : BoundedBytes 8)
    (wide : UInt64) :
    Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := 0, flag := _s.flag, target := _s.target },
      OpenCall.callSuccess target
        (Remote.sink tag { data with length := UInt32.ofNat wide.toNat }))
  else
    .error .overflow

/-- Bounded `string` argument through CALL: `label(string)`. ABI `string` is not `bytes`.
The Anvil mock records decoded length, payload keccak, and keccak of whole calldata. -/
@[pf_entry]
def sinkString (_s : State) (target : Address) (text : BoundedString 8) :
    Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := 0, flag := _s.flag, target := _s.target },
      OpenCall.callSuccess target (Remote.label text))
  else
    .error .overflow

/-- Bounded `string` argument through STATICCALL: `stringHash(string)` returns keccak of the
calldata the callee received. -/
@[pf_entry]
def hashString (_s : State) (target : Address) (text : BoundedString 8) : UInt256 :=
  OpenCall.staticWord target (Remote.stringHash text)

/-- Source-built `BoundedString` from scalar bytes. The emit path must revert before CALL when
the bytes are not UTF-8; forwarding an ABI-decoded `string` already passed the entry scanner. -/
@[pf_entry]
def sinkBadUtf8 (_s : State) (target : Address) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := 0, flag := _s.flag, target := _s.target },
      OpenCall.callSuccess target (Remote.label {
        length := 2,
        values := #v[0xc0, 0x80, 0, 0, 0, 0, 0, 0]
      }))
  else
    .error .overflow

/-- A STATICCALL read as a guard: `ping()` runs only when the callee's `isOn()` answers true.
The read is materialized before the branch, so a false word never reaches the CALL. -/
@[pf_entry]
def pingIfOn (s : State) (target : Address) : Except Error (State × Bool) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ s with dummy := 0 },
      Effect.thenTrue
        (if OpenCall.staticBool target Remote.isOn then OpenCall.callSuccess target Remote.ping
         else 0))
  else
    .error .overflow

/-- A `UInt256` read compared in a view: whether `balanceOf(who)` covers `amt`. -/
@[pf_entry]
def covers (_s : State) (token who : Address) (amt : UInt256) : Bool :=
  UInt256.ge (OpenCall.staticWord token (Remote.balanceOf who)) amt

/-- A read as the argument of another read: `echo(balanceOf(who))`. -/
@[pf_entry]
def echoBalance (_s : State) (token who : Address) : UInt256 :=
  OpenCall.staticWord token (Remote.echo (OpenCall.staticWord token (Remote.balanceOf who)))

/-- An `Address` read compared with a parameter: whether `ownerOf()` names `who`. -/
@[pf_entry]
def ownedBy (_s : State) (target who : Address) : Bool :=
  Address.eq (OpenCall.staticAddress target Remote.ownerOf) who

/-- A `Bool` read selecting a value: the echoed word when `isOn()` is true, else zero. -/
@[pf_entry]
def echoIfOn (_s : State) (target : Address) (n : UInt256) : UInt256 :=
  if OpenCall.staticBool target Remote.isOn then OpenCall.staticWord target (Remote.echo n)
  else UInt256.zero

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

/-- Receiver hook through CALL with the magic policy: the callee must answer
`onERC721Received(address,address,uint256,bytes)` with exactly one word equal to that selector,
left-aligned. Any other length or word reverts the whole transaction. -/
@[pf_entry]
def notifyReceiver (s : State) (target operator origin : Address) (tokenId : UInt256)
    (data : BoundedBytes 8) : Except Error (State × Bool) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ s with dummy := 0 },
      Effect.thenTrue
        (OpenCall.callMagic target (Remote.onERC721Received operator origin tokenId data)))
  else
    .error .overflow

/-- Batch receiver hook: two `uint256[]` arguments and one `bytes` tail through the same
magic policy. The arrays are bounded to four slots. -/
@[pf_entry]
def notifyBatchReceiver (s : State) (target operator origin : Address)
    (ids values : BoundedVec UInt256 4) (data : BoundedBytes 8) :
    Except Error (State × Bool) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ s with dummy := 0 },
      Effect.thenTrue
        (OpenCall.callMagic target
          (Remote.onERC1155BatchReceived operator origin ids values data)))
  else
    .error .overflow

end Examples.Evm.EvmOpenCall
