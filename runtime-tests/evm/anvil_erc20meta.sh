#!/usr/bin/env bash
# Erc20Meta: ERC-20-shaped string name/symbol + owner-gated mint + standard allowance/transfer/approve.
# Receipts: canonical Transfer/Approval LOG3 (indexed from/to or owner/spender, uint256 data).
# Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-erc20meta
bin="$root/build/evm/Erc20Meta.bin"
abi="$root/build/evm/Erc20Meta.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building Erc20Meta.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" Erc20Meta \
    || { echo "FAIL: pf build Erc20Meta failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18576}" "$root/build/evm/anvil-erc20meta.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty Erc20Meta.bin" >&2; exit 1; }

sender="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_address "$bytecode" "$sender")"

other_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
dest="$("$cast" wallet address --private-key "$other_key")"
zero="0x0000000000000000000000000000000000000000"

# ABI JSON is the source of truth for signatures; pin them against the canonical ERC-20 shapes.
sig_xfer="$(pf_evm_typed_event_sig "$abi" Transfer)"
sig_appr="$(pf_evm_typed_event_sig "$abi" Approval)"
pf_evm_require_equal "$sig_xfer" 'Transfer(address,address,uint256)' "ABI Transfer signature"
pf_evm_require_equal "$sig_appr" 'Approval(address,address,uint256)' "ABI Approval signature"
topic_xfer="$("$cast" keccak "$sig_xfer")"
topic_appr="$("$cast" keccak "$sig_appr")"
want_xfer_topic="$("$cast" keccak 'Transfer(address,address,uint256)')"
want_appr_topic="$("$cast" keccak 'Approval(address,address,uint256)')"
pf_evm_require_equal "${topic_xfer,,}" "${want_xfer_topic,,}" "Transfer topic0 vs canonical keccak"
pf_evm_require_equal "${topic_appr,,}" "${want_appr_topic,,}" "Approval topic0 vs canonical keccak"

"$python" -I -S -c "
import json
abi=json.load(open('$abi'))
def fn(name):
    hits=[e for e in abi if e.get('type')=='function' and e.get('name')==name]
    if len(hits)!=1:
        raise SystemExit(f'FAIL: ABI must declare {name}() once, got {len(hits)}')
    return hits[0]
for name in ('name','symbol'):
    outs=fn(name).get('outputs') or []
    if not outs or outs[0].get('type')!='string':
        raise SystemExit(f'FAIL: {name}() must return ABI string, got {outs}')
allow=fn('allowance')
if any(e.get('name')=='allowanceOf' for e in abi if e.get('type')=='function'):
    raise SystemExit('FAIL: non-standard allowanceOf must not appear')
if (allow.get('outputs') or [{}])[0].get('type')!='uint256':
    raise SystemExit('FAIL: allowance() must return uint256')
"

got_name="$("$cast" call --rpc-url "$rpc" "$addr" 'name()(string)')"
got_symbol="$("$cast" call --rpc-url "$rpc" "$addr" 'symbol()(string)')"
got_name="${got_name#\"}"; got_name="${got_name%\"}"
got_symbol="${got_symbol#\"}"; got_symbol="${got_symbol%\"}"
pf_evm_require_equal "$got_name" "Token" "compile-time string name"
pf_evm_require_equal "$got_symbol" "PF" "compile-time string symbol"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'decimals()(uint8)')" \
  18 "compile-time decimals"
got_owner="$("$cast" call --rpc-url "$rpc" "$addr" 'ownerOf()(address)')"
pf_evm_require_equal "${got_owner,,}" "${sender,,}" "ownerOf"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'totalSupply()(uint256)')" \
  0 "absent total supply"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$sender")" \
  0 "absent sender balance"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'allowance(address,address)(uint256)' "$sender" "$dest")" \
  0 "absent allowance"

if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'mint(address,uint256)' "$zero" 100 >/dev/null 2>&1; then
  echo "FAIL: mint to zero unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_zero_address "$addr" "$sender" \
  "$("$cast" calldata 'mint(address,uint256)' "$zero" 100)" \
  "mint to zero"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'totalSupply()(uint256)')" \
  0 "mint to zero holds supply"

if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'mint(address,uint256)' "$dest" 100 >/dev/null 2>&1; then
  echo "FAIL: non-owner mint unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_unauthorized "$addr" "$dest" \
  "$("$cast" calldata 'mint(address,uint256)' "$dest" 100)" "$dest" \
  "non-owner mint"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'totalSupply()(uint256)')" \
  0 "non-owner mint holds supply"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(address,uint256)' "$sender" 100)"
printf '%s' "$receipt" | "$python" -I -S -c "
import json,sys
r=json.load(sys.stdin)
logs=r.get('logs') or []
want='$topic_xfer'.lower()
zero=int('$zero', 16)
sender=int('$sender', 16)
hit=None
for lg in logs:
    topics=lg.get('topics') or []
    if topics and topics[0].lower()==want:
        hit=lg
        break
if hit is None:
    raise SystemExit('FAIL: missing Transfer(address,address,uint256) log on mint')
topics=hit.get('topics') or []
if len(topics)!=3:
    raise SystemExit(f'FAIL: mint Transfer should be LOG3, got {len(topics)} topics')
if int(topics[1],16)!=zero:
    raise SystemExit(f'FAIL: mint Transfer from {topics[1]} != zero')
if int(topics[2],16)!=sender:
    raise SystemExit(f'FAIL: mint Transfer to {topics[2]} != sender')
data=int(hit.get('data') or '0x0', 16)
if data!=100:
    raise SystemExit(f'FAIL: mint Transfer data {data} != 100')
"
pf_evm_typed_event_check "$abi" "$receipt" Transfer "$topic_xfer" \
  "{\"from\": \"$zero\", \"to\": \"$sender\", \"value\": 100}" "mint Transfer LOG3 ABI decode"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$sender")" \
  100 "minted sender balance"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'totalSupply()(uint256)')" \
  100 "totalSupply after mint"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'transfer(address,uint256)' "$dest" 30)"
printf '%s' "$receipt" | "$python" -I -S -c "
import json,sys
r=json.load(sys.stdin)
logs=r.get('logs') or []
want='$topic_xfer'.lower()
sender=int('$sender', 16)
dest=int('$dest', 16)
hit=None
for lg in logs:
    topics=lg.get('topics') or []
    if topics and topics[0].lower()==want:
        hit=lg
        break
if hit is None:
    raise SystemExit('FAIL: missing Transfer(address,address,uint256) log')
topics=hit.get('topics') or []
if len(topics)!=3:
    raise SystemExit(f'FAIL: Transfer should be LOG3, got {len(topics)} topics')
if int(topics[1],16)!=sender:
    raise SystemExit(f'FAIL: Transfer from {topics[1]} != sender')
if int(topics[2],16)!=dest:
    raise SystemExit(f'FAIL: Transfer to {topics[2]} != dest')
data=int(hit.get('data') or '0x0', 16)
if data!=30:
    raise SystemExit(f'FAIL: transfer log data {data} != 30')
"
pf_evm_typed_event_check "$abi" "$receipt" Transfer "$topic_xfer" \
  "{\"from\": \"$sender\", \"to\": \"$dest\", \"value\": 30}" "Transfer LOG3 ABI decode"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$sender")" \
  70 "sender after transfer"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$dest")" \
  30 "dest after transfer"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'totalSupply()(uint256)')" \
  100 "totalSupply unchanged by transfer"

if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'transfer(address,uint256)' "$zero" 1 >/dev/null 2>&1; then
  echo "FAIL: transfer to zero unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_zero_address "$addr" "$sender" \
  "$("$cast" calldata 'transfer(address,uint256)' "$zero" 1)" \
  "transfer to zero"

if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'approve(address,uint256)' "$zero" 1 >/dev/null 2>&1; then
  echo "FAIL: approve zero unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_zero_address "$addr" "$sender" \
  "$("$cast" calldata 'approve(address,uint256)' "$zero" 1)" \
  "approve zero"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'approve(address,uint256)' "$dest" 20)"
printf '%s' "$receipt" | "$python" -I -S -c "
import json,sys
r=json.load(sys.stdin)
logs=r.get('logs') or []
want='$topic_appr'.lower()
sender=int('$sender', 16)
dest=int('$dest', 16)
hit=None
for lg in logs:
    topics=lg.get('topics') or []
    if topics and topics[0].lower()==want:
        hit=lg
        break
if hit is None:
    raise SystemExit('FAIL: missing Approval(address,address,uint256) log')
topics=hit.get('topics') or []
if len(topics)!=3:
    raise SystemExit(f'FAIL: Approval should be LOG3, got {len(topics)} topics')
if int(topics[1],16)!=sender:
    raise SystemExit(f'FAIL: Approval owner {topics[1]} != sender')
if int(topics[2],16)!=dest:
    raise SystemExit(f'FAIL: Approval spender {topics[2]} != dest')
data=int(hit.get('data') or '0x0', 16)
if data!=20:
    raise SystemExit(f'FAIL: approval log data {data} != 20')
"
pf_evm_typed_event_check "$abi" "$receipt" Approval "$topic_appr" \
  "{\"owner\": \"$sender\", \"spender\": \"$dest\", \"value\": 20}" "Approval LOG3 ABI decode"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'allowance(address,address)(uint256)' "$sender" "$dest")" \
  20 "allowance after approve"

"$cast" send --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" 'transferFrom(address,address,uint256)' "$sender" "$dest" 5 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$sender")" \
  65 "owner after transferFrom"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$dest")" \
  35 "dest after transferFrom"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'allowance(address,address)(uint256)' "$sender" "$dest")" \
  15 "allowance after transferFrom"

got_name2="$("$cast" call --rpc-url "$rpc" "$addr" 'name()(string)')"
got_symbol2="$("$cast" call --rpc-url "$rpc" "$addr" 'symbol()(string)')"
got_name2="${got_name2#\"}"; got_name2="${got_name2%\"}"
got_symbol2="${got_symbol2#\"}"; got_symbol2="${got_symbol2%\"}"
pf_evm_require_equal "$got_name2" "Token" "string name holds after transfer"
pf_evm_require_equal "$got_symbol2" "PF" "string symbol holds after transfer"

echo "evm-anvil-erc20meta: ok (string name/symbol ABI + owner mint + LOG3 Transfer/Approval topics/data; engineering only)"
