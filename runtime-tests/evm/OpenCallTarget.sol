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

    uint256 public balanceWord = 1000;

    function setOnWord(uint256 w) external { onWord = w; }
    function setOwnerWord(uint256 w) external { ownerWord = w; }
    function setTripleWords(uint256 n) external { tripleWords = n; }
    function setQuadWords(uint256 n) external { quadWords = n; }
    function setBalanceWord(uint256 w) external { balanceWord = w; }

    function balanceOf(address) external view returns (uint256) {
        return balanceWord;
    }

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

    /// What a bounded `bytes` argument decodes to, plus the keccak of the whole calldata so
    /// the gate can compare the caller's encoding byte for byte with `cast calldata`.
    uint256 public sunkTag;
    uint256 public sunkLength;
    bytes32 public sunkHash;
    bytes32 public sunkCalldataHash;

    function sink(uint256 tag, bytes calldata data) external {
        sunkTag = tag;
        sunkLength = data.length;
        sunkHash = keccak256(data);
        sunkCalldataHash = keccak256(msg.data);
    }

    /// Keccak of the whole calldata, so a STATICCALL read proves its selector, head, tail,
    /// and size at once against `cast calldata`.
    function calldataHash(bytes calldata) external pure returns (bytes32) {
        return keccak256(msg.data);
    }

    /// Receiver hook. The returned frame is `hookWord` over `hookSize` bytes so the gate can
    /// answer with the right magic, a wrong selector, a dirty low byte, or a wrong size.
    /// `onERC721Received(address,address,uint256,bytes)`, left-aligned.
    uint256 public hookWord = uint256(bytes32(bytes4(0x150b7a02)));
    uint256 public hookSize = 32;
    address public hookOperator;
    address public hookFrom;
    uint256 public hookTokenId;
    bytes32 public hookDataHash;

    function setHookWord(uint256 w) external { hookWord = w; }
    function setHookSize(uint256 n) external { hookSize = n; }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4)
    {
        hookOperator = operator;
        hookFrom = from;
        hookTokenId = tokenId;
        hookDataHash = keccak256(data);
        uint256 w = hookWord;
        uint256 n = hookSize;
        assembly {
            mstore(0, w)
            return(0, n)
        }
    }
}
