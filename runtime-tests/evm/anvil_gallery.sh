#!/usr/bin/env bash
# Gallery: capacity-4 IERC721Enumerable (UInt64 ids). Mint, owner-list swap-remove on
# transfer, global swap-remove on burn, CapExceeded on a fifth live token, and a
# tokenByIndex selector mutation that must go red.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"

pf_pack_addr_u256() {
  local addr="$1"
  "$python" -I -S -c "
addr=int('$addr', 16)
b=addr.to_bytes(20, 'big')
w0=int.from_bytes(b[0:8], 'little')
w1=int.from_bytes(b[8:16], 'little')
w2=int.from_bytes(b[16:20], 'little')
print(w0 | (w1 << 64) | (w2 << 128))
"
}

pf_evm_evm_init evm-anvil-gallery
bin="$root/build/evm/Gallery.bin"
abi="$root/build/evm/Gallery.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building Gallery.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" Gallery \
    || { echo "FAIL: pf build Gallery failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18720}" "$root/build/evm/anvil-gallery.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty Gallery.bin" >&2; exit 1; }
size="$("$python" -I -S -c "print(len(bytes.fromhex('${bytecode#0x}')))")"
if (( size > 24576 )); then
  echo "FAIL: Gallery.bin is $size bytes, over EIP-170 24576" >&2
  exit 1
fi

sender="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_address "$bytecode" "$sender")"
other_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
other="$("$cast" wallet address --private-key "$other_key")"
sender_packed="$(pf_pack_addr_u256 "$sender")"
other_packed="$(pf_pack_addr_u256 "$other")"
zero="0x0000000000000000000000000000000000000000"
wide_id="0x100000000000000000000000000000000000000000000000000000000"

supports_interface() {
  "$cast" call --rpc-url "$rpc" "$addr" 'supportsInterface(bytes4)(bool)' "$1"
}
pf_evm_require_equal "$(supports_interface 0x01ffc9a7)" true "IERC165 support"
pf_evm_require_equal "$(supports_interface 0x80ac58cd)" false "incomplete IERC721 is unsupported"
pf_evm_require_equal "$(supports_interface 0x780e9d63)" false "incomplete IERC721Enumerable is unsupported"

sig_xfer="$(pf_evm_typed_event_sig "$abi" Transfer)"
pf_evm_require_equal "$sig_xfer" 'Transfer(address,address,uint256)' "ABI Transfer signature"
topic_xfer="$("$cast" keccak "$sig_xfer")"

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalSupply()(uint256)')" 0 \
  "empty totalSupply"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'tokenByIndex(uint256)(uint256)' 0)" 0 \
  "empty tokenByIndex"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(address,uint256)' "$sender" 0)"
pf_evm_typed_event_check "$abi" "$receipt" Transfer "$topic_xfer" \
  "{\"from\": \"$zero\", \"to\": \"$sender\", \"tokenId\": 0}" \
  "mint id 0 Transfer LOG4"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(address,uint256)' "$sender" 1 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(address,uint256)' "$sender" 2 >/dev/null

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalSupply()(uint256)')" 3 \
  "totalSupply after three mints"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'tokenByIndex(uint256)(uint256)' 0)" 0 \
  "tokenByIndex 0"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'tokenByIndex(uint256)(uint256)' 1)" 1 \
  "tokenByIndex 1"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'tokenByIndex(uint256)(uint256)' 2)" 2 \
  "tokenByIndex 2"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'tokenOfOwnerByIndex(address,uint256)(uint256)' "$sender" 0)" 0 \
  "owner index 0"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'tokenOfOwnerByIndex(address,uint256)(uint256)' "$sender" 1)" 1 \
  "owner index 1"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'tokenOfOwnerByIndex(address,uint256)(uint256)' "$sender" 2)" 2 \
  "owner index 2"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'ownerOf(uint256)(uint256)' 1)" \
  "$sender_packed" "owner of 1"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'balanceOf(address)(uint256)' "$sender")" \
  3 "sender balance 3"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'transferFrom(address,address,uint256)' "$sender" "$other" 1 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'ownerOf(uint256)(uint256)' 1)" \
  "$other_packed" "owner after transfer"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'balanceOf(address)(uint256)' "$sender")" \
  2 "sender balance after transfer"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'balanceOf(address)(uint256)' "$other")" \
  1 "other balance after transfer"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'tokenOfOwnerByIndex(address,uint256)(uint256)' "$sender" 0)" 0 \
  "sender keeps id 0"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'tokenOfOwnerByIndex(address,uint256)(uint256)' "$sender" 1)" 2 \
  "swap-remove moved id 2 into the hole"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'tokenOfOwnerByIndex(address,uint256)(uint256)' "$other" 0)" 1 \
  "other holds id 1"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'tokenByIndex(uint256)(uint256)' 1)" 1 \
  "global list still holds transferred id 1"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalSupply()(uint256)')" 3 \
  "transfer does not change totalSupply"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'burn(uint256)' 0 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalSupply()(uint256)')" 2 \
  "totalSupply after burn"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'tokenByIndex(uint256)(uint256)' 0)" 2 \
  "global swap-remove moved last id into slot 0"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'tokenByIndex(uint256)(uint256)' 1)" 1 \
  "global slot 1 still id 1"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'ownerOf(uint256)(uint256)' 0)" 0 \
  "burned id has no owner"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'tokenOfOwnerByIndex(address,uint256)(uint256)' "$sender" 0)" 2 \
  "sender's remaining token"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(address,uint256)' "$sender" 3 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(address,uint256)' "$sender" 4 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalSupply()(uint256)')" 4 \
  "full totalSupply"
pf_evm_require_cap_exceeded "$addr" "$sender" \
  "$("$cast" calldata 'mint(address,uint256)' "$sender" 5)" "fifth live token"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'mint(address,uint256)' "$sender" 5 >/dev/null 2>&1; then
  echo "FAIL: fifth mint unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalSupply()(uint256)')" 4 \
  "capExceeded left totalSupply at 4"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'burn(uint256)' 4 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalSupply()(uint256)')" 3 \
  "burning the last global slot drops count only"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'tokenByIndex(uint256)(uint256)' 2)" 3 \
  "last-slot burn leaves index 2 in place"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'tokenByIndex(uint256)(uint256)' 3)" 0 \
  "last-slot burn clears the old last index"

pf_evm_require_unauthorized "$addr" "$other" \
  "$("$cast" calldata 'mint(address,uint256)' "$other" 6)" "$other" "non-minter mint"
pf_evm_require_zero_address "$addr" "$sender" \
  "$("$cast" calldata 'mint(address,uint256)' "$zero" 6)" "mint to zero"
pf_evm_require_unauthorized "$addr" "$sender" \
  "$("$cast" calldata 'mint(address,uint256)' "$sender" "$wide_id")" "$sender" "wide token id"
pf_evm_require_unauthorized "$addr" "$other" \
  "$("$cast" calldata 'transferFrom(address,address,uint256)' "$sender" "$other" 2)" \
  "$other" "non-owner transferFrom"
pf_evm_require_unauthorized "$addr" "$other" \
  "$("$cast" calldata 'burn(uint256)' 2)" "$other" "non-owner burn"

yul="$root/build/evm/Gallery.yul"
if [[ ! -f "$yul" ]]; then
  echo "building Gallery.yul" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" Gallery \
    || { echo "FAIL: pf build Gallery failed" >&2; exit 1; }
fi
mut_dir="$(mktemp -d)"
"$python" -I -S -c "
from pathlib import Path
import re
text = Path('$yul').read_text()
new, n = re.subn(
    r'case 0x4f6ccce7 \{.*?\n      case ',
    'case 0x4f6ccce7 { mstore(0, 0) return(0, 32) }\n      case ',
    text,
    count=1,
    flags=re.S,
)
if n != 1:
    raise SystemExit('FAIL: Gallery.yul lost tokenByIndex case 0x4f6ccce7')
Path('$mut_dir/Gallery.yul').write_text(new)
"
mut_code="$(solc --strict-assembly --bin "$mut_dir/Gallery.yul" 2>/dev/null | awk '/^Binary/{getline; print; exit}')"
[[ -n "$mut_code" ]] || { echo "FAIL: empty mutated Gallery bytecode" >&2; exit 1; }
mut_addr="$(pf_evm_deploy_ctor_address "$mut_code" "$sender")"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$mut_addr" 'mint(address,uint256)' "$sender" 7 >/dev/null
got="$("$cast" call --rpc-url "$rpc" "$mut_addr" 'tokenByIndex(uint256)(uint256)' 0)"
got_dec="$("$python" -I -S -c "print(int('$got', 0) if str('$got').startswith('0x') else int('$got'))")"
if [[ "$got_dec" == "7" ]]; then
  echo "FAIL: mutated tokenByIndex still returned the minted id" >&2
  exit 1
fi
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'tokenByIndex(uint256)(uint256)' 0)" 2 \
  "pristine tokenByIndex still enumerates after the mutation deploy"

echo "evm-anvil-gallery: ok (capacity-4 enumerable mint/transfer/burn + tokenByIndex mutation; $size runtime bytes)"
