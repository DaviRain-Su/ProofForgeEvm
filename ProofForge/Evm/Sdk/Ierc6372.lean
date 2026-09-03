import ProofForge.Core.Value
import ProofForge.Core.Collections
import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.Ierc6372

/-!
# EVM SDK IERC6372 clock / `CLOCK_MODE()` helpers

Bounded static `CLOCK_MODE()` strings plus runtime `clock()` from `Context.blockNumber` or
`Context.timestamp`. There is no votes checkpoint model or dynamic mode mutation. Consumers pick
one compile-time `ClockKind` and validate `canPublish` before advertising the pair of views.

Fail-closed gates:
- Unknown or unpublished kinds yield zero `clock()` and empty `CLOCK_MODE()`.

Extract note: `pf_entry` clock views must return explicit bounded-string constructors and inline
`Context.blockNumber` / `Context.timestamp` at the consumer boundary.
-/

open ProofForge.Core.Value

/-- Static compile-time capacity for IERC6372 `CLOCK_MODE()`. -/
def defaultModeCapacity : Nat := 32

abbrev ModeString := BoundedString 32

/-- Supported bounded clock modes (no votes / arbitrary strings). -/
inductive ClockKind where
  | blockNumber
  | timestamp
  deriving Repr, DecidableEq, Inhabited, BEq

/-- Empty bounded mode (fail-closed response). -/
@[pf_inline] def emptyMode : ModeString :=
  { length := 0
    values := #v[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0] }

/-- UTF-8 bytes for `mode=blocknumber&from=default` (29 bytes). -/
private def blockNumberModeValues : Vector UInt8 32 :=
  #v[0x6d, 0x6f, 0x64, 0x65, 0x3d, 0x62, 0x6c, 0x6f, 0x63, 0x6b, 0x6e, 0x75, 0x6d, 0x62, 0x65,
    0x72, 0x26, 0x66, 0x72, 0x6f, 0x6d, 0x3d, 0x64, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0, 0, 0]

/-- UTF-8 bytes for `mode=timestamp&from=default` (28 bytes). -/
private def timestampModeValues : Vector UInt8 32 :=
  #v[0x6d, 0x6f, 0x64, 0x65, 0x3d, 0x74, 0x69, 0x6d, 0x65, 0x73, 0x74, 0x61, 0x6d, 0x70, 0x26,
    0x66, 0x72, 0x6f, 0x6d, 0x3d, 0x64, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0, 0, 0, 0, 0]

/-- Canonical bounded `CLOCK_MODE()` for block-number clocks. -/
@[pf_inline] def blockNumberMode : ModeString :=
  { length := 29, values := blockNumberModeValues }

/-- Canonical bounded `CLOCK_MODE()` for timestamp clocks. -/
@[pf_inline] def timestampMode : ModeString :=
  { length := 28, values := timestampModeValues }

/-- True when the static mode string is well formed within capacity. -/
@[pf_inline] def wellFormedMode (mode : ModeString) : Bool :=
  mode.length > 0 && BoundedString.wellFormed mode

/-- Clock views may be advertised for the shipped static kinds only. -/
@[pf_inline] def canPublish (_kind : ClockKind) : Bool :=
  true

/-- Publish the bounded `CLOCK_MODE()` string for `kind`; fail closed to empty. -/
@[pf_inline] def selectMode (kind : ClockKind) : ModeString :=
  if canPublish kind then
    match kind with
    | .blockNumber => blockNumberMode
    | .timestamp => timestampMode
  else
    emptyMode

/-- Runtime `clock()` from `Context.blockNumber` or `Context.timestamp`. Returns zero when
unpublished (reserved for future kind gating). -/
@[pf_inline] def clock (kind : ClockKind) : UInt64 :=
  if canPublish kind then
    match kind with
    | .blockNumber => Context.blockNumber
    | .timestamp => Context.timestamp
  else
    0

end ProofForge.Evm.Sdk.Ierc6372
