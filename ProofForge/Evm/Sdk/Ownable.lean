import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.Ownable

/-!
# EVM SDK Ownable event helper

Canonical OpenZeppelin `OwnershipTransferred` and Ownable2Step `OwnershipTransferStarted` as
reusable `Event.emit` wrappers. Authorization, storage of the owner handle, two-step nomination,
and the explicit owner/pending-state clear used by `renounceOwnership` remain in `Sdk.Access` /
the application.

Constructor policy that *is* extractable: applications store a nonzero owner argument into an
explicit `State` field and start with `Access.Ownership.none`. Constructor logs and constructor
zero-owner reverts are **not** extractable: `Evm.Emit` refuses constructor effects
(`extract/unsupported: EVM constructor effects are not lowered`). `Log.constructorTransferred`
exists so the ABI-identical `OwnershipTransferred(address(0), newOwner)` shape is spelled once,
but it must be used from a runtime entry, not from `init`.
-/

/-- Canonical Ownable / Ownable2Step events. Constructor and field names are the ABI surface.
Indexed flags produce LOG3 with empty data. -/
inductive Notice where
  | OwnershipTransferred (previousOwner : Event.Indexed Address)
      (newOwner : Event.Indexed Address)
  | OwnershipTransferStarted (previousOwner : Event.Indexed Address)
      (newOwner : Event.Indexed Address)
  deriving Repr, DecidableEq, Inhabited

/-- True when `owner` may be stored as the constructor owner. Zero is an invalid Ownable owner. -/
@[pf_inline] def canInit (owner : Address) : Bool :=
  !Address.isZero owner

namespace Log

/-- LOG3 `OwnershipTransferred(address indexed previousOwner, address indexed newOwner)`. -/
@[pf_inline] def ownershipTransferred (previousOwner newOwner : Address) : UInt64 :=
  Event.emit (Notice.OwnershipTransferred (Event.indexed previousOwner)
    (Event.indexed newOwner))

/-- LOG3 `OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner)`. -/
@[pf_inline] def ownershipTransferStarted (previousOwner newOwner : Address) : UInt64 :=
  Event.emit (Notice.OwnershipTransferStarted (Event.indexed previousOwner)
    (Event.indexed newOwner))

/-- ABI-identical constructor transfer `OwnershipTransferred(address(0), newOwner)`. Not lowered
from `init`; use only on a runtime entry. -/
@[pf_inline] def constructorTransferred (newOwner : Address) : UInt64 :=
  ownershipTransferred Address.zero newOwner

end Log

end ProofForge.Evm.Sdk.Ownable
