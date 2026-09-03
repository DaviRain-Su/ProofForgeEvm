#!/usr/bin/env bash
# RoyaltyArt: static ERC-2981 royaltyInfo + IERC165/IERC2981. Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-royaltyart
bin="$root/build/evm/RoyaltyArt.bin"
abi="$root/build/evm/RoyaltyArt.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building RoyaltyArt.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" RoyaltyArt \
    || { echo "FAIL: pf build RoyaltyArt failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18693}" "$root/build/evm/anvil-royaltyart.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty RoyaltyArt.bin" >&2; exit 1; }

receiver="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_address "$bytecode" "$receiver")"

supports_interface() { # interface id
  "$cast" call --rpc-url "$rpc" "$addr" 'supportsInterface(bytes4)(bool)' "$1"
}
pf_evm_require_equal "$(supports_interface 0x01ffc9a7)" true "IERC165 support"
pf_evm_require_equal "$(supports_interface 0x2a55205a)" true "IERC2981 support"
pf_evm_require_equal "$(supports_interface 0x80ac58cd)" false "IERC721 is unsupported"
pf_evm_require_equal "$(supports_interface 0xd9b67a26)" false "IERC1155 is unsupported"
pf_evm_require_equal "$(supports_interface 0xffffffff)" false "ERC-165 invalid interface id"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'receiver()(address)')" \
  "$receiver" "constructor receiver"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'feeNumeratorOf()(uint256)')" \
  250 "static 2.5% numerator"

# 10000 * 250 / 10000 = 250; token id is ignored.
quote="$("$cast" call --rpc-url "$rpc" "$addr" \
  'royaltyInfo(uint256,uint256)(address,uint256)' 7 10000)"
recv="$(printf '%s\n' "$quote" | awk 'NR==1 {print}')"
amt="$(printf '%s\n' "$quote" | awk 'NR==2 {print}')"
pf_evm_require_equal "$recv" "$receiver" "royalty receiver"
pf_evm_require_uint "$amt" 250 "2.5% of 10000"

quote2="$("$cast" call --rpc-url "$rpc" "$addr" \
  'royaltyInfo(uint256,uint256)(address,uint256)' 99 20000)"
recv2="$(printf '%s\n' "$quote2" | awk 'NR==1 {print}')"
amt2="$(printf '%s\n' "$quote2" | awk 'NR==2 {print}')"
pf_evm_require_equal "$recv2" "$receiver" "token id ignored"
pf_evm_require_uint "$amt2" 500 "2.5% of 20000"

echo "evm-anvil-royaltyart: ok (IERC165+IERC2981 + static 2.5% royaltyInfo)"
