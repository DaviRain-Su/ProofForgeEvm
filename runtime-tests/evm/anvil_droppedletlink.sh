#!/usr/bin/env bash
# DroppedLetLink: a map write in an unused let still persists when the if skips count.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-droppedletlink
echo "building DroppedLetLink" >&2
lake exe pf -- build --target evm --out "$root/build/evm" DroppedLetLink \
  || { echo "FAIL: pf build DroppedLetLink failed" >&2; exit 1; }
bin="$root/build/evm/DroppedLetLink.bin"
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18711}" "$root/build/evm/anvil-droppedletlink.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty DroppedLetLink.bin" >&2; exit 1; }
addr="$(pf_evm_deploy_ctor_u64 "$bytecode" 0)"

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'countOf()(uint64)')" \
  0 "ctor count"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'get(uint64)(uint64)' 7)" \
  0 "ctor map miss"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'putThenGuard(uint64,uint64,uint64)(bool)' 1 7 70)" false \
  "flag 1 returns false"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'putThenGuard(uint64,uint64,uint64)' 1 7 70 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'get(uint64)(uint64)' 7)" \
  70 "flag 1 still writes the map"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'countOf()(uint64)')" \
  0 "flag 1 keeps count"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'putThenGuard(uint64,uint64,uint64)(bool)' 0 8 80)" true \
  "flag 0 returns true"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'putThenGuard(uint64,uint64,uint64)' 0 8 80 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'get(uint64)(uint64)' 8)" \
  80 "flag 0 writes the map"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'countOf()(uint64)')" \
  1 "flag 0 increments count"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'get(uint64)(uint64)' 7)" \
  70 "flag 0 keeps the earlier map write"

echo "evm-anvil-droppedletlink: ok (unused let map write before if; both flags persist the put)"
