#!/usr/bin/env bash
# AuditLink: OZ completion-audit inventory witness (fail-closed auditOk gate). Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-auditlink
bin="$root/build/evm/AuditLink.bin"
abi="$root/build/evm/AuditLink.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building AuditLink.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" AuditLink \
    || { echo "FAIL: pf build AuditLink failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18698}" "$root/build/evm/anvil-auditlink.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty AuditLink.bin" >&2; exit 1; }

encoded="$("$cast" abi-encode 'constructor(uint64)' 0)"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${encoded#0x}")"
addr="$(printf '%s' "$receipt" | pf_evm_contract_address)"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'coverageRows()(uint64)')" \
  32 "coverage row count"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'classifiedCount()(uint64)')" \
  32 "classified row count"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'isComplete()(bool)')" \
  true "inventory complete"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'auditOk(uint64,uint64)(bool)' 452 367)" \
  true "authority snapshot matches"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'auditOk(uint64,uint64)(bool)' 451 367)" \
  false "stale tree path count fails closed"

echo "evm-anvil-auditlink: ok (OZ audit inventory witness + fail-closed auditOk gate)"
