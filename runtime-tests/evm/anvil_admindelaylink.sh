#!/usr/bin/env bash
# AdminDelayLink: bounded delayed default-admin profile. Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-admindelaylink
bin="$root/build/evm/AdminDelayLink.bin"
abi="$root/build/evm/AdminDelayLink.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building AdminDelayLink.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" AdminDelayLink \
    || { echo "FAIL: pf build AdminDelayLink failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18700}" "$root/build/evm/anvil-admindelaylink.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty AdminDelayLink.bin" >&2; exit 1; }

sender="$("$cast" wallet address --private-key "$private_key")"
other_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
other="$("$cast" wallet address --private-key "$other_key")"
delay=60
encoded="$("$cast" abi-encode 'constructor(address,uint64)' "$sender" "$delay")"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${encoded#0x}")"
addr="$(printf '%s' "$receipt" | pf_evm_contract_address)"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'defaultAdmin()(address)')" \
  "$sender" "defaultAdmin after init"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'defaultAdminDelay()(uint64)')" \
  "$delay" "defaultAdminDelay"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'pendingDefaultAdmin()(address)')" \
  "0x0000000000000000000000000000000000000000" "no initial pending admin"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'beginDefaultAdminTransfer(address)' "$other" >/dev/null
schedule_raw="$("$cast" call --rpc-url "$rpc" "$addr" 'acceptSchedule()(uint64)')"
schedule="$(pf_evm_to_dec "$schedule_raw")"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'pendingDefaultAdmin()(address)')" \
  "$other" "pending admin after begin"
now="$("$cast" block latest --rpc-url "$rpc" --json |
  "$python" -I -S -c 'import json,sys; b=json.load(sys.stdin); ts=b["timestamp"]; print(int(ts,16) if isinstance(ts,str) and ts.startswith("0x") else int(ts))')"
pf_evm_require_equal "$schedule" "$(( now + delay ))" "acceptSchedule == now + delay"

if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'acceptDefaultAdminTransfer()' >/dev/null 2>&1; then
  echo "FAIL: accept before delay unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_ownable_unauthorized_account "$addr" "$other" \
  "$("$cast" calldata 'acceptDefaultAdminTransfer()')" "$other" \
  "accept before delay"

"$cast" rpc --rpc-url "$rpc" evm_increaseTime "$(( delay + 1 ))" >/dev/null
"$cast" rpc --rpc-url "$rpc" evm_mine >/dev/null

"$cast" send --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" 'acceptDefaultAdminTransfer()' >/dev/null
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'defaultAdmin()(address)')" \
  "$other" "defaultAdmin after accept"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'pendingDefaultAdmin()(address)')" \
  "0x0000000000000000000000000000000000000000" "pending cleared after accept"

"$cast" send --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" 'bump(uint64)' 3 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'get()(uint64)')" 3 "new admin bump"

echo "evm-anvil-admindelaylink: ok (delayed default-admin schedule/accept; engineering only)"
