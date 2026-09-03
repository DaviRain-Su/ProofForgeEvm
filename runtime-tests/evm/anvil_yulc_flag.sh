#!/usr/bin/env bash
# Dual-backend Anvil gate: Flag u8 mask with solc vs yulc bytecode (E-B3).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"
# shellcheck source=runtime-tests/evm/lib_yulc.sh
source "$here/lib_yulc.sh"

pf_evm_evm_init evm-anvil-yulc-flag
pf_evm_yulc_or_skip evm-anvil-yulc-flag

out="$root/build/evm-yulc-anvil-flag"
pf_evm_dual_build_program Flag "$out"
pf_evm_dual_bytecode_note evm-anvil-yulc-flag

pf_evm_start_anvil "${PF_EVM_PORT:-18593}" "$root/build/evm/anvil-yulc-flag.log"

run_flag_suite() {
  local label="$1" bytecode="$2"
  local addr
  addr="$(pf_evm_deploy_ctor_u64 "$bytecode" 7)"

  pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'getFlag()(uint64)')" \
    0 "$label: ctor getFlag"
  pf_evm_require_storage "$addr" 0 0 "$label: ctor flag slot"
  pf_evm_require_storage "$addr" 1 7 "$label: ctor count slot"

  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'setFlag(uint64)' 1 >/dev/null
  pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'getFlag()(uint64)')" \
    1 "$label: setFlag view"
  pf_evm_require_storage "$addr" 0 1 "$label: setFlag flag"
  pf_evm_require_storage "$addr" 1 7 "$label: setFlag keeps count"

  if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
      "$addr" 'setFlag(uint64)' 256 >/dev/null 2>&1; then
    echo "FAIL: $label setFlag(256) should revert" >&2
    exit 1
  fi
  pf_evm_require_storage "$addr" 0 1 "$label: overflow holds flag"
  echo "$addr"
}

solc_addr="$(run_flag_suite solc "$SOLC_HEX")"
yulc_addr="$(run_flag_suite yulc "$YULC_HEX")"

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$solc_addr" 'getFlag()(uint64)')" \
  "$("$cast" call --rpc-url "$rpc" "$yulc_addr" 'getFlag()(uint64)')" \
  "solc vs yulc final getFlag mismatch"

echo "evm-anvil-yulc-flag: ok (dual-backend behavior match; engineering only)"
