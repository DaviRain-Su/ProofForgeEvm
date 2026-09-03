#!/usr/bin/env bash
# Erc20Meta: ERC-20-shaped string name/symbol + standard allowance/transfer/approve.
# Receipts: canonical Transfer/Approval LOG3 (indexed from/to or owner/spender, uint256 data).
# Erc20Meta has no mint; the hashed Addr256 balance map is seeded Anvil-locally for a
# non-zero Transfer. Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

# Hashed Addr256 slot: keccak256(w0||w1||w2||base) with LE address limbs, base 0.
# Tag at slot, packed UInt256 payload at slot+1 (same geometry as HashedMap.Emit).
pf_erc20meta_balance_slots() {
  local who="$1"
  local blob raw
  blob="$("$python" -I -S -c "
addr=int('$who', 16)
b=addr.to_bytes(20, 'big')
w0=int.from_bytes(b[0:8], 'little')
w1=int.from_bytes(b[8:16], 'little')
w2=int.from_bytes(b[16:20], 'little')
print('0x' + (w0.to_bytes(32,'big') + w1.to_bytes(32,'big') +
              w2.to_bytes(32,'big') + (0).to_bytes(32,'big')).hex())
")"
  raw="$("$cast" keccak "$blob")"
  "$python" -I -S -c "s=int('$raw', 16); print(s); print(s+1)"
}

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
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'totalSupply()(uint256)')" \
  0 "absent total supply (no mint)"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$sender")" \
  0 "absent sender balance"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'allowance(address,address)(uint256)' "$sender" "$dest")" \
  0 "absent allowance"

# Seed hashed balance map: tag=1, payload=100. Anvil-local only (lib.sh fails closed otherwise).
{
  read -r tag_slot
  read -r payload_slot
} < <(pf_erc20meta_balance_slots "$sender")
pf_evm_set_storage_word "$addr" "$tag_slot" 1
pf_evm_set_storage_word "$addr" "$payload_slot" 100
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$sender")" \
  100 "seeded sender balance"

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
  0 "totalSupply is not updated (no mint path)"

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

echo "evm-anvil-erc20meta: ok (string name/symbol ABI + LOG3 Transfer/Approval topics/data; engineering only)"
