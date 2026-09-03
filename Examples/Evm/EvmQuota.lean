import ProofForge

/-!
W3 quota consumer: bounded per-address nonces plus a fixed-window rate limiter.

The SDK owns pure nonce and rate-limit decisions; this contract owns three disjoint hashed-map
namespaces (`nonces`, `lastUsed`, `lastTimepoint`), authorization, and closed failure terminals.
Successful `act` checks the caller nonce, consumes quota, advances the nonce, and increments a
scalar action counter. A stale nonce reverts as `Insufficient(current, provided)`; rate exhaustion
uses the typed `rateLimitExceeded()` error.
-/

namespace Examples.Evm.EvmQuota
open ProofForge.Evm.Sdk

structure State where
  capacity : UInt64
  window : UInt64
  totalActions : UInt64
  deriving Repr, DecidableEq, Inhabited

structure QuotaMaps where
  nonces : Storage.AddressMap256
  lastUsed : Storage.AddressMap
  lastTimepoint : Storage.AddressMap

attribute [pf_inline] QuotaMaps.nonces QuotaMaps.lastUsed QuotaMaps.lastTimepoint

@[pf_inline] def maps : QuotaMaps :=
  { nonces := Storage.Layout.root.addressMap256 |>.handle
    lastUsed := Storage.Layout.root.addressMap256 |>.next |>.addressMap |>.handle
    lastTimepoint := Storage.Layout.root.addressMap256 |>.next |>.addressMap |>.next
      |>.addressMap |>.handle }

inductive Error where
  | rateLimitExceeded
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_inline] private def config (s : State) : RateLimit.Config :=
  { capacity := s.capacity, window := s.window }

@[pf_inline] private def entryOf (who : Address) : RateLimit.Entry :=
  { lastUsed := maps.lastUsed.get who
    lastTimepoint := maps.lastTimepoint.get who }

@[pf_entry]
def init (capacity window : UInt64) (_owner : Address) : State :=
  { capacity := capacity, window := window, totalActions := 0 }

@[pf_entry]
def noncesOf (_s : State) (who : Address) : UInt256 :=
  Nonces.current maps.nonces who

@[pf_entry]
def capacityOf (s : State) : UInt64 :=
  s.capacity

@[pf_entry]
def windowOf (s : State) : UInt64 :=
  s.window

@[pf_entry]
def lastUsedOf (_s : State) (who : Address) : UInt64 :=
  maps.lastUsed.get who

@[pf_entry]
def lastTimepointOf (_s : State) (who : Address) : UInt64 :=
  maps.lastTimepoint.get who

@[pf_entry]
def totalActionsOf (s : State) : UInt64 :=
  s.totalActions

@[pf_entry]
def act (s : State) (nonce : UInt256) (amount : UInt64) : Except Error (State × UInt64) :=
  if !Nonces.useChecked maps.nonces Context.caller nonce then
    .ok (s, Revert.insufficient (Nonces.current maps.nonces Context.caller) nonce)
  else if !RateLimit.FixedWindow.canConsume (config s) (entryOf Context.caller) Context.timestamp amount then
    .error .rateLimitExceeded
  else
    let bucket := entryOf Context.caller
    let now := Context.timestamp
    let elapsed :=
      RateLimit.FixedWindow.windowElapsed (config s) bucket now
    let nextUsed :=
      if amount == 0 then bucket.lastUsed
      else if elapsed then amount else bucket.lastUsed + amount
    let nextTimepoint :=
      if amount == 0 then bucket.lastTimepoint
      else if elapsed then now else bucket.lastTimepoint
    .ok ({ s with totalActions := s.totalActions + 1 },
      maps.nonces.put Context.caller (Nonces.useNext maps.nonces Context.caller)
        ||| maps.lastUsed.put Context.caller nextUsed
        ||| maps.lastTimepoint.put Context.caller nextTimepoint)

end Examples.Evm.EvmQuota
