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
encoded="$("$cast" abi-encode 'constructor(address,uint64,uint64,uint64)' "$beneficiary" "$start_ts" "$duration" 0)"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${encoded#0x}")"
addr="$(printf '%s' "$receipt" | pf_evm_contract_address)"

token="$(printf '%s' "$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" --create "0x$mock_hex")" | pf_evm_contract_address)"
token_b="$(printf '%s' "$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" --create "0x$mock_hex")" | pf_evm_contract_address)"
zero="0x0000000000000000000000000000000000000000"
sig_own="$(pf_evm_typed_event_sig "$abi" OwnershipTransferred)"
pf_evm_require_equal "$sig_own" 'OwnershipTransferred(address,address)' \
  "ABI OwnershipTransferred signature"
topic_own="$("$cast" keccak "$sig_own")"
pf_evm_typed_event_check "$abi" "$receipt" OwnershipTransferred "$topic_own" \
  "{\"previousOwner\": \"$zero\", \"newOwner\": \"$beneficiary\"}" \
  "CREATE OwnershipTransferred LOG3"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'beneficiary()(address)')" \
  "$beneficiary" "stored beneficiary"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'start()(uint256)')" \
  "$start_ts" "constructor start"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'duration()(uint256)')" \
  "$duration" "constructor duration"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'cliff()(uint256)')" \
  "$start_ts" "zero cliffDuration makes cliff equal start"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$token" 'mint(address,uint256)' "$addr" 1000 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$token_b" 'mint(address,uint256)' "$addr" 400 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$addr" --value 1ether >/dev/null
pf_evm_require_uint "$("$cast" balance --rpc-url "$rpc" "$addr")" \
  1000000000000000000 "wallet holds 1 ETH beside the tokens"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasable()(uint256)')" \
  0 "funded ETH still nothing releasable before start"

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
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'vestedAmount(address,uint64)(uint256)' \
  "$token" "$quarter")" 250 "vestedAmount at the quarter mark"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'vestedAmount(address,uint64)(uint256)' \
  "$token_b" "$quarter")" 100 "second token vestedAmount at the quarter mark"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'vestedAmount(uint64)(uint256)' \
  "$quarter")" 250000000000000000 "native vestedAmount at the quarter mark"

topic0="$("$cast" keccak 'ERC20Released(address,uint256)')"
pf_evm_stamp_next "$quarter"
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
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasedOf()(uint256)')" \
  0 "native released stays zero after ERC-20 quarter"
eth_topic="$("$cast" keccak 'EtherReleased(uint256)')"
half=$((start_ts + duration / 2))
pf_evm_stamp_next "$half"
eth_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'release()')"
pf_evm_typed_event_check "$abi" "$eth_receipt" EtherReleased "$eth_topic" \
  '{"amount": 500000000000000000}' "release() pays the ETH half"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasedOf()(uint256)')" \
  500000000000000000 "native released counter after half release()"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasedOf(address)(uint256)' "$token")" \
  250 "ERC-20 released map stays independent of the ETH book"
pf_evm_require_uint "$("$cast" balance --rpc-url "$rpc" "$addr")" \
  500000000000000000 "wallet kept half of the ETH"

if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'transferOwnership(address)' "$other" >/dev/null 2>&1; then
  echo "FAIL: non-owner transferOwnership unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_ownable_unauthorized_account "$addr" "$other" \
  "$("$cast" calldata 'transferOwnership(address)' "$other")" "$other" \
  "non-owner transferOwnership"
pf_evm_require_ownable_invalid_owner "$addr" "$beneficiary" \
  "$("$cast" calldata 'transferOwnership(address)' "$zero")" "$zero" \
  "zero new owner"
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
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasable()(uint256)')" \
  500000000000000000 "ETH remainder releasable after end"
other_before="$(pf_evm_to_dec "$("$cast" balance --rpc-url "$rpc" "$other")")"
eth_rest="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'release()')"
pf_evm_typed_event_check "$abi" "$eth_rest" EtherReleased "$eth_topic" \
  '{"amount": 500000000000000000}' "release() after rotation pays the ETH remainder"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasedOf()(uint256)')" \
  1000000000000000000 "native released counter after full release()"
pf_evm_require_uint "$("$cast" balance --rpc-url "$rpc" "$addr")" \
  0 "wallet empty of ETH after remainder"
other_after="$(pf_evm_to_dec "$("$cast" balance --rpc-url "$rpc" "$other")")"
"$python" -I -S -c "
before=int('$other_before')
after=int('$other_after')
if after - before != 500000000000000000:
    raise SystemExit(f'FAIL: rotated beneficiary ETH delta {after-before}, want 500000000000000000')
"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'release(address)' "$token_b" >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token_b" 'balanceOf(address)(uint256)' "$other")" \
  400 "rotated beneficiary received the full token B allocation"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasedOf(address)(uint256)' "$token_b")" \
  400 "released map credits token B"

zero_encoded="$("$cast" abi-encode 'constructor(address,uint64,uint64,uint64)' "$zero" "$start_ts" "$duration" 0)"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    --create "0x${bytecode}${zero_encoded#0x}" >/dev/null 2>&1; then
  echo "FAIL: zero-owner constructor CREATE unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_create_ownable_invalid_owner "$bytecode" "$zero_encoded" "$beneficiary" \
  "zero beneficiary CREATE"

now_cliff="$(pf_evm_to_dec "$("$cast" block --rpc-url "$rpc" latest --json | "$python" -I -S -c 'import json,sys; print(json.load(sys.stdin)["timestamp"])')")"
c_start=$((now_cliff + 100))
c_duration=1000
c_cliff=500
c_encoded="$("$cast" abi-encode 'constructor(address,uint64,uint64,uint64)' \
  "$beneficiary" "$c_start" "$c_duration" "$c_cliff")"
c_addr="$(printf '%s' "$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${c_encoded#0x}")" | pf_evm_contract_address)"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$token" 'mint(address,uint256)' "$c_addr" 1000 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$c_addr" 'cliff()(uint256)')" \
  "$((c_start + c_cliff))" "ERC-20 cliff is start + cliffDuration"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$c_addr" 'vestedAmount(address,uint64)(uint256)' \
  "$token" "$((c_start + 250))")" 0 "ERC-20 vestedAmount is 0 before the cliff"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$c_addr" 'vestedAmount(address,uint64)(uint256)' \
  "$token" "$((c_start + c_cliff))")" 500 "OZ jump at the cliff is half the ERC-20 allocation"
pf_evm_stamp_next "$((c_start + c_cliff))"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$c_addr" 'release(address)' "$token" >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" 'balanceOf(address)(uint256)' "$beneficiary")" \
  750 "original beneficiary received the original quarter plus the cliff jump"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" 'balanceOf(address)(uint256)' "$c_addr")" \
  500 "cliff wallet kept the unvested ERC-20 half"

yul="$root/build/evm/Vest20Link.yul"
[[ -f "$yul" ]] || { echo "FAIL: missing $yul" >&2; exit 1; }
ctor_mut_dir="$root/build/evm/vest20link-ctor-mut"
rm -rf "$ctor_mut_dir"
mkdir -p "$ctor_mut_dir"
pf_evm_strip_ctor_invalid_owner_guard "$yul" Vest20Link "$ctor_mut_dir/Vest20Link.yul"
ctor_mut_code="$("$solc_bin" --strict-assembly --optimize --evm-version cancun --bin \
  "$ctor_mut_dir/Vest20Link.yul" | "$python" -I -S -c "
import sys
lines=[ln.strip() for ln in sys.stdin.read().splitlines() if ln.strip()]
hexes=[ln for ln in lines if len(ln)>100 and all(c in '0123456789abcdefABCDEF' for c in ln)]
if not hexes:
    raise SystemExit('FAIL: solc produced no Vest20Link constructor-guard mutation bytecode')
print(hexes[-1])
")"
ctor_mut_zero="$("$cast" abi-encode 'constructor(address,uint64,uint64,uint64)' "$zero" "$start_ts" "$duration" 0)"
pf_evm_require_create_ok "$ctor_mut_code" "$ctor_mut_zero" "$beneficiary" \
  "constructor-guard mutation CREATE"
ctor_mut_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${ctor_mut_code}${ctor_mut_zero#0x}")" \
  || { echo "FAIL: mutation unexpectedly still reverted" >&2; exit 1; }
ctor_mut_addr="$(printf '%s' "$ctor_mut_receipt" | "$python" -I -S -c "
import json,sys
r=json.load(sys.stdin)
st=str(r.get('status') or '').lower()
if st not in ('0x1','1'):
    raise SystemExit('FAIL: mutation unexpectedly still reverted')
addr=r.get('contractAddress') or ''
if not addr or set(addr[2:])=={'0'}:
    raise SystemExit('FAIL: mutation unexpectedly still reverted')
print(addr)
")"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$ctor_mut_addr" 'owner()(address)')" \
  "$zero" "constructor-guard mutation stored a zero owner"

log_mut_dir="$root/build/evm/vest20link-ctor-log-mut"
rm -rf "$log_mut_dir"
mkdir -p "$log_mut_dir"
pf_evm_strip_ctor_ownership_log "$yul" Vest20Link "$log_mut_dir/Vest20Link.yul"
log_mut_code="$("$solc_bin" --strict-assembly --optimize --evm-version cancun --bin \
  "$log_mut_dir/Vest20Link.yul" | "$python" -I -S -c "
import sys
lines=[ln.strip() for ln in sys.stdin.read().splitlines() if ln.strip()]
hexes=[ln for ln in lines if len(ln)>100 and all(c in '0123456789abcdefABCDEF' for c in ln)]
if not hexes:
    raise SystemExit('FAIL: solc produced no Vest20Link constructor-log mutation bytecode')
print(hexes[-1])
")"
log_mut_encoded="$("$cast" abi-encode 'constructor(address,uint64,uint64,uint64)' "$beneficiary" "$start_ts" "$duration" 0)"
log_mut_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${log_mut_code}${log_mut_encoded#0x}")"
log_mut_addr="$(printf '%s' "$log_mut_receipt" | pf_evm_contract_address)"
pf_evm_typed_event_check "$abi" "$log_mut_receipt" OwnershipTransferred "$topic_own" \
  '{}' "constructor-log mutation CREATE" 0
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$log_mut_addr" 'owner()(address)')" \
  "$beneficiary" "constructor-log mutation still stored the owner"

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
mut_encoded="$("$cast" abi-encode 'constructor(address,uint64,uint64,uint64)' "$beneficiary" "$start_ts" "$duration" 0)"
mut_addr="$(printf '%s' "$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${mut_code}${mut_encoded#0x}")" | pf_evm_contract_address)"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$token" 'mint(address,uint256)' "$mut_addr" 1000 >/dev/null
before_mut="$(pf_evm_to_dec "$("$cast" call --rpc-url "$rpc" "$token" 'balanceOf(address)(uint256)' "$beneficiary")")"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$mut_addr" 'release(address)' "$token" >/dev/null 2>&1; then
  echo "FAIL: STATICCALL mutation unexpectedly succeeded at a CALL transfer" >&2
  exit 1
fi
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" 'balanceOf(address)(uint256)' "$beneficiary")" \
  "$before_mut" "STATICCALL mutation left the original beneficiary token A balance unchanged"

echo "evm-anvil-vest20link: ok (dual-asset ETH+ERC-20 release + rotation + ERC20Released + EtherReleased + two-token independence + zero-owner CREATE + CREATE OwnershipTransferred + constructor-guard mutation + constructor-log mutation + CALL mutation, $runtime_bytes bytes)"
