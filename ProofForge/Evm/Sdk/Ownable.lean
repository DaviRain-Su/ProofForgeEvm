import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.Ownable

/-!
# EVM SDK Ownable event helper

Canonical OpenZeppelin `OwnershipTransferred` and Ownable2Step `OwnershipTransferStarted` as
reusable `Event.emit` wrappers. Authorization, storage of the owner handle, two-step nomination,
and the explicit owner/pending-state clear used by `renounceOwnership` remain in `Sdk.Access` /
the application.

Constructor policy that *is* extractable: applications store a nonzero owner argument into an
explicit `State` field and start with `Access.Ownership.none`. A dropped-let
`Revert.zeroAddress` before the `returnState` vector lowers as a constructor prefix. VestLink and
Vest20Link CREATE of `address(0)` revert `ZeroAddress()`. The else-arm of that dropped-let may
emit `Log.constructorTransferred` (LOG3 `OwnershipTransferred(address(0), newOwner)`). CALL, map
writes, value transfers, and any other constructor log stay refused
(`extract/unsupported: EVM constructor effects are not lowered`). TwoStepCounter and Credits still
store a zero owner without reverting CREATE and without a constructor log.
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

/-- ABI-identical constructor transfer `OwnershipTransferred(address(0), newOwner)`. Lowers from
`init` when it is the else-arm of the ZeroAddress revert-guard. -/
@[pf_inline] def constructorTransferred (newOwner : Address) : UInt64 :=
  ownershipTransferred Address.zero newOwner

end Log

end ProofForge.Evm.Sdk.Ownable
