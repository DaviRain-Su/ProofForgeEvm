// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// Minimal callee for OpenCall Anvil. Not a product contract.
contract OpenCallTarget {
    uint256 public seenFlag;
    uint256 public pings;

    function ping() external {
        pings += 1;
        (bool ok, bytes memory data) = msg.sender.staticcall(abi.encodeWithSignature("flagOf()"));
        if (ok && data.length == 32) {
            seenFlag = abi.decode(data, (uint256));
        }
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    /// `n == 0` returns two words so OpenCall.staticWord (exact one word) fails closed.
    function echo(uint256 n) external pure returns (uint256) {
        if (n == 0) {
            assembly {
                mstore(0, 0)
                mstore(32, 1)
                return(0, 64)
            }
        }
        return n;
    }

    function getPair() external pure returns (uint256, uint256) {
        return (1, 2);
    }

    /// Raw words behind the typed reads. The gate rewrites them to prove each fail-closed
    /// path: a bool word above 1, an address word with dirty high bytes, a frame of the
    /// wrong size.
    uint256 public onWord = 1;
    uint256 public ownerWord = uint256(uint160(address(this)));
    uint256 public tripleWords = 3;
    uint256 public quadWords = 4;

    function setOnWord(uint256 w) external { onWord = w; }
    function setOwnerWord(uint256 w) external { ownerWord = w; }
    function setTripleWords(uint256 n) external { tripleWords = n; }
    function setQuadWords(uint256 n) external { quadWords = n; }

    function isOn() external view returns (bool) {
        uint256 w = onWord;
        assembly { mstore(0, w) return(0, 32) }
    }

    function ownerOf() external view returns (address) {
        uint256 w = ownerWord;
        assembly { mstore(0, w) return(0, 32) }
    }

    /// Returns `n` words `1, 2, …, n` so the caller's exact-frame gate is observable.
    function returnWords(uint256 n) private pure {
        assembly {
            for { let i := 0 } lt(i, n) { i := add(i, 1) } { mstore(mul(i, 32), add(i, 1)) }
            return(0, mul(n, 32))
        }
    }

    function getTriple() external view returns (uint256, uint256, uint256) {
        returnWords(tripleWords);
    }

    function getQuad() external view returns (uint256, uint256, uint256, uint256) {
        returnWords(quadWords);
    }

    function deposit() external payable {}
}
