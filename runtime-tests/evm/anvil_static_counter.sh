#!/usr/bin/env bash
# EvmStaticCounter: static scalar/wide/record layout, immutable-owner policy, and the
# bounded static operator role set (EVM-SDK-3).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-static-counter
bin="$root/build/evm/EvmStaticCounter.bin"
abi="$root/build/evm/EvmStaticCounter.abi.json"
pf_evm_ensure_bin "$bin"
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18563}" "$root/build/evm/anvil-static-counter.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
sender="$("$cast" wallet address --private-key "$private_key")"
encoded="$("$cast" abi-encode 'constructor(uint64,address)' 7 "$sender")"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${encoded#0x}")"
addr="$(printf '%s' "$receipt" | pf_evm_contract_address)"

# Declaration order is paused@0, total_w0..w3@1..4, tally.count@5, tally.window@6.
pf_evm_require_storage "$addr" 0 0 "constructor paused"
pf_evm_require_storage "$addr" 1 7 "constructor total.w0"
for slot in 2 3 4 5 6; do
  pf_evm_require_storage "$addr" "$slot" 0 "constructor zero neighbor"
done
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalOf()(uint256)')" \
  7 "constructor total getter"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'countOf()(uint64)')" \
  0 "constructor count getter"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'bump(uint64)' 5 >/dev/null
pf_evm_require_storage "$addr" 1 12 "wide total targeted mutation"
for slot in 2 3 4; do
  pf_evm_require_storage "$addr" "$slot" 0 "wide high limb remains zero"
done
pf_evm_require_storage "$addr" 5 5 "record count targeted mutation"
pf_evm_require_storage "$addr" 6 0 "record window neighbor remains zero"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'totalOf()(uint256)')" \
  12 "wide total after bump"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'countOf()(uint64)')" \
  5 "record count after bump"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'setWindow(uint16)' 513 >/dev/null
pf_evm_require_storage "$addr" 6 513 "record window targeted mutation"
pf_evm_require_storage "$addr" 5 5 "record count neighbor holds"

other_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
other="$("$cast" wallet address --private-key "$other_key")"
pf_evm_require_unauthorized "$addr" "$other" \
  "$("$cast" calldata 'setWindow(uint16)' 9)" "$other" "non-owner window update"
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'setWindow(uint16)' 9 >/dev/null 2>&1; then
  echo "FAIL: non-owner window update unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_storage "$addr" 6 513 "unauthorized update holds window"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$addr" 'pause()' >/dev/null
pf_evm_require_storage "$addr" 0 1 "paused flag"
pf_evm_require_paused "$addr" "$sender" \
  "$("$cast" calldata 'bump(uint64)' 1)" "paused bump"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'bump(uint64)' 1 >/dev/null 2>&1; then
  echo "FAIL: paused bump unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_storage "$addr" 1 12 "paused bump holds total"
pf_evm_require_storage "$addr" 5 5 "paused bump holds count"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$addr" 'unpause()' >/dev/null
pf_evm_require_storage "$addr" 0 0 "unpaused flag"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'windowOf()(uint16)')" \
  513 "record window getter"

# EVM-SDK-3 roles: bounded static operator set, two explicit address slots (7..12).
# S4d: actual grants/revokes emit LOG4 RoleGranted/RoleRevoked; idempotent no-ops do not.
zero_addr="0x0000000000000000000000000000000000000000"
op2="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
op3="0x90F79bf6EB2c4f870365E785982E1f101E93b906"
role_op="$("$cast" keccak "OPERATOR_ROLE")"
sig_granted="$(pf_evm_typed_event_sig "$abi" RoleGranted)"
sig_revoked="$(pf_evm_typed_event_sig "$abi" RoleRevoked)"
pf_evm_require_equal "$sig_granted" 'RoleGranted(bytes32,address,address)' \
  "ABI RoleGranted signature"
pf_evm_require_equal "$sig_revoked" 'RoleRevoked(bytes32,address,address)' \
  "ABI RoleRevoked signature"
topic_granted="$("$cast" keccak "$sig_granted")"
topic_revoked="$("$cast" keccak "$sig_revoked")"

operator_limbs() {
  "$python" -I -S -c "
b=bytes.fromhex('${1#0x}')
print(int.from_bytes(b[0:8], 'little'), int.from_bytes(b[8:16], 'little'),
      int.from_bytes(b[16:20], 'little'))
"
}

for slot in 7 8 9 10 11 12; do
  pf_evm_require_storage "$addr" "$slot" 0 "constructor operator slot vacant"
done
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'isOperator(address)(bool)' "$other")" false "vacant membership view"

# Non-owner grant reverts Unauthorized(other) and cannot mutate the role slots.
pf_evm_require_unauthorized "$addr" "$other" \
  "$("$cast" calldata 'grantOperator(address)' "$other")" "$other" "non-owner operator grant"
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'grantOperator(address)' "$other" >/dev/null 2>&1; then
  echo "FAIL: non-owner operator grant unexpectedly succeeded" >&2
  exit 1
fi
for slot in 7 8 9; do
  pf_evm_require_storage "$addr" "$slot" 0 "unauthorized grant holds slot0"
done

# Zero candidate reverts ZeroAddress().
pf_evm_require_zero_address "$addr" "$sender" \
  "$("$cast" calldata 'grantOperator(address)' "$zero_addr")" "zero operator grant"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'grantOperator(address)' "$zero_addr" >/dev/null 2>&1; then
  echo "FAIL: zero operator grant unexpectedly succeeded" >&2
  exit 1
fi

# Owner grant fills slot 0 only (slots 7..9 = address limbs; 10..12 stay zero).
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'grantOperator(address)' "$other")"
pf_evm_typed_event_check "$abi" "$receipt" RoleGranted "$topic_granted" \
  "{\"role\": \"$role_op\", \"account\": \"$other\", \"sender\": \"$sender\"}" \
  "grant operator slot0 RoleGranted LOG4"
read -r ow0 ow1 ow2 <<< "$(operator_limbs "$other")"
pf_evm_require_storage "$addr" 7 "$ow0" "grant operator slot0 w0"
pf_evm_require_storage "$addr" 8 "$ow1" "grant operator slot0 w1"
pf_evm_require_storage "$addr" 9 "$ow2" "grant operator slot0 w2"
for slot in 10 11 12; do
  pf_evm_require_storage "$addr" "$slot" 0 "grant leaves slot1 vacant"
done
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'isOperator(address)(bool)' "$other")" true "membership view after grant"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'isOperator(address)(bool)' "$sender")" false "nonmember view after grant"

# Duplicate grant is a successful idempotent no-op: nothing moves, no RoleGranted.
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'grantOperator(address)' "$other")"
pf_evm_typed_event_absent "$receipt" RoleGranted "$topic_granted" \
  "duplicate operator grant has no RoleGranted"
for slot in 10 11 12; do
  pf_evm_require_storage "$addr" "$slot" 0 "duplicate grant holds slot1 vacant"
done
pf_evm_require_storage "$addr" 7 "$ow0" "duplicate grant holds slot0"

# Second distinct grant fills slot 1 (slots 10..12).
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'grantOperator(address)' "$op2")"
pf_evm_typed_event_check "$abi" "$receipt" RoleGranted "$topic_granted" \
  "{\"role\": \"$role_op\", \"account\": \"$op2\", \"sender\": \"$sender\"}" \
  "grant operator slot1 RoleGranted LOG4"
read -r pw0 pw1 pw2 <<< "$(operator_limbs "$op2")"
pf_evm_require_storage "$addr" 10 "$pw0" "grant operator slot1 w0"
pf_evm_require_storage "$addr" 11 "$pw1" "grant operator slot1 w1"
pf_evm_require_storage "$addr" 12 "$pw2" "grant operator slot1 w2"

# Full set reverts CapExceeded().
pf_evm_require_cap_exceeded "$addr" "$sender" \
  "$("$cast" calldata 'grantOperator(address)' "$op3")" "full operator set grant"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'grantOperator(address)' "$op3" >/dev/null 2>&1; then
  echo "FAIL: full-set operator grant unexpectedly succeeded" >&2
  exit 1
fi

# Nonmember revoke is a successful idempotent no-op.
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'revokeOperator(address)' "$op3")"
pf_evm_typed_event_absent "$receipt" RoleRevoked "$topic_revoked" \
  "nonmember operator revoke has no RoleRevoked"
pf_evm_require_storage "$addr" 7 "$ow0" "nonmember revoke holds slot0"
pf_evm_require_storage "$addr" 10 "$pw0" "nonmember revoke holds slot1"

# Member revoke clears exactly slot 0.
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'revokeOperator(address)' "$other")"
pf_evm_typed_event_check "$abi" "$receipt" RoleRevoked "$topic_revoked" \
  "{\"role\": \"$role_op\", \"account\": \"$other\", \"sender\": \"$sender\"}" \
  "revoke operator slot0 RoleRevoked LOG4"
for slot in 7 8 9; do
  pf_evm_require_storage "$addr" "$slot" 0 "revoke clears slot0"
done
pf_evm_require_storage "$addr" 10 "$pw0" "revoke holds slot1"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'isOperator(address)(bool)' "$other")" false "membership cleared after revoke"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'isOperator(address)(bool)' "$op2")" true "other member survives revoke"

# Non-owner revoke reverts Unauthorized(other) and cannot clear slot1.
pf_evm_require_unauthorized "$addr" "$other" \
  "$("$cast" calldata 'revokeOperator(address)' "$op2")" "$other" "non-owner operator revoke"
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'revokeOperator(address)' "$op2" >/dev/null 2>&1; then
  echo "FAIL: non-owner operator revoke unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_storage "$addr" 10 "$pw0" "unauthorized revoke holds slot1"

echo "evm-anvil-static-counter: ok (scalar/wide/record slots + access gates + bounded operator roles + RoleGranted/RoleRevoked; engineering only)"
