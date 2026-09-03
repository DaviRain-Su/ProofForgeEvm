import ProofForge.Core.Value
import ProofForge.Core.Collections

namespace ProofForge.Evm.Sdk.Erc20Meta

/-!
# EVM SDK ERC-20 metadata profile

Compile-time bounded UTF-8 `name` / `symbol` and a static `decimals` constant for ERC-20-shaped
ABI views. There is no on-chain metadata mutation, template interpolation, or unbounded string
allocation. Consumers must validate `canPublish` on configured name/symbol before advertising
metadata methods.

Fail-closed gates:
- Invalid UTF-8 or empty name/symbol should yield zero-length strings at view boundaries.
- `decimals` is a compile-time profile constant (`defaultDecimals`).

Extract note: `pf_entry` string views must return explicit bounded-string constructors (`if
canPublish then name else empty`). Do not route returns through parameterized SDK helpers; use
the predicates here and assemble the bounded frame at the consumer boundary.
-/

open ProofForge.Core.Value

/-- Default compile-time capacity for ERC-20 `name`. -/
def defaultNameCapacity : Nat := 32

/-- Default compile-time capacity for ERC-20 `symbol`. -/
def defaultSymbolCapacity : Nat := 8

/-- Common compile-time decimals for fungible profiles. -/
def defaultDecimals : UInt8 := 18

abbrev Name := BoundedString 32
abbrev Symbol := BoundedString 8

/-- Empty bounded token name (fail-closed response). -/
@[pf_inline] def emptyName : Name :=
  { length := 0
    values := #v[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0] }

/-- Empty bounded token symbol (fail-closed response). -/
@[pf_inline] def emptySymbol : Symbol :=
  { length := 0, values := #v[0, 0, 0, 0, 0, 0, 0, 0] }

/-- True when the configured name is non-empty valid UTF-8 within capacity. -/
@[pf_inline] def wellFormedName {cap : Nat} (name : BoundedString cap) : Bool :=
  name.length > 0 && BoundedString.wellFormed name

/-- True when the configured symbol is non-empty valid UTF-8 within capacity. -/
@[pf_inline] def wellFormedSymbol {cap : Nat} (symbol : BoundedString cap) : Bool :=
  symbol.length > 0 && BoundedString.wellFormed symbol

/-- Metadata views may be advertised only with a well-formed static name and symbol. -/
@[pf_inline] def canPublish {n m : Nat} (name : BoundedString n) (symbol : BoundedString m) : Bool :=
  wellFormedName name && wellFormedSymbol symbol

end ProofForge.Evm.Sdk.Erc20Meta
