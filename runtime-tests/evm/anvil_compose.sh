#!/usr/bin/env bash
# Composition without a proxy: one ProofForge contract (EvmOpenCall) CALLs another
# ProofForge contract (Erc20Meta) through typed OpenCall. Balances move, the callee's
# Transfer log lands in the caller's transaction, and a callee revert fails the whole
# transaction with no partial state. It then reads the token's balance and owner and a
# pf-compiled Badge's ERC-165 answer through typed STATICCALL. No Solidity mock, no
# delegatecall, no proxy.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-compose
caller_bin="$root/build/evm/EvmOpenCall.bin"
token_bin="$root/build/evm/Erc20Meta.bin"
token_abi="$root/build/evm/Erc20Meta.abi.json"
badge_bin="$root/build/evm/Badge.bin"
pf_evm_ensure_bin "$caller_bin"
pf_evm_ensure_bin "$token_bin"
pf_evm_ensure_bin "$badge_bin"
[[ -f "$token_abi" ]] || { echo "FAIL: missing $token_abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18717}" "$root/build/evm/anvil-compose.log"

sender="$("$cast" wallet address --private-key "$private_key")"
dest="$("$cast" wallet address --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d)"

token="$(pf_evm_deploy_ctor_address "$(tr -d '\n\r ' < "$token_bin")" "$sender")"
caller="$(pf_evm_deploy_ctor_u64 "$(tr -d '\n\r ' < "$caller_bin")" 0)"
[[ "$token" != "$caller" ]] || { echo "FAIL: token and caller share an address" >&2; exit 1; }

sig_xfer="$(pf_evm_typed_event_sig "$token_abi" Transfer)"
topic_xfer="$("$cast" keccak "$sig_xfer")"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$token" 'mint(address,uint256)' "$caller" 100 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" 'balanceOf(address)(uint256)' "$caller")" \
  100 "caller contract holds minted balance"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$caller" 'openTransfer(address,address,uint256)' "$token" "$dest" 60)"
pf_evm_typed_event_check "$token_abi" "$receipt" Transfer "$topic_xfer" \
  "{\"from\": \"$caller\", \"to\": \"$dest\", \"value\": 60}" \
  "callee Transfer log inside the caller transaction"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" 'balanceOf(address)(uint256)' "$dest")" \
  60 "destination credited through CALL"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" 'balanceOf(address)(uint256)' "$caller")" \
  40 "caller debited through CALL"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" 'totalSupply()(uint256)')" \
  100 "supply unchanged by transfer"

if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$caller" 'openTransfer(address,address,uint256)' "$token" "$dest" 1000 >/dev/null 2>&1; then
  echo "FAIL: over-balance transfer through CALL unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" 'balanceOf(address)(uint256)' "$dest")" \
  60 "callee revert leaves destination unchanged"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$token" 'balanceOf(address)(uint256)' "$caller")" \
  40 "callee revert leaves caller unchanged"

if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$caller" 'openTransfer(address,address,uint256)' "$dest" "$dest" 1 >/dev/null 2>&1; then
  echo "FAIL: ERC-20 CALL to an EOA unexpectedly succeeded" >&2
  exit 1
fi

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$caller" \
  'readBalance(address,address)(uint256)' "$token" "$caller")" 40 \
  "balanceOf read through STATICCALL matches the token's own view"
owner="$("$cast" call --rpc-url "$rpc" "$caller" 'readOwner(address)(address)' "$token")"
pf_evm_require_equal "$(tr 'A-F' 'a-f' <<<"$owner")" "$(tr 'A-F' 'a-f' <<<"$sender")" \
  "ownerOf read through STATICCALL as a typed Address"

badge="$(pf_evm_deploy_ctor_address "$(tr -d '\n\r ' < "$badge_bin")" "$sender")"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$caller" \
  'readSupports(address,bytes4)(bool)' "$badge" 0x01ffc9a7)" true \
  "IERC165 detected on a pf-compiled Badge through strict-bool STATICCALL"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$caller" \
  'readSupports(address,bytes4)(bool)' "$badge" 0x80ac58cd)" false \
  "partial IERC721 surface reports false through strict-bool STATICCALL"

if "$cast" call --rpc-url "$rpc" "$caller" 'readOn(address)(bool)' "$token" >/dev/null 2>&1; then
  echo "FAIL: bool read of a selector the token does not implement unexpectedly succeeded" >&2
  exit 1
fi
if "$cast" call --rpc-url "$rpc" "$caller" 'readOwner(address)(address)' "$dest" >/dev/null 2>&1; then
  echo "FAIL: address read from an EOA unexpectedly succeeded" >&2
  exit 1
fi

echo "evm-anvil-compose: ok (ProofForge -> ProofForge typed CALL and STATICCALL: balances, callee log, revert, EOA, uint256/address/bool reads; no proxy; engineering only)"
