import ProofForge.Evm.Sdk

/-!
W3 quota consumer: bounded per-address nonces plus a refilling-bucket rate limiter.

The SDK owns pure nonce and rate-limit decisions; this contract owns three disjoint hashed-map
namespaces (`nonces`, `lastUsed`, `lastTimepoint`), authorization, and typed failure terminals.
Successful `act` checks the caller nonce, consumes quota, advances the nonce, and increments a
scalar action counter.
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
  | invalidNonce (current : UInt256) (expected : UInt256)
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
def availableOf (s : State) (who : Address) : UInt64 :=
  let lastUsed := maps.lastUsed.get who
  let lastTime := maps.lastTimepoint.get who
  let usedNow :=
    if Context.timestamp > lastTime &&
        Context.timestamp - lastTime ≥ RateLimit.FixedWindow.effectiveWindow s.window then
      (0 : UInt64)
    else
      lastUsed
  if usedNow ≥ s.capacity then 0 else s.capacity - usedNow

@[pf_entry]
def totalActionsOf (s : State) : UInt64 :=
  s.totalActions

@[pf_entry]
def act (s : State) (nonce : UInt256) (amount : UInt64) : Except Error (State × UInt64) :=
  if Nonces.useChecked maps.nonces Context.caller nonce then
    let bucket := entryOf Context.caller
    if RateLimit.FixedWindow.canConsume (config s) bucket Context.timestamp amount then
      let _ := maps.nonces.put Context.caller (Nonces.useNext maps.nonces Context.caller)
      let nextBucket :=
        RateLimit.FixedWindow.consume (config s) bucket Context.timestamp amount
      let _ := maps.lastUsed.put Context.caller nextBucket.lastUsed
      let _ := maps.lastTimepoint.put Context.caller nextBucket.lastTimepoint
      .ok ({ s with totalActions := s.totalActions + 1 }, s.totalActions + 1)
    else
      .error .rateLimitExceeded
  else
    .error (.invalidNonce nonce (Nonces.current maps.nonces Context.caller))

end Examples.Evm.EvmQuota
