#!/usr/bin/env bash
# ClockLink: IERC6372 clock() + CLOCK_MODE() block-number profile. Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-clocklink
bin="$root/build/evm/ClockLink.bin"
abi="$root/build/evm/ClockLink.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building ClockLink.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" ClockLink \
    || { echo "FAIL: pf build ClockLink failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18697}" "$root/build/evm/anvil-clocklink.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty ClockLink.bin" >&2; exit 1; }

sender="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_address "$bytecode" "$sender")"

strip_string() {
  local s="$1"
  s="${s#\"}"; s="${s%\"}"
  printf '%s' "$s"
}

block="$("$cast" block-number --rpc-url "$rpc")"
got_clock="$("$cast" call --rpc-url "$rpc" "$addr" 'clock()(uint256)')"
pf_evm_require_uint "$got_clock" "$block" "clock matches block number"
pf_evm_require_equal "$(strip_string "$("$cast" call --rpc-url "$rpc" "$addr" \
  'CLOCK_MODE()(string)')")" \
  "mode=blocknumber&from=default" "bounded CLOCK_MODE string"

echo "evm-anvil-clocklink: ok (IERC6372 block-number clock + CLOCK_MODE)"
