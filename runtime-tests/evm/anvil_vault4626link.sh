#!/usr/bin/env bash
# Vault4626Link: bounded ERC-4626 vault — floor assets * totalSupply / totalAssets, closed ERC-20, reentrancy guard.
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
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'convertToShares(uint256)(uint256)' 100)" 100 \
  "empty vault is 1:1 shares"

# 2^128 * 2^128 overflows checked 256-bit mul; mulDiv keeps convertToShares 1:1.
two128=340282366920938463463374607431768211456
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$token" \
  'mint(address,uint256)' "$sender" "$two128" >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$token" \
  'approve(address,uint256)' "$addr" "$two128" >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$addr" \
  'deposit(uint256,address)' "$two128" "$sender" >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'convertToShares(uint256)(uint256)' "$two128")" \
  "$two128" "full-precision convertToShares(2^128) is 2^128"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'convertToAssets(uint256)(uint256)' "$two128")" \
  "$two128" "full-precision convertToAssets(2^128) is 2^128"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$addr" \
  'redeem(uint256,address,address)' "$two128" "$sender" "$sender" >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalSupply()(uint256)')" 0 \
  "redeemed 2^128 shares"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$token" 'mint(address,uint256)' "$sender" 500 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$token" 'approve(address,uint256)' "$addr" 500 >/dev/null

dep_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" "$addr" 'deposit(uint256,address)' 100 "$sender")"
pf_evm_typed_event_check "$abi" "$dep_receipt" Deposit "$topic_dep" \
  "{\"sender\": \"$sender\", \"owner\": \"$sender\", \"assets\": 100, \"shares\": 100}" "deposit"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalAssets()(uint256)')" 100 "totalAssets"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalSupply()(uint256)')" 100 "totalSupply after deposit"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'balanceOf(address)(uint256)' "$sender")" 100 "shares"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'convertToShares(uint256)(uint256)' 100)" 100 \
  "funded 1:1 still 100 shares"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$token" 'mint(address,uint256)' "$addr" 100 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalAssets()(uint256)')" 200 "donated totalAssets"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'convertToShares(uint256)(uint256)' 100)" 50 \
  "donated convertToShares is 50"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'convertToAssets(uint256)(uint256)' 100)" 200 \
  "donated convertToAssets is 200"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'convertToShares(uint256)(uint256)' 1)" 0 \
  "floor convertToShares(1) is 0"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'previewWithdraw(uint256)(uint256)' 1)" 1 \
  "ceiling previewWithdraw(1) is 1"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$token" 'mint(address,uint256)' "$addr" 1 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalAssets()(uint256)')" 201 "uneven totalAssets"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'convertToAssets(uint256)(uint256)' 1)" 2 \
  "floor convertToAssets(1) is 2"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'previewMint(uint256)(uint256)' 1)" 3 \
  "ceiling previewMint(1) is 3"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$token" 'burn(address,uint256)' "$addr" 1 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalAssets()(uint256)')" 200 "restored donated totalAssets"

dep2_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" "$addr" 'deposit(uint256,address)' 100 "$sender")"
pf_evm_typed_event_check "$abi" "$dep2_receipt" Deposit "$topic_dep" \
  "{\"sender\": \"$sender\", \"owner\": \"$sender\", \"assets\": 100, \"shares\": 50}" "second deposit"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalSupply()(uint256)')" 150 \
  "second deposit mints 50"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'balanceOf(address)(uint256)' "$sender")" 150 \
  "shares after second deposit"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalAssets()(uint256)')" 300 \
  "totalAssets after second deposit"

wdr_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" "$addr" 'redeem(uint256,address,address)' 50 "$dest" "$sender")"
pf_evm_typed_event_check "$abi" "$wdr_receipt" Withdraw "$topic_wdr" \
  "{\"sender\": \"$sender\", \"receiver\": \"$dest\", \"owner\": \"$sender\", \"assets\": 100, \"shares\": 50}" "redeem"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" 'balanceOf(address)(uint256)' "$dest")" 100 "dest token"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$token" 'burn(address,uint256)' "$addr" 200 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalAssets()(uint256)')" 0 "drained totalAssets"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalSupply()(uint256)')" 100 \
  "shares remain after drain"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'convertToShares(uint256)(uint256)' 100)" 0 \
  "zero totalAssets convertToShares is 0"

echo "evm-anvil-vault4626link: ok"
