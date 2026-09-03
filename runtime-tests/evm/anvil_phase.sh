#!/usr/bin/env bash
# Phase: zero-payload variant tag transitions. Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-phase
bin="$root/build/evm/Phase.bin"
pf_evm_ensure_bin "$bin"
pf_evm_start_anvil "${PF_EVM_PORT:-18558}" "$root/build/evm/anvil-phase.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
addr="$(pf_evm_deploy_ctor_u64 "$bytecode" 42)"

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'isLive()(uint64)')" \
  0 "constructor isLive"
pf_evm_require_storage "$addr" 0 0 "constructor idle tag"

simulated_live="$("$cast" call --rpc-url "$rpc" "$addr" 'setLive(uint64)(uint64)' 9)"
pf_evm_require_uint "$simulated_live" 1 "setLive return"
pf_evm_require_storage "$addr" 0 0 "eth_call setLive does not commit"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'setLive(uint64)' 9 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'isLive()(uint64)')" \
  1 "setLive isLive"
pf_evm_require_storage "$addr" 0 1 "setLive live tag"

simulated_idle="$("$cast" call --rpc-url "$rpc" "$addr" 'setIdle()(uint64)')"
pf_evm_require_uint "$simulated_idle" 0 "setIdle return"
pf_evm_require_storage "$addr" 0 1 "eth_call setIdle does not commit"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'setIdle()' >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'isLive()(uint64)')" \
  0 "setIdle isLive"
pf_evm_require_storage "$addr" 0 0 "setIdle idle tag"

echo "evm-anvil-phase: ok (idle/live tag transitions; engineering only)"
