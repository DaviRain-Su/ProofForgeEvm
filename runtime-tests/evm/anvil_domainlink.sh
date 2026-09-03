#!/usr/bin/env bash
# DomainLink: EIP-5267-style static domain fields + closed DOMAIN_SEPARATOR. Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-domainlink
bin="$root/build/evm/DomainLink.bin"
abi="$root/build/evm/DomainLink.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building DomainLink.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" DomainLink \
    || { echo "FAIL: pf build DomainLink failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18695}" "$root/build/evm/anvil-domainlink.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty DomainLink.bin" >&2; exit 1; }

sender="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_address "$bytecode" "$sender")"
zero="0x0000000000000000000000000000000000000000"
chain_id="$("$cast" chain-id --rpc-url "$rpc")"

strip_string() {
  local s="$1"
  s="${s#\"}"; s="${s%\"}"
  printf '%s' "$s"
}

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'eip712DomainFields()(uint8)')" \
  15 "fields mask is name|version|chainId|verifyingContract"
pf_evm_require_equal "$(strip_string "$("$cast" call --rpc-url "$rpc" "$addr" \
  'eip712DomainName()(string)')")" "Token" "static domain name"
pf_evm_require_equal "$(strip_string "$("$cast" call --rpc-url "$rpc" "$addr" \
  'eip712DomainVersion()(string)')")" "1" "static domain version"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'eip712DomainChainId()(uint256)')" \
  "$chain_id" "runtime chainId"
got_contract="$("$cast" call --rpc-url "$rpc" "$addr" \
  'eip712DomainVerifyingContract()(address)')"
pf_evm_require_equal "${got_contract,,}" "${addr,,}" "verifyingContract is self"
got_salt="$("$cast" call --rpc-url "$rpc" "$addr" 'eip712DomainSalt()(bytes32)')"
if [[ ! "${got_salt,,}" =~ ^0x0+$ ]]; then
  echo "FAIL: static zero salt: $got_salt" >&2
  exit 1
fi
got_dom="$("$cast" call --rpc-url "$rpc" "$addr" 'DOMAIN_SEPARATOR()(bytes32)')"
if [[ ! "$got_dom" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
  echo "FAIL: DOMAIN_SEPARATOR not bytes32: $got_dom" >&2
  exit 1
fi

echo "evm-anvil-domainlink: ok (IERC5267-style static domain fields + DOMAIN_SEPARATOR)"
