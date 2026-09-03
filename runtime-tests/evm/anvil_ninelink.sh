#!/usr/bin/env bash
# NineLink: bounded fixed-id ERC-6909 consumer.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-ninelink
bin="$root/build/evm/NineLink.bin"
abi="$root/build/evm/NineLink.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  lake exe pf -- build --target evm --out "$root/build/evm" NineLink \
    || { echo "FAIL: pf build NineLink failed" >&2; exit 1; }
fi
pf_evm_start_anvil "${PF_EVM_PORT:-18716}" "$root/build/evm/anvil-ninelink.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
sender="$("$cast" wallet address --private-key "$private_key")"
other_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
other="$("$cast" wallet address --private-key "$other_key")"
token_id=7
wrong_id=8
zero="0x0000000000000000000000000000000000000000"

encoded="$("$cast" abi-encode 'constructor(address,uint64)' "$sender" "$token_id")"
addr="$(printf '%s' "$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" --create "0x${bytecode}${encoded#0x}")" | pf_evm_contract_address)"

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'tokenId()(uint256)')" "$token_id" "fixed id"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'balanceOf(address,uint256)(uint256)' "$sender" "$wrong_id")" 0 "wrong id zero"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$addr" 'mint(address,uint256,uint256)' "$sender" "$token_id" 100 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'balanceOf(address,uint256)(uint256)' "$sender" "$token_id")" 100 "minted"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$addr" 'approve(address,uint256,uint256)' "$other" "$token_id" 25 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$other_key" "$addr" 'transferFrom(address,address,uint256,uint256)' "$sender" "$other" "$token_id" 10 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'balanceOf(address,uint256)(uint256)' "$sender" "$token_id")" 90 "after transferFrom"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$addr" 'setOperator(address,bool)' "$other" true >/dev/null
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'isOperator(address,address)(bool)' "$sender" "$other")" true "operator"

echo "evm-anvil-ninelink: ok"
