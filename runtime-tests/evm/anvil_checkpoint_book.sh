#!/usr/bin/env bash
# Owner-gated capacity-4 bounded UInt64 checkpoints: append, same-key overwrite, latest/lower
# lookup, authorization, full/decreasing distinctions, and anvil_setStorageAt corruption probes.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-checkpoint-book
bin="$root/build/evm/EvmCheckpointBook.bin"
if [[ ! -f "$bin" ]]; then
  lake build Examples.EvmCheckpointBook >/dev/null
  lake exe pf -- build --target evm --out "$root/build/evm" EvmCheckpointBook >/dev/null
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18686}" "$root/build/evm/anvil-checkpoint-book.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
sender="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_address "$bytecode" "$sender")"

for slot in 3 4 5 6 7 8 9 10 11; do
  pf_evm_require_storage "$addr" "$slot" 0 "constructor zero checkpoint state"
done
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'countOf()(uint64)')" 0 \
  "empty count"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'latestValue()(uint64)')" 0 \
  "empty latest fallback"

other_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
other="$("$cast" wallet address --private-key "$other_key")"
pf_evm_require_unauthorized "$addr" "$other" \
  "$("$cast" calldata 'push(uint64,uint64)' 10 100)" "$other" "non-admin checkpoint push"
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'push(uint64,uint64)' 10 100 >/dev/null 2>&1; then
  echo "FAIL: non-admin checkpoint push unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_storage "$addr" 11 0 "unauthorized push holds count"

# Append two ordered checkpoints, then overwrite the latest key without growing count.
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" --from "$sender" "$addr" \
  'push(uint64,uint64)(uint64)' 10 100)" 1 "first append returns count"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'push(uint64,uint64)' 10 100 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'push(uint64,uint64)' 20 200 >/dev/null
pf_evm_require_storage "$addr" 3 10 "first key"
pf_evm_require_storage "$addr" 4 20 "second key"
pf_evm_require_storage "$addr" 7 100 "first value"
pf_evm_require_storage "$addr" 8 200 "second value"
pf_evm_require_storage "$addr" 11 2 "two-checkpoint count"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'push(uint64,uint64)' 20 250 >/dev/null
pf_evm_require_storage "$addr" 8 250 "same-key overwrite replaces latest value"
pf_evm_require_storage "$addr" 11 2 "same-key overwrite does not grow count"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'latestValue()(uint64)')" 250 \
  "latest after overwrite"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'lowerValue(uint64)(uint64)' 0)" 100 "lower bound below first"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'lowerValue(uint64)(uint64)' 11)" 250 "lower bound between checkpoints"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'lowerValue(uint64)(uint64)' 21)" 0 "lower bound above latest"

# Decreasing keys have a typed ordered-key rejection before capacity is reached.
pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'push(uint64,uint64)' 19 190)" 'unordered()' "decreasing key"

# Fill the static trace. Valid growth beyond capacity is CapExceeded, while a decreasing key
# remains unordered even when the trace is full. Same-latest overwrite remains valid at full.
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'push(uint64,uint64)' 30 300 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'push(uint64,uint64)' 40 400 >/dev/null
pf_evm_require_storage "$addr" 11 4 "full checkpoint count"
pf_evm_require_cap_exceeded "$addr" "$sender" \
  "$("$cast" calldata 'push(uint64,uint64)' 50 500)" "full checkpoint growth"
pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'push(uint64,uint64)' 39 390)" 'unordered()' "full decreasing key"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'push(uint64,uint64)' 40 444 >/dev/null
pf_evm_require_storage "$addr" 10 444 "full latest overwrite"
pf_evm_require_storage "$addr" 11 4 "full overwrite holds count"

# Corrupt count through Anvil's test-only storage RPC. Views fail closed and mutation does not
# repair or partially overwrite any key/value slot.
pf_evm_set_storage_word "$addr" 11 5
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'latestValue()(uint64)')" 0 \
  "malformed count closes latest view"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'lowerValue(uint64)(uint64)' 10)" 0 "malformed count closes lower view"
pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'push(uint64,uint64)' 50 500)" 'malformed()' "malformed count push"
pf_evm_require_storage "$addr" 11 5 "malformed push does not repair count"
pf_evm_require_storage "$addr" 10 444 "malformed push holds latest value"

# Restore a two-item count but forge duplicate live keys. Strict ordering is part of canonical
# storage, so both views and writes fail closed rather than accepting or repairing it.
pf_evm_set_storage_word "$addr" 11 2
pf_evm_set_storage_word "$addr" 4 10
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'latestValue()(uint64)')" 0 \
  "duplicate stored key closes latest view"
pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'push(uint64,uint64)' 20 999)" 'malformed()' "duplicate stored key push"
pf_evm_require_storage "$addr" 4 10 "malformed ordering is not repaired"
pf_evm_require_storage "$addr" 8 250 "malformed ordering holds value"

echo "evm-anvil-checkpoint-book: ok (owner + append/overwrite/latest/lower + full/order + count/key corruption; engineering only)"
