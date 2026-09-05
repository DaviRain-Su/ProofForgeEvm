#!/usr/bin/env bash
# ReceiverLink answers onERC721Received / onERC1155Received / onERC1155BatchReceived with
# each selector as bytes4. Collectible, CraftToken, and MultiToken drive the hooks.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_pack_addr_u256() {
  local addr="$1"
  "$python" -I -S -c "
addr=int('$addr', 16)
b=addr.to_bytes(20, 'big')
w0=int.from_bytes(b[0:8], 'little')
w1=int.from_bytes(b[8:16], 'little')
w2=int.from_bytes(b[16:20], 'little')
print(w0 | (w1 << 64) | (w2 << 128))
"
}

expect_bytes4() {
  local actual="$1" expected="$2" message="$3"
  actual="$(tr 'A-F' 'a-f' <<<"$actual")"
  actual="${actual#0x}"
  actual="${actual:0:8}"
  expected="$(tr 'A-F' 'a-f' <<<"$expected")"
  expected="${expected#0x}"
  pf_evm_require_equal "$actual" "$expected" "$message"
}

pf_evm_evm_init evm-anvil-receiverlink
echo "building ReceiverLink Collectible CraftToken MultiToken" >&2
lake exe pf -- build --target evm --out "$root/build/evm" \
  ReceiverLink Collectible CraftToken MultiToken \
  || { echo "FAIL: pf build ReceiverLink/Collectible/CraftToken/MultiToken failed" >&2; exit 1; }
recv_bin="$root/build/evm/ReceiverLink.bin"
nft_bin="$root/build/evm/Collectible.bin"
ft_bin="$root/build/evm/CraftToken.bin"
batch_bin="$root/build/evm/MultiToken.bin"
nft_abi="$root/build/evm/Collectible.abi.json"
for path in "$recv_bin" "$nft_bin" "$ft_bin" "$batch_bin" "$nft_abi"; do
  [[ -f "$path" ]] || { echo "FAIL: missing $path" >&2; exit 1; }
done
if ! grep -q '"name":"safeTransferFrom"' "$nft_abi"; then
  echo "FAIL: Collectible ABI has no safeTransferFrom" >&2
  exit 1
fi

size="$("$python" -I -S -c "
text=open('$recv_bin').read().strip()
if text.startswith('0x') or text.startswith('0X'):
    text=text[2:]
print(len(text)//2)
")"
if (( size > 24576 )); then
  echo "FAIL: ReceiverLink.bin is $size bytes, over EIP-170 24576" >&2
  exit 1
fi

pf_evm_start_anvil "${PF_EVM_PORT:-18719}" "$root/build/evm/anvil-receiverlink.log"

sender="$("$cast" wallet address --private-key "$private_key")"
recv="$(pf_evm_deploy_ctor_address "$(tr -d '\n\r ' < "$recv_bin")" "$sender")"
nft="$(pf_evm_deploy_ctor_address "$(tr -d '\n\r ' < "$nft_bin")" "$sender")"
ft="$(pf_evm_deploy_ctor_address "$(tr -d '\n\r ' < "$ft_bin")" "$sender")"
batch="$(pf_evm_deploy_ctor_address "$(tr -d '\n\r ' < "$batch_bin")" "$sender")"
recv_packed="$(pf_pack_addr_u256 "$recv")"
sender_packed="$(pf_pack_addr_u256 "$sender")"

supports() {
  "$cast" call --rpc-url "$rpc" "$recv" 'supportsInterface(bytes4)(bool)' "$1"
}
pf_evm_require_equal "$(supports 0x01ffc9a7)" true "IERC165 support"
pf_evm_require_equal "$(supports 0x150b7a02)" true "IERC721Receiver support"
pf_evm_require_equal "$(supports 0x4e2312e0)" true "IERC1155Receiver support"
pf_evm_require_equal "$(supports 0x80ac58cd)" false "incomplete IERC721 is unsupported"
pf_evm_require_equal "$(supports 0xd9b67a26)" false "incomplete IERC1155 is unsupported"

expect_bytes4 "$("$cast" call --rpc-url "$rpc" --from "$sender" "$recv" \
  'onERC721Received(address,address,uint256,bytes)(bytes4)' "$sender" "$sender" 1 0x616263)" \
  150b7a02 "onERC721Received returns its selector"
expect_bytes4 "$("$cast" call --rpc-url "$rpc" --from "$sender" "$recv" \
  'onERC1155Received(address,address,uint256,uint256,bytes)(bytes4)' \
  "$sender" "$sender" 7 4 0x)" \
  f23a6e61 "onERC1155Received returns its selector"
expect_bytes4 "$("$cast" call --rpc-url "$rpc" --from "$sender" "$recv" \
  'onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)(bytes4)' \
  "$sender" "$sender" "[1,2]" "[3,4]" 0x)" \
  bc197c81 "onERC1155BatchReceived returns its selector"

seen_op() { "$cast" call --rpc-url "$rpc" "$recv" 'seenOperator()(uint256)'; }
seen_from() { "$cast" call --rpc-url "$rpc" "$recv" 'seenFrom()(uint256)'; }
seen_id() { "$cast" call --rpc-url "$rpc" "$recv" 'seenId()(uint256)'; }
seen_value() { "$cast" call --rpc-url "$rpc" "$recv" 'seenValue()(uint256)'; }
seen_len() { "$cast" call --rpc-url "$rpc" "$recv" 'seenDataLen()(uint64)'; }

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$nft" 'mint(address,uint256)' "$sender" 1 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$nft" 'safeTransferFrom(address,address,uint256,bytes)' "$sender" "$recv" 1 0x616263 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$nft" 'ownerOf(uint256)(uint256)' 1)" \
  "$recv_packed" "Collectible owner after safeTransferFrom to ReceiverLink"
pf_evm_require_uint "$(seen_op)" "$sender_packed" "ERC-721 hook saw the operator"
pf_evm_require_uint "$(seen_from)" "$sender_packed" "ERC-721 hook saw from"
pf_evm_require_uint "$(seen_id)" 1 "ERC-721 hook saw the token id"
pf_evm_require_uint "$(seen_value)" 0 "ERC-721 hook stored value 0"
pf_evm_require_uint "$(seen_len)" 3 "ERC-721 hook saw data length 3"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$ft" 'mint(uint256,uint256)' 7 10 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$ft" 'safeTransferFrom(address,address,uint256,uint256,bytes)' \
  "$sender" "$recv" 7 4 0x >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$ft" \
  'balanceOf(address,uint256)(uint256)' "$recv" 7)" 4 \
  "CraftToken credited ReceiverLink"
pf_evm_require_uint "$(seen_op)" "$sender_packed" "ERC-1155 hook saw the operator"
pf_evm_require_uint "$(seen_from)" "$sender_packed" "ERC-1155 hook saw from"
pf_evm_require_uint "$(seen_id)" 7 "ERC-1155 hook saw the id"
pf_evm_require_uint "$(seen_value)" 4 "ERC-1155 hook saw the value"
pf_evm_require_uint "$(seen_len)" 0 "ERC-1155 hook saw empty data"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$batch" 'mint(address,uint256,uint256)' "$sender" 1 10 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$batch" 'mint(address,uint256,uint256)' "$sender" 2 5 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$batch" 'safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)' \
  "$sender" "$recv" "[1,2]" "[3,4]" 0x >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$batch" \
  'balanceOf(address,uint256)(uint256)' "$recv" 1)" 3 \
  "MultiToken credited batch slot 0"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$batch" \
  'balanceOf(address,uint256)(uint256)' "$recv" 2)" 4 \
  "MultiToken credited batch slot 1"
pf_evm_require_uint "$(seen_id)" 1 "batch hook recorded slot 0 id"
pf_evm_require_uint "$(seen_value)" 3 "batch hook recorded slot 0 value"
pf_evm_require_uint "$(seen_len)" 0 "batch hook saw empty data"

echo "evm-anvil-receiverlink: ok (ReceiverLink answers onERC721Received/onERC1155Received/onERC1155BatchReceived; Collectible/CraftToken/MultiToken safe transfers credit it; $size runtime bytes)"
