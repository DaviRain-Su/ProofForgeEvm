import ProofForge.Evm.Sdk
import ProofForge.Core.Value

/-!
EIP-5267-style static domain field consumer. Compile-time name/version match the closed Token/1
permit profile (`Permit.domainSeparator`). There is no salt, extensions array, or dynamic domain
mutation. Invalid static configuration would fail closed to zero fields and empty strings at
each view boundary.
-/

namespace Examples.Evm.DomainLink
open ProofForge.Evm.Sdk
open ProofForge.Core.Value

structure State where
  dummy : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

/-- UTF-8 bytes for `Token` padded to the domain name capacity. -/
@[pf_inline] private def nameValues : Vector UInt8 32 :=
  #v[0x54, 0x6f, 0x6b, 0x65, 0x6e, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0]

/-- Static domain name: `Token` (5 UTF-8 bytes). -/
@[pf_inline] def domainName : Eip712Domain.Name :=
  { length := 5, values := nameValues }

/-- Static domain version: `1` (1 UTF-8 byte). -/
@[pf_inline] def domainVersion : Eip712Domain.Version :=
  { length := 1, values := #v[0x31, 0, 0, 0, 0, 0, 0, 0] }

@[pf_entry]
def init (_owner : Address) : State :=
  { dummy := 0 }

/-- Satisfies the extractor's mutating-method requirement; domain state is static. -/
@[pf_entry]
def touch (_s : State) (v : UInt64) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := v }, v)
  else
    .error .overflow

/-- IERC5267 `fields` byte: name | version | chainId | verifyingContract. Misconfigured static
domains fail closed to zero via `Eip712Domain.canPublish`. -/
@[pf_entry]
def eip712DomainFields (_s : State) : UInt8 :=
  if Eip712Domain.canPublish domainName domainVersion then 15 else 0

/-- Bounded static domain `name`. Fail closed to empty when `canPublish` is false. -/
@[pf_entry]
def eip712DomainName (_s : State) : BoundedString 32 :=
  { length := if Eip712Domain.canPublish domainName domainVersion then 5 else 0
    values := #v[0x54, 0x6f, 0x6b, 0x65, 0x6e, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0] }

/-- Bounded static domain `version`. Fail closed to empty when `canPublish` is false. -/
@[pf_entry]
def eip712DomainVersion (_s : State) : BoundedString 8 :=
  { length := if Eip712Domain.canPublish domainName domainVersion then 1 else 0
    values := #v[0x31, 0, 0, 0, 0, 0, 0, 0] }

@[pf_entry]
def eip712DomainChainId (_s : State) : UInt256 :=
  Eip712Domain.chainId

@[pf_entry]
def eip712DomainVerifyingContract (_s : State) : Address :=
  Eip712Domain.verifyingContract

@[pf_entry]
def eip712DomainSalt (_s : State) : Bytes32 :=
  Eip712Domain.zeroSalt

/-- Closed Token/1 domain separator shared with the permit profile. -/
@[pf_entry]
def DOMAIN_SEPARATOR (_s : State) : Bytes32 :=
  Permit.domainSeparator

end Examples.Evm.DomainLink
