#!/usr/bin/env bash
# Vest20Link: bounded ERC-20 vesting map + ERC20Released. Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-vest20link
bin="$root/build/evm/Vest20Link.bin"
abi="$root/build/evm/Vest20Link.abi.json"
echo "building Vest20Link.bin" >&2
lake exe pf -- build --target evm --out "$root/build/evm" Vest20Link \
  || { echo "FAIL: pf build Vest20Link failed" >&2; exit 1; }
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
runtime_bytes="$(python3 -I -S -c "from pathlib import Path; print(len(Path('$bin').read_text().strip())//2)")"
if [[ "$runtime_bytes" -gt 24576 ]]; then
  echo "FAIL: Vest20Link is $runtime_bytes bytes, over EIP-170" >&2
  exit 1
fi
pf_evm_start_anvil "${PF_EVM_PORT:-18708}" "$root/build/evm/anvil-vest20link.log"

solc_bin=""
for c in /opt/homebrew/bin/solc /usr/local/bin/solc solc; do
  if command -v "$c" >/dev/null 2>&1 || [[ -x "$c" ]]; then
    solc_bin="$c"
    break
  fi
done
if [[ -z "$solc_bin" ]]; then
  echo "evm-anvil-vest20link: skip: solc not found" >&2
  exit 0
fi

"$solc_bin" --bin --optimize --overwrite -o "$root/build/evm" \
  "$here/ERC20Mock.sol" >/dev/null
mock_out="$root/build/evm/ERC20Mock.bin"
[[ -f "$mock_out" ]] || { echo "FAIL: missing ERC20Mock.bin" >&2; exit 1; }

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty Vest20Link.bin" >&2; exit 1; }
mock_hex="$(tr -d '\n\r ' < "$mock_out")"

beneficiary="$("$cast" wallet address --private-key "$private_key")"
other_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
other="$("$cast" wallet address --private-key "$other_key")"
now_block="$(pf_evm_to_dec "$("$cast" block --rpc-url "$rpc" latest --json | "$python" -I -S -c 'import json,sys; print(json.load(sys.stdin)["timestamp"])')")"
start_ts=$((now_block + 100))
duration=1000
encoded="$("$cast" abi-encode 'constructor(address,uint64,uint64)' "$beneficiary" "$start_ts" "$duration")"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${encoded#0x}")"
addr="$(printf '%s' "$receipt" | pf_evm_contract_address)"

token="$(printf '%s' "$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" --create "0x$mock_hex")" | pf_evm_contract_address)"
token_b="$(printf '%s' "$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" --create "0x$mock_hex")" | pf_evm_contract_address)"
zero="0x0000000000000000000000000000000000000000"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'beneficiary()(address)')" \
  "$beneficiary" "immutable beneficiary"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'start()(uint256)')" \
  "$start_ts" "constructor start"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'duration()(uint256)')" \
  "$duration" "constructor duration"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$token" 'mint(address,uint256)' "$addr" 1000 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$token_b" 'mint(address,uint256)' "$addr" 400 >/dev/null

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasable(address)(uint256)' "$token")" \
  0 "nothing releasable before start"
if ! "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'release(address)' "$token" >/dev/null; then
  echo "FAIL: parameterless pre-start release reverted" >&2
  exit 1
fi
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" 'balanceOf(address)(uint256)' "$beneficiary")" \
  0 "pre-start release pays zero"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasedOf(address)(uint256)' "$token")" \
  0 "pre-start released map stays zero"

if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'release(address)' "$zero" >/dev/null 2>&1; then
  echo "FAIL: zero token release unexpectedly succeeded" >&2
  exit 1
fi

quarter=$((start_ts + duration / 4))
"$cast" rpc --rpc-url "$rpc" evm_setNextBlockTimestamp "$quarter" >/dev/null
"$cast" rpc --rpc-url "$rpc" evm_mine >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasable(address)(uint256)' "$token")" \
  250 "a quarter releasable at start + duration/4"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'vestedAmount(address,uint64)(uint256)' \
  "$token" "$quarter")" 250 "vestedAmount at the quarter mark"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasable(address)(uint256)' "$token_b")" \
  100 "second token vests on its own balance"

topic0="$("$cast" keccak 'ERC20Released(address,uint256)')"
release_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'release(address)' "$token")"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" 'balanceOf(address)(uint256)' "$beneficiary")" \
  250 "beneficiary received the quarter"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" 'balanceOf(address)(uint256)' "$addr")" \
  750 "vesting wallet kept the unvested remainder"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasedOf(address)(uint256)' "$token")" \
  250 "released map credits token A"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasedOf(address)(uint256)' "$token_b")" \
  0 "token B released map is independent"
token_lc="$("$python" -I -S -c "print('$token'.lower())")"
pf_evm_typed_event_check "$abi" "$release_receipt" ERC20Released "$topic0" \
  "{\"token\": \"$token_lc\", \"amount\": 250}" "quarter ERC-20 release"

if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'transferOwnership(address)' "$other" >/dev/null 2>&1; then
  echo "FAIL: non-owner transferOwnership unexpectedly succeeded" >&2
  exit 1
fi
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'transferOwnership(address)' "$other" >/dev/null
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'beneficiary()(address)')" \
  "$other" "ERC-20 beneficiary rotated"

after_end=$((start_ts + duration + 1))
"$cast" rpc --rpc-url "$rpc" evm_setNextBlockTimestamp "$after_end" >/dev/null
"$cast" rpc --rpc-url "$rpc" evm_mine >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasable(address)(uint256)' "$token")" \
  750 "remainder releasable after end"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'release(address)' "$token" >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" 'balanceOf(address)(uint256)' "$beneficiary")" \
  250 "original beneficiary kept the quarter"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" 'balanceOf(address)(uint256)' "$other")" \
  750 "rotated beneficiary received the remainder"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" 'balanceOf(address)(uint256)' "$addr")" \
  0 "vesting wallet empty of token A"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'release(address)' "$token_b" >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token_b" 'balanceOf(address)(uint256)' "$other")" \
  400 "rotated beneficiary received the full token B allocation"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasedOf(address)(uint256)' "$token_b")" \
  400 "released map credits token B"

zero_encoded="$("$cast" abi-encode 'constructor(address,uint64,uint64)' "$zero" "$start_ts" "$duration")"
zero_addr="$(printf '%s' "$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${zero_encoded#0x}")" | pf_evm_contract_address)"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$zero_addr" 'releasable(address)(uint256)' "$token")" \
  0 "zero beneficiary fails closed on releasable"

yul="$root/build/evm/Vest20Link.yul"
[[ -f "$yul" ]] || { echo "FAIL: missing $yul" >&2; exit 1; }
mut_dir="$root/build/evm/vest20link-call-mut"
rm -rf "$mut_dir"
mkdir -p "$mut_dir"
"$python" -I -S -c "
from pathlib import Path
import re, sys
src = Path('$yul').read_text()
pat = r'call\\(gas\\(\\), ([A-Za-z0-9_]+), 0, 0, 68, 0, 32\\)'
n = len(re.findall(pat, src))
if n < 1:
    sys.stderr.write(f'FAIL: expected at least one ERC-20 transfer call(, got {n}\\n')
    sys.exit(1)
out, k = re.subn(pat, r'staticcall(gas(), \\1, 0, 68, 0, 32)', src)
if k != n:
    sys.stderr.write(f'FAIL: call rewrite changed {k}, counted {n}\\n')
    sys.exit(1)
Path('$mut_dir/Vest20Link.yul').write_text(out)
print(f'rewrote {k} call( transfer sites to staticcall(')
"
mut_code="$("$solc_bin" --strict-assembly --optimize --evm-version cancun --bin \
  "$mut_dir/Vest20Link.yul" | "$python" -I -S -c "
import sys
lines=[ln.strip() for ln in sys.stdin.read().splitlines() if ln.strip()]
hexes=[ln for ln in lines if len(ln)>100 and all(c in '0123456789abcdefABCDEF' for c in ln)]
if not hexes:
    raise SystemExit('FAIL: solc produced no Vest20Link mutation bytecode')
print(hexes[-1])
")"
mut_encoded="$("$cast" abi-encode 'constructor(address,uint64,uint64)' "$beneficiary" "$start_ts" "$duration")"
mut_addr="$(printf '%s' "$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${mut_code}${mut_encoded#0x}")" | pf_evm_contract_address)"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$token" 'mint(address,uint256)' "$mut_addr" 1000 >/dev/null
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$mut_addr" 'release(address)' "$token" >/dev/null 2>&1; then
  echo "FAIL: STATICCALL mutation unexpectedly succeeded at a CALL transfer" >&2
  exit 1
fi
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" 'balanceOf(address)(uint256)' "$beneficiary")" \
  250 "STATICCALL mutation left the original beneficiary token A balance unchanged"

echo "evm-anvil-vest20link: ok (ERC-20 map release + rotation + ERC20Released + two-token independence + CALL mutation, $runtime_bytes bytes)"
