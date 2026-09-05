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

# Stamp the next mined block. Do not evm_mine after this when the following
# send must land on that exact timestamp. A mined empty block consumes the stamp
# and Anvil's following tx is parent+1.
pf_evm_stamp_next() {
  "$cast" rpc --rpc-url "$rpc" evm_setNextBlockTimestamp "$1" >/dev/null
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

# eth_call must revert with ABI error OwnableInvalidOwner(address).
pf_evm_require_ownable_invalid_owner() {
  local addr="$1" from="$2" data="$3" who="$4" message="$5"
  local sel
  sel="$("$cast" keccak 'OwnableInvalidOwner(address)')"
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
    raise SystemExit('FAIL: $message: missing OwnableInvalidOwner(owner) (got '+repr(err)+')')
got=blob[8+24:8+64]
if got != '$who':
    raise SystemExit(f'FAIL: $message: OwnableInvalidOwner(0x{got}) != 0x$who')
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

# eth_call must revert with ABI error OwnableUnauthorizedAccount(address).
pf_evm_require_ownable_unauthorized_account() {
  local addr="$1" from="$2" data="$3" who="$4" message="$5"
  local sel
  sel="$("$cast" keccak 'OwnableUnauthorizedAccount(address)')"
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
    raise SystemExit('FAIL: $message: missing OwnableUnauthorizedAccount(who) (got '+repr(err)+')')
got=blob[8+24:8+64]
if got != '$who':
    raise SystemExit(f'FAIL: $message: OwnableUnauthorizedAccount(0x{got}) != 0x$who')
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

# eth_call must revert with empty returndata: the `revert(0, 0)` of checked arithmetic and
# decoder guards, as opposed to a typed error.
pf_evm_require_empty_revert() {
  local addr="$1" from="$2" data="$3" message="$4"
  "$python" -I -S - "$rpc" "$addr" "$from" "$data" "$message" <<'PY'
import json, sys, urllib.error, urllib.request

rpc, addr, sender, data, message = sys.argv[1:]
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
failure = response.get("error")
if failure is None:
    raise SystemExit(f"FAIL: {message}: call succeeded with {response.get('result')!r}")
blob = failure.get("data") or ""
if isinstance(blob, dict):
    blob = blob.get("data") or blob.get("raw") or ""
blob = str(blob).lower().removeprefix("0x")
if blob != "":
    raise SystemExit(f"FAIL: {message}: expected empty returndata, got {blob!r}")
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

# CREATE simulation must revert with ABI error OwnableInvalidOwner(address(0)).
# BYTECODE is the creation hex without 0x. ENCODED is the ABI-encoded constructor
# args including 0x.
pf_evm_require_create_ownable_invalid_owner() {
  local bytecode="$1" encoded="$2" from="$3" message="$4"
  local sel data
  sel="$("$cast" keccak 'OwnableInvalidOwner(address)')"
  sel="${sel#0x}"
  sel="$(printf '%s' "$sel" | cut -c1-8 | tr 'A-Z' 'a-z')"
  data="0x${bytecode}${encoded#0x}"
  "$python" -I -S -c "
import json, urllib.request, urllib.error
rpc='$rpc'
payload={
  'jsonrpc':'2.0','id':1,'method':'eth_call',
  'params':[{'from':'$from','data':'$data'}, 'latest']
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
    raise SystemExit('FAIL: $message: missing OwnableInvalidOwner(owner) (got '+repr(err)+')')
got=blob[8+24:8+64]
if got != '0'*40:
    raise SystemExit(f'FAIL: $message: OwnableInvalidOwner(0x{got}) != address(0)')
"
}

# CREATE simulation must succeed. Used after stripping the constructor
# OwnableInvalidOwner guard. Fails if that mutation still reverts OwnableInvalidOwner.
pf_evm_require_create_ok() {
  local bytecode="$1" encoded="$2" from="$3" message="$4"
  local sel data
  sel="$("$cast" keccak 'OwnableInvalidOwner(address)')"
  sel="${sel#0x}"
  sel="$(printf '%s' "$sel" | cut -c1-8 | tr 'A-Z' 'a-z')"
  data="0x${bytecode}${encoded#0x}"
  "$python" -I -S -c "
import json, urllib.request, urllib.error
rpc='$rpc'
payload={
  'jsonrpc':'2.0','id':1,'method':'eth_call',
  'params':[{'from':'$from','data':'$data'}, 'latest']
}
req=urllib.request.Request(rpc, data=json.dumps(payload).encode(),
  headers={'Content-Type':'application/json'})
try:
    raw=urllib.request.urlopen(req).read().decode()
except urllib.error.HTTPError as e:
    raw=e.read().decode()
resp=json.loads(raw)
err=resp.get('error') or {}
if not err:
    raise SystemExit(0)
blob=(err.get('data') or '')
if isinstance(blob, dict):
    blob=blob.get('data') or blob.get('raw') or ''
blob=str(blob).lower()
if blob.startswith('0x'):
    blob=blob[2:]
sel='$sel'
if blob.startswith(sel):
    raise SystemExit('FAIL: mutation unexpectedly still reverted')
raise SystemExit('FAIL: $message: CREATE still reverted ('+repr(err)+')')
"
}

# Write DEST_YUL from SRC_YUL with the constructor-only OwnableInvalidOwner revert
# removed once. NAME is the Yul object (VestLink / Vest20Link / TwoStepCounter / Credits).
# Fourth argument 0 skips the runtime-selector check for consumers whose transferOwnership
# still uses ZeroAddress.
pf_evm_strip_ctor_invalid_owner_guard() {
  local src="$1" name="$2" dest="$3"
  local need_runtime="${4:-1}"
  "$python" -I -S -c "
from pathlib import Path
import re, sys
src = Path('$src').read_text()
marker = 'object \"${name}_runtime\"'
idx = src.find(marker)
if idx < 0:
    sys.stderr.write(f'FAIL: missing {marker}\\n')
    sys.exit(1)
head, tail = src[:idx], src[idx:]
pat = (
    r'let pf_owner := [^\\n]+\\n'
    r'\\s*mstore\\(0, shl\\(224, 0x1e4fbdf7\\)\\)\\s*'
    r'mstore\\(4, pf_owner\\)\\s*revert\\(0, 36\\)'
)
out, k = re.subn(pat, '', head, count=1)
if k != 1:
    sys.stderr.write(f'FAIL: constructor OwnableInvalidOwner revert not found (k={k})\\n')
    sys.exit(1)
need_runtime = int('$need_runtime')
if need_runtime and '0x1e4fbdf7' not in tail:
    sys.stderr.write('FAIL: runtime lost OwnableInvalidOwner selector after constructor strip\\n')
    sys.exit(1)
Path('$dest').write_text(out + tail)
print('stripped one constructor OwnableInvalidOwner revert; runtime selector kept')
"
}

# Write DEST_YUL from SRC_YUL with the constructor-only OwnershipTransferred LOG3
# removed once. NAME is the Yul object. The runtime object must keep the topic so
# transferOwnership is not stripped.
pf_evm_strip_ctor_ownership_log() {
  local src="$1" name="$2" dest="$3"
  "$python" -I -S -c "
from pathlib import Path
import re, sys
src = Path('$src').read_text()
marker = 'object \"${name}_runtime\"'
idx = src.find(marker)
if idx < 0:
    sys.stderr.write(f'FAIL: missing {marker}\\n')
    sys.exit(1)
head, tail = src[:idx], src[idx:]
topic = '0x8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e0'
pat = r'log3\\(0, 0, ' + re.escape(topic) + r', [^)]+\\)'
out, k = re.subn(pat, '', head, count=1)
if k != 1:
    sys.stderr.write(f'FAIL: constructor OwnershipTransferred log3 not found (k={k})\\n')
    sys.exit(1)
if topic not in tail:
    sys.stderr.write('FAIL: runtime lost OwnershipTransferred topic after constructor strip\\n')
    sys.exit(1)
Path('$dest').write_text(out + tail)
print('stripped one constructor OwnershipTransferred log3; runtime topic kept')
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

# Decode the receipt log with topic0 == keccak(sig) using the ABI declaration of NAME:
# indexed inputs come from topics in declaration order, non-indexed inputs from the data
# section: one head word per input, holding the value for a static type or the byte offset of
# the tail for a `T[]` type. A tail is a length word followed by `length` element words. The
# layout must be canonical: tails follow the head in declaration order with no gap, every
# offset is exactly where the previous tail ended, and the data ends with the last tail. Every
# decoded word must be canonical for its type, and the decoded arguments must equal EXPECTED
# (JSON object keyed by input name; ints, bools, hex addresses, or lists of those). The receipt
# must carry exactly COUNT such logs (default 1) and INDEX (default 0) selects which one is
# decoded, in log order.
pf_evm_typed_event_check() {
  local abi_json="$1" receipt="$2" name="$3" topic0="$4" expected="$5" label="$6"
  local count="${7:-1}" index="${8:-0}"
  printf '%s' "$receipt" | "$python" -I -S -c "
import json,sys
abi=json.load(open('$abi_json'))
ev=[e for e in abi if e.get('type')=='event' and e.get('name')=='$name'][0]
inputs=ev['inputs']
want='$topic0'.lower()
expected=json.loads('''$expected''')
r=json.load(sys.stdin)
hits=[lg for lg in (r.get('logs') or []) if (lg.get('topics') or []) and lg['topics'][0].lower()==want]
if len(hits)!=$count:
    raise SystemExit(f'FAIL: $label: expected $name log count $count, got {len(hits)}')
if $count == 0:
    raise SystemExit(0)
lg=hits[$index]
topics=lg['topics']
indexed=[i for i in inputs if i.get('indexed')]
plain=[i for i in inputs if not i.get('indexed')]
if len(topics)!=1+len(indexed):
    raise SystemExit(f'FAIL: $label: $name should carry {1+len(indexed)} topics, got {len(topics)}')
data=(lg.get('data') or '0x')[2:]
if len(data)%64:
    raise SystemExit(f'FAIL: $label: $name data is {len(data)//2} bytes, not whole words')
words=len(data)//64
if words<len(plain):
    raise SystemExit(f'FAIL: $label: $name data should hold {len(plain)} head words, got {words}')
def word_at(i):
    return data[i*64:(i+1)*64]
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
tail=len(plain)
for inp in inputs:
    ty=inp['type']
    if inp.get('indexed'):
        if ty.endswith('[]'):
            raise SystemExit(f'FAIL: $label: indexed {ty} is not a decodable topic')
        got[inp['name']]=decode(ty, topics[ti][2:]); ti+=1
        continue
    head=word_at(di); di+=1
    if not ty.endswith('[]'):
        got[inp['name']]=decode(ty, head)
        continue
    offset=int(head,16)
    if offset!=tail*32:
        raise SystemExit(f'FAIL: $label: {inp[\"name\"]} offset {offset} is not the canonical {tail*32}')
    length=int(word_at(tail),16)
    if tail+1+length>words:
        raise SystemExit(f'FAIL: $label: {inp[\"name\"]} length {length} overruns the data')
    elem=ty[:-2]
    got[inp['name']]=[decode(elem, word_at(tail+1+k)) for k in range(length)]
    tail+=1+length
if words!=tail:
    raise SystemExit(f'FAIL: $label: $name data holds {words} words, canonical encoding is {tail}')
def norm(v):
    if isinstance(v,str):
        return v.lower()
    if isinstance(v,list):
        return [norm(x) for x in v]
    return v
want_args={k:norm(v) for k,v in expected.items()}
if got!=want_args:
    raise SystemExit(f'FAIL: $label: decoded {got} != expected {want_args}')
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
