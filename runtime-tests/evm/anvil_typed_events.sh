#!/usr/bin/env bash
# Typed events: address-indexed + uint256 data, boolean data, nested-ite Ticked once, and
# receipt decoding driven by the generated ABI JSON (topic0 signature, indexed geometry, canonical
# words).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-typed-events
bin="$root/build/evm/EvmTypedEvents.bin"
abi="$root/build/evm/EvmTypedEvents.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  lake build Examples.Evm.EvmTypedEvents >/dev/null
  lake exe pf -- build --target evm --out "$root/build/evm" EvmTypedEvents >/dev/null
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18689}" "$root/build/evm/anvil-typed-events.log"

pf_typed_event_sig() { pf_evm_typed_event_sig "$abi" "$1"; }
pf_typed_event_check() { pf_evm_typed_event_check "$abi" "$@"; }

bytecode="$(tr -d '\n\r ' < "$bin")"
sender="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_u64 "$bytecode" 0)"

pf_evm_require_storage "$addr" 0 0 "constructor ticks"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'ticksOf()(uint64)')" 0 \
  "initial ticks"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'flagOf()(bool)')" false \
  "initial flag"

dest_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
dest="$("$cast" wallet address --private-key "$dest_key")"

# The ABI JSON is the source of truth for signatures; pin them against the spec'd shapes too.
sig_xfer="$(pf_typed_event_sig Transferred)"
sig_flag="$(pf_typed_event_sig Flagged)"
sig_tick="$(pf_typed_event_sig Ticked)"
pf_evm_require_equal "$sig_xfer" 'Transferred(address,address,uint256)' "ABI Transferred signature"
pf_evm_require_equal "$sig_flag" 'Flagged(bool)' "ABI Flagged signature"
pf_evm_require_equal "$sig_tick" 'Ticked(uint64)' "ABI Ticked signature"
topic_xfer="$("$cast" keccak "$sig_xfer")"
topic_flag="$("$cast" keccak "$sig_flag")"
topic_tick="$("$cast" keccak "$sig_tick")"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'transfer(address,address,uint256)' "$sender" "$dest" 42)"
pf_typed_event_check "$receipt" Transferred "$topic_xfer" \
  "{\"from\": \"$sender\", \"to\": \"$dest\", \"value\": 42}" "Transferred LOG3"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'setFlag(bool)' true)"
pf_typed_event_check "$receipt" Flagged "$topic_flag" '{"ok": true}' "Flagged(true) LOG1"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'flagOf()(bool)')" true \
  "flag persisted"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'setFlag(bool)' false)"
pf_typed_event_check "$receipt" Flagged "$topic_flag" '{"ok": false}' "Flagged(false) LOG1"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'flagOf()(bool)')" false \
  "flag cleared"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'pulse(uint64)' 0)"
pf_typed_event_check "$receipt" Ticked "$topic_tick" '{"n": 0}' "Ticked n=0 branch"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'ticksOf()(uint64)')" 0 \
  "ticks untouched on n=0 branch"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'pulse(uint64)' 7)"
pf_typed_event_check "$receipt" Ticked "$topic_tick" '{"n": 7}' "Ticked n!=0 branch"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'ticksOf()(uint64)')" 7 \
  "ticks persisted from n!=0 branch"

echo "evm-anvil-typed-events: ok (ABI-decoded Transferred LOG3 + Flagged bool + nested Ticked; engineering only)"
