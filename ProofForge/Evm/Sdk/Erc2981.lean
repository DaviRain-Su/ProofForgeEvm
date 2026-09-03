import ProofForge.Evm.Sdk.Erc165

namespace ProofForge.Evm.Sdk.Erc2981

/-!
# EVM SDK static ERC-2981 royalty profile

EIP-2981 `royaltyInfo(uint256,uint256)` as a compile-time receiver plus basis-point fraction.
The token id is ignored: there is no per-token royalty map, metadata URI, or receiver
callback. Overflow of `salePrice * feeNumerator` yields a zero amount rather than a wrapped fee.

Advertise `Erc165.erc2981` only together with a `royaltyInfo` entry. This is a restricted
profile, not an OpenZeppelin ERC2981 clone.
-/

/-- Same packed `bytes4` as `Erc165.erc2981`. -/
@[pf_inline] def interfaceId : Erc165.InterfaceId :=
  Erc165.erc2981

/-- EIP-2981 fee denominator (10000 = 100%). -/
@[pf_inline] def feeDenominator : UInt256 :=
  ⟨10000, 0, 0, 0⟩

@[pf_inline] def wordMax : UInt256 :=
  ⟨~~~(0 : UInt64), ~~~(0 : UInt64), ~~~(0 : UInt64), ~~~(0 : UInt64)⟩

/-- `feeNumerator` does not exceed 100%. -/
@[pf_inline] def canFraction (feeNumerator : UInt256) : Bool :=
  UInt256.le feeNumerator feeDenominator

/-- `salePrice * feeNumerator` fits in UInt256. A zero numerator is always safe. -/
@[pf_inline] def canAmount (salePrice feeNumerator : UInt256) : Bool :=
  UInt256.eq feeNumerator UInt256.zero ||
    UInt256.le salePrice (UInt256.div wordMax feeNumerator)

/-- Floor of `salePrice * feeNumerator / 10000`. Precondition:
`canAmount salePrice feeNumerator`. Extract cannot return a product from an `ite`, so overflow
preflight belongs to the caller; this quote always performs the multiplication. -/
@[pf_inline] def amount (salePrice feeNumerator : UInt256) : UInt256 :=
  UInt256.div (UInt256.mul salePrice feeNumerator) feeDenominator

/-- Default royalty quote. `tokenId` is unused. Reconstruct constructors so Extract can flatten
the `(address,uint256)` product. -/
@[pf_inline] def royaltyInfo (receiver : Address) (feeNumerator salePrice : UInt256) :
    Address × UInt256 :=
  let amt := amount salePrice feeNumerator
  (⟨receiver.w0, receiver.w1, receiver.w2⟩, ⟨amt.w0, amt.w1, amt.w2, amt.w3⟩)

end ProofForge.Evm.Sdk.Erc2981
