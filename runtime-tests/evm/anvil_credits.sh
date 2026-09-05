#!/usr/bin/env bash
# Credits: EVM-SDK-1 second independent Access consumer — owner-granted credit ledger
# reusing requireOwner/requireRunning and Access.Ownership two-step transfer. Darwin + Linux.
# Receipts are ABI-decoded: OwnershipTransferred is LOG3; Paused/Unpaused are LOG1.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-credits
bin="$root/build/evm/Credits.bin"
abi="$root/build/evm/Credits.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building Credits.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" Credits \
    || { echo "FAIL: pf build Credits failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18561}" "$root/build/evm/anvil-credits.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty Credits.bin" >&2; exit 1; }

sender="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_address "$bytecode" "$sender")"
# Anvil default account 1 and 2.
other_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
other="$("$cast" wallet address --private-key "$other_key")"
third_key="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
third="$("$cast" wallet address --private-key "$third_key")"

sig_own="$(pf_evm_typed_event_sig "$abi" OwnershipTransferred)"
sig_started="$(pf_evm_typed_event_sig "$abi" OwnershipTransferStarted)"
sig_paused="$(pf_evm_typed_event_sig "$abi" Paused)"
sig_unpaused="$(pf_evm_typed_event_sig "$abi" Unpaused)"
pf_evm_require_equal "$sig_own" 'OwnershipTransferred(address,address)' \
  "ABI OwnershipTransferred signature"
pf_evm_require_equal "$sig_started" 'OwnershipTransferStarted(address,address)' \
  "ABI OwnershipTransferStarted signature"
pf_evm_require_equal "$sig_paused" 'Paused(address)' "ABI Paused signature"
pf_evm_require_equal "$sig_unpaused" 'Unpaused(address)' "ABI Unpaused signature"
topic_own="$("$cast" keccak "$sig_own")"
topic_started="$("$cast" keccak "$sig_started")"
topic_paused="$("$cast" keccak "$sig_paused")"
topic_unpaused="$("$cast" keccak "$sig_unpaused")"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'ownerOf()(address)')" \
  "$sender" "ownerOf after init"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'pausedOf()(uint8)')" \
  0 "initial paused"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalOf()(uint256)')" \
  0 "initial total"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'creditOf(address)(uint256)' "$other")" \
  0 "no initial credit"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'grant(address,uint256)' "$other" 7 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'creditOf(address)(uint256)' "$other")" \
  7 "owner grant"

if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'grant(address,uint256)' "$other" 1 >/dev/null 2>&1; then
  echo "FAIL: non-owner grant unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_ownable_unauthorized_account "$addr" "$other" \
  "$("$cast" calldata 'grant(address,uint256)' "$other" 1)" "$other" \
  "non-owner grant"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'creditOf(address)(uint256)' "$other")" \
  7 "non-owner grant holds credit"

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'pause()')"
pf_evm_typed_event_check "$abi" "$receipt" Paused "$topic_paused" \
  "{\"account\": \"$sender\"}" \
  "pause Paused LOG1"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'grant(address,uint256)' "$other" 1 >/dev/null 2>&1; then
  echo "FAIL: grant while paused unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_paused "$addr" "$sender" \
  "$("$cast" calldata 'grant(address,uint256)' "$other" 1)" \
  "grant while paused"
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'claim(uint256)' 1 >/dev/null 2>&1; then
  echo "FAIL: claim while paused unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_paused "$addr" "$other" \
  "$("$cast" calldata 'claim(uint256)' 1)" \
  "claim while paused"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'unpause()')"
pf_evm_typed_event_check "$abi" "$receipt" Unpaused "$topic_unpaused" \
  "{\"account\": \"$sender\"}" \
  "unpause Unpaused LOG1"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'pausedOf()(uint8)')" \
  0 "unpaused"

"$cast" send --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" 'claim(uint256)' 7 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalOf()(uint256)')" \
  7 "claim moves credit into total"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'creditOf(address)(uint256)' "$other")" \
  0 "claim debits credit"

if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'claim(uint256)' 1 >/dev/null 2>&1; then
  echo "FAIL: over-credit claim unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_insufficient "$addr" "$other" \
  "$("$cast" calldata 'claim(uint256)' 1)" 0 1 \
  "over-credit claim"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalOf()(uint256)')" \
  7 "over-credit claim holds total"

# Two-step rotation replaces the sole pending address; a stale nominee cannot accept.
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'transferOwnership(address)' "$other")"
pf_evm_typed_event_check "$abi" "$receipt" OwnershipTransferStarted "$topic_started" \
  "{\"previousOwner\": \"$sender\", \"newOwner\": \"$other\"}" \
  "transferOwnership OwnershipTransferStarted LOG3"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'pendingOf(address)(uint64)' "$other")" \
  1 "first nomination recorded"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'pendingOwner()(address)')" \
  "$other" "pendingOwner after first nomination"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'transferOwnership(address)' "$third")"
pf_evm_typed_event_check "$abi" "$receipt" OwnershipTransferStarted "$topic_started" \
  "{\"previousOwner\": \"$sender\", \"newOwner\": \"$third\"}" \
  "replacement OwnershipTransferStarted LOG3"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'pendingOf(address)(uint64)' "$other")" \
  0 "replacement invalidates stale nominee"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'pendingOf(address)(uint64)' "$third")" \
  1 "replacement nomination recorded"
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'acceptOwnership()' >/dev/null 2>&1; then
  echo "FAIL: stale nominee acceptOwnership unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_ownable_unauthorized_account "$addr" "$other" \
  "$("$cast" calldata 'acceptOwnership()')" "$other" \
  "stale nominee acceptOwnership"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$third_key" \
  "$addr" 'acceptOwnership()')"
pf_evm_typed_event_check "$abi" "$receipt" OwnershipTransferred "$topic_own" \
  "{\"previousOwner\": \"$sender\", \"newOwner\": \"$third\"}" \
  "acceptOwnership OwnershipTransferred LOG3"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'ownerOf()(address)')" \
  "$third" "owner rotated to nominee"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'pendingOf(address)(uint64)' "$third")" \
  0 "nomination consumed"

if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'grant(address,uint256)' "$other" 1 >/dev/null 2>&1; then
  echo "FAIL: old-owner grant unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_ownable_unauthorized_account "$addr" "$sender" \
  "$("$cast" calldata 'grant(address,uint256)' "$other" 1)" "$sender" \
  "old-owner grant"

"$cast" send --rpc-url "$rpc" --private-key "$third_key" \
  "$addr" 'grant(address,uint256)' "$third" 5 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'creditOf(address)(uint256)' "$third")" \
  5 "new-owner grant"
"$cast" send --rpc-url "$rpc" --private-key "$third_key" \
  "$addr" 'claim(uint256)' 5 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalOf()(uint256)')" \
  12 "new-owner claim accumulates"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'creditOf(address)(uint256)' "$third")" \
  0 "new-owner claim debits credit"

# Renunciation clears both the owner and a live pending nomination.
"$cast" send --rpc-url "$rpc" --private-key "$third_key" \
  "$addr" 'transferOwnership(address)' "$sender" >/dev/null
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$third_key" \
  "$addr" 'renounceOwnership()')"
pf_evm_typed_event_check "$abi" "$receipt" OwnershipTransferred "$topic_own" \
  "{\"previousOwner\": \"$third\", \"newOwner\": \"0x0000000000000000000000000000000000000000\"}" \
  "renounceOwnership OwnershipTransferred LOG3"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'ownerOf()(address)')" \
  "0x0000000000000000000000000000000000000000" "owner cleared after renounce"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'pendingOwner()(address)')" \
  "0x0000000000000000000000000000000000000000" "pendingOwner cleared after renounce"
if "$cast" send --rpc-url "$rpc" --private-key "$third_key" \
    "$addr" 'grant(address,uint256)' "$third" 1 >/dev/null 2>&1; then
  echo "FAIL: owner action after renounce unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_ownable_unauthorized_account "$addr" "$third" \
  "$("$cast" calldata 'grant(address,uint256)' "$third" 1)" "$third" \
  "owner action after renounce"

echo "evm-anvil-credits: ok (Access reuse + ownership transfer/renounce LOG3 + Paused/Unpaused LOG1)"
