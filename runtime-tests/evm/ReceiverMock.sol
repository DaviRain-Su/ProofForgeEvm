// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// Contract recipient for the safeTransferFrom Anvil gates. Not a product contract.
/// Each hook records its arguments, reads the token's state back through `msg.sender` while
/// the transfer is still running, and answers with `hookWord` over `hookSize` bytes, or reverts
/// with that same frame when `hookReverts` is set, so the gate can drive the right magic, a
/// wrong selector, a dirty low byte, an empty frame, a two-word frame, and a revert whose data
/// is the magic word.
contract ReceiverMock {
    uint256 public hookWord;
    uint256 public hookSize = 32;
    bool public hookReverts;

    address public seenOperator;
    address public seenFrom;
    uint256 public seenId;
    uint256 public seenValue;
    bytes32 public seenDataHash;
    /// `ownerOf(seenId)` as the ERC-721 token answered it inside the hook (its packed word).
    uint256 public seenOwnerWord;
    /// `balanceOf(this, seenId)` as the ERC-1155 token answered it inside the hook.
    uint256 public seenBalance;

    function setHookWord(uint256 w) external { hookWord = w; }
    function setHookSize(uint256 n) external { hookSize = n; }
    function setHookReverts(bool r) external { hookReverts = r; }

    function answer() private view {
        uint256 w = hookWord;
        uint256 n = hookSize;
        bool r = hookReverts;
        assembly {
            mstore(0, w)
            if r { revert(0, n) }
            return(0, n)
        }
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4)
    {
        seenOperator = operator;
        seenFrom = from;
        seenId = tokenId;
        seenDataHash = keccak256(data);
        (bool ok, bytes memory ret) =
            msg.sender.staticcall(abi.encodeWithSignature("ownerOf(uint256)", tokenId));
        if (ok && ret.length == 32) {
            seenOwnerWord = abi.decode(ret, (uint256));
        }
        answer();
    }

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4) {
        seenOperator = operator;
        seenFrom = from;
        seenId = id;
        seenValue = value;
        seenDataHash = keccak256(data);
        (bool ok, bytes memory ret) = msg.sender.staticcall(
            abi.encodeWithSignature("balanceOf(address,uint256)", address(this), id)
        );
        if (ok && ret.length == 32) {
            seenBalance = abi.decode(ret, (uint256));
        }
        answer();
    }
}
