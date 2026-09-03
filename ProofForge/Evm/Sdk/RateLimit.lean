import ProofForge.Attr
import ProofForge.Core.Math
import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.RateLimit

/-!
# EVM SDK bounded fixed-window rate limit

Reusable per-key fixed-window counter policy: shared `capacity` and `window` configuration plus
explicit `lastUsed` and `lastTimepoint` scalars (typically one hashed-map entry each).
`lastTimepoint` is the active window's start: it is preserved by consumption within that window
and replaced only when an elapsed window is consumed. Zero-quantity consumption is always
admissible and does not modify entry state. `window = 0` is treated as one second.

This is a bounded profile, not a drop-in OpenZeppelin `RateLimiter` clone: there is no linear
token-bucket refill, sliding-window checkpoint trace, or settings-mutation API.
-/

/-- Shared limiter configuration. -/
structure Config where
  capacity : UInt64
  window : UInt64
  deriving Repr, DecidableEq, Inhabited

/-- Per-key counter state reconstructed from two explicit stored scalars. -/
structure Entry where
  lastUsed : UInt64
  lastTimepoint : UInt64
  deriving Repr, DecidableEq, Inhabited

namespace FixedWindow

/-- Canonical empty entry. -/
@[pf_inline] def empty : Entry := ⟨0, 0⟩

/-- Effective window length; zero window is treated as one second. -/
@[pf_inline] def effectiveWindow (window : UInt64) : UInt64 :=
  if window == 0 then 1 else window

/-- True when the entry's window has elapsed at `now`. -/
@[pf_inline] def windowElapsed (config : Config) (entry : Entry) (now : UInt64) : Bool :=
  now > entry.lastTimepoint &&
    now - entry.lastTimepoint ≥ effectiveWindow config.window

/-- Currently used quantity within the active window. -/
@[pf_inline] def used (config : Config) (entry : Entry) (now : UInt64) : UInt64 :=
  if windowElapsed config entry now then 0 else entry.lastUsed

/-- Currently available quantity within the active window. -/
@[pf_inline] def available (config : Config) (entry : Entry) (now : UInt64) : UInt64 :=
  let usedNow := used config entry now
  if usedNow ≥ config.capacity then 0 else config.capacity - usedNow

/-- Whether `quantity` may be consumed at `now`. Zero quantity is always admissible. -/
@[pf_inline] def canConsume (config : Config) (entry : Entry) (now : UInt64)
    (quantity : UInt64) : Bool :=
  quantity == 0 || quantity ≤ available config entry now

/-- Entry state after a successful consumption. Zero quantity returns `entry` unchanged. -/
@[pf_inline] def consume (config : Config) (entry : Entry) (now : UInt64)
    (quantity : UInt64) : Entry :=
  if quantity == 0 then
    entry
  else if windowElapsed config entry now then
    { lastUsed := quantity, lastTimepoint := now }
  else
    { lastUsed := entry.lastUsed + quantity, lastTimepoint := entry.lastTimepoint }

end FixedWindow

end ProofForge.Evm.Sdk.RateLimit
