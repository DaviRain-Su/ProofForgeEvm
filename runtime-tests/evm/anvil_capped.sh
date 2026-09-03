#!/usr/bin/env bash
# Capped: owner + pause + fixed cap, no hashed map. Darwin + Linux.
# Receipts are ABI-decoded: Paused/Unpaused are LOG1 (non-indexed account).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-capped
bin="$root/build/evm/Capped.bin"
abi="$root/build/evm/Capped.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building Capped.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" Capped \
    || { echo "FAIL: pf build Capped failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18559}" "$root/build/evm/anvil-capped.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty Capped.bin" >&2; exit 1; }

sender="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_address "$bytecode" "$sender")"
other_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
other="$("$cast" wallet address --private-key "$other_key")"

sig_paused="$(pf_evm_typed_event_sig "$abi" Paused)"
sig_unpaused="$(pf_evm_typed_event_sig "$abi" Unpaused)"
pf_evm_require_equal "$sig_paused" 'Paused(address)' "ABI Paused signature"
pf_evm_require_equal "$sig_unpaused" 'Unpaused(address)' "ABI Unpaused signature"
topic_paused="$("$cast" keccak "$sig_paused")"
topic_unpaused="$("$cast" keccak "$sig_unpaused")"

got_owner="$("$cast" call --rpc-url "$rpc" "$addr" 'ownerOf()(address)')"
pf_evm_require_equal "${got_owner,,}" "${sender,,}" "ownerOf"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'pausedOf()(uint8)')" \
  0 "initial paused"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'capOf()(uint256)')" \
  100 "fixed mint cap"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'totalSupply()(uint256)')" \
  0 "initial supply"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(uint256)' 40 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'totalSupply()(uint256)')" \
  40 "owner mint"

if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'mint(uint256)' 1 >/dev/null 2>&1; then
  echo "FAIL: non-owner mint unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_unauthorized "$addr" "$other" \
  "$("$cast" calldata 'mint(uint256)' 1)" "$other" \
  "non-owner mint"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'totalSupply()(uint256)')" \
  40 "non-owner mint holds supply"

if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'mint(uint256)' 61 >/dev/null 2>&1; then
  echo "FAIL: mint over cap unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_cap_exceeded "$addr" "$sender" \
  "$("$cast" calldata 'mint(uint256)' 61)" \
  "mint over cap"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'totalSupply()(uint256)')" \
  40 "mint over cap holds supply"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'capOf()(uint256)')" \
  100 "cap holds after over-mint"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'pause()')"
pf_evm_typed_event_check "$abi" "$receipt" Paused "$topic_paused" \
  "{\"account\": \"$sender\"}" \
  "pause Paused LOG1"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'pausedOf()(uint8)')" \
  1 "paused after pause"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'mint(uint256)' 1 >/dev/null 2>&1; then
  echo "FAIL: mint while paused unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_paused "$addr" "$sender" \
  "$("$cast" calldata 'mint(uint256)' 1)" \
  "mint while paused"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'totalSupply()(uint256)')" \
  40 "pause holds supply"
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'unpause()' >/dev/null 2>&1; then
  echo "FAIL: non-owner unpause unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_unauthorized "$addr" "$other" \
  "$("$cast" calldata 'unpause()')" "$other" \
  "non-owner unpause"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'unpause()')"
pf_evm_typed_event_check "$abi" "$receipt" Unpaused "$topic_unpaused" \
  "{\"account\": \"$sender\"}" \
  "unpause Unpaused LOG1"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'pausedOf()(uint8)')" \
  0 "unpaused"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(uint256)' 60 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'totalSupply()(uint256)')" \
  100 "mint to cap"

echo "evm-anvil-capped: ok (owner/pause/cap + Paused/Unpaused LOG1)"
