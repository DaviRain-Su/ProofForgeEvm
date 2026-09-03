#!/usr/bin/env bash
# RecoverLink: public Sdk.Ecdsa.recover via closed ecrecover precompile. Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-recoverlink
bin="$root/build/evm/RecoverLink.bin"
abi="$root/build/evm/RecoverLink.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building RecoverLink.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" RecoverLink \
    || { echo "FAIL: pf build RecoverLink failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18698}" "$root/build/evm/anvil-recoverlink.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty RecoverLink.bin" >&2; exit 1; }

sender="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_address "$bytecode" "$sender")"

digest="$("$cast" keccak "RecoverLink-test")"
sig="$("$cast" wallet sign --no-hash --private-key "$private_key" "$digest")"
r="0x$(echo "${sig:2:64}")"
s="0x$(echo "${sig:66:64}")"
v_hex="0x$(echo "${sig:130:2}")"
v="$("$cast" to-dec "$v_hex")"
if [[ "$v" -lt 27 ]]; then v=$((v + 27)); fi

got="$("$cast" call --rpc-url "$rpc" "$addr" \
  'recover(bytes32,uint8,bytes32,bytes32)(address)' "$digest" "$v" "$r" "$s")"
pf_evm_require_equal "${got,,}" "${sender,,}" "recover returns signer"

bad_r="0x0000000000000000000000000000000000000000000000000000000000000001"
bad_got="$("$cast" call --rpc-url "$rpc" "$addr" \
  'recover(bytes32,uint8,bytes32,bytes32)(address)' "$digest" 27 "$bad_r" "$s")"
if [[ "${bad_got,,}" == "${sender,,}" ]]; then
  echo "FAIL: invalid signature recovered expected signer: $bad_got" >&2
  exit 1
fi

echo "evm-anvil-recoverlink: ok (typed ECDSA recover via ecrecover precompile)"
