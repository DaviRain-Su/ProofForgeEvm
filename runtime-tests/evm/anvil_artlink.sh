#!/usr/bin/env bash
# ArtLink: owner mint + bounded static tokenURI over Erc721 ledger. Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-artlink
bin="$root/build/evm/ArtLink.bin"
abi="$root/build/evm/ArtLink.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building ArtLink.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" ArtLink \
    || { echo "FAIL: pf build ArtLink failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18694}" "$root/build/evm/anvil-artlink.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty ArtLink.bin" >&2; exit 1; }

sender="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_address "$bytecode" "$sender")"
token_id=1
zero="0x0000000000000000000000000000000000000000"
static_uri="ipfs://QmPfLink"

strip_string() {
  local s="$1"
  s="${s#\"}"; s="${s%\"}"
  printf '%s' "$s"
}

supports_interface() { # interface id
  "$cast" call --rpc-url "$rpc" "$addr" 'supportsInterface(bytes4)(bool)' "$1"
}
pf_evm_require_equal "$(supports_interface 0x01ffc9a7)" true "IERC165 support"
pf_evm_require_equal "$(supports_interface 0x80ac58cd)" false "incomplete IERC721 is unsupported"
pf_evm_require_equal "$(supports_interface 0xd9b67a26)" false "IERC1155 is unsupported"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(address,uint256)' "$sender" "$token_id")"
sig_xfer="$(pf_evm_typed_event_sig "$abi" Transfer)"
topic_xfer="$("$cast" keccak "$sig_xfer")"
pf_evm_typed_event_check "$abi" "$receipt" Transfer "$topic_xfer" \
  "{\"from\": \"$zero\", \"to\": \"$sender\", \"tokenId\": $token_id}" \
  "mint Transfer LOG4"

pf_evm_require_equal "$(strip_string "$("$cast" call --rpc-url "$rpc" "$addr" \
  'tokenURI(uint256)(string)' "$token_id")")" "$static_uri" "minted tokenURI is static"

alias_id="$("$python" -I -S -c "print($token_id + (1 << 192))")"
pf_evm_require_equal "$(strip_string "$("$cast" call --rpc-url "$rpc" "$addr" \
  'tokenURI(uint256)(string)' "$alias_id")")" "" "unencodable alias tokenURI is empty"

echo "evm-anvil-artlink: ok (static tokenURI + mint fail-closed gates)"
