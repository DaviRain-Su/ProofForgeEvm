import ProofForge.Attr
import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.Nonces

/-!
# EVM SDK bounded per-address nonces

Reusable nonce policy over one explicit `Storage.AddressMap256` namespace. Each account tracks
its next unused nonce as a wide map entry; uninitialized keys read as zero and increment by one
on consumption. This is a bounded hashed-map profile, not OpenZeppelin's unbounded
`mapping(address => uint256)` surface: there is no enumeration, no key rotation API, and no
general-purpose map escape hatch.

Applications own authorization, error terminals, and the literal map writes. `useValue` /
`useNext` expose the postfix increment semantics of `_useNonce`; `matches` is the checked gate
for `_useCheckedNonce`. Fail closed by returning typed errors or closed revert terminals at the
consumer when `matches` is false.
-/

abbrev Map := Storage.AddressMap256

/-- The next unused nonce for `account`. Uninitialized map entries read as zero. -/
@[pf_inline] def current (map : Map) (account : Address) : UInt256 :=
  map.get account

/-- Whether `nonce` equals the next unused nonce for `account`. -/
@[pf_inline] def nonceMatches (map : Map) (account : Address) (nonce : UInt256) : Bool :=
  UInt256.eq (map.get account) nonce

/-- Nonce consumed on success (postfix semantics: return current, then advance). -/
@[pf_inline] def useValue (map : Map) (account : Address) : UInt256 :=
  map.get account

/-- Updated nonce to store after a successful unchecked consumption. -/
@[pf_inline] def useNext (map : Map) (account : Address) : UInt256 :=
  map.nextAdd account ⟨1, 0, 0, 0⟩

/-- Checked use: true when `nonce` equals current; consumer stores `useNext` on success. -/
@[pf_inline] def useChecked (map : Map) (account : Address) (nonce : UInt256) : Bool :=
  Nonces.nonceMatches map account nonce

end ProofForge.Evm.Sdk.Nonces
