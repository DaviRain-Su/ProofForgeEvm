#!/usr/bin/env bash
# VestLink: bounded single-beneficiary native-ETH vesting + EtherReleased. Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-vestlink
bin="$root/build/evm/VestLink.bin"
abi="$root/build/evm/VestLink.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building VestLink.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" VestLink \
    || { echo "FAIL: pf build VestLink failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18696}" "$root/build/evm/anvil-vestlink.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty VestLink.bin" >&2; exit 1; }

beneficiary="$("$cast" wallet address --private-key "$private_key")"
now_block="$(pf_evm_to_dec "$("$cast" block --rpc-url "$rpc" latest --json | "$python" -I -S -c 'import json,sys; print(json.load(sys.stdin)["timestamp"])')")"
start_ts=$((now_block + 100))
duration=1000
encoded="$("$cast" abi-encode 'constructor(address,uint64,uint64)' "$beneficiary" "$start_ts" "$duration")"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${encoded#0x}")"
addr="$(printf '%s' "$receipt" | pf_evm_contract_address)"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'beneficiary()(address)')" \
  "$beneficiary" "immutable beneficiary"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'start()(uint256)')" \
  "$start_ts" "constructor start"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'duration()(uint256)')" \
  "$duration" "constructor duration"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'endTime()(uint256)')" \
  "$((start_ts + duration))" "start + duration"

# Before start nothing is releasable.
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasable()(uint256)')" \
  0 "nothing releasable before start"

# Fund the vesting wallet with 1 ETH; still locked until start.
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$addr" --value 1ether >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasable()(uint256)')" \
  0 "funded but still before start"

# After end, the full allocation is releasable.
after_end=$((start_ts + duration + 1))
"$cast" rpc --rpc-url "$rpc" evm_setNextBlockTimestamp "$after_end" >/dev/null
"$cast" rpc --rpc-url "$rpc" evm_mine >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasable()(uint256)')" \
  1000000000000000000 "fully vested after end"

topic0="$("$cast" keccak 'EtherReleased(uint256)')"
release_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'release(uint256)' 1000000000000000000)"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasedOf()(uint256)')" \
  1000000000000000000 "released counter updated"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasable()(uint256)')" \
  0 "nothing left after full release"
pf_evm_typed_event_check "$abi" "$release_receipt" EtherReleased "$topic0" \
  '{"amount": 1000000000000000000}' "release after end"

# Zero beneficiary fails closed on schedule views.
zero="0x0000000000000000000000000000000000000000"
zero_encoded="$("$cast" abi-encode 'constructor(address,uint64,uint64)' "$zero" "$start_ts" "$duration")"
zero_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${zero_encoded#0x}")"
zero_addr="$(printf '%s' "$zero_receipt" | pf_evm_contract_address)"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$zero_addr" 'start()(uint256)')" \
  0 "zero beneficiary fails closed on start"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$zero_addr" 'releasable()(uint256)')" \
  0 "zero beneficiary fails closed on releasable"

echo "evm-anvil-vestlink: ok (bounded single-beneficiary native-ETH vesting + EtherReleased)"
