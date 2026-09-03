#!/usr/bin/env bash
# OpenCall S3: parameter- and state-supplied targets, two-word STATICCALL, CALL value,
# EOA rejection, malformed returndata, and CALL-before-sstore effect order.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-opencall
bin="$root/build/evm/EvmOpenCall.bin"
pf_evm_ensure_bin "$bin"
pf_evm_start_anvil "${PF_EVM_PORT:-18691}" "$root/build/evm/anvil-opencall.log"

solc_bin=""
for c in /opt/homebrew/bin/solc /usr/local/bin/solc solc; do
  if command -v "$c" >/dev/null 2>&1 || [[ -x "$c" ]]; then
    solc_bin="$c"
    break
  fi
done
if [[ -z "$solc_bin" ]]; then
  echo "evm-anvil-opencall: skip: solc not found" >&2
  exit 0
fi

mock_out="$root/build/evm/OpenCallTarget.bin"
"$solc_bin" --bin --optimize --overwrite -o "$root/build/evm" \
  "$here/OpenCallTarget.sol" >/dev/null
[[ -f "$mock_out" ]] || { echo "FAIL: missing OpenCallTarget.bin" >&2; exit 1; }

bytecode="$(tr -d '\n\r ' < "$bin")"
addr="$(pf_evm_deploy_ctor_u64 "$bytecode" 0)"

mock_hex="$(tr -d '\n\r ' < "$mock_out")"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" --create "0x$mock_hex")"
target="$(printf '%s' "$receipt" | pf_evm_contract_address)"

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'flagOf()(uint64)')" 0 \
  "initial flag"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'pingTarget(address)' "$target" >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$target" 'pings()(uint256)')" 1 \
  "parameter-supplied ping"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'setTarget(address)' "$target" >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'pingStored()' >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$target" 'pings()(uint256)')" 2 \
  "state-supplied ping"

eoa="$("$cast" wallet address --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d)"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'pingTarget(address)' "$eoa" >/dev/null 2>&1; then
  echo "FAIL: callSuccess to EOA unexpectedly succeeded" >&2
  exit 1
fi

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'readEcho(address,uint256)(uint256)' \
  "$target" 7)" 7 "echo one word"
if "$cast" call --rpc-url "$rpc" "$addr" 'readEcho(address,uint256)(uint256)' \
    "$target" 0 >/dev/null 2>&1; then
  echo "FAIL: malformed two-word echo unexpectedly succeeded" >&2
  exit 1
fi

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'readPair(address)(uint256)' \
  "$target")" 1 "getPair first word"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'openTransfer(address,address,uint256)' "$target" "$eoa" 1 >/dev/null

before="$(pf_evm_to_dec "$("$cast" balance --rpc-url "$rpc" "$target")")"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" --value 5 \
  "$addr" 'payTarget(address,uint256)' "$target" 5 >/dev/null
after="$(pf_evm_to_dec "$("$cast" balance --rpc-url "$rpc" "$target")")"
want="$("$python" -I -S -c "print(int('$before') + 5)")"
pf_evm_require_equal "$after" "$want" "CALL value must credit target"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'markThenPing(address)' "$target" >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'flagOf()(uint64)')" 1 \
  "flag stored after CALL"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$target" 'seenFlag()(uint256)')" 0 \
  "CALL observed pre-store flag (effect before sstore)"

echo "evm-anvil-opencall: ok (typed CALL/STATICCALL + value + EOA + malformed + effect-order; engineering only)"
