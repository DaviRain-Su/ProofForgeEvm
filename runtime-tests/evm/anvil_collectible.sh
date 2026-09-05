#!/usr/bin/env bash
# Collectible: owner mint, approve, transferFrom over Erc721 ledger, and the safeTransferFrom
# receiver hook against a Solidity receiver. Darwin + Linux.
# Receipts are ABI-decoded: ERC-721 Transfer/Approval are LOG4 (indexed tokenId, empty data).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

# Pack a 20-byte address into the ProofForge UInt256 limb layout (LE w0/w1/w2).
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

pf_evm_evm_init evm-anvil-collectible
bin="$root/build/evm/Collectible.bin"
abi="$root/build/evm/Collectible.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building Collectible.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" Collectible \
    || { echo "FAIL: pf build Collectible failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18570}" "$root/build/evm/anvil-collectible.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty Collectible.bin" >&2; exit 1; }

sender="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_address "$bytecode" "$sender")"
other_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
other="$("$cast" wallet address --private-key "$other_key")"
token_id=1
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
sig_appr="$(pf_evm_typed_event_sig "$abi" Approval)"
pf_evm_require_equal "$sig_xfer" 'Transfer(address,address,uint256)' "ABI Transfer signature"
pf_evm_require_equal "$sig_appr" 'Approval(address,address,uint256)' "ABI Approval signature"
topic_xfer="$("$cast" keccak "$sig_xfer")"
topic_appr="$("$cast" keccak "$sig_appr")"

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$sender")" \
  0 "absent minter balance"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'ownerOf(uint256)(uint256)' "$token_id")" \
  0 "absent token owner"

if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'mint(address,uint256)' "0x0000000000000000000000000000000000000000" "$token_id" \
    >/dev/null 2>&1; then
  echo "FAIL: mint to zero unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_zero_address "$addr" "$sender" \
  "$("$cast" calldata 'mint(address,uint256)' \
    '0x0000000000000000000000000000000000000000' "$token_id")" \
  "mint to zero"

if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'mint(address,uint256)' "$other" "$token_id" >/dev/null 2>&1; then
  echo "FAIL: non-owner mint unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_unauthorized "$addr" "$other" \
  "$("$cast" calldata 'mint(address,uint256)' "$other" "$token_id")" "$other" \
  "non-owner mint"

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

if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'mint(address,uint256)' "$sender" "$token_id" >/dev/null 2>&1; then
  echo "FAIL: duplicate mint unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_unauthorized "$addr" "$sender" \
  "$("$cast" calldata 'mint(address,uint256)' "$sender" "$token_id")" "$sender" \
  "duplicate mint"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'approve(address,uint256)' "$other" "$token_id")"
pf_evm_typed_event_check "$abi" "$receipt" Approval "$topic_appr" \
  "{\"owner\": \"$sender\", \"approved\": \"$other\", \"tokenId\": $token_id}" \
  "approve Approval LOG4"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'getApproved(uint256)(uint256)' "$token_id")" \
  "$other_packed" "approved spender"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" 'transferFrom(address,address,uint256)' "$sender" "$other" "$token_id")"
pf_evm_typed_event_check "$abi" "$receipt" Transfer "$topic_xfer" \
  "{\"from\": \"$sender\", \"to\": \"$other\", \"tokenId\": $token_id}" \
  "transferFrom Transfer LOG4"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'ownerOf(uint256)(uint256)' "$token_id")" \
  "$other_packed" "owner after transfer"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$sender")" \
  0 "sender balance after transfer"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$other")" \
  1 "recipient balance after transfer"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'getApproved(uint256)(uint256)' "$token_id")" \
  0 "approval cleared"

# tokenKey drops w3; ownerOf/getApproved must not alias id with id+2^192.
alias_id="$("$python" -I -S -c "print($token_id + (1 << 192))")"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'ownerOf(uint256)(uint256)' "$alias_id")" \
  0 "ownerOf rejects unencodable alias"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'getApproved(uint256)(uint256)' "$alias_id")" \
  0 "getApproved rejects unencodable alias"
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'transferFrom(address,address,uint256)' "$other" "$sender" "$alias_id" \
    >/dev/null 2>&1; then
  echo "FAIL: transferFrom on unencodable alias unexpectedly succeeded" >&2
  exit 1
fi

if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'transferFrom(address,address,uint256)' "$other" "$sender" "$token_id" \
    >/dev/null 2>&1; then
  echo "FAIL: unauthorized transfer unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_unauthorized "$addr" "$sender" \
  "$("$cast" calldata 'transferFrom(address,address,uint256)' "$other" "$sender" "$token_id")" \
  "$sender" "unauthorized transfer"

# safeTransferFrom: a recipient with code must answer onERC721Received with its own selector.
# The Solidity receiver records the hook's arguments, reads ownerOf back through msg.sender while
# the transfer is still running, and answers with a settable frame, so the right magic, a wrong
# selector, a dirty low byte, an empty frame, a two-word frame, and a revert carrying the magic
# word are each driven. Every refusal is an empty revert that leaves the owner in place; a
# recipient without code is never called.
solc_bin="$(pf_evm_find_tool solc)" || {
  echo "evm-anvil-collectible: skip: solc not found, safeTransferFrom receiver hook not driven" >&2
  echo "evm-anvil-collectible: ok (mint/approve/transferFrom + ERC-721 Transfer/Approval LOG4; safeTransferFrom skipped)"
  exit 0
}
"$solc_bin" --bin --optimize --overwrite -o "$root/build/evm" "$here/ReceiverMock.sol" >/dev/null
mock_bin="$root/build/evm/ReceiverMock.bin"
[[ -f "$mock_bin" ]] || { echo "FAIL: missing ReceiverMock.bin" >&2; exit 1; }
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x$(tr -d '\n\r ' < "$mock_bin")")"
receiver="$(printf '%s' "$receipt" | pf_evm_contract_address)"
receiver_packed="$(pf_pack_addr_u256 "$receiver")"
hook_word="$("$python" -I -S -c \
  "print(int('$("$cast" sig 'onERC721Received(address,address,uint256,bytes)')', 16) << 224)")"
safe_sig='safeTransferFrom(address,address,uint256,bytes)'

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
owner_of() { # id
  "$cast" call --rpc-url "$rpc" "$addr" 'ownerOf(uint256)(uint256)' "$1"
}
mint_to_sender() { # id
  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'mint(address,uint256)' "$sender" "$1" >/dev/null
}

set_hook "$hook_word" 32 false
mint_to_sender 2
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" --from "$sender" "$addr" \
  "$safe_sig(bool)" "$sender" "$receiver" 2 0x616263)" true "safeTransferFrom answers true"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" "$safe_sig" "$sender" "$receiver" 2 0x616263)"
pf_evm_typed_event_check "$abi" "$receipt" Transfer "$topic_xfer" \
  "{\"from\": \"$sender\", \"to\": \"$receiver\", \"tokenId\": 2}" \
  "safeTransferFrom Transfer LOG4"
pf_evm_require_uint "$(owner_of 2)" "$receiver_packed" "owner after safeTransferFrom to a contract"
pf_evm_require_equal "$(lower "$(seen 'seenOperator()(address)')")" "$(lower "$sender")" \
  "hook saw the operator"
pf_evm_require_equal "$(lower "$(seen 'seenFrom()(address)')")" "$(lower "$sender")" \
  "hook saw from"
pf_evm_require_uint "$(seen 'seenId()(uint256)')" 2 "hook saw the token id"
pf_evm_require_equal "$(seen 'seenDataHash()(bytes32)')" "$("$cast" keccak 0x616263)" \
  "hook saw the bytes payload"
pf_evm_require_uint "$(seen 'seenOwnerWord()(uint256)')" "$receiver_packed" \
  "hook read ownerOf and saw itself (stores land before the CALL)"

# Operator path: the approved spender is the operator, the owner is from.
mint_to_sender 6
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'approve(address,uint256)' "$other" 6 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" "$safe_sig" "$sender" "$receiver" 6 0x >/dev/null
pf_evm_require_equal "$(lower "$(seen 'seenOperator()(address)')")" "$(lower "$other")" \
  "hook saw the approved spender as operator"
pf_evm_require_equal "$(lower "$(seen 'seenFrom()(address)')")" "$(lower "$sender")" \
  "hook saw the owner as from"
pf_evm_require_equal "$(seen 'seenDataHash()(bytes32)')" "$("$cast" keccak 0x)" \
  "hook saw the empty payload"

# A recipient without code is not called.
mint_to_sender 3
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" "$safe_sig" "$sender" "$other" 3 0x >/dev/null
pf_evm_require_uint "$(owner_of 3)" "$other_packed" "safeTransferFrom to an EOA skips the hook"

# Every other answer is an empty revert that leaves the owner in place.
mint_to_sender 4
refuse() { # word size reverts label
  set_hook "$1" "$2" "$3"
  pf_evm_require_empty_revert "$addr" "$sender" \
    "$("$cast" calldata "$safe_sig" "$sender" "$receiver" 4 0x)" "$4"
  if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
      "$addr" "$safe_sig" "$sender" "$receiver" 4 0x >/dev/null 2>&1; then
    echo "FAIL: $4 passed the magic gate" >&2
    exit 1
  fi
  pf_evm_require_uint "$(owner_of 4)" "$sender_packed" "$4 left the owner in place"
}
refuse "$("$python" -I -S -c "print(0xdeadbeef << 224)")" 32 false "a wrong selector"
refuse "$("$python" -I -S -c "print(($hook_word) | 1)")" 32 false "a dirty low byte"
refuse "$hook_word" 0 false "an empty frame"
refuse "$hook_word" 64 false "a two-word frame"
refuse "$hook_word" 32 true "a receiver reverting with the magic word"
set_hook "$hook_word" 32 false
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" "$safe_sig" "$sender" "$receiver" 4 0x >/dev/null
pf_evm_require_uint "$(seen 'seenId()(uint256)')" 4 \
  "hook accepted again once the magic frame is restored"

# The entry's own gates still stand in front of the hook: authorization, the zero address, and
# the 32-byte data bound.
mint_to_sender 5
pf_evm_require_unauthorized "$addr" "$other" \
  "$("$cast" calldata "$safe_sig" "$sender" "$receiver" 5 0x)" "$other" \
  "unauthorized safeTransferFrom"
pf_evm_require_zero_address "$addr" "$sender" \
  "$("$cast" calldata "$safe_sig" "$sender" "$zero" 5 0x)" "safeTransferFrom to zero"
data32="0x$(printf '%02x' $(seq 1 32))"
pf_evm_require_empty_revert "$addr" "$sender" \
  "$("$cast" calldata "$safe_sig" "$sender" "$receiver" 5 "${data32}ff")" \
  "33 bytes of data exceed the bound"
pf_evm_require_uint "$(owner_of 5)" "$sender_packed" "refused data left the owner in place"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" "$safe_sig" "$sender" "$receiver" 5 "$data32" >/dev/null
pf_evm_require_equal "$(seen 'seenDataHash()(bytes32)')" "$("$cast" keccak "$data32")" \
  "hook saw all 32 data bytes"

# Three-argument overload: empty data, same hook, selector 0x42842e0e.
safe3_sig='safeTransferFrom(address,address,uint256)'
"$python" -I -S -c "
import json, sys
abi=json.load(open('$abi'))
ins=[tuple(i['type'] for i in e.get('inputs',[]))
     for e in abi if e.get('type')=='function' and e.get('name')=='safeTransferFrom']
if ('address','address','uint256') not in ins:
    sys.stderr.write('FAIL: Collectible ABI lost safeTransferFrom(address,address,uint256)\\n')
    sys.exit(1)
if ('address','address','uint256','bytes') not in ins:
    sys.stderr.write('FAIL: Collectible ABI lost safeTransferFrom(address,address,uint256,bytes)\\n')
    sys.exit(1)
"
set_hook "$hook_word" 32 false
mint_to_sender 7
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" --from "$sender" "$addr" \
  "$safe3_sig(bool)" "$sender" "$receiver" 7)" true \
  "safeTransferFrom(address,address,uint256) answers true"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" "$safe3_sig" "$sender" "$receiver" 7 >/dev/null
pf_evm_require_uint "$(owner_of 7)" "$receiver_packed" \
  "owner after three-argument safeTransferFrom to a contract"
pf_evm_require_equal "$(seen 'seenDataHash()(bytes32)')" "$("$cast" keccak 0x)" \
  "three-argument overload forwarded empty data"
mint_to_sender 8
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" "$safe3_sig" "$sender" "$other" 8 >/dev/null
pf_evm_require_uint "$(owner_of 8)" "$other_packed" \
  "three-argument safeTransferFrom to an EOA skips the hook"

yul="$root/build/evm/Collectible.yul"
if [[ ! -f "$yul" ]]; then
  echo "building Collectible.yul" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" Collectible \
    || { echo "FAIL: pf build Collectible failed" >&2; exit 1; }
fi
[[ -f "$yul" ]] || { echo "FAIL: missing $yul" >&2; exit 1; }
mut_dir="$root/build/evm/collectible-safe3-mut"
rm -rf "$mut_dir"
mkdir -p "$mut_dir"
"$python" -I -S -c "
from pathlib import Path
import sys
src = Path('$yul').read_text()
n = src.count('case 0x42842e0e')
if n != 1:
    sys.stderr.write(f'FAIL: expected one case 0x42842e0e, got {n}\\n')
    sys.exit(1)
out = src.replace('case 0x42842e0e', 'case 0xdeadbeef', 1)
if out == src:
    sys.stderr.write('FAIL: 3-arg selector rewrite missed\\n')
    sys.exit(1)
Path('$mut_dir/Collectible.yul').write_text(out)
"
mut_code="$("$solc_bin" --strict-assembly --optimize --evm-version cancun --bin \
  "$mut_dir/Collectible.yul" | "$python" -I -S -c "
import sys
lines=[ln.strip() for ln in sys.stdin.read().splitlines() if ln.strip()]
hexes=[ln for ln in lines if len(ln)>100 and all(c in '0123456789abcdefABCDEF' for c in ln)]
if not hexes:
    raise SystemExit('FAIL: solc --strict-assembly wrote no 3-arg-mut bytecode')
print(hexes[-1])
")"
[[ -n "$mut_code" ]] || { echo "FAIL: empty mutated Collectible bytecode" >&2; exit 1; }
mut_addr="$(pf_evm_deploy_ctor_address "$mut_code" "$sender")"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$mut_addr" 'mint(address,uint256)' "$sender" 9 >/dev/null
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$mut_addr" "$safe3_sig" "$sender" "$receiver" 9 >/dev/null 2>&1; then
  echo "FAIL: mutated 3-arg selector still transferred" >&2
  exit 1
fi
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$mut_addr" \
  'ownerOf(uint256)(uint256)' 9)" "$sender_packed" \
  "rewrote 3-arg selector left the owner in place"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$mut_addr" "$safe_sig" "$sender" "$receiver" 9 0x >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$mut_addr" \
  'ownerOf(uint256)(uint256)' 9)" "$receiver_packed" \
  "4-arg safeTransferFrom still moves after the 3-arg selector rewrite"

echo "evm-anvil-collectible: ok (mint/approve/transferFrom + ERC-721 Transfer/Approval LOG4 + safeTransferFrom receiver hook: magic, operator, EOA skip, five refusals, data bound, three-argument overload, 3-arg selector mutation)"
