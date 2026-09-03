#!/usr/bin/env bash
# CraftToken: open-mint bounded ERC-1155 consumer with per-id supply cap. Darwin + Linux.
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
  lake build Examples.CraftToken >/dev/null \
    || { echo "FAIL: lake build Examples.CraftToken failed" >&2; exit 1; }
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
  "$addr" 'transferFrom(address,address,uint256,uint256)' \
  "$other" "$sender" "$token_id" 3)"
pf_evm_typed_event_check "$abi" "$receipt" TransferSingle "$topic_xfer" \
  "{\"operator\": \"$other\", \"from\": \"$other\", \"to\": \"$sender\", \"id\": $token_id, \"value\": 3}" \
  "owner transferFrom TransferSingle LOG4"
pf_evm_require_uint "$(balance_of "$other" "$token_id")" 4 "source after transfer"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 996 "destination after transfer"

# Same-address transfer keeps the balance.
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'transferFrom(address,address,uint256,uint256)' \
  "$sender" "$sender" "$token_id" 100)"
pf_evm_typed_event_check "$abi" "$receipt" TransferSingle "$topic_xfer" \
  "{\"operator\": \"$sender\", \"from\": \"$sender\", \"to\": \"$sender\", \"id\": $token_id, \"value\": 100}" \
  "self transferFrom TransferSingle LOG4"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 996 "self transfer keeps balance"

# Unauthorized operator rejected; approval lets the operator move; revoke restores rejection.
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'transferFrom(address,address,uint256,uint256)' \
    "$other" "$sender" "$token_id" 1 >/dev/null 2>&1; then
  echo "FAIL: unauthorized operator transfer unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_unauthorized "$addr" "$sender" \
  "$("$cast" calldata 'transferFrom(address,address,uint256,uint256)' \
    "$other" "$sender" "$token_id" 1)" "$sender" "unauthorized operator transfer"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" 'setApprovalForAll(address,bool)' "$sender" true)"
pf_evm_typed_event_check "$abi" "$receipt" ApprovalForAll "$topic_op" \
  "{\"account\": \"$other\", \"operator\": \"$sender\", \"approved\": true}" \
  "setApprovalForAll(true) LOG3"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'transferFrom(address,address,uint256,uint256)' \
  "$other" "$sender" "$token_id" 2)"
pf_evm_typed_event_check "$abi" "$receipt" TransferSingle "$topic_xfer" \
  "{\"operator\": \"$sender\", \"from\": \"$other\", \"to\": \"$sender\", \"id\": $token_id, \"value\": 2}" \
  "operator transferFrom TransferSingle LOG4"
pf_evm_require_uint "$(balance_of "$other" "$token_id")" 2 "source after operator transfer"
pf_evm_require_uint "$(balance_of "$sender" "$token_id")" 998 \
  "destination after operator transfer"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" 'setApprovalForAll(address,bool)' "$sender" false)"
pf_evm_typed_event_check "$abi" "$receipt" ApprovalForAll "$topic_op" \
  "{\"account\": \"$other\", \"operator\": \"$sender\", \"approved\": false}" \
  "setApprovalForAll(false) LOG3"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'transferFrom(address,address,uint256,uint256)' \
    "$other" "$sender" "$token_id" 1 >/dev/null 2>&1; then
  echo "FAIL: revoked operator transfer unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_uint "$(balance_of "$other" "$token_id")" 2 "revoke left source untouched"

# Underflow: other holds 2, moving 3 fails the debit gate without writes.
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'transferFrom(address,address,uint256,uint256)' \
    "$other" "$sender" "$token_id" 3 >/dev/null 2>&1; then
  echo "FAIL: underflow transfer unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_insufficient "$addr" "$other" \
  "$("$cast" calldata 'transferFrom(address,address,uint256,uint256)' \
    "$other" "$sender" "$token_id" 3)" 2 3 "underflow transfer"
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

echo "evm-anvil-crafttoken: ok (open capped mint/burn/transferFrom/operator + ERC-1155 TransferSingle LOG4 / ApprovalForAll LOG3)"
