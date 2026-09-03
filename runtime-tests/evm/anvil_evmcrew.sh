#!/usr/bin/env bash
# EvmCrew: bounded static four-slot crew role set (Roles.Set4) with LOG4 RoleGranted/RoleRevoked.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-evmcrew
bin="$root/build/evm/EvmCrew.bin"
abi="$root/build/evm/EvmCrew.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building EvmCrew.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" EvmCrew \
    || { echo "FAIL: pf build EvmCrew failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18564}" "$root/build/evm/anvil-evmcrew.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
sender="$("$cast" wallet address --private-key "$private_key")"
encoded="$("$cast" abi-encode 'constructor(uint64,address)' 0 "$sender")"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${encoded#0x}")"
addr="$(printf '%s' "$receipt" | pf_evm_contract_address)"

zero_addr="0x0000000000000000000000000000000000000000"
op2="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
op3="0x90F79bf6EB2c4f870365E785982E1f101E93b906"
op4="0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65"
op5_key="0x8b3a350cf5c34c9194ca85829a2df0ec3153beccd8246193bbef0810e859554f"
op5="$("$cast" wallet address --private-key "$op5_key")"
role_crew="$("$cast" keccak "CREW_ROLE")"
sig_granted="$(pf_evm_typed_event_sig "$abi" RoleGranted)"
sig_revoked="$(pf_evm_typed_event_sig "$abi" RoleRevoked)"
topic_granted="$("$cast" keccak "$sig_granted")"
topic_revoked="$("$cast" keccak "$sig_revoked")"

other_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
other="$("$cast" wallet address --private-key "$other_key")"

crew_limbs() {
  "$python" -I -S -c "
b=bytes.fromhex('${1#0x}')
print(int.from_bytes(b[0:8], 'little'), int.from_bytes(b[8:16], 'little'),
      int.from_bytes(b[16:20], 'little'))
"
}

for slot in 1 2 3 4 5 6 7 8 9 10 11 12; do
  pf_evm_require_storage "$addr" "$slot" 0 "constructor crew slot vacant"
done

# Fill all four slots in order.
for who in "$other" "$op2" "$op3" "$op4"; do
  receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'grantCrew(address)' "$who")"
  pf_evm_typed_event_check "$abi" "$receipt" RoleGranted "$topic_granted" \
    "{\"role\": \"$role_crew\", \"account\": \"$who\", \"sender\": \"$sender\"}" \
    "grant crew RoleGranted LOG4"
done

# Fifth distinct grant reverts CapExceeded().
pf_evm_require_cap_exceeded "$addr" "$sender" \
  "$("$cast" calldata 'grantCrew(address)' "$op5")" "full crew set grant"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'grantCrew(address)' "$op5" >/dev/null 2>&1; then
  echo "FAIL: full-set crew grant unexpectedly succeeded" >&2
  exit 1
fi

# Non-owner grant reverts Unauthorized.
pf_evm_require_unauthorized "$addr" "$other" \
  "$("$cast" calldata 'grantCrew(address)' "$op5")" "$other" "non-owner crew grant"

# Revoke one member and confirm RoleRevoked LOG4.
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'revokeCrew(address)' "$other")"
pf_evm_typed_event_check "$abi" "$receipt" RoleRevoked "$topic_revoked" \
  "{\"role\": \"$role_crew\", \"account\": \"$other\", \"sender\": \"$sender\"}" \
  "revoke crew RoleRevoked LOG4"
for slot in 1 2 3; do
  pf_evm_require_storage "$addr" "$slot" 0 "revoke clears crew0"
done
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'isCrew(address)(bool)' "$other")" false "membership cleared after revoke"

echo "evm-anvil-evmcrew: ok (Set4 crew roles + RoleGranted/RoleRevoked LOG4; engineering only)"
