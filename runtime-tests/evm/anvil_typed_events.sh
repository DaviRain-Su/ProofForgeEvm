#!/usr/bin/env bash
# Typed events: address-indexed + uint256 data, boolean data, nested-ite Ticked once, and
# receipt decoding driven by the generated ABI JSON (topic0 signature, indexed geometry, canonical
# words).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-typed-events
bin="$root/build/evm/EvmTypedEvents.bin"
abi="$root/build/evm/EvmTypedEvents.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  lake build Examples.Evm.EvmTypedEvents >/dev/null
  lake exe pf -- build --target evm --out "$root/build/evm" EvmTypedEvents >/dev/null
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18689}" "$root/build/evm/anvil-typed-events.log"

# Canonical `Name(type,...)` of one event declared exactly once in the generated ABI.
pf_typed_event_sig() {
  local name="$1"
  "$python" -I -S -c "
import json
abi=json.load(open('$abi'))
events=[e for e in abi if e.get('type')=='event' and e.get('name')=='$name']
if len(events)!=1:
    raise SystemExit(f'FAIL: ABI must declare $name exactly once, got {len(events)}')
ev=events[0]
if ev.get('anonymous'):
    raise SystemExit('FAIL: $name must not be anonymous')
print(ev['name']+'('+','.join(i['type'] for i in ev['inputs'])+')')
"
}

# Decode the one receipt log with topic0 == keccak(sig) using the ABI declaration of NAME:
# indexed inputs come from topics in declaration order, non-indexed inputs from consecutive
# 32-byte data words. Every decoded word must be canonical for its type, and the decoded
# arguments must equal EXPECTED (JSON object keyed by input name; ints, bools, or hex
# addresses).
pf_typed_event_check() {
  local receipt="$1" name="$2" topic0="$3" expected="$4" label="$5"
  printf '%s' "$receipt" | "$python" -I -S -c "
import json,sys
abi=json.load(open('$abi'))
ev=[e for e in abi if e.get('type')=='event' and e.get('name')=='$name'][0]
inputs=ev['inputs']
want='$topic0'.lower()
expected=json.loads('''$expected''')
r=json.load(sys.stdin)
hits=[lg for lg in (r.get('logs') or []) if (lg.get('topics') or []) and lg['topics'][0].lower()==want]
if len(hits)!=1:
    raise SystemExit(f'FAIL: $label: expected exactly one $name log, got {len(hits)}')
lg=hits[0]
topics=lg['topics']
indexed=[i for i in inputs if i.get('indexed')]
plain=[i for i in inputs if not i.get('indexed')]
if len(topics)!=1+len(indexed):
    raise SystemExit(f'FAIL: $label: $name should carry {1+len(indexed)} topics, got {len(topics)}')
data=(lg.get('data') or '0x')[2:]
if len(data)!=64*len(plain):
    raise SystemExit(f'FAIL: $label: $name data should be {len(plain)} words, got {len(data)//2} bytes')
def decode(ty, word):
    v=int(word,16)
    if ty=='address':
        if v>>160:
            raise SystemExit(f'FAIL: $label: non-canonical address word {word}')
        return '0x%040x'%v
    if ty=='bool':
        if v>1:
            raise SystemExit(f'FAIL: $label: non-canonical bool word {word}')
        return v==1
    if ty.startswith('uint'):
        bits=int(ty[4:])
        if v>>bits:
            raise SystemExit(f'FAIL: $label: {ty} word {word} exceeds {bits} bits')
        return v
    raise SystemExit(f'FAIL: $label: unsupported ABI type {ty} in test decoder')
got={}
ti=1
di=0
for inp in inputs:
    if inp.get('indexed'):
        word=topics[ti][2:]; ti+=1
    else:
        word=data[di:di+64]; di+=64
    got[inp['name']]=decode(inp['type'], word)
norm={k:(v.lower() if isinstance(v,str) else v) for k,v in expected.items()}
if got!=norm:
    raise SystemExit(f'FAIL: $label: decoded {got} != expected {norm}')
"
}

bytecode="$(tr -d '\n\r ' < "$bin")"
sender="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_u64 "$bytecode" 0)"

pf_evm_require_storage "$addr" 0 0 "constructor ticks"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'ticksOf()(uint64)')" 0 \
  "initial ticks"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'flagOf()(bool)')" false \
  "initial flag"

dest_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
dest="$("$cast" wallet address --private-key "$dest_key")"

# The ABI JSON is the source of truth for signatures; pin them against the spec'd shapes too.
sig_xfer="$(pf_typed_event_sig Transferred)"
sig_flag="$(pf_typed_event_sig Flagged)"
sig_tick="$(pf_typed_event_sig Ticked)"
pf_evm_require_equal "$sig_xfer" 'Transferred(address,address,uint256)' "ABI Transferred signature"
pf_evm_require_equal "$sig_flag" 'Flagged(bool)' "ABI Flagged signature"
pf_evm_require_equal "$sig_tick" 'Ticked(uint64)' "ABI Ticked signature"
topic_xfer="$("$cast" keccak "$sig_xfer")"
topic_flag="$("$cast" keccak "$sig_flag")"
topic_tick="$("$cast" keccak "$sig_tick")"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'transfer(address,address,uint256)' "$sender" "$dest" 42)"
pf_typed_event_check "$receipt" Transferred "$topic_xfer" \
  "{\"from\": \"$sender\", \"to\": \"$dest\", \"value\": 42}" "Transferred LOG3"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'setFlag(bool)' true)"
pf_typed_event_check "$receipt" Flagged "$topic_flag" '{"ok": true}' "Flagged(true) LOG1"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'flagOf()(bool)')" true \
  "flag persisted"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'setFlag(bool)' false)"
pf_typed_event_check "$receipt" Flagged "$topic_flag" '{"ok": false}' "Flagged(false) LOG1"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'flagOf()(bool)')" false \
  "flag cleared"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'pulse(uint64)' 0)"
pf_typed_event_check "$receipt" Ticked "$topic_tick" '{"n": 0}' "Ticked n=0 branch"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'ticksOf()(uint64)')" 0 \
  "ticks untouched on n=0 branch"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'pulse(uint64)' 7)"
pf_typed_event_check "$receipt" Ticked "$topic_tick" '{"n": 7}' "Ticked n!=0 branch"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'ticksOf()(uint64)')" 7 \
  "ticks persisted from n!=0 branch"

echo "evm-anvil-typed-events: ok (ABI-decoded Transferred LOG3 + Flagged bool + nested Ticked; engineering only)"
