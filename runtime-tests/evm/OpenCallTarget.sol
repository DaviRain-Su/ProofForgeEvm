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

    function deposit() external payable {}
}
