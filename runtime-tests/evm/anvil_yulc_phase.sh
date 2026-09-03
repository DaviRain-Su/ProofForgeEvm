#!/usr/bin/env bash
# Dual-backend Anvil gate: Phase variant tags with solc vs yulc bytecode (E-B3).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"
# shellcheck source=runtime-tests/evm/lib_yulc.sh
source "$here/lib_yulc.sh"

pf_evm_evm_init evm-anvil-yulc-phase
pf_evm_yulc_or_skip evm-anvil-yulc-phase

out="$root/build/evm-yulc-anvil-phase"
pf_evm_dual_build_program Phase "$out"
pf_evm_dual_bytecode_note evm-anvil-yulc-phase

pf_evm_start_anvil "${PF_EVM_PORT:-18594}" "$root/build/evm/anvil-yulc-phase.log"

run_phase_suite() {
  local label="$1" bytecode="$2"
  local addr simulated_live simulated_idle
  addr="$(pf_evm_deploy_ctor_u64 "$bytecode" 42)"

  pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'isLive()(uint64)')" \
    0 "$label: constructor isLive"
  pf_evm_require_storage "$addr" 0 0 "$label: constructor idle tag"

  simulated_live="$("$cast" call --rpc-url "$rpc" "$addr" 'setLive(uint64)(uint64)' 9)"
  pf_evm_require_uint "$simulated_live" 1 "$label: setLive return"
  pf_evm_require_storage "$addr" 0 0 "$label: eth_call setLive does not commit"

  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'setLive(uint64)' 9 >/dev/null
  pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'isLive()(uint64)')" \
    1 "$label: setLive isLive"
  pf_evm_require_storage "$addr" 0 1 "$label: setLive live tag"

  simulated_idle="$("$cast" call --rpc-url "$rpc" "$addr" 'setIdle()(uint64)')"
  pf_evm_require_uint "$simulated_idle" 0 "$label: setIdle return"
  pf_evm_require_storage "$addr" 0 1 "$label: eth_call setIdle does not commit"

  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'setIdle()' >/dev/null
  pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'isLive()(uint64)')" \
    0 "$label: setIdle isLive"
  echo "$addr"
}

solc_addr="$(run_phase_suite solc "$SOLC_HEX")"
yulc_addr="$(run_phase_suite yulc "$YULC_HEX")"

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$solc_addr" 'isLive()(uint64)')" \
  "$("$cast" call --rpc-url "$rpc" "$yulc_addr" 'isLive()(uint64)')" \
  "solc vs yulc final isLive mismatch"

echo "evm-anvil-yulc-phase: ok (dual-backend behavior match; engineering only)"
