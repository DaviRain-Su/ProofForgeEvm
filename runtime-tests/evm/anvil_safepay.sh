#!/usr/bin/env bash
# SafePay: fail-closed ERC-20 consumer helpers (zero-address, increase/decrease, forceApprove).
# Darwin + Linux. Requires solc for ERC20Mock.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-safepay
bin="$root/build/evm/SafePay.bin"
pf_evm_ensure_bin "$bin"
pf_evm_start_anvil "${PF_EVM_PORT:-18692}" "$root/build/evm/anvil-safepay.log"

solc_bin=""
for c in /opt/homebrew/bin/solc /usr/local/bin/solc solc; do
  if command -v "$c" >/dev/null 2>&1 || [[ -x "$c" ]]; then
    solc_bin="$c"
    break
  fi
done
if [[ -z "$solc_bin" ]]; then
  echo "evm-anvil-safepay: skip: solc not found" >&2
  exit 0
fi

mock_out="$root/build/evm/ERC20Mock.bin"
"$solc_bin" --bin --optimize --overwrite -o "$root/build/evm" \
  "$here/ERC20Mock.sol" >/dev/null
[[ -f "$mock_out" ]] || { echo "FAIL: missing ERC20Mock.bin" >&2; exit 1; }

bytecode="$(tr -d '\n\r ' < "$bin")"
addr="$(pf_evm_deploy_ctor_u64 "$bytecode" 0)"

sender="$("$cast" wallet address --private-key "$private_key")"
other_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
recipient="$("$cast" wallet address --private-key "$other_key")"
zero="0x0000000000000000000000000000000000000000"

mock_hex="$(tr -d '\n\r ' < "$mock_out")"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" --create "0x$mock_hex")"
token="$(printf '%s' "$receipt" | pf_evm_contract_address)"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$token" 'mint(address,uint256)' "$addr" 1000 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'held(address)(uint256)' "$token")" \
  1000 "held after mint"

if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'pull(address,address,uint256)' "$token" "$zero" 1 >/dev/null 2>&1; then
  echo "FAIL: pull to zero unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'held(address)(uint256)' "$token")" \
  1000 "zero-destination pull holds tokens"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'pull(address,address,uint256)' "$token" "$recipient" 100 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'held(address)(uint256)' "$token")" \
  900 "held after pull"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" 'balanceOf(address)(uint256)' "$recipient")" \
  100 "recipient after pull"

if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'grant(address,address,uint256)' "$token" "$zero" 1 >/dev/null 2>&1; then
  echo "FAIL: grant to zero unexpectedly succeeded" >&2
  exit 1
fi
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'force(address,address,uint256)' "$token" "$zero" 1 >/dev/null 2>&1; then
  echo "FAIL: forceApprove to zero unexpectedly succeeded" >&2
  exit 1
fi

# CALL success plus empty returndata from a non-contract must still fail closed.
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'pull(address,address,uint256)' "$zero" "$recipient" 1 >/dev/null 2>&1; then
  echo "FAIL: zero token address unexpectedly succeeded" >&2
  exit 1
fi

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'grant(address,address,uint256)' "$token" "$recipient" 40 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'allowed(address,address)(uint256)' "$token" "$recipient")" \
  40 "allowed after grant"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'bump(address,address,uint256)' "$token" "$recipient" 10 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'allowed(address,address)(uint256)' "$token" "$recipient")" \
  50 "allowed after bump"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'drop(address,address,uint256)' "$token" "$recipient" 15 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'allowed(address,address)(uint256)' "$token" "$recipient")" \
  35 "allowed after drop"

if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'drop(address,address,uint256)' "$token" "$recipient" 1000 >/dev/null 2>&1; then
  echo "FAIL: over-drop unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'allowed(address,address)(uint256)' "$token" "$recipient")" \
  35 "over-drop holds allowance"

max_uint="0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'bump(address,address,uint256)' "$token" "$recipient" "$max_uint" >/dev/null 2>&1; then
  echo "FAIL: overflowing bump unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'allowed(address,address)(uint256)' "$token" "$recipient")" \
  35 "overflowing bump holds allowance"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$token" 'setUsdtApprove(bool)' true >/dev/null
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'grant(address,address,uint256)' "$token" "$recipient" 99 >/dev/null 2>&1; then
  echo "FAIL: USDT-style direct grant from nonzero unexpectedly succeeded" >&2
  exit 1
fi
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'force(address,address,uint256)' "$token" "$recipient" 99 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'allowed(address,address)(uint256)' "$token" "$recipient")" \
  99 "forceApprove bypasses USDT nonzero-to-nonzero"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$token" 'setUsdtApprove(bool)' false >/dev/null

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$token" 'mint(address,uint256)' "$sender" 200 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$token" 'approve(address,uint256)' "$addr" 80 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'take(address,address,address,uint256)' "$token" "$sender" "$recipient" 25 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" \
  'balanceOf(address)(uint256)' "$sender")" \
  175 "owner after take"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" \
  'balanceOf(address)(uint256)' "$recipient")" \
  125 "recipient after take"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$token" 'setNoReturn(bool)' true >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'pull(address,address,uint256)' "$token" "$recipient" 50 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'held(address)(uint256)' "$token")" \
  850 "USDT-style no-return transfer succeeds"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$token" 'setNoReturn(bool)' false >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$token" 'setReturnFalse(bool)' true >/dev/null
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'pull(address,address,uint256)' "$token" "$recipient" 10 >/dev/null 2>&1; then
  echo "FAIL: false-returning token transfer unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'held(address)(uint256)' "$token")" \
  850 "false-returning transfer rolls back"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$token" 'setReturnFalse(bool)' false >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$token" 'setReturnTwo(bool)' true >/dev/null
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'pull(address,address,uint256)' "$token" "$recipient" 10 >/dev/null 2>&1; then
  echo "FAIL: noncanonical true token transfer unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'held(address)(uint256)' "$token")" \
  850 "noncanonical-return transfer rolls back"

echo "evm-anvil-safepay: ok (zero-address/increase/decrease/forceApprove/fail-closed returns)"
