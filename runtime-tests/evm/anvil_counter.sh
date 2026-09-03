#!/usr/bin/env bash
# Engineering Anvil gate for Counter. Darwin + Linux.
# Missing anvil/cast → skip (exit 0), not pass.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-counter
UINT64_MAX="18446744073709551615"
bin="$root/build/evm/Counter.bin"
pf_evm_ensure_bin "$bin"
pf_evm_start_anvil "${PF_EVM_PORT:-18547}" "$root/build/evm/anvil-counter.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty Counter.bin" >&2; exit 1; }

addr="$(pf_evm_deploy_ctor_u64 "$bytecode" 7)"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'get()(uint64)')" \
  7 "constructor state mismatch (view)"
pf_evm_require_storage "$addr" 0 7 "constructor state mismatch (storage)"

simulated="$("$cast" call --rpc-url "$rpc" "$addr" 'increment(uint64)(uint64)' 5)"
pf_evm_require_uint "$simulated" 12 "increment return mismatch"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'get()(uint64)')" \
  7 "eth_call increment unexpectedly committed state"

if "$cast" send --rpc-url "$rpc" --private-key "$private_key" --value 2 \
    "$addr" 'increment(uint64)' 5 >/dev/null 2>&1; then
  echo "FAIL: nonpayable increment unexpectedly accepted value" >&2
  exit 1
fi
encoded7="$("$cast" abi-encode 'constructor(uint64)' 7)"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" --value 1 --create \
    "0x${bytecode}${encoded7#0x}" >/dev/null 2>&1; then
  echo "FAIL: nonpayable constructor unexpectedly accepted value" >&2
  exit 1
fi

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'increment(uint64)' 5 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'get()(uint64)')" \
  12 "increment state mismatch (view)"
pf_evm_require_storage "$addr" 0 12 "increment state mismatch (storage)"
pf_evm_require_equal "$(pf_evm_to_dec "$("$cast" balance --rpc-url "$rpc" "$addr")")" \
  0 "contract accepted native value"

max_addr="$(pf_evm_deploy_ctor_u64 "$bytecode" "$UINT64_MAX")"
pf_evm_require_storage "$max_addr" 0 "$UINT64_MAX" "max constructor storage"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$max_addr" 'increment(uint64)' 1 >/dev/null 2>&1; then
  echo "FAIL: overflow increment unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_storage "$max_addr" 0 "$UINT64_MAX" "overflow must leave slot 0"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$max_addr" 'get()(uint64)')" \
  "$UINT64_MAX" "overflow changed view state"

echo "evm-anvil-counter: ok (ctor/get/increment/overflow hold; engineering only)"
