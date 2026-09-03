#!/usr/bin/env bash
# EvmQuota: bounded per-address nonces plus fixed-window rate limit (Nonces + RateLimit SDK).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-evmquota
bin="$root/build/evm/EvmQuota.bin"
abi="$root/build/evm/EvmQuota.abi.json"
pf_evm_ensure_bin "$bin"
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18565}" "$root/build/evm/anvil-evmquota.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
sender="$("$cast" wallet address --private-key "$private_key")"
encoded="$("$cast" abi-encode 'constructor(uint64,uint64,address)' 5 3600 "$sender")"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${encoded#0x}")"
addr="$(printf '%s' "$receipt" | pf_evm_contract_address)"

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'noncesOf(address)(uint256)' "$sender")" \
  0 "initial nonce"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'availableOf(address)(uint64)' "$sender")" \
  5 "initial quota available"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalActionsOf()(uint64)')" \
  0 "initial action count"

# Successful act: nonce 0, amount 2.
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'act(uint256,uint64)' 0 2 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'noncesOf(address)(uint256)' "$sender")" \
  1 "nonce after act"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'availableOf(address)(uint64)' "$sender")" \
  3 "quota after act"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalActionsOf()(uint64)')" \
  1 "action count after act"

# Stale nonce reverts invalidNonce(current, expected).
pf_evm_require_word_revert "$addr" "$sender" \
  "$("$cast" calldata 'act(uint256,uint64)' 0 1)" 'invalidNonce(uint256,uint256)' \
  "stale nonce" 0 1
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalActionsOf()(uint64)')" \
  1 "stale nonce is atomic"

# Consume remaining quota (nonce 1, amount 3).
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'act(uint256,uint64)' 1 3 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'availableOf(address)(uint64)' "$sender")" \
  0 "quota exhausted"

# Rate limit exceeded on nonce 2.
pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'act(uint256,uint64)' 2 1)" 'rateLimitExceeded()' \
  "rate limit exceeded"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'noncesOf(address)(uint256)' "$sender")" \
  2 "rate limit failure is atomic on nonce"

echo "evm-anvil-evmquota: ok (Nonces + RateLimit fixed-window quota; engineering only)"
