# Shared Anvil / RPC helpers for Darwin and Linux.
# Source after `set -euo pipefail`. Sets: root, anvil, cast, python, chain_id, private_key,
# rpc (after start), anvil_mode (1 = locally launched Anvil).
#
# Env:
#   PF_EVM_RPC_URL      If set, skip launching Anvil and use this JSON-RPC URL.
#                       PF_EVM_CHAIN_ID is then required (fail-closed; no 31338 default).
#   PF_EVM_CHAIN_ID     Expected chain id. Local Anvil default: 31338.
#   PF_EVM_PRIVATE_KEY  Signing key (never written to disk). Required for external RPC;
#                       local Anvil default: account 0.
#   PF_EVM_PORT         Preferred loopback port for a locally launched Anvil.
#   FOUNDRY_BIN         Optional directory containing `anvil` / `cast`.
#
# Missing tools on the local-Anvil path → skip (exit 0), not pass. Unsupported OS → skip.
# Configured external RPC that mismatches chain-id or is unreachable → fail (exit 1).

pf_evm_evm_root() {
  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/lakefile.lean" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "FAIL: cannot locate ProofForge repo root from ${BASH_SOURCE[1]}" >&2
  return 1
}

pf_evm_python() {
  if command -v python3 >/dev/null 2>&1; then
    echo python3
  elif command -v python >/dev/null 2>&1; then
    echo python
  else
    return 1
  fi
}

# Prefer FOUNDRY_BIN, then ~/.foundry/bin (foundryup on macOS and Linux), then PATH.
pf_evm_find_tool() {
  local name="$1"
  local dir candidate
  if [[ -n "${FOUNDRY_BIN:-}" ]]; then
    candidate="${FOUNDRY_BIN%/}/$name"
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  fi
  if [[ -n "${HOME:-}" ]]; then
    candidate="$HOME/.foundry/bin/$name"
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  fi
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  for dir in /usr/local/bin /opt/homebrew/bin /usr/bin; do
    candidate="$dir/$name"
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

pf_evm_evm_init() {
  local label="${1:-evm-anvil}"
  case "$(uname -s)" in
    Darwin|Linux) ;;
    *)
      echo "$label: skip: unsupported host $(uname -s) (want Darwin or Linux)" >&2
      exit 0
      ;;
  esac
  root="$(pf_evm_evm_root)"
  cd "$root"
  python="$(pf_evm_python)" || {
    echo "$label: skip: python3/python not found" >&2
    exit 0
  }
  cast="$(pf_evm_find_tool cast)" || {
    echo "$label: skip: cast not found (install foundryup, or set FOUNDRY_BIN)" >&2
    exit 0
  }
  anvil=""
  anvil_pid=""
  if [[ -n "${PF_EVM_RPC_URL:-}" ]]; then
    anvil_mode=0
    rpc="$PF_EVM_RPC_URL"
    if [[ -z "${PF_EVM_CHAIN_ID:-}" ]]; then
      echo "$label: FAIL: PF_EVM_RPC_URL is set but PF_EVM_CHAIN_ID is missing (fail-closed)" >&2
      exit 1
    fi
    if [[ -z "${PF_EVM_PRIVATE_KEY:-}" ]]; then
      echo "$label: FAIL: PF_EVM_RPC_URL is set but PF_EVM_PRIVATE_KEY is missing (fail-closed)" >&2
      exit 1
    fi
    chain_id="$PF_EVM_CHAIN_ID"
    private_key="$PF_EVM_PRIVATE_KEY"
  else
    anvil_mode=1
    anvil="$(pf_evm_find_tool anvil)" || {
      echo "$label: skip: anvil not found (install foundryup, or set FOUNDRY_BIN)" >&2
      exit 0
    }
    chain_id="${PF_EVM_CHAIN_ID:-31338}"
    # Public Anvil account 0 is safe only for the local node this helper launches.
    private_key="${PF_EVM_PRIVATE_KEY:-ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
  fi
}

pf_evm_to_dec() {
  local x="$1"
  x="${x//$'\n'/}"
  x="${x%%[*}"
  x="${x// /}"
  if [[ -z "$x" ]]; then
    echo ""
    return
  fi
  if [[ "$x" == 0x* || "$x" == 0X* ]]; then
    "$python" -I -S -c "print(int('$x', 16))"
  else
    echo "$x"
  fi
}

pf_evm_require_equal() {
  local actual="$1" expected="$2" message="$3"
  [[ "$actual" == "$expected" ]] || {
    echo "FAIL: $message (expected '$expected', got '$actual')" >&2
    exit 1
  }
}

pf_evm_require_uint() {
  local raw="$1" expected="$2" message="$3"
  pf_evm_require_equal "$(pf_evm_to_dec "$raw")" "$expected" "$message (raw='$raw')"
}

pf_evm_require_storage() {
  local addr="$1" slot="$2" expected="$3" message="$4"
  local raw
  raw="$("$cast" storage --rpc-url "$rpc" "$addr" "$slot")"
  pf_evm_require_uint "$raw" "$expected" "$message (slot $slot)"
}

# Observed JSON-RPC chain id must equal $chain_id before any signing/deploy.
pf_evm_require_rpc_chain_id() {
  local message="${1:-RPC chain identity mismatch}"
  local observed
  observed="$("$cast" chain-id --rpc-url "$rpc")" || {
    echo "FAIL: cannot read chain-id from $rpc" >&2
    exit 1
  }
  pf_evm_require_equal "$observed" "$chain_id" "$message"
}

# Anvil-only corruption probe: replace one full storage word so fail-closed malformed-state paths
# can be exercised. Production/deployment scripts never call this helper. Disabled on any RPC we
# did not launch locally (including an external Anvil) because anvil_setStorageAt is not a
# JSON-RPC contract.
pf_evm_set_storage_word() {
  local addr="$1" slot="$2" value="$3"
  local slot_word value_word
  if [[ "${anvil_mode:-1}" != 1 ]]; then
    echo "FAIL: anvil_setStorageAt is disabled on non-Anvil RPC ($rpc)" >&2
    exit 1
  fi
  slot_word="$("$python" -I -S -c "print(f'0x{int(\"$slot\"):064x}')")"
  value_word="$("$python" -I -S -c "print(f'0x{int(\"$value\"):064x}')")"
  "$cast" rpc --rpc-url "$rpc" anvil_setStorageAt \
    "$addr" "$slot_word" "$value_word" >/dev/null
}

pf_evm_contract_address() {
  "$python" -I -S -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])'
}

pf_evm_ensure_bin() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "assembling $path" >&2
    lake exe pfEvmAssemble -- "$root/build/evm" >/dev/null \
      || { echo "FAIL: lake exe pfEvmAssemble failed" >&2; exit 1; }
  fi
  [[ -f "$path" ]] || { echo "FAIL: missing $path" >&2; exit 1; }
}

pf_evm_stop_anvil() {
  if [[ "${anvil_mode:-1}" != 1 ]]; then
    return 0
  fi
  if [[ -n "${anvil_pid:-}" ]]; then
    kill "$anvil_pid" 2>/dev/null || true
    wait "$anvil_pid" 2>/dev/null || true
    anvil_pid=""
  fi
}

# Attach to PF_EVM_RPC_URL, or start Anvil on $port. Sets rpc, anvil_pid (local only).
# Traps cleanup for a locally launched node. Safe to call again to restart with a new chain_id.
pf_evm_start_anvil() {
  local port="$1"
  local log="$2"
  if [[ "${anvil_mode:-1}" != 1 ]]; then
    rpc="${PF_EVM_RPC_URL:-$rpc}"
    pf_evm_require_rpc_chain_id "external RPC chain identity mismatch"
    return 0
  fi
  pf_evm_stop_anvil
  rpc="http://127.0.0.1:$port"
  local wait_i
  for wait_i in $(seq 1 20); do
    if ! "$cast" chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
  if "$cast" chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
    echo "FAIL: RPC endpoint $rpc is already occupied" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$log")"
  "$anvil" --host 127.0.0.1 --port "$port" --chain-id "$chain_id" \
    --silent >"$log" 2>&1 &
  anvil_pid=$!
  cleanup() {
    kill "$anvil_pid" 2>/dev/null || true
    wait "$anvil_pid" 2>/dev/null || true
  }
  trap cleanup EXIT
  local ready=0 i
  for i in $(seq 1 50); do
    if ! kill -0 "$anvil_pid" 2>/dev/null; then
      echo "FAIL: anvil exited before readiness; see $log" >&2
      exit 1
    fi
    if "$cast" chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 0.1
  done
  [[ "$ready" == 1 ]] || { echo "FAIL: anvil failed to start; see $log" >&2; exit 1; }
  pf_evm_require_rpc_chain_id "launched Anvil chain identity mismatch"
}

pf_evm_deploy_ctor_u64() {
  local bytecode="$1"
  local initial="$2"
  local encoded receipt
  pf_evm_require_rpc_chain_id "refusing to sign deploy: chain identity mismatch"
  encoded="$("$cast" abi-encode 'constructor(uint64)' "$initial")"
  receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
    --create "0x${bytecode}${encoded#0x}")"
  printf '%s' "$receipt" | pf_evm_contract_address
}

pf_evm_deploy_ctor_u64x3() {
  local bytecode="$1"
  local a="$2"
  local b="$3"
  local c="$4"
  local encoded receipt
  pf_evm_require_rpc_chain_id "refusing to sign deploy: chain identity mismatch"
  encoded="$("$cast" abi-encode 'constructor(uint64,uint64,uint64)' "$a" "$b" "$c")"
  receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
    --create "0x${bytecode}${encoded#0x}")"
  printf '%s' "$receipt" | pf_evm_contract_address
}

# eth_call must revert with ABI error Insufficient(uint256,uint256).
pf_evm_require_insufficient() {
  local addr="$1" from="$2" data="$3" have="$4" want="$5" message="$6"
  local sel
  sel="$("$cast" keccak 'Insufficient(uint256,uint256)')"
  sel="${sel#0x}"
  sel="$(printf '%s' "$sel" | cut -c1-8 | tr 'A-Z' 'a-z')"
  "$python" -I -S -c "
import json, urllib.request, urllib.error
rpc='$rpc'
payload={
  'jsonrpc':'2.0','id':1,'method':'eth_call',
  'params':[{'to':'$addr','from':'$from','data':'$data'}, 'latest']
}
req=urllib.request.Request(rpc, data=json.dumps(payload).encode(),
  headers={'Content-Type':'application/json'})
try:
    raw=urllib.request.urlopen(req).read().decode()
except urllib.error.HTTPError as e:
    raw=e.read().decode()
resp=json.loads(raw)
err=resp.get('error') or {}
blob=(err.get('data') or '')
if isinstance(blob, dict):
    blob=blob.get('data') or blob.get('raw') or ''
blob=str(blob).lower()
if blob.startswith('0x'):
    blob=blob[2:]
sel='$sel'
if len(blob) < 8+64+64 or not blob.startswith(sel):
    raise SystemExit('FAIL: $message: missing Insufficient(have,want) (got '+repr(err)+' result='+repr(resp.get('result'))+')')
have=int(blob[8:72], 16)
want=int(blob[72:136], 16)
if have != int('$have') or want != int('$want'):
    raise SystemExit(f'FAIL: $message: Insufficient({have},{want}) != ($have,$want)')
"
}

# eth_call must revert with ABI error Unauthorized(address).
pf_evm_require_unauthorized() {
  local addr="$1" from="$2" data="$3" who="$4" message="$5"
  local sel
  sel="$("$cast" keccak 'Unauthorized(address)')"
  sel="${sel#0x}"
  sel="$(printf '%s' "$sel" | cut -c1-8 | tr 'A-Z' 'a-z')"
  who="$(printf '%s' "$who" | tr 'A-Z' 'a-z')"
  who="${who#0x}"
  "$python" -I -S -c "
import json, urllib.request, urllib.error
rpc='$rpc'
payload={
  'jsonrpc':'2.0','id':1,'method':'eth_call',
  'params':[{'to':'$addr','from':'$from','data':'$data'}, 'latest']
}
req=urllib.request.Request(rpc, data=json.dumps(payload).encode(),
  headers={'Content-Type':'application/json'})
try:
    raw=urllib.request.urlopen(req).read().decode()
except urllib.error.HTTPError as e:
    raw=e.read().decode()
resp=json.loads(raw)
err=resp.get('error') or {}
blob=(err.get('data') or '')
if isinstance(blob, dict):
    blob=blob.get('data') or blob.get('raw') or ''
blob=str(blob).lower()
if blob.startswith('0x'):
    blob=blob[2:]
sel='$sel'
if len(blob) < 8+64 or not blob.startswith(sel):
    raise SystemExit('FAIL: $message: missing Unauthorized(who) (got '+repr(err)+')')
got=blob[8+24:8+64]
if got != '$who':
    raise SystemExit(f'FAIL: $message: Unauthorized(0x{got}) != 0x$who')
"
}

# eth_call must revert with the ABI error of the given signature (e.g. 'oob()'), no arguments.
pf_evm_require_named_revert() {
  local addr="$1" from="$2" data="$3" signature="$4" message="$5"
  local sel
  sel="$("$cast" keccak "$signature")"
  sel="${sel#0x}"
  sel="$(printf '%s' "$sel" | cut -c1-8 | tr 'A-Z' 'a-z')"
  "$python" -I -S -c "
import json, urllib.request, urllib.error
rpc='$rpc'
payload={
  'jsonrpc':'2.0','id':1,'method':'eth_call',
  'params':[{'to':'$addr','from':'$from','data':'$data'}, 'latest']
}
req=urllib.request.Request(rpc, data=json.dumps(payload).encode(),
  headers={'Content-Type':'application/json'})
try:
    raw=urllib.request.urlopen(req).read().decode()
except urllib.error.HTTPError as e:
    raw=e.read().decode()
resp=json.loads(raw)
err=resp.get('error') or {}
blob=(err.get('data') or '')
if isinstance(blob, dict):
    blob=blob.get('data') or blob.get('raw') or ''
blob=str(blob).lower()
if blob.startswith('0x'):
    blob=blob[2:]
sel='$sel'
if len(blob) < 8 or not blob.startswith(sel):
    raise SystemExit('FAIL: $message: missing $signature revert (got '+repr(err)+')')
"
}

# eth_call must revert with the exact selector and ordered ABI uint words supplied after message.
pf_evm_require_word_revert() {
  local addr="$1" from="$2" data="$3" signature="$4" message="$5"
  shift 5
  local sel
  sel="$("$cast" keccak "$signature")"
  sel="${sel#0x}"
  sel="$(printf '%s' "$sel" | cut -c1-8 | tr 'A-Z' 'a-z')"
  "$python" -I -S - "$rpc" "$addr" "$from" "$data" "$sel" "$signature" "$message" "$@" <<'PY'
import json, sys, urllib.error, urllib.request

rpc, addr, sender, data, selector, signature, message, *words = sys.argv[1:]
payload = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "eth_call",
    "params": [{"to": addr, "from": sender, "data": data}, "latest"],
}
request = urllib.request.Request(
    rpc,
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json"},
)
try:
    raw = urllib.request.urlopen(request).read().decode()
except urllib.error.HTTPError as error:
    raw = error.read().decode()
response = json.loads(raw)
failure = response.get("error") or {}
blob = failure.get("data") or ""
if isinstance(blob, dict):
    blob = blob.get("data") or blob.get("raw") or ""
blob = str(blob).lower().removeprefix("0x")
expected = selector + "".join(f"{int(word, 0):064x}" for word in words)
if blob != expected:
    raise SystemExit(
        f"FAIL: {message}: {signature} returndata {blob!r} != {expected!r} "
        f"(error={failure!r})"
    )
PY
}

# eth_call must revert with ABI error CapExceeded().
pf_evm_require_cap_exceeded() {
  local addr="$1" from="$2" data="$3" message="$4"
  local sel
  sel="$("$cast" keccak 'CapExceeded()')"
  sel="${sel#0x}"
  sel="$(printf '%s' "$sel" | cut -c1-8 | tr 'A-Z' 'a-z')"
  "$python" -I -S -c "
import json, urllib.request, urllib.error
rpc='$rpc'
payload={
  'jsonrpc':'2.0','id':1,'method':'eth_call',
  'params':[{'to':'$addr','from':'$from','data':'$data'}, 'latest']
}
req=urllib.request.Request(rpc, data=json.dumps(payload).encode(),
  headers={'Content-Type':'application/json'})
try:
    raw=urllib.request.urlopen(req).read().decode()
except urllib.error.HTTPError as e:
    raw=e.read().decode()
resp=json.loads(raw)
err=resp.get('error') or {}
blob=(err.get('data') or '')
if isinstance(blob, dict):
    blob=blob.get('data') or blob.get('raw') or ''
blob=str(blob).lower()
if blob.startswith('0x'):
    blob=blob[2:]
sel='$sel'
if len(blob) < 8 or not blob.startswith(sel):
    raise SystemExit('FAIL: $message: missing CapExceeded() (got '+repr(err)+')')
"
}

# eth_call must revert with ABI error Paused().
pf_evm_require_paused() {
  local addr="$1" from="$2" data="$3" message="$4"
  local sel
  sel="$("$cast" keccak 'Paused()')"
  sel="${sel#0x}"
  sel="$(printf '%s' "$sel" | cut -c1-8 | tr 'A-Z' 'a-z')"
  "$python" -I -S -c "
import json, urllib.request, urllib.error
rpc='$rpc'
payload={
  'jsonrpc':'2.0','id':1,'method':'eth_call',
  'params':[{'to':'$addr','from':'$from','data':'$data'}, 'latest']
}
req=urllib.request.Request(rpc, data=json.dumps(payload).encode(),
  headers={'Content-Type':'application/json'})
try:
    raw=urllib.request.urlopen(req).read().decode()
except urllib.error.HTTPError as e:
    raw=e.read().decode()
resp=json.loads(raw)
err=resp.get('error') or {}
blob=(err.get('data') or '')
if isinstance(blob, dict):
    blob=blob.get('data') or blob.get('raw') or ''
blob=str(blob).lower()
if blob.startswith('0x'):
    blob=blob[2:]
sel='$sel'
if len(blob) < 8 or not blob.startswith(sel):
    raise SystemExit('FAIL: $message: missing Paused() (got '+repr(err)+')')
"
}

# eth_call must revert with ABI error ZeroAddress().
pf_evm_require_zero_address() {
  local addr="$1" from="$2" data="$3" message="$4"
  local sel
  sel="$("$cast" keccak 'ZeroAddress()')"
  sel="${sel#0x}"
  sel="$(printf '%s' "$sel" | cut -c1-8 | tr 'A-Z' 'a-z')"
  "$python" -I -S -c "
import json, urllib.request, urllib.error
rpc='$rpc'
payload={
  'jsonrpc':'2.0','id':1,'method':'eth_call',
  'params':[{'to':'$addr','from':'$from','data':'$data'}, 'latest']
}
req=urllib.request.Request(rpc, data=json.dumps(payload).encode(),
  headers={'Content-Type':'application/json'})
try:
    raw=urllib.request.urlopen(req).read().decode()
except urllib.error.HTTPError as e:
    raw=e.read().decode()
resp=json.loads(raw)
err=resp.get('error') or {}
blob=(err.get('data') or '')
if isinstance(blob, dict):
    blob=blob.get('data') or blob.get('raw') or ''
blob=str(blob).lower()
if blob.startswith('0x'):
    blob=blob[2:]
sel='$sel'
if len(blob) < 8 or not blob.startswith(sel):
    raise SystemExit('FAIL: $message: missing ZeroAddress() (got '+repr(err)+')')
"
}

pf_evm_deploy_ctor_address() {
  local bytecode="$1"
  local addr="$2"
  local encoded receipt
  pf_evm_require_rpc_chain_id "refusing to sign deploy: chain identity mismatch"
  encoded="$("$cast" abi-encode 'constructor(address)' "$addr")"
  receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
    --create "0x${bytecode}${encoded#0x}")"
  printf '%s' "$receipt" | pf_evm_contract_address
}

# Canonical `Name(type,...)` of one event declared exactly once in ABI_JSON.
pf_evm_typed_event_sig() {
  local abi_json="$1" name="$2"
  "$python" -I -S -c "
import json
abi=json.load(open('$abi_json'))
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
pf_evm_typed_event_check() {
  local abi_json="$1" receipt="$2" name="$3" topic0="$4" expected="$5" label="$6"
  printf '%s' "$receipt" | "$python" -I -S -c "
import json,sys
abi=json.load(open('$abi_json'))
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
    if ty.startswith('bytes'):
        n=int(ty[5:])
        if n < 1 or n > 32:
            raise SystemExit(f'FAIL: $label: unsupported {ty}')
        if len(word) != 64:
            raise SystemExit(f'FAIL: $label: {ty} topic/data word {word} is not 32 bytes')
        return '0x'+word.lower()
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

# Assert the receipt has no log whose topic0 equals the ABI event NAME signature hash.
pf_evm_typed_event_absent() {
  local receipt="$1" name="$2" topic0="$3" label="$4"
  printf '%s' "$receipt" | "$python" -I -S -c "
import json,sys
want='$topic0'.lower()
r=json.load(sys.stdin)
hits=[lg for lg in (r.get('logs') or []) if (lg.get('topics') or []) and lg['topics'][0].lower()==want]
if hits:
    raise SystemExit(f'FAIL: $label: expected no $name log, got {len(hits)}')
"
}
