import ProofForge.Evm.Sdk.Erc165

namespace ProofForge.Evm.Sdk.Erc2981

/-!
# EVM SDK static ERC-2981 royalty profile

EIP-2981 `royaltyInfo(uint256,uint256)` as a compile-time receiver plus basis-point fraction.
The token id is ignored: there is no per-token royalty map, metadata URI, or receiver
callback. The quote uses quotient/remainder decomposition so every valid fraction supports the
full `salePrice` range without overflowing or losing precision. Consumers must validate that the
static receiver is nonzero before advertising IERC2981.

Advertise `Erc165.erc2981` only together with a `royaltyInfo` entry. This is a restricted
profile, not an OpenZeppelin ERC2981 clone.
-/

/-- Same packed `bytes4` as `Erc165.erc2981`. -/
@[pf_inline] def interfaceId : Erc165.InterfaceId :=
  Erc165.erc2981

/-- EIP-2981 fee denominator (10000 = 100%). -/
@[pf_inline] def feeDenominator : UInt256 :=
  ⟨10000, 0, 0, 0⟩

/-- `feeNumerator` does not exceed 100%. -/
@[pf_inline] def canFraction (feeNumerator : UInt256) : Bool :=
  UInt256.le feeNumerator feeDenominator

/-- A configured royalty quote needs a payable recipient. -/
@[pf_inline] def canReceive (receiver : Address) : Bool :=
  !Address.isZero receiver

/-- Exact floor of `salePrice * feeNumerator / 10000`. Precondition:
`canFraction feeNumerator`. Splitting `salePrice` into quotient and remainder keeps both checked
products and their sum in UInt256 for every valid fraction, including `salePrice = 2^256 - 1`. -/
@[pf_inline] def amount (salePrice feeNumerator : UInt256) : UInt256 :=
  let whole :=
    UInt256.mul (UInt256.div salePrice feeDenominator) feeNumerator
  let fraction :=
    UInt256.div
      (UInt256.mul (UInt256.mod salePrice feeDenominator) feeNumerator)
      feeDenominator
  UInt256.add whole fraction

/-- Default royalty quote. `tokenId` is unused. Reconstruct constructors so Extract can flatten
the `(address,uint256)` product. Precondition: `canReceive receiver`. -/
@[pf_inline] def royaltyInfo (receiver : Address) (feeNumerator salePrice : UInt256) :
    Address × UInt256 :=
  let amt := amount salePrice feeNumerator
  (⟨receiver.w0, receiver.w1, receiver.w2⟩, ⟨amt.w0, amt.w1, amt.w2, amt.w3⟩)

end ProofForge.Evm.Sdk.Erc2981
