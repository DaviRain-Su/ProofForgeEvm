#!/usr/bin/env bash
# MultiToken: owner-minted bounded ERC-1155 core consumer. Darwin + Linux.
# Receipts are ABI-decoded: TransferSingle LOG4 (id+value data), TransferBatch LOG4 (two
# uint256[] tails), and ApprovalForAll LOG3.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-multitoken
bin="$root/build/evm/MultiToken.bin"
abi="$root/build/evm/MultiToken.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building registered MultiToken.bin" >&2
  lake build Examples.Evm.MultiToken >/dev/null \
    || { echo "FAIL: lake build Examples.Evm.MultiToken failed" >&2; exit 1; }
  lake exe pf -- build --target evm --out "$root/build/evm" MultiToken >/dev/null \
    || { echo "FAIL: build registered MultiToken failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18574}" "$root/build/evm/anvil-multitoken.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty MultiToken.bin" >&2; exit 1; }

sender="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_address "$bytecode" "$sender")"
other_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
other="$("$cast" wallet address --private-key "$other_key")"
token_id=7
alias_id="$("$python" -I -S -c "print($token_id + (1 << 192))")"
zero="0x0000000000000000000000000000000000000000"

supports_interface() { # interface id
  "$cast" call --rpc-url "$rpc" "$addr" 'supportsInterface(bytes4)(bool)' "$1"
}
pf_evm_require_equal "$(supports_interface 0x01ffc9a7)" true "IERC165 support"
pf_evm_require_equal "$(supports_interface 0xd9b67a26)" false "incomplete IERC1155 is unsupported"
pf_evm_require_equal "$(supports_interface 0x80ac58cd)" false "IERC721 is unsupported"
pf_evm_require_equal "$(supports_interface 0xffffffff)" false "ERC-165 invalid interface id"
pf_evm_require_equal "$(supports_interface 0xdeadbeef)" false "unknown interface id"

sig_xfer="$(pf_evm_typed_event_sig "$abi" TransferSingle)"
sig_batch="$(pf_evm_typed_event_sig "$abi" TransferBatch)"
sig_op="$(pf_evm_typed_event_sig "$abi" ApprovalForAll)"
pf_evm_require_equal "$sig_xfer" 'TransferSingle(address,address,address,uint256,uint256)' \
  "ABI TransferSingle signature"
pf_evm_require_equal "$sig_batch" 'TransferBatch(address,address,address,uint256[],uint256[])' \
  "ABI TransferBatch signature"
pf_evm_require_equal "$sig_op" 'ApprovalForAll(address,address,bool)' \
  "ABI ApprovalForAll signature"
topic_xfer="$("$cast" keccak "$sig_xfer")"
topic_batch="$("$cast" keccak "$sig_batch")"
topic_op="$("$cast" keccak "$sig_op")"
# The ERC-1155 TransferBatch topic0 every indexer matches on.
pf_evm_require_equal "$topic_batch" \
  0x4a39dc06d4c0dbc64b70af90fd698a233a518aa5d07e595d983b8c0526c8f7fb "TransferBatch topic0"

balance_of() { # owner id
  pf_evm_to_dec "$("$cast" call --rpc-url "$rpc" "$addr" \
    'balanceOf(address,uint256)(uint256)' "$1" "$2")"
}

pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 0 "absent balance"

# Zero recipient mint → ZeroAddress().
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'mint(address,uint256,uint256)' "$zero" "$token_id" 1 >/dev/null 2>&1; then
  echo "FAIL: mint to zero unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_zero_address "$addr" "$sender" \
  "$("$cast" calldata 'mint(address,uint256,uint256)' "$zero" "$token_id" 1)" \
  "mint to zero"

# Non-minter mint → Unauthorized(other).
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'mint(address,uint256,uint256)' "$other" "$token_id" 1 >/dev/null 2>&1; then
  echo "FAIL: non-minter mint unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_unauthorized "$addr" "$other" \
  "$("$cast" calldata 'mint(address,uint256,uint256)' "$other" "$token_id" 1)" "$other" \
  "non-minter mint"

# Unencodable id (id + 2^192) mint → Unauthorized; the view must not alias a live id.
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'mint(address,uint256,uint256)' "$sender" "$alias_id" 1 >/dev/null 2>&1; then
  echo "FAIL: mint on unencodable alias unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_unauthorized "$addr" "$sender" \
  "$("$cast" calldata 'mint(address,uint256,uint256)' "$sender" "$alias_id" 1)" "$sender" \
  "unencodable alias mint"
pf_evm_require_uint "$(balance_of "$sender" "$alias_id")" 0 "alias balance view gated"

# Owner mint 100 of id 7.
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(address,uint256,uint256)' "$sender" "$token_id" 100)"
pf_evm_typed_event_check "$abi" "$receipt" TransferSingle "$topic_xfer" \
  "{\"operator\": \"$sender\", \"from\": \"$zero\", \"to\": \"$sender\", \"id\": $token_id, \"value\": 100}" \
  "mint TransferSingle LOG4"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 100 "balance after mint"
pf_evm_require_uint "$(balance_of "$sender" "$alias_id")" 0 \
  "alias does not see minted balance"

# Credit overflow: mint 2^256-10 of a fresh id, then +20 must wrap → Unauthorized, no write.
big_id=8
near_max="$("$python" -I -S -c "print((1 << 256) - 10)")"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(address,uint256,uint256)' "$sender" "$big_id" "$near_max" >/dev/null
pf_evm_require_uint "$(balance_of "$sender" "$big_id")" "$near_max" "near-max balance"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'mint(address,uint256,uint256)' "$sender" "$big_id" 20 >/dev/null 2>&1; then
  echo "FAIL: wrapping credit unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_uint "$(balance_of "$sender" "$big_id")" "$near_max" \
  "overflow mint left balance untouched"

# Cross-owner movement: sender moves 40 to other.
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'transferFrom(address,address,uint256,uint256)' \
  "$sender" "$other" "$token_id" 40)"
pf_evm_typed_event_check "$abi" "$receipt" TransferSingle "$topic_xfer" \
  "{\"operator\": \"$sender\", \"from\": \"$sender\", \"to\": \"$other\", \"id\": $token_id, \"value\": 40}" \
  "transferFrom TransferSingle LOG4"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 60 "source after transfer"
pf_evm_require_uint "$(balance_of "$other" "$token_id")" 40 "destination after transfer"

# Same-address transfer is a successful no-op after the debit gate (still logs).
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'transferFrom(address,address,uint256,uint256)' \
  "$sender" "$sender" "$token_id" 15)"
pf_evm_typed_event_check "$abi" "$receipt" TransferSingle "$topic_xfer" \
  "{\"operator\": \"$sender\", \"from\": \"$sender\", \"to\": \"$sender\", \"id\": $token_id, \"value\": 15}" \
  "self transferFrom TransferSingle LOG4"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 60 "self transfer keeps balance"

# Underflow: other owns 40, moving 41 as the owner passes auth but fails the debit gate.
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'transferFrom(address,address,uint256,uint256)' \
    "$other" "$sender" "$token_id" 41 >/dev/null 2>&1; then
  echo "FAIL: underflow transfer unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_insufficient "$addr" "$other" \
  "$("$cast" calldata 'transferFrom(address,address,uint256,uint256)' \
    "$other" "$sender" "$token_id" 41)" 40 41 "underflow transfer"
pf_evm_require_uint "$(balance_of "$other" "$token_id")" 40 "underflow left source untouched"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 60 \
  "underflow left destination untouched"

# Unauthorized operator: other cannot move sender funds without approval.
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'transferFrom(address,address,uint256,uint256)' \
    "$sender" "$other" "$token_id" 1 >/dev/null 2>&1; then
  echo "FAIL: unauthorized operator transfer unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_unauthorized "$addr" "$other" \
  "$("$cast" calldata 'transferFrom(address,address,uint256,uint256)' \
    "$sender" "$other" "$token_id" 1)" "$other" "unauthorized operator transfer"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 60 \
  "unauthorized transfer left source untouched"

# Approve operator, operator moves 5, revoke, operator is rejected again.
approved="$("$cast" call --rpc-url "$rpc" "$addr" \
  'isApprovedForAll(address,address)(bool)' "$sender" "$other")"
if [[ "${approved,,}" == "true" ]]; then
  echo "FAIL: operator unexpectedly approved" >&2
  exit 1
fi
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'setApprovalForAll(address,bool)' "$other" true)"
pf_evm_typed_event_check "$abi" "$receipt" ApprovalForAll "$topic_op" \
  "{\"account\": \"$sender\", \"operator\": \"$other\", \"approved\": true}" \
  "setApprovalForAll(true) LOG3"
approved="$("$cast" call --rpc-url "$rpc" "$addr" \
  'isApprovedForAll(address,address)(bool)' "$sender" "$other")"
if [[ "${approved,,}" != "true" ]]; then
  echo "FAIL: operator not approved (got $approved)" >&2
  exit 1
fi
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" 'transferFrom(address,address,uint256,uint256)' \
  "$sender" "$other" "$token_id" 5)"
pf_evm_typed_event_check "$abi" "$receipt" TransferSingle "$topic_xfer" \
  "{\"operator\": \"$other\", \"from\": \"$sender\", \"to\": \"$other\", \"id\": $token_id, \"value\": 5}" \
  "operator transferFrom TransferSingle LOG4"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 55 "source after operator transfer"
pf_evm_require_uint "$(balance_of "$other" "$token_id")" 45 \
  "destination after operator transfer"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'setApprovalForAll(address,bool)' "$other" false)"
pf_evm_typed_event_check "$abi" "$receipt" ApprovalForAll "$topic_op" \
  "{\"account\": \"$sender\", \"operator\": \"$other\", \"approved\": false}" \
  "setApprovalForAll(false) LOG3"
approved="$("$cast" call --rpc-url "$rpc" "$addr" \
  'isApprovedForAll(address,address)(bool)' "$sender" "$other")"
if [[ "${approved,,}" == "true" ]]; then
  echo "FAIL: operator approval not revoked" >&2
  exit 1
fi
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'transferFrom(address,address,uint256,uint256)' \
    "$sender" "$other" "$token_id" 5 >/dev/null 2>&1; then
  echo "FAIL: revoked operator transfer unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 55 "revoke left source untouched"
pf_evm_require_uint "$(balance_of "$other" "$token_id")" 45 "revoke left dest untouched"

# Burn: owner debits self; underflow and unencodable ids fail without writes.
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'burn(uint256,uint256)' "$token_id" 5)"
pf_evm_typed_event_check "$abi" "$receipt" TransferSingle "$topic_xfer" \
  "{\"operator\": \"$sender\", \"from\": \"$sender\", \"to\": \"$zero\", \"id\": $token_id, \"value\": 5}" \
  "burn TransferSingle to zero LOG4"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 50 "balance after burn"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'burn(uint256,uint256)' "$token_id" 51 >/dev/null 2>&1; then
  echo "FAIL: underflow burn unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_insufficient "$addr" "$sender" \
  "$("$cast" calldata 'burn(uint256,uint256)' "$token_id" 51)" 50 51 "underflow burn"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 50 "underflow burn untouched"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'burn(uint256,uint256)' "$alias_id" 1 >/dev/null 2>&1; then
  echo "FAIL: burn on unencodable alias unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_unauthorized "$addr" "$sender" \
  "$("$cast" calldata 'burn(uint256,uint256)' "$alias_id" 1)" "$sender" \
  "unencodable alias burn"

# Transfer to the zero address → ZeroAddress().
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'transferFrom(address,address,uint256,uint256)' \
    "$sender" "$zero" "$token_id" 1 >/dev/null 2>&1; then
  echo "FAIL: transfer to zero unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_zero_address "$addr" "$sender" \
  "$("$cast" calldata 'transferFrom(address,address,uint256,uint256)' \
    "$sender" "$zero" "$token_id" 1)" "transfer to zero"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 50 \
  "zero-address transfer left source untouched"

# Bounded balanceOfBatch: capacity 4, one checked single-id read per slot.
balance_of_batch() { # owners ids
  "$cast" call --rpc-url "$rpc" "$addr" \
    'balanceOfBatch(address[],uint256[])(uint256[])' "$1" "$2"
}
pf_evm_require_equal "$(balance_of_batch "[$sender,$other]" "[$token_id,$token_id]")" \
  "[50, 45]" "balanceOfBatch matches the two single reads"
pf_evm_require_equal "$(balance_of_batch "[$other]" "[$token_id]")" \
  "[45]" "one-element batch"
pf_evm_require_equal "$(balance_of_batch "[$sender,$other,$sender,$zero]" \
  "[$token_id,$alias_id,0,$token_id]")" "[50, 0, 0, 0]" \
  "full-capacity batch: unencodable alias and unknown pairs read zero"
pf_evm_require_equal "$(balance_of_batch "[]" "[]")" "[]" "empty batch"
pf_evm_require_equal "$(balance_of_batch "[$sender]" "[$token_id,$token_id]")" "[]" \
  "unequal batch lengths answer an empty array"
pf_evm_require_equal "$(balance_of_batch "[$sender,$other]" "[$token_id]")" "[]" \
  "unequal batch lengths answer an empty array (more owners)"
if "$cast" call --rpc-url "$rpc" "$addr" 'balanceOfBatch(address[],uint256[])(uint256[])' \
    "[$sender,$other,$sender,$other,$sender]" "[$token_id,$token_id,$token_id,$token_id,$token_id]" \
    >/dev/null 2>&1; then
  echo "FAIL: five-element batch exceeded capacity 4 but decoded" >&2
  exit 1
fi

# Bounded batchTransferFrom: capacity 4, OZ check order, OZ log rule (a one-slot batch logs
# TransferSingle, any other length logs one TransferBatch whose arrays are the submitted slots).
# State here: sender holds 50 of id 7 and near_max of id 8; other holds 45 of id 7.
second_id=9
batch_calldata() { # source to ids amounts
  "$cast" calldata 'batchTransferFrom(address,address,uint256[],uint256[])' "$1" "$2" "$3" "$4"
}
batch_send() { # key source to ids amounts
  "$cast" send --json --rpc-url "$rpc" --private-key "$1" \
    "$addr" 'batchTransferFrom(address,address,uint256[],uint256[])' "$2" "$3" "$4" "$5"
}
batch_must_fail() { # key source to ids amounts label
  if "$cast" send --rpc-url "$rpc" --private-key "$1" \
      "$addr" 'batchTransferFrom(address,address,uint256[],uint256[])' "$2" "$3" "$4" "$5" \
      >/dev/null 2>&1; then
    echo "FAIL: $6 unexpectedly succeeded" >&2
    exit 1
  fi
}
sig_len_mismatch='ERC1155InvalidArrayLength(uint256,uint256)'
sig_short='ERC1155InsufficientBalance(address,uint256,uint256,uint256)'
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(address,uint256,uint256)' "$sender" "$second_id" 30 >/dev/null

batch_must_fail "$other_key" "$sender" "$other" "[$token_id]" "[1]" "unauthorized batch"
pf_evm_require_unauthorized "$addr" "$other" \
  "$(batch_calldata "$sender" "$other" "[$token_id]" "[1]")" "$other" "unauthorized batch"
batch_must_fail "$private_key" "$sender" "$other" "[$alias_id]" "[1]" "unencodable alias batch"
pf_evm_require_unauthorized "$addr" "$sender" \
  "$(batch_calldata "$sender" "$other" "[$token_id,$alias_id]" "[1,1]")" "$sender" \
  "unencodable alias in a batch"
batch_must_fail "$private_key" "$sender" "$zero" "[$token_id]" "[1]" "batch to zero"
pf_evm_require_zero_address "$addr" "$sender" \
  "$(batch_calldata "$sender" "$zero" "[$token_id]" "[1]")" "batch to zero"
batch_must_fail "$private_key" "$sender" "$other" "[$token_id,$second_id]" "[1]" \
  "batch length mismatch"
pf_evm_require_word_revert "$addr" "$sender" \
  "$(batch_calldata "$sender" "$other" "[$token_id,$second_id]" "[1]")" "$sig_len_mismatch" \
  "batch length mismatch (2 ids, 1 amount)" 2 1
pf_evm_require_word_revert "$addr" "$sender" \
  "$(batch_calldata "$sender" "$other" "[]" "[1]")" "$sig_len_mismatch" \
  "batch length mismatch (0 ids, 1 amount)" 0 1
batch_must_fail "$private_key" "$sender" "$other" "[$token_id,$token_id]" "[1,1]" \
  "duplicate id batch"
pf_evm_require_named_revert "$addr" "$sender" \
  "$(batch_calldata "$sender" "$other" "[$token_id,$second_id,$token_id]" "[1,1,1]")" \
  'DuplicateId()' "duplicate id in slot 2"
# Slot 0 would pass; slot 1 is short. Nothing is written before every slot is checked.
batch_must_fail "$private_key" "$sender" "$other" "[$token_id,$second_id]" "[10,31]" \
  "short second slot"
pf_evm_require_word_revert "$addr" "$sender" \
  "$(batch_calldata "$sender" "$other" "[$token_id,$second_id]" "[10,31]")" "$sig_short" \
  "short second slot reverts with its balance and need" "$sender" 30 31 "$second_id"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 50 "short batch left slot 0 untouched"
pf_evm_require_uint "$(balance_of "$other" "$token_id")" 45 "short batch left slot 0 destination"
# A credit that would wrap the destination stops in the checked add256 of the slot's
# pre-check, the same empty revert the single mint above takes; nothing is written.
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(address,uint256,uint256)' "$other" "$big_id" 20 >/dev/null
batch_must_fail "$private_key" "$sender" "$other" "[$big_id]" "[$near_max]" "wrapping batch credit"
pf_evm_require_empty_revert "$addr" "$sender" \
  "$(batch_calldata "$sender" "$other" "[$token_id,$big_id]" "[1,$near_max]")" \
  "wrapping batch credit in slot 1 is the checked-add revert"
pf_evm_require_uint "$(balance_of "$other" "$big_id")" 20 "wrapping batch left destination"
pf_evm_require_uint "$(balance_of "$sender" "$big_id")" "$near_max" "wrapping batch left source"

receipt="$(batch_send "$private_key" "$sender" "$other" "[$token_id,$second_id]" "[10,30]")"
pf_evm_typed_event_check "$abi" "$receipt" TransferBatch "$topic_batch" \
  "{\"operator\": \"$sender\", \"from\": \"$sender\", \"to\": \"$other\", \"ids\": [$token_id, $second_id], \"values\": [10, 30]}" \
  "two-slot batch TransferBatch LOG4"
pf_evm_typed_event_absent "$receipt" TransferSingle "$topic_xfer" \
  "two-slot batch logs no TransferSingle"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 40 "batch source slot 0"
pf_evm_require_uint "$(balance_of "$other" "$token_id")" 55 "batch destination slot 0"
pf_evm_require_uint "$(balance_of "$sender" "$second_id")" 0 "batch source slot 1"
pf_evm_require_uint "$(balance_of "$other" "$second_id")" 30 "batch destination slot 1"
pf_evm_require_equal "$(balance_of_batch "[$sender,$other,$sender,$other]" \
  "[$token_id,$token_id,$second_id,$second_id]")" "[40, 55, 0, 30]" \
  "balanceOfBatch reflects the batch transfer"

# Empty batch: authorized no-op that logs a TransferBatch with two empty arrays, as OZ does.
# A one-slot batch takes the OZ TransferSingle branch; zero amounts on a held id move nothing.
receipt="$(batch_send "$private_key" "$sender" "$other" "[]" "[]")"
pf_evm_typed_event_check "$abi" "$receipt" TransferBatch "$topic_batch" \
  "{\"operator\": \"$sender\", \"from\": \"$sender\", \"to\": \"$other\", \"ids\": [], \"values\": []}" \
  "empty batch TransferBatch LOG4"
pf_evm_typed_event_absent "$receipt" TransferSingle "$topic_xfer" "empty batch logs no TransferSingle"
receipt="$(batch_send "$private_key" "$sender" "$other" "[$token_id]" "[0]")"
pf_evm_typed_event_check "$abi" "$receipt" TransferSingle "$topic_xfer" \
  "{\"operator\": \"$sender\", \"from\": \"$sender\", \"to\": \"$other\", \"id\": $token_id, \"value\": 0}" \
  "one-slot batch logs TransferSingle"
pf_evm_typed_event_absent "$receipt" TransferBatch "$topic_batch" \
  "one-slot batch logs no TransferBatch"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 40 "zero-amount slot moves nothing"

# Operator batch at full capacity, then revoked. other holds 55 of id 7 and 30 of id 9.
third_id=10
fourth_id=11
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(address,uint256,uint256)' "$other" "$third_id" 3 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(address,uint256,uint256)' "$other" "$fourth_id" 4 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" 'setApprovalForAll(address,bool)' "$sender" true >/dev/null
receipt="$(batch_send "$private_key" "$other" "$sender" \
  "[$token_id,$second_id,$third_id,$fourth_id]" "[5,30,3,4]")"
pf_evm_typed_event_check "$abi" "$receipt" TransferBatch "$topic_batch" \
  "{\"operator\": \"$sender\", \"from\": \"$other\", \"to\": \"$sender\", \"ids\": [$token_id, $second_id, $third_id, $fourth_id], \"values\": [5, 30, 3, 4]}" \
  "full-capacity operator batch TransferBatch LOG4"
pf_evm_typed_event_absent "$receipt" TransferSingle "$topic_xfer" \
  "full-capacity batch logs no TransferSingle"
pf_evm_require_equal "$(balance_of_batch "[$sender,$sender,$sender,$sender]" \
  "[$token_id,$second_id,$third_id,$fourth_id]")" "[45, 30, 3, 4]" \
  "operator batch credited every slot"
pf_evm_require_equal "$(balance_of_batch "[$other,$other,$other,$other]" \
  "[$token_id,$second_id,$third_id,$fourth_id]")" "[50, 0, 0, 0]" \
  "operator batch debited every slot"
"$cast" send --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" 'setApprovalForAll(address,bool)' "$sender" false >/dev/null
batch_must_fail "$private_key" "$other" "$sender" "[$token_id]" "[1]" "revoked operator batch"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'batchTransferFrom(address,address,uint256[],uint256[])' "$sender" "$other" \
    "[$token_id,$second_id,$third_id,$fourth_id,$token_id]" "[1,1,1,1,1]" >/dev/null 2>&1; then
  echo "FAIL: five-slot batch exceeded capacity 4 but decoded" >&2
  exit 1
fi

echo "evm-anvil-multitoken: ok (mint/burn/transferFrom/operator/balanceOfBatch/batchTransferFrom + ERC-1155 TransferSingle LOG4 / TransferBatch LOG4 / ApprovalForAll LOG3)"
