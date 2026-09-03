import ProofForge.Core.Value
import ProofForge.Core.Collections
import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.Eip712Domain

/-!
# EVM SDK EIP-5267-style static domain fields

Compile-time `BoundedString` name/version plus runtime `chainId` and `verifyingContract` for
EIP-712 domain introspection. There is no salt, extensions array, or per-deployment domain
mutation. Consumers must validate `canPublish` on configured name/version before advertising
domain field views.

Fail-closed gates:
- Invalid UTF-8 or empty name/version should yield `empty` strings and zero `fields`.
- Salt is always zero; extensions are outside this bounded profile.

Extract note: `pf_entry` string views must return explicit bounded-string constructors (`if
canPublish then name else empty`). Do not route returns through parameterized SDK helpers; use
the predicates here and assemble the bounded frame at the consumer boundary.
-/

open ProofForge.Core.Value

/-- Default compile-time capacity for EIP-712 domain `name`. -/
def defaultNameCapacity : Nat := 32

/-- Default compile-time capacity for EIP-712 domain `version`. -/
def defaultVersionCapacity : Nat := 8

abbrev Name := BoundedString 32
abbrev Version := BoundedString 8

/-- IERC5267 field bitmask: name | version | chainId | verifyingContract. Salt/extensions omitted. -/
def fieldsMask : UInt8 := 0x0f

/-- Empty bounded domain name (fail-closed response). -/
@[pf_inline] def emptyName : Name :=
  { length := 0
    values := #v[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0] }

/-- Empty bounded domain version (fail-closed response). -/
@[pf_inline] def emptyVersion : Version :=
  { length := 0, values := #v[0, 0, 0, 0, 0, 0, 0, 0] }

/-- True when the configured domain name is non-empty valid UTF-8 within capacity. -/
@[pf_inline] def wellFormedName (name : Name) : Bool :=
  name.length > 0 && BoundedString.wellFormed name

/-- True when the configured domain version is non-empty valid UTF-8 within capacity. -/
@[pf_inline] def wellFormedVersion (version : Version) : Bool :=
  version.length > 0 && BoundedString.wellFormed version

/-- Domain field views may be advertised only with a well-formed static name and version. -/
@[pf_inline] def canPublish (name : Name) (version : Version) : Bool :=
  wellFormedName name && wellFormedVersion version

/-- Publish `fieldsMask` when the domain gate passes; otherwise fail closed to zero. -/
@[pf_inline] def selectFields (name : Name) (version : Version) : UInt8 :=
  if canPublish name version then fieldsMask else 0

/-- Publish `name` when the domain gate passes; otherwise fail closed to `emptyName`. -/
@[pf_inline] def selectName (name : Name) (version : Version) : Name :=
  { length := if canPublish name version then name.length else 0, values := name.values }

/-- Publish `version` when the domain gate passes; otherwise fail closed to `emptyVersion`. -/
@[pf_inline] def selectVersion (name : Name) (version : Version) : Version :=
  { length := if canPublish name version then version.length else 0, values := version.values }

/-- Runtime `chainid()` as EIP-712 `uint256`. -/
@[pf_inline] def chainId : UInt256 :=
  ⟨Runtime.evmChainId, 0, 0, 0⟩

/-- Current contract as EIP-712 `verifyingContract`. -/
@[pf_inline] def verifyingContract : Address :=
  Context.self

/-- Static profile uses zero salt; salt is not included in `fieldsMask`. -/
@[pf_inline] def zeroSalt : Bytes32 :=
  ⟨0, 0, 0, 0⟩

end ProofForge.Evm.Sdk.Eip712Domain
