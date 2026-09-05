#!/usr/bin/env bash
# VestLink: stored-beneficiary native-ETH vesting, release(), transferOwnership, EtherReleased.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-vestlink
bin="$root/build/evm/VestLink.bin"
abi="$root/build/evm/VestLink.abi.json"
echo "building VestLink.bin" >&2
lake exe pf -- build --target evm --out "$root/build/evm" VestLink \
  || { echo "FAIL: pf build VestLink failed" >&2; exit 1; }
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
runtime_bytes="$(python3 -I -S -c "from pathlib import Path; print(len(Path('$bin').read_text().strip())//2)")"
if [[ "$runtime_bytes" -gt 24576 ]]; then
  echo "FAIL: VestLink is $runtime_bytes bytes, over EIP-170" >&2
  exit 1
fi
pf_evm_start_anvil "${PF_EVM_PORT:-18696}" "$root/build/evm/anvil-vestlink.log"

solc_bin=""
for c in /opt/homebrew/bin/solc /usr/local/bin/solc solc; do
  if command -v "$c" >/dev/null 2>&1 || [[ -x "$c" ]]; then
    solc_bin="$c"
    break
  fi
done

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty VestLink.bin" >&2; exit 1; }

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
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'owner()(address)')" \
  "$beneficiary" "owner matches beneficiary"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'start()(uint256)')" \
  "$start_ts" "constructor start"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'duration()(uint256)')" \
  "$duration" "constructor duration"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'cliff()(uint256)')" \
  "$start_ts" "zero cliffDuration makes cliff equal start"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'endTime()(uint256)')" \
  "$((start_ts + duration))" "start + duration"

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasable()(uint256)')" \
  0 "nothing releasable before start"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$addr" --value 1ether >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasable()(uint256)')" \
  0 "funded but still before start"

topic0="$("$cast" keccak 'EtherReleased(uint256)')"
zero_release="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'release()')"
pf_evm_typed_event_check "$abi" "$zero_release" EtherReleased "$topic0" \
  '{"amount": 0}' "pre-start release() logs zero"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasedOf()(uint256)')" \
  0 "pre-start release() leaves released at zero"
pf_evm_require_uint "$("$cast" balance --rpc-url "$rpc" "$addr")" \
  1000000000000000000 "pre-start release() keeps the 1 ETH"

if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'release(uint256)' 1 >/dev/null 2>&1; then
  echo "FAIL: pre-vesting release(uint256) unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_insufficient "$addr" "$beneficiary" \
  "$("$cast" calldata 'release(uint256)' 1)" 0 1 "pre-vesting release(uint256)"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasedOf()(uint256)')" \
  0 "rejected release keeps accounting"

quarter=$((start_ts + duration / 4))
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'vestedAmount(uint64)(uint256)' \
  "$quarter")" 250000000000000000 "vestedAmount at the quarter mark"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'vestedAmount(uint64)(uint256)' \
  "$((start_ts + duration / 2))")" 500000000000000000 "vestedAmount at the half mark"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'vestedAmount(uint64)(uint256)' \
  "$((start_ts + duration))")" 1000000000000000000 "vestedAmount at the end"

pf_evm_stamp_next "$quarter"
quarter_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'release()')"
pf_evm_typed_event_check "$abi" "$quarter_receipt" EtherReleased "$topic0" \
  '{"amount": 250000000000000000}' "release() pays the quarter"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasedOf()(uint256)')" \
  250000000000000000 "released counter after quarter release()"
pf_evm_require_uint "$("$cast" balance --rpc-url "$rpc" "$addr")" \
  750000000000000000 "wallet kept three quarters"

if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'transferOwnership(address)' "$other" >/dev/null 2>&1; then
  echo "FAIL: non-owner transferOwnership unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_unauthorized "$addr" "$other" \
  "$("$cast" calldata 'transferOwnership(address)' "$other")" "$other" \
  "non-owner transferOwnership"
pf_evm_require_ownable_invalid_owner "$addr" "$beneficiary" \
  "$("$cast" calldata 'transferOwnership(address)' "$zero")" "$zero" \
  "zero new owner"
rotate_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'transferOwnership(address)' "$other")"
pf_evm_typed_event_check "$abi" "$rotate_receipt" OwnershipTransferred "$topic_own" \
  "{\"previousOwner\": \"$beneficiary\", \"newOwner\": \"$other\"}" \
  "transferOwnership OwnershipTransferred LOG3"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'beneficiary()(address)')" \
  "$other" "beneficiary rotated"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'owner()(address)')" \
  "$other" "owner rotated"

other_before="$(pf_evm_to_dec "$("$cast" balance --rpc-url "$rpc" "$other")")"
after_end=$((start_ts + duration + 1))
"$cast" rpc --rpc-url "$rpc" evm_setNextBlockTimestamp "$after_end" >/dev/null
"$cast" rpc --rpc-url "$rpc" evm_mine >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasable()(uint256)')" \
  750000000000000000 "remainder releasable after end"
rest_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'release()')"
pf_evm_typed_event_check "$abi" "$rest_receipt" EtherReleased "$topic0" \
  '{"amount": 750000000000000000}' "release() after rotation pays the remainder"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'releasedOf()(uint256)')" \
  1000000000000000000 "released counter after full release"
pf_evm_require_uint "$("$cast" balance --rpc-url "$rpc" "$addr")" \
  0 "wallet empty after remainder"
other_after="$(pf_evm_to_dec "$("$cast" balance --rpc-url "$rpc" "$other")")"
"$python" -I -S -c "
before=int('$other_before')
after=int('$other_after')
if after - before != 750000000000000000:
    raise SystemExit(f'FAIL: rotated beneficiary delta {after-before}, want 750000000000000000')
"

zero_encoded="$("$cast" abi-encode 'constructor(address,uint64,uint64,uint64)' "$zero" "$start_ts" "$duration" 0)"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    --create "0x${bytecode}${zero_encoded#0x}" >/dev/null 2>&1; then
  echo "FAIL: zero-owner constructor CREATE unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_create_ownable_invalid_owner "$bytecode" "$zero_encoded" "$beneficiary" \
  "zero beneficiary CREATE"

max_u64=18446744073709551615
bad_encoded="$("$cast" abi-encode 'constructor(address,uint64,uint64,uint64)' \
  "$beneficiary" "$max_u64" 1 0)"
bad_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${bad_encoded#0x}")"
bad_addr="$(printf '%s' "$bad_receipt" | pf_evm_contract_address)"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$bad_addr" 'beneficiary()(address)')" \
  "$zero" "overflowing schedule hides beneficiary"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$bad_addr" 'endTime()(uint256)')" \
  0 "overflowing schedule hides end"

now_cliff="$(pf_evm_to_dec "$("$cast" block --rpc-url "$rpc" latest --json | "$python" -I -S -c 'import json,sys; print(json.load(sys.stdin)["timestamp"])')")"
c_start=$((now_cliff + 100))
c_duration=1000
c_cliff=500
c_encoded="$("$cast" abi-encode 'constructor(address,uint64,uint64,uint64)' \
  "$beneficiary" "$c_start" "$c_duration" "$c_cliff")"
c_addr="$(printf '%s' "$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${c_encoded#0x}")" | pf_evm_contract_address)"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$c_addr" --value 1ether >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$c_addr" 'cliff()(uint256)')" \
  "$((c_start + c_cliff))" "cliff is start + cliffDuration"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$c_addr" 'vestedAmount(uint64)(uint256)' \
  "$((c_start + 250))")" 0 "vestedAmount is 0 before the cliff"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$c_addr" 'vestedAmount(uint64)(uint256)' \
  "$((c_start + c_cliff))")" 500000000000000000 "OZ jump at the cliff is half the allocation"
pf_evm_stamp_next "$((c_start + c_cliff))"
c_release="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$c_addr" 'release()')"
pf_evm_typed_event_check "$abi" "$c_release" EtherReleased "$topic0" \
  '{"amount": 500000000000000000}' "release() at the cliff pays the jump"
pf_evm_require_uint "$("$cast" balance --rpc-url "$rpc" "$c_addr")" \
  500000000000000000 "cliff wallet kept the unvested half"

over_encoded="$("$cast" abi-encode 'constructor(address,uint64,uint64,uint64)' \
  "$beneficiary" "$c_start" "$c_duration" "$((c_duration + 1))")"
over_addr="$(printf '%s' "$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${over_encoded#0x}")" | pf_evm_contract_address)"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$over_addr" 'cliff()(uint256)')" \
  0 "cliff longer than duration fails closed"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$over_addr" 'start()(uint256)')" \
  0 "cliff longer than duration hides start"

if [[ -z "$solc_bin" ]]; then
  echo "evm-anvil-vestlink: ok (release() + transferOwnership, solc skip, $runtime_bytes bytes)"
  exit 0
fi

yul="$root/build/evm/VestLink.yul"
[[ -f "$yul" ]] || { echo "FAIL: missing $yul" >&2; exit 1; }
ctor_mut_dir="$root/build/evm/vestlink-ctor-mut"
rm -rf "$ctor_mut_dir"
mkdir -p "$ctor_mut_dir"
pf_evm_strip_ctor_invalid_owner_guard "$yul" VestLink "$ctor_mut_dir/VestLink.yul"
ctor_mut_code="$("$solc_bin" --strict-assembly --optimize --evm-version cancun --bin \
  "$ctor_mut_dir/VestLink.yul" | "$python" -I -S -c "
import sys
lines=[ln.strip() for ln in sys.stdin.read().splitlines() if ln.strip()]
hexes=[ln for ln in lines if len(ln)>100 and all(c in '0123456789abcdefABCDEF' for c in ln)]
if not hexes:
    raise SystemExit('FAIL: solc produced no VestLink constructor-guard mutation bytecode')
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

log_mut_dir="$root/build/evm/vestlink-ctor-log-mut"
rm -rf "$log_mut_dir"
mkdir -p "$log_mut_dir"
pf_evm_strip_ctor_ownership_log "$yul" VestLink "$log_mut_dir/VestLink.yul"
log_mut_code="$("$solc_bin" --strict-assembly --optimize --evm-version cancun --bin \
  "$log_mut_dir/VestLink.yul" | "$python" -I -S -c "
import sys
lines=[ln.strip() for ln in sys.stdin.read().splitlines() if ln.strip()]
hexes=[ln for ln in lines if len(ln)>100 and all(c in '0123456789abcdefABCDEF' for c in ln)]
if not hexes:
    raise SystemExit('FAIL: solc produced no VestLink constructor-log mutation bytecode')
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

mut_dir="$root/build/evm/vestlink-call-mut"
rm -rf "$mut_dir"
mkdir -p "$mut_dir"
"$python" -I -S -c "
from pathlib import Path
import re, sys
src = Path('$yul').read_text()
pat = r'call\\(gas\\(\\), mload\\(0\\), ([A-Za-z0-9_]+), 0, 0, 0, 0\\)'
n = len(re.findall(pat, src))
if n < 1:
    sys.stderr.write(f'FAIL: expected at least one native send call(, got {n}\\n')
    sys.exit(1)
out, k = re.subn(pat, r'call(gas(), mload(0), 0, 0, 0, 0, 0)', src)
if k != n:
    sys.stderr.write(f'FAIL: call rewrite changed {k}, counted {n}\\n')
    sys.exit(1)
Path('$mut_dir/VestLink.yul').write_text(out)
print(f'rewrote {k} native send value words to 0')
"
mut_code="$("$solc_bin" --strict-assembly --optimize --evm-version cancun --bin \
  "$mut_dir/VestLink.yul" | "$python" -I -S -c "
import sys
lines=[ln.strip() for ln in sys.stdin.read().splitlines() if ln.strip()]
hexes=[ln for ln in lines if len(ln)>100 and all(c in '0123456789abcdefABCDEF' for c in ln)]
if not hexes:
    raise SystemExit('FAIL: solc produced no VestLink mutation bytecode')
print(hexes[-1])
")"
mut_encoded="$("$cast" abi-encode 'constructor(address,uint64,uint64,uint64)' "$beneficiary" "$start_ts" "$duration" 0)"
mut_addr="$(printf '%s' "$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${mut_code}${mut_encoded#0x}")" | pf_evm_contract_address)"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$mut_addr" --value 1ether >/dev/null
# Happy path already mined at after_end. Reusing that timestamp reverts on Anvil.
if ! "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$mut_addr" 'release()' >/dev/null 2>&1; then
  echo "FAIL: zero-value CALL mutation unexpectedly reverted" >&2
  exit 1
fi
pf_evm_require_uint "$("$cast" balance --rpc-url "$rpc" "$mut_addr")" \
  1000000000000000000 "zero-value CALL mutation left the mutated wallet funded"

echo "evm-anvil-vestlink: ok (release() + transferOwnership + cliff + zero-owner CREATE + CREATE OwnershipTransferred + constructor-guard mutation + constructor-log mutation + value mutation, $runtime_bytes bytes)"
