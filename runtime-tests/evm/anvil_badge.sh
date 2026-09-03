#!/usr/bin/env bash
# Badge: operator approval + burn over Erc721 ledger. Darwin + Linux.
# Receipts are ABI-decoded: Transfer LOG4 (including burn to zero) and ApprovalForAll LOG3.
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

pf_evm_evm_init evm-anvil-badge
bin="$root/build/evm/Badge.bin"
abi="$root/build/evm/Badge.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building Badge.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" Badge \
    || { echo "FAIL: pf build Badge failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18571}" "$root/build/evm/anvil-badge.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty Badge.bin" >&2; exit 1; }

sender="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_address "$bytecode" "$sender")"
other_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
other="$("$cast" wallet address --private-key "$other_key")"
token_id=42
sender_packed="$(pf_pack_addr_u256 "$sender")"
other_packed="$(pf_pack_addr_u256 "$other")"
zero="0x0000000000000000000000000000000000000000"

supports_interface() { # interface id
  "$cast" call --rpc-url "$rpc" "$addr" 'supportsInterface(bytes4)(bool)' "$1"
}
pf_evm_require_equal "$(supports_interface 0x01ffc9a7)" true "IERC165 support"
pf_evm_require_equal "$(supports_interface 0x80ac58cd)" false "incomplete IERC721 is unsupported"
pf_evm_require_equal "$(supports_interface 0xd9b67a26)" false "IERC1155 is unsupported"
pf_evm_require_equal "$(supports_interface 0xffffffff)" false "ERC-165 invalid interface id"
pf_evm_require_equal "$(supports_interface 0xdeadbeef)" false "unknown interface id"

sig_xfer="$(pf_evm_typed_event_sig "$abi" Transfer)"
sig_op="$(pf_evm_typed_event_sig "$abi" ApprovalForAll)"
pf_evm_require_equal "$sig_xfer" 'Transfer(address,address,uint256)' "ABI Transfer signature"
pf_evm_require_equal "$sig_op" 'ApprovalForAll(address,address,bool)' "ABI ApprovalForAll signature"
topic_xfer="$("$cast" keccak "$sig_xfer")"
topic_op="$("$cast" keccak "$sig_op")"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(address,uint256)' "$sender" "$token_id")"
pf_evm_typed_event_check "$abi" "$receipt" Transfer "$topic_xfer" \
  "{\"from\": \"$zero\", \"to\": \"$sender\", \"tokenId\": $token_id}" \
  "mint Transfer LOG4"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'ownerOf(uint256)(uint256)' "$token_id")" \
  "$sender_packed" "owner after mint"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$sender")" \
  1 "balance after mint"

approved="$("$cast" call --rpc-url "$rpc" "$addr" \
  'isApprovedForAll(address,address)(bool)' "$sender" "$other")"
if [[ "${approved,,}" == "true" ]]; then
  echo "FAIL: operator unexpectedly approved" >&2
  exit 1
fi

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'setApprovalForAll(address,bool)' "$other" true)"
pf_evm_typed_event_check "$abi" "$receipt" ApprovalForAll "$topic_op" \
  "{\"owner\": \"$sender\", \"operator\": \"$other\", \"approved\": true}" \
  "setApprovalForAll(true) LOG3"
approved="$("$cast" call --rpc-url "$rpc" "$addr" \
  'isApprovedForAll(address,address)(bool)' "$sender" "$other")"
if [[ "${approved,,}" != "true" ]]; then
  echo "FAIL: operator not approved (got $approved)" >&2
  exit 1
fi

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" 'transferFrom(address,address,uint256)' "$sender" "$other" "$token_id")"
pf_evm_typed_event_check "$abi" "$receipt" Transfer "$topic_xfer" \
  "{\"from\": \"$sender\", \"to\": \"$other\", \"tokenId\": $token_id}" \
  "operator transferFrom Transfer LOG4"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'ownerOf(uint256)(uint256)' "$token_id")" \
  "$other_packed" "owner after operator transfer"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$other")" \
  1 "operator recipient balance"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" 'burn(uint256)' "$token_id")"
pf_evm_typed_event_check "$abi" "$receipt" Transfer "$topic_xfer" \
  "{\"from\": \"$other\", \"to\": \"$zero\", \"tokenId\": $token_id}" \
  "burn Transfer to zero LOG4"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'ownerOf(uint256)(uint256)' "$token_id")" \
  0 "owner cleared after burn"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$other")" \
  0 "balance after burn"

token_id2=43
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'setApprovalForAll(address,bool)' "$other" false)"
pf_evm_typed_event_check "$abi" "$receipt" ApprovalForAll "$topic_op" \
  "{\"owner\": \"$sender\", \"operator\": \"$other\", \"approved\": false}" \
  "setApprovalForAll(false) LOG3"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(address,uint256)' "$sender" "$token_id2" >/dev/null
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'burn(uint256)' "$token_id2" >/dev/null 2>&1; then
  echo "FAIL: non-approved burn unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_unauthorized "$addr" "$other" \
  "$("$cast" calldata 'burn(uint256)' "$token_id2")" "$other" \
  "non-approved burn"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'ownerOf(uint256)(uint256)' "$token_id2")" \
  "$sender_packed" "non-approved burn holds owner"

# tokenKey drops w3; views/auth must not treat id+2^192 as the minted token.
alias_id="$("$python" -I -S -c "print($token_id2 + (1 << 192))")"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'ownerOf(uint256)(uint256)' "$alias_id")" \
  0 "ownerOf rejects unencodable alias"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'burn(uint256)' "$alias_id" >/dev/null 2>&1; then
  echo "FAIL: burn on unencodable alias unexpectedly succeeded" >&2
  exit 1
fi

echo "evm-anvil-badge: ok (operator transfer/burn + ERC-721 Transfer LOG4 / ApprovalForAll LOG3)"
