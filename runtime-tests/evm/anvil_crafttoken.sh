#!/usr/bin/env bash
# CraftToken: open-mint bounded ERC-1155 consumer with per-id supply cap, and the
# safeTransferFrom receiver hook against a Solidity receiver. Darwin + Linux.
# Receipts are ABI-decoded: TransferSingle LOG4 (id+value data) and ApprovalForAll LOG3.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-crafttoken
bin="$root/build/evm/CraftToken.bin"
abi="$root/build/evm/CraftToken.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building registered CraftToken.bin" >&2
  lake build Examples.Evm.CraftToken >/dev/null \
    || { echo "FAIL: lake build Examples.Evm.CraftToken failed" >&2; exit 1; }
  lake exe pf -- build --target evm --out "$root/build/evm" CraftToken >/dev/null \
    || { echo "FAIL: build registered CraftToken failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18575}" "$root/build/evm/anvil-crafttoken.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty CraftToken.bin" >&2; exit 1; }

sender="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_address "$bytecode" "$sender")"
other_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
other="$("$cast" wallet address --private-key "$other_key")"
token_id=3
alias_id="$("$python" -I -S -c "print($token_id + (1 << 192))")"
zero="0x0000000000000000000000000000000000000000"
safe_sig='safeTransferFrom(address,address,uint256,uint256,bytes)'

supports_interface() { # interface id
  "$cast" call --rpc-url "$rpc" "$addr" 'supportsInterface(bytes4)(bool)' "$1"
}
pf_evm_require_equal "$(supports_interface 0x01ffc9a7)" true "IERC165 support"
pf_evm_require_equal "$(supports_interface 0xd9b67a26)" false "incomplete IERC1155 is unsupported"
pf_evm_require_equal "$(supports_interface 0x80ac58cd)" false "IERC721 is unsupported"
pf_evm_require_equal "$(supports_interface 0xffffffff)" false "ERC-165 invalid interface id"
pf_evm_require_equal "$(supports_interface 0xdeadbeef)" false "unknown interface id"

sig_xfer="$(pf_evm_typed_event_sig "$abi" TransferSingle)"
sig_op="$(pf_evm_typed_event_sig "$abi" ApprovalForAll)"
pf_evm_require_equal "$sig_xfer" 'TransferSingle(address,address,address,uint256,uint256)' \
  "ABI TransferSingle signature"
pf_evm_require_equal "$sig_op" 'ApprovalForAll(address,address,bool)' \
  "ABI ApprovalForAll signature"
topic_xfer="$("$cast" keccak "$sig_xfer")"
topic_op="$("$cast" keccak "$sig_op")"

balance_of() { # owner id
  pf_evm_to_dec "$("$cast" call --rpc-url "$rpc" "$addr" \
    'balanceOf(address,uint256)(uint256)' "$1" "$2")"
}
supply_of() { # id
  pf_evm_to_dec "$("$cast" call --rpc-url "$rpc" "$addr" \
    'supplyOf(uint256)(uint256)' "$1")"
}

# Open mint: any caller mints to self, supply tracks.
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" 'mint(uint256,uint256)' "$token_id" 7)"
pf_evm_typed_event_check "$abi" "$receipt" TransferSingle "$topic_xfer" \
  "{\"operator\": \"$other\", \"from\": \"$zero\", \"to\": \"$other\", \"id\": $token_id, \"value\": 7}" \
  "open mint TransferSingle LOG4"
pf_evm_require_uint "$(balance_of "$other" "$token_id")" 7 "open mint balance"
pf_evm_require_uint "$(supply_of "$token_id")" 7 "supply after open mint"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(uint256,uint256)' "$token_id" 993)"
pf_evm_typed_event_check "$abi" "$receipt" TransferSingle "$topic_xfer" \
  "{\"operator\": \"$sender\", \"from\": \"$zero\", \"to\": \"$sender\", \"id\": $token_id, \"value\": 993}" \
  "cap-fill mint TransferSingle LOG4"
pf_evm_require_uint "$(supply_of "$token_id")" 1000 "supply at cap"

# Cap: one more unit exceeds the per-id cap → CapExceeded(), no write.
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'mint(uint256,uint256)' "$token_id" 1 >/dev/null 2>&1; then
  echo "FAIL: over-cap mint unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_cap_exceeded "$addr" "$other" \
  "$("$cast" calldata 'mint(uint256,uint256)' "$token_id" 1)" "over-cap mint"
pf_evm_require_uint "$(supply_of "$token_id")" 1000 "over-cap mint left supply untouched"
pf_evm_require_uint "$(balance_of "$other" "$token_id")" 7 \
  "over-cap mint left balance untouched"

# Unencodable alias id: mint rejected, views gated to zero.
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'mint(uint256,uint256)' "$alias_id" 1 >/dev/null 2>&1; then
  echo "FAIL: mint on unencodable alias unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_unauthorized "$addr" "$other" \
  "$("$cast" calldata 'mint(uint256,uint256)' "$alias_id" 1)" "$other" \
  "unencodable alias mint"
pf_evm_require_uint "$(supply_of "$alias_id")" 0 "alias supply view gated"
pf_evm_require_uint "$(balance_of "$other" "$alias_id")" 0 "alias balance view gated"

# Cross-owner movement by the owner.
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" "$safe_sig" \
  "$other" "$sender" "$token_id" 3 0x)"
pf_evm_typed_event_check "$abi" "$receipt" TransferSingle "$topic_xfer" \
  "{\"operator\": \"$other\", \"from\": \"$other\", \"to\": \"$sender\", \"id\": $token_id, \"value\": 3}" \
  "owner safeTransferFrom TransferSingle LOG4"
pf_evm_require_uint "$(balance_of "$other" "$token_id")" 4 "source after transfer"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 996 "destination after transfer"

# Same-address transfer keeps the balance.
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" "$safe_sig" \
  "$sender" "$sender" "$token_id" 100 0x)"
pf_evm_typed_event_check "$abi" "$receipt" TransferSingle "$topic_xfer" \
  "{\"operator\": \"$sender\", \"from\": \"$sender\", \"to\": \"$sender\", \"id\": $token_id, \"value\": 100}" \
  "self safeTransferFrom TransferSingle LOG4"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 996 "self transfer keeps balance"

# Unauthorized operator rejected; approval lets the operator move; revoke restores rejection.
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" "$safe_sig" \
    "$other" "$sender" "$token_id" 1 0x >/dev/null 2>&1; then
  echo "FAIL: unauthorized operator transfer unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_unauthorized "$addr" "$sender" \
  "$("$cast" calldata "$safe_sig" \
    "$other" "$sender" "$token_id" 1 0x)" "$sender" "unauthorized operator transfer"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" 'setApprovalForAll(address,bool)' "$sender" true)"
pf_evm_typed_event_check "$abi" "$receipt" ApprovalForAll "$topic_op" \
  "{\"account\": \"$other\", \"operator\": \"$sender\", \"approved\": true}" \
  "setApprovalForAll(true) LOG3"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" "$safe_sig" \
  "$other" "$sender" "$token_id" 2 0x)"
pf_evm_typed_event_check "$abi" "$receipt" TransferSingle "$topic_xfer" \
  "{\"operator\": \"$sender\", \"from\": \"$other\", \"to\": \"$sender\", \"id\": $token_id, \"value\": 2}" \
  "operator safeTransferFrom TransferSingle LOG4"
pf_evm_require_uint "$(balance_of "$other" "$token_id")" 2 "source after operator transfer"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 998 \
  "destination after operator transfer"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" 'setApprovalForAll(address,bool)' "$sender" false)"
pf_evm_typed_event_check "$abi" "$receipt" ApprovalForAll "$topic_op" \
  "{\"account\": \"$other\", \"operator\": \"$sender\", \"approved\": false}" \
  "setApprovalForAll(false) LOG3"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" "$safe_sig" \
    "$other" "$sender" "$token_id" 1 0x >/dev/null 2>&1; then
  echo "FAIL: revoked operator transfer unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_uint "$(balance_of "$other" "$token_id")" 2 "revoke left source untouched"

# Underflow: other holds 2, moving 3 fails the debit gate without writes.
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" "$safe_sig" \
    "$other" "$sender" "$token_id" 3 0x >/dev/null 2>&1; then
  echo "FAIL: underflow transfer unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_insufficient "$addr" "$other" \
  "$("$cast" calldata "$safe_sig" \
    "$other" "$sender" "$token_id" 3 0x)" 2 3 "underflow transfer"
pf_evm_require_uint "$(balance_of "$other" "$token_id")" 2 "underflow left source untouched"

# Burn debits balance and supply together; underflow and alias fail without writes.
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'burn(uint256,uint256)' "$token_id" 8)"
pf_evm_typed_event_check "$abi" "$receipt" TransferSingle "$topic_xfer" \
  "{\"operator\": \"$sender\", \"from\": \"$sender\", \"to\": \"$zero\", \"id\": $token_id, \"value\": 8}" \
  "burn TransferSingle to zero LOG4"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 990 "balance after burn"
pf_evm_require_uint "$(supply_of "$token_id")" 992 "supply after burn"
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'burn(uint256,uint256)' "$token_id" 3 >/dev/null 2>&1; then
  echo "FAIL: underflow burn unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_insufficient "$addr" "$other" \
  "$("$cast" calldata 'burn(uint256,uint256)' "$token_id" 3)" 2 3 "underflow burn"
pf_evm_require_uint "$(supply_of "$token_id")" 992 "underflow burn left supply untouched"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'burn(uint256,uint256)' "$alias_id" 1 >/dev/null 2>&1; then
  echo "FAIL: burn on unencodable alias unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_unauthorized "$addr" "$sender" \
  "$("$cast" calldata 'burn(uint256,uint256)' "$alias_id" 1)" "$sender" \
  "unencodable alias burn"

# safeTransferFrom to a contract: the recipient must answer onERC1155Received with its own
# selector. The Solidity receiver records the hook's arguments, reads balanceOf back through
# msg.sender while the transfer is still running, and answers with a settable frame, so the right
# magic, a wrong selector, a dirty low byte, an empty frame, a two-word frame, and a revert
# carrying the magic word are each driven. Every refusal is an empty revert that leaves both
# balances in place. Balances here: sender 990, other 2.
solc_bin="$(pf_evm_find_tool solc)" || {
  echo "evm-anvil-crafttoken: skip: solc not found, safeTransferFrom receiver hook not driven" >&2
  echo "evm-anvil-crafttoken: ok (open capped mint/burn/safeTransferFrom/operator + ERC-1155 TransferSingle LOG4 / ApprovalForAll LOG3; receiver hook skipped)"
  exit 0
}
"$solc_bin" --bin --optimize --overwrite -o "$root/build/evm" "$here/ReceiverMock.sol" >/dev/null
mock_bin="$root/build/evm/ReceiverMock.bin"
[[ -f "$mock_bin" ]] || { echo "FAIL: missing ReceiverMock.bin" >&2; exit 1; }
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x$(tr -d '\n\r ' < "$mock_bin")")"
receiver="$(printf '%s' "$receipt" | pf_evm_contract_address)"
hook_word="$("$python" -I -S -c \
  "print(int('$("$cast" sig 'onERC1155Received(address,address,uint256,uint256,bytes)')', 16) << 224)")"

set_hook() { # word size reverts
  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$receiver" 'setHookWord(uint256)' "$1" >/dev/null
  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$receiver" 'setHookSize(uint256)' "$2" >/dev/null
  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$receiver" 'setHookReverts(bool)' "$3" >/dev/null
}
seen() { # getter signature
  "$cast" call --rpc-url "$rpc" "$receiver" "$1"
}
lower() { tr 'A-F' 'a-f' <<<"$1"; }

set_hook "$hook_word" 32 false
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" --from "$sender" "$addr" \
  "$safe_sig(bool)" "$sender" "$receiver" "$token_id" 5 0x616263)" true \
  "safeTransferFrom answers true"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" "$safe_sig" "$sender" "$receiver" "$token_id" 5 0x616263)"
pf_evm_typed_event_check "$abi" "$receipt" TransferSingle "$topic_xfer" \
  "{\"operator\": \"$sender\", \"from\": \"$sender\", \"to\": \"$receiver\", \"id\": $token_id, \"value\": 5}" \
  "safeTransferFrom to a contract TransferSingle LOG4"
pf_evm_require_uint "$(balance_of "$receiver" "$token_id")" 5 "receiver credited"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 985 "sender debited"
pf_evm_require_equal "$(lower "$(seen 'seenOperator()(address)')")" "$(lower "$sender")" \
  "hook saw the operator"
pf_evm_require_equal "$(lower "$(seen 'seenFrom()(address)')")" "$(lower "$sender")" \
  "hook saw from"
pf_evm_require_uint "$(seen 'seenId()(uint256)')" "$token_id" "hook saw the id"
pf_evm_require_uint "$(seen 'seenValue()(uint256)')" 5 "hook saw the value"
pf_evm_require_equal "$(seen 'seenDataHash()(bytes32)')" "$("$cast" keccak 0x616263)" \
  "hook saw the bytes payload"
pf_evm_require_uint "$(seen 'seenBalance()(uint256)')" 5 \
  "hook read balanceOf and saw the credited balance (stores land before the CALL)"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" "$safe_sig" "$sender" "$receiver" "$token_id" 2 0x >/dev/null
pf_evm_require_uint "$(seen 'seenValue()(uint256)')" 2 "second hook saw its own value"
pf_evm_require_uint "$(seen 'seenBalance()(uint256)')" 7 \
  "second hook saw the running balance, not the amount"

# Operator path through the hook: the approved operator is operator, the holder is from.
"$cast" send --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" 'setApprovalForAll(address,bool)' "$sender" true >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" "$safe_sig" "$other" "$receiver" "$token_id" 1 0x >/dev/null
pf_evm_require_equal "$(lower "$(seen 'seenOperator()(address)')")" "$(lower "$sender")" \
  "hook saw the approved operator"
pf_evm_require_equal "$(lower "$(seen 'seenFrom()(address)')")" "$(lower "$other")" \
  "hook saw the holder as from"
pf_evm_require_uint "$(balance_of "$other" "$token_id")" 1 "holder debited by the operator"
pf_evm_require_uint "$(seen 'seenBalance()(uint256)')" 8 "hook saw the balance after the operator move"

# Every other answer is an empty revert that leaves both balances in place.
refuse() { # word size reverts label
  set_hook "$1" "$2" "$3"
  pf_evm_require_empty_revert "$addr" "$sender" \
    "$("$cast" calldata "$safe_sig" "$sender" "$receiver" "$token_id" 1 0x)" "$4"
  if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
      "$addr" "$safe_sig" "$sender" "$receiver" "$token_id" 1 0x >/dev/null 2>&1; then
    echo "FAIL: $4 passed the magic gate" >&2
    exit 1
  fi
  pf_evm_require_uint "$(balance_of "$receiver" "$token_id")" 8 "$4 left the receiver balance"
  pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 983 "$4 left the sender balance"
}
refuse "$("$python" -I -S -c "print(0xdeadbeef << 224)")" 32 false "a wrong selector"
refuse "$("$python" -I -S -c "print(($hook_word) | 1)")" 32 false "a dirty low byte"
refuse "$hook_word" 0 false "an empty frame"
refuse "$hook_word" 64 false "a two-word frame"
refuse "$hook_word" 32 true "a receiver reverting with the magic word"
set_hook "$hook_word" 32 false
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" "$safe_sig" "$sender" "$receiver" "$token_id" 1 0x >/dev/null
pf_evm_require_uint "$(balance_of "$receiver" "$token_id")" 9 \
  "hook accepted again once the magic frame is restored"

# The 32-byte data bound stands in front of the hook.
data32="0x$(printf '%02x' $(seq 1 32))"
pf_evm_require_empty_revert "$addr" "$sender" \
  "$("$cast" calldata "$safe_sig" "$sender" "$receiver" "$token_id" 1 "${data32}ff")" \
  "33 bytes of data exceed the bound"
pf_evm_require_uint "$(balance_of "$receiver" "$token_id")" 9 "refused data left the balance"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" "$safe_sig" "$sender" "$receiver" "$token_id" 1 "$data32" >/dev/null
pf_evm_require_equal "$(seen 'seenDataHash()(bytes32)')" "$("$cast" keccak "$data32")" \
  "hook saw all 32 data bytes"

echo "evm-anvil-crafttoken: ok (open capped mint/burn/safeTransferFrom/operator + ERC-1155 TransferSingle LOG4 / ApprovalForAll LOG3 + receiver hook: magic, running balance, operator, five refusals, data bound)"
