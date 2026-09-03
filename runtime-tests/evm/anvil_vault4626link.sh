#!/usr/bin/env bash
# Vault4626Link: bounded 1:1 ERC-4626 vault — fixed asset, closed ERC-20, reentrancy guard.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-vault4626link
bin="$root/build/evm/Vault4626Link.bin"
abi="$root/build/evm/Vault4626Link.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  lake exe pf -- build --target evm --out "$root/build/evm" Vault4626Link \
    || { echo "FAIL: pf build Vault4626Link failed" >&2; exit 1; }
fi
pf_evm_start_anvil "${PF_EVM_PORT:-18706}" "$root/build/evm/anvil-vault4626link.log"

solc_bin=""
for c in /opt/homebrew/bin/solc /usr/local/bin/solc solc; do
  command -v "$c" >/dev/null 2>&1 && { solc_bin="$c"; break; }
done
if [[ -z "$solc_bin" ]]; then
  echo "evm-anvil-vault4626link: skip: solc not found" >&2
  exit 0
fi

mock_out="$root/build/evm/ERC20Mock.bin"
"$solc_bin" --bin --optimize --overwrite -o "$root/build/evm" "$here/ERC20Mock.sol" >/dev/null

bytecode="$(tr -d '\n\r ' < "$bin")"
sender="$("$cast" wallet address --private-key "$private_key")"
other_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
dest="$("$cast" wallet address --private-key "$other_key")"
zero="0x0000000000000000000000000000000000000000"

mock_hex="$(tr -d '\n\r ' < "$mock_out")"
token="$(printf '%s' "$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" --create "0x$mock_hex")" | pf_evm_contract_address)"
encoded="$("$cast" abi-encode 'constructor(address)' "$token")"
addr="$(printf '%s' "$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" --create "0x${bytecode}${encoded#0x}")" | pf_evm_contract_address)"

topic_dep="$("$cast" keccak 'Deposit(address,address,uint256,uint256)')"
topic_wdr="$("$cast" keccak 'Withdraw(address,address,address,uint256,uint256)')"

got_asset="$("$cast" call --rpc-url "$rpc" "$addr" 'asset()(address)')"
pf_evm_require_equal "${got_asset,,}" "${token,,}" "asset"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'convertToShares(uint256)(uint256)' 100)" 100 "1:1 shares"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$token" 'mint(address,uint256)' "$sender" 500 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$token" 'approve(address,uint256)' "$addr" 500 >/dev/null

dep_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" "$addr" 'deposit(uint256,address)' 100 "$sender")"
pf_evm_typed_event_check "$abi" "$dep_receipt" Deposit "$topic_dep" \
  "{\"sender\": \"$sender\", \"owner\": \"$sender\", \"assets\": 100, \"shares\": 100}" "deposit"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalAssets()(uint256)')" 100 "totalAssets"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'balanceOf(address)(uint256)' "$sender")" 100 "shares"

wdr_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" "$addr" 'redeem(uint256,address,address)' 30 "$dest" "$sender")"
pf_evm_typed_event_check "$abi" "$wdr_receipt" Withdraw "$topic_wdr" \
  "{\"sender\": \"$sender\", \"receiver\": \"$dest\", \"owner\": \"$sender\", \"assets\": 30, \"shares\": 30}" "redeem"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" 'balanceOf(address)(uint256)' "$dest")" 30 "dest token"

echo "evm-anvil-vault4626link: ok"
