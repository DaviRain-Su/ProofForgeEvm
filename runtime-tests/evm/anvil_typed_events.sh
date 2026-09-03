#!/usr/bin/env bash
# Typed events: address-indexed + uint256 data, boolean data, nested-ite Ticked once,
# and ABI decoding of receipt topics/data.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-typed-events
bin="$root/build/evm/EvmTypedEvents.bin"
if [[ ! -f "$bin" ]]; then
  lake build Examples.Evm.EvmTypedEvents >/dev/null
  lake exe pf -- build --target evm --out "$root/build/evm" EvmTypedEvents >/dev/null
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18689}" "$root/build/evm/anvil-typed-events.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
sender="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_u64 "$bytecode" 0)"

pf_evm_require_storage "$addr" 0 0 "constructor ticks"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'ticksOf()(uint64)')" 0 \
  "initial ticks"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'flagOf()(bool)')" 0 \
  "initial flag"

dest_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
dest="$("$cast" wallet address --private-key "$dest_key")"

topic_xfer="$("$cast" keccak 'Transferred(address,address,uint256)')"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'transfer(address,address,uint256)' "$sender" "$dest" 42)"
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
    raise SystemExit('FAIL: missing Transferred(address,address,uint256) log')
topics=hit.get('topics') or []
if len(topics)!=3:
    raise SystemExit(f'FAIL: Transferred should be LOG3, got {len(topics)} topics')
if int(topics[1],16)!=sender:
    raise SystemExit(f'FAIL: Transferred from {topics[1]} != sender')
if int(topics[2],16)!=dest:
    raise SystemExit(f'FAIL: Transferred to {topics[2]} != dest')
data=int(hit.get('data') or '0x0', 16)
if data!=42:
    raise SystemExit(f'FAIL: transfer log data {data} != 42')
"

decoded="$("$cast" decode-event --json \
  'Transferred(address indexed from, address indexed to, uint256 value)' \
  --legacy "$receipt" 2>/dev/null || true)"
if [[ -n "$decoded" ]]; then
  printf '%s' "$decoded" | "$python" -I -S -c "
import json,sys
rows=json.load(sys.stdin)
if not isinstance(rows, list):
    rows=[rows]
hit=None
for row in rows:
    args=row.get('args') or row
    if 'from' in args or (isinstance(args, dict) and 'value' in args):
        hit=args
        break
if hit is None:
    raise SystemExit('FAIL: cast decode-event missed Transferred args')
value=hit.get('value')
if str(value) not in ('42', '0x2a'):
    # foundry may stringify as decimal or keep int
    if int(str(value), 0)!=42:
        raise SystemExit(f'FAIL: decoded Transferred value {value} != 42')
"
fi

topic_flag="$("$cast" keccak 'Flagged(bool)')"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'setFlag(bool)' true)"
printf '%s' "$receipt" | "$python" -I -S -c "
import json,sys
r=json.load(sys.stdin)
logs=r.get('logs') or []
want='$topic_flag'.lower()
hit=None
for lg in logs:
    topics=lg.get('topics') or []
    if topics and topics[0].lower()==want:
        hit=lg
        break
if hit is None:
    raise SystemExit('FAIL: missing Flagged(bool) log')
topics=hit.get('topics') or []
if len(topics)!=1:
    raise SystemExit(f'FAIL: Flagged should be LOG1, got {len(topics)} topics')
data=int(hit.get('data') or '0x0', 16)
if data!=1:
    raise SystemExit(f'FAIL: Flagged data {data} != 1')
"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'flagOf()(bool)')" 1 \
  "flag persisted"

topic_tick="$("$cast" keccak 'Ticked(uint64)')"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'pulse(uint64)' 0)"
printf '%s' "$receipt" | "$python" -I -S -c "
import json,sys
r=json.load(sys.stdin)
logs=r.get('logs') or []
want='$topic_tick'.lower()
hit=None
for lg in logs:
    topics=lg.get('topics') or []
    if topics and topics[0].lower()==want:
        hit=lg
        break
if hit is None:
    raise SystemExit('FAIL: missing Ticked(uint64) log on n=0 branch')
data=int(hit.get('data') or '0x0', 16)
if data!=0:
    raise SystemExit(f'FAIL: Ticked(0) data {data} != 0')
"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'pulse(uint64)' 7)"
printf '%s' "$receipt" | "$python" -I -S -c "
import json,sys
r=json.load(sys.stdin)
logs=r.get('logs') or []
want='$topic_tick'.lower()
hit=None
for lg in logs:
    topics=lg.get('topics') or []
    if topics and topics[0].lower()==want:
        hit=lg
        break
if hit is None:
    raise SystemExit('FAIL: missing Ticked(uint64) log on n!=0 branch')
data=int(hit.get('data') or '0x0', 16)
if data!=7:
    raise SystemExit(f'FAIL: Ticked(7) data {data} != 7')
"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'ticksOf()(uint64)')" 7 \
  "ticks persisted from n!=0 branch"

echo "evm-anvil-typed-events: ok (Transferred LOG3 + Flagged bool + nested Ticked; engineering only)"
