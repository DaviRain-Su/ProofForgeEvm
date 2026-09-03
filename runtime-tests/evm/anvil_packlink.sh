#!/usr/bin/env bash
# PackLink: owner mint + bounded static uri over Erc1155 ledger. Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-packlink
bin="$root/build/evm/PackLink.bin"
abi="$root/build/evm/PackLink.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building PackLink.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" PackLink \
    || { echo "FAIL: pf build PackLink failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18695}" "$root/build/evm/anvil-packlink.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty PackLink.bin" >&2; exit 1; }

sender="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_address "$bytecode" "$sender")"
token_id=7
amount=100
zero="0x0000000000000000000000000000000000000000"
static_uri="ipfs://QmPfPack"

strip_string() {
  local s="$1"
  s="${s#\"}"; s="${s%\"}"
  printf '%s' "$s"
}

supports_interface() { # interface id
  "$cast" call --rpc-url "$rpc" "$addr" 'supportsInterface(bytes4)(bool)' "$1"
}
pf_evm_require_equal "$(supports_interface 0x01ffc9a7)" true "IERC165 support"
pf_evm_require_equal "$(supports_interface 0xd9b67a26)" false "incomplete IERC1155 is unsupported"
pf_evm_require_equal "$(supports_interface 0x80ac58cd)" false "IERC721 is unsupported"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(address,uint256,uint256)' "$sender" "$token_id" "$amount")"
sig_xfer="$(pf_evm_typed_event_sig "$abi" TransferSingle)"
topic_xfer="$("$cast" keccak "$sig_xfer")"
pf_evm_typed_event_check "$abi" "$receipt" TransferSingle "$topic_xfer" \
  "{\"operator\": \"$sender\", \"from\": \"$zero\", \"to\": \"$sender\", \"id\": $token_id, \"value\": $amount}" \
  "mint TransferSingle LOG4"

pf_evm_require_equal "$(strip_string "$("$cast" call --rpc-url "$rpc" "$addr" \
  'uri(uint256)(string)' "$token_id")")" "$static_uri" "encodable uri is static"

alias_id="$("$python" -I -S -c "print($token_id + (1 << 192))")"
pf_evm_require_equal "$(strip_string "$("$cast" call --rpc-url "$rpc" "$addr" \
  'uri(uint256)(string)' "$alias_id")")" "" "unencodable alias uri is empty"

echo "evm-anvil-packlink: ok (static uri + encodable-id fail-closed gate)"
