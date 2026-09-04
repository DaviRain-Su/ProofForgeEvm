// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// Contract signer for the SignerLink Anvil gate. Not a product contract.
/// Behaves as OZ's ERC1271WalletMock by default: `isValidSignature` recovers the 65-byte
/// `r || s || v` over `hash` with the ecrecover precompile and answers its own selector when the
/// signer is `owner`, `bytes4(0)` otherwise. It records what it was asked so the gate can check
/// the calldata the check built, and it takes a settable frame (`frameWord` over `frameSize`
/// bytes, or a revert carrying it) so the gate can drive a wrong selector, a dirty low byte, an
/// empty frame, a two-word frame, and a revert whose data is the magic word. A real wallet
/// declares the view `view`; this one writes, which a CALL reaches and a STATICCALL would not.
contract Erc1271WalletMock {
    address public immutable owner;

    bytes32 public seenHash;
    bytes32 public seenSignatureHash;
    uint256 public seenLength;
    uint256 public calls;

    bool public useFrame;
    uint256 public frameWord;
    uint256 public frameSize;
    bool public frameReverts;

    constructor(address owner_) {
        owner = owner_;
    }

    function setFrame(uint256 word, uint256 size, bool reverts) external {
        useFrame = true;
        frameWord = word;
        frameSize = size;
        frameReverts = reverts;
    }

    function clearFrame() external {
        useFrame = false;
    }

    function recover(bytes32 hash, bytes calldata signature) private pure returns (address) {
        if (signature.length != 65) return address(0);
        bytes32 r = bytes32(signature[0:32]);
        bytes32 s = bytes32(signature[32:64]);
        uint8 v = uint8(signature[64]);
        if (v < 27) v += 27;
        return ecrecover(hash, v, r, s);
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external returns (bytes4) {
        seenHash = hash;
        seenSignatureHash = keccak256(signature);
        seenLength = signature.length;
        calls += 1;
        if (useFrame) {
            uint256 w = frameWord;
            uint256 n = frameSize;
            bool r = frameReverts;
            assembly {
                mstore(0, w)
                if r { revert(0, n) }
                return(0, n)
            }
        }
        address signer = recover(hash, signature);
        return signer != address(0) && signer == owner ? this.isValidSignature.selector : bytes4(0);
    }
}
