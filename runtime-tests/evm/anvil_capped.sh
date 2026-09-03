#!/usr/bin/env bash
# Capped: owner + pause + fixed cap, no hashed map. Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-capped
bin="$root/build/evm/Capped.bin"
pf_evm_ensure_bin "$bin"
pf_evm_start_anvil "${PF_EVM_PORT:-18559}" "$root/build/evm/anvil-capped.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty Capped.bin" >&2; exit 1; }

sender="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_address "$bytecode" "$sender")"
other_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
other="$("$cast" wallet address --private-key "$other_key")"

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

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'pause()' >/dev/null
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
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'unpause()' >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'pausedOf()(uint8)')" \
  0 "unpaused"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(uint256)' 60 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'totalSupply()(uint256)')" \
  100 "mint to cap"

echo "evm-anvil-capped: ok (owner/pause/cap; engineering only)"
