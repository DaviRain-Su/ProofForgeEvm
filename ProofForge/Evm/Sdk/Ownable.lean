import ProofForge.Evm.Sdk.Base

namespace ProofForge.Evm.Sdk.Ownable

/-!
# EVM SDK Ownable event helper

Canonical OpenZeppelin `OwnershipTransferred` as a reusable `Event.emit` wrapper. Authorization,
storage of the owner handle, and two-step nomination remain in `Sdk.Access` / the application.
This module does not allocate a slot, hide a storage write, emit constructor logs, or add
`OwnershipTransferStarted` (Ownable2Step).
-/

/-- Canonical Ownable event. Constructor and field names are the ABI surface
(`OwnershipTransferred`). Indexed flags produce LOG3 with empty data. -/
inductive Notice where
  | OwnershipTransferred (previousOwner : Event.Indexed Address)
      (newOwner : Event.Indexed Address)
  deriving Repr, DecidableEq, Inhabited

namespace Log

/-- LOG3 `OwnershipTransferred(address indexed previousOwner, address indexed newOwner)`. -/
@[pf_inline] def ownershipTransferred (previousOwner newOwner : Address) : UInt64 :=
  Event.emit (Notice.OwnershipTransferred (Event.indexed previousOwner)
    (Event.indexed newOwner))

end Log

end ProofForge.Evm.Sdk.Ownable
