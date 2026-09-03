#!/usr/bin/env bash
# HeaderLink: bounded Blockhash/BlockHeader profile. Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-headerlink
bin="$root/build/evm/HeaderLink.bin"
abi="$root/build/evm/HeaderLink.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building HeaderLink.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" HeaderLink \
    || { echo "FAIL: pf build HeaderLink failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18699}" "$root/build/evm/anvil-headerlink.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty HeaderLink.bin" >&2; exit 1; }

encoded="$("$cast" abi-encode 'constructor(uint64)' 0)"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${encoded#0x}")"
addr="$(printf '%s' "$receipt" | pf_evm_contract_address)"

bn="$("$cast" block-number --rpc-url "$rpc")"
bn_dec="$(pf_evm_to_dec "$bn")"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'number()(uint64)')" \
  "$bn_dec" "NUMBER == block number"

block_env="$("$cast" block --rpc-url "$rpc" latest --json)"
ts="$(printf '%s' "$block_env" | "$python" -I -S -c 'import json,sys; print(json.load(sys.stdin)["timestamp"])')"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'timestamp()(uint64)')" \
  "$(pf_evm_to_dec "$ts")" "TIMESTAMP"

read -r block_base_fee block_gas_limit block_randao <<<"$(printf '%s' "$block_env" |
  "$python" -I -S -c '
import json, sys
b = json.load(sys.stdin)
def value(*names):
    for name in names:
        if name in b and b[name] is not None:
            return int(b[name], 16) if isinstance(b[name], str) else int(b[name])
    raise KeyError(names)
print(value("baseFeePerGas", "base_fee_per_gas"),
      value("gasLimit", "gas_limit"),
      value("mixHash", "mix_hash", "prevRandao", "prev_randao"))
')"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'baseFee()(uint256)')" \
  "$block_base_fee" "BASEFEE"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'gasLimit()(uint256)')" \
  "$block_gas_limit" "GASLIMIT"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'prevRandao()(uint256)')" \
  "$block_randao" "PREVRANDAO"

block_coinbase="$(printf '%s' "$block_env" | "$python" -I -S -c '
import json, sys
b = json.load(sys.stdin)
print((b.get("miner") or b.get("beneficiary") or b.get("author")).lower())
')"
pf_evm_require_equal \
  "$("$cast" call --rpc-url "$rpc" "$addr" 'coinbase()(address)' | tr '[:upper:]' '[:lower:]')" \
  "$block_coinbase" "COINBASE"

previous="$(( bn_dec - 1 ))"
previous_hash="$("$cast" block --rpc-url "$rpc" "$previous" --json |
  "$python" -I -S -c 'import json,sys; print(int(json.load(sys.stdin)["hash"], 16))')"
pf_evm_require_uint \
  "$("$cast" call --rpc-url "$rpc" "$addr" 'blockHash(uint64)(uint256)' "$previous")" \
  "$previous_hash" "BLOCKHASH previous block"

pf_evm_require_equal \
  "$("$cast" call --rpc-url "$rpc" "$addr" 'inHistoryWindow(uint64)(bool)' "$previous")" \
  true "previous block in history window"

old="$(( bn_dec - 300 ))"
if [[ "$old" -ge 0 ]]; then
  pf_evm_require_equal \
    "$("$cast" call --rpc-url "$rpc" "$addr" 'inHistoryWindow(uint64)(bool)' "$old")" \
    false "block older than 256 is outside history window"
  pf_evm_require_uint \
    "$("$cast" call --rpc-url "$rpc" "$addr" 'blockHash(uint64)(uint256)' "$old")" \
    0 "BLOCKHASH zero outside history window"
fi

future="$(( bn_dec + 1 ))"
pf_evm_require_equal \
  "$("$cast" call --rpc-url "$rpc" "$addr" 'inHistoryWindow(uint64)(bool)' "$future")" \
  false "future block outside history window"

echo "evm-anvil-headerlink: ok (header fields + BLOCKHASH history window; engineering only)"
