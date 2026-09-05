// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// View ERC-1271 wallet for SignerLink `tryNow`. Not a product contract.
/// `isValidSignature` is `view`, so a STATICCALL can reach it. The recording
/// `Erc1271WalletMock` writes and is only for the fail-closed CALL path.
contract Erc1271ViewWalletMock {
    address public immutable owner;

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

    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
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
