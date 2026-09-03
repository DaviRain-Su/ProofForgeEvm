#!/usr/bin/env bash
# Window: fixed Vector leaves and dynamic update. Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-window
bin="$root/build/evm/Window.bin"
pf_evm_ensure_bin "$bin"
pf_evm_start_anvil "${PF_EVM_PORT:-18557}" "$root/build/evm/anvil-window.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
addr="$(pf_evm_deploy_ctor_u64 "$bytecode" 7)"

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'getHead()(uint64)')" \
  7 "constructor getHead"
pf_evm_require_storage "$addr" 0 7 "constructor head"
pf_evm_require_storage "$addr" 1 0 "constructor tail"

simulated="$("$cast" call --rpc-url "$rpc" "$addr" 'setTail(uint64)(uint64)' 9)"
pf_evm_require_uint "$simulated" 9 "setTail return"
pf_evm_require_storage "$addr" 0 7 "eth_call keeps head"
pf_evm_require_storage "$addr" 1 0 "eth_call does not commit tail"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'setTail(uint64)' 9 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'getHead()(uint64)')" \
  7 "setTail keeps getHead"
pf_evm_require_storage "$addr" 0 7 "setTail keeps head"
pf_evm_require_storage "$addr" 1 9 "setTail writes tail"

echo "evm-anvil-window: ok (ctor/vector set/head hold; engineering only)"
