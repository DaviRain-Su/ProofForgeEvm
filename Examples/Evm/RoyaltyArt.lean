import ProofForge.Evm.Sdk

/-!
Static ERC-2981 consumer. The constructor immutable is the royalty receiver; zero disables
royalties and returns `(address(0), 0)`. The fee is a compile-time 2.5% (250 / 10000).
`tokenId` is ignored: there is no per-token royalty map, metadata URI, or receiver callback.

IERC2981's required surface is exactly `royaltyInfo`, so this profile advertises IERC165 and
IERC2981. It does not advertise IERC721.
-/

namespace Examples.Evm.RoyaltyArt
open ProofForge.Evm.Sdk

structure State where
  dummy : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

/-- 250 / 10000 = 2.5%. Compile-time constant; not a storage field. -/
@[pf_inline] def feeNumerator : UInt256 :=
  ⟨250, 0, 0, 0⟩

@[pf_entry]
def init (_receiver : Address) : State :=
  { dummy := 0 }

/-- Satisfies the extractor's mutating-method requirement; royalty state is immutable. -/
@[pf_entry]
def touch (_s : State) (v : UInt64) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := v }, v)
  else
    .error .overflow

/-- Packed constructor receiver. Same Extract limitation as other immutable Address views: the
ABI word is a 20-byte address, not a hashed-map load. -/
@[pf_entry]
def receiver (_s : State) : Address :=
  Immutable.address

@[pf_entry]
def feeNumeratorOf (_s : State) : UInt256 :=
  feeNumerator

/-- EIP-2981 `royaltyInfo(uint256,uint256) → (address,uint256)`. The token id is unused, and a
zero immutable receiver returns the no-royalty tuple. -/
@[pf_entry]
def royaltyInfo (_s : State) (_tokenId salePrice : UInt256) : Address × UInt256 :=
  Erc2981.royaltyInfo Immutable.address feeNumerator salePrice

/-- Explicit bounded ERC-165 declaration: IERC165 + complete IERC2981. -/
@[pf_entry]
def supportsInterface (_s : State) (interfaceId : Bytes4) : Bool :=
  Erc165.supportsRoyalty interfaceId

end Examples.Evm.RoyaltyArt
