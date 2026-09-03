#!/usr/bin/env bash
# EvmQuota: bounded per-address nonces plus fixed-window rate limit (Nonces + RateLimit SDK).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_quota_available() {
  local addr="$1" who="$2"
  local capacity window lastUsed lastTime now effWindow usedNow
  capacity="$(pf_evm_to_dec "$("$cast" call --rpc-url "$rpc" "$addr" 'capacityOf()(uint64)')")"
  window="$(pf_evm_to_dec "$("$cast" call --rpc-url "$rpc" "$addr" 'windowOf()(uint64)')")"
  lastUsed="$(pf_evm_to_dec "$("$cast" call --rpc-url "$rpc" "$addr" 'lastUsedOf(address)(uint64)' "$who")")"
  lastTime="$(pf_evm_to_dec "$("$cast" call --rpc-url "$rpc" "$addr" 'lastTimepointOf(address)(uint64)' "$who")")"
  now="$("$cast" block --rpc-url "$rpc" latest --json | "$python" -I -S -c 'import json,sys; print(json.load(sys.stdin)["timestamp"])')"
  effWindow="$window"
  if [[ "$window" == "0" ]]; then effWindow=1; fi
  usedNow="$lastUsed"
  if [[ "$now" -gt "$lastTime" ]] && [[ $((now - lastTime)) -ge $effWindow ]]; then
    usedNow=0
  fi
  if [[ "$usedNow" -ge "$capacity" ]]; then
    echo 0
  else
    echo $((capacity - usedNow))
  fi
}

pf_evm_evm_init evm-anvil-evmquota
bin="$root/build/evm/EvmQuota.bin"
abi="$root/build/evm/EvmQuota.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building EvmQuota.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" EvmQuota \
    || { echo "FAIL: pf build EvmQuota failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
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
pf_evm_require_uint "$(pf_evm_quota_available "$addr" "$sender")" \
  5 "initial quota available"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalActionsOf()(uint64)')" \
  0 "initial action count"

# Successful act: nonce 0, amount 2.
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'act(uint256,uint64)' 0 2 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'noncesOf(address)(uint256)' "$sender")" \
  1 "nonce after act"
windowStart="$("$cast" call --rpc-url "$rpc" "$addr" \
  'lastTimepointOf(address)(uint64)' "$sender")"
pf_evm_require_uint "$(pf_evm_quota_available "$addr" "$sender")" \
  3 "quota after act"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalActionsOf()(uint64)')" \
  1 "action count after act"

# Stale nonce reverts Insufficient(current, provided) until dedicated invalidNonce lowering lands.
pf_evm_require_word_revert "$addr" "$sender" \
  "$("$cast" calldata 'act(uint256,uint64)' 0 1)" 'Insufficient(uint256,uint256)' \
  "stale nonce" 1 0
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalActionsOf()(uint64)')" \
  1 "stale nonce is atomic"

# Consume remaining quota (nonce 1, amount 3).
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'act(uint256,uint64)' 1 3 >/dev/null
pf_evm_require_uint "$(pf_evm_quota_available "$addr" "$sender")" \
  0 "quota exhausted"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'lastTimepointOf(address)(uint64)' "$sender")" "$windowStart" \
  "within-window consume preserves window start"

# Zero quantity is admissible even when full and leaves the limiter entry unchanged.
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'act(uint256,uint64)' 2 0 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'lastUsedOf(address)(uint64)' "$sender")" 5 "zero quantity preserves usage"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'lastTimepointOf(address)(uint64)' "$sender")" "$windowStart" \
  "zero quantity preserves window start"

# Rate limit exceeded on nonce 3.
pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'act(uint256,uint64)' 3 1)" 'rateLimitExceeded()' \
  "rate limit exceeded"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'noncesOf(address)(uint256)' "$sender")" \
  3 "rate limit failure is atomic on nonce"

echo "evm-anvil-evmquota: ok (Nonces + RateLimit fixed-window quota; engineering only)"
