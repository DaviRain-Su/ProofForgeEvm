#!/usr/bin/env bash
# AuditLink: OZ completion-audit bounded static table (path tag + status + blocker per row). Darwin + Linux.
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
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'blockedCount()(uint64)')" \
  14 "blocked row count"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'isComplete()(bool)')" \
  true "inventory complete"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'pathTagOf(uint64)(uint8)' 7)" \
  8 "IERC165 path tag"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'statusOf(uint64)(uint8)' 7)" \
  1 "IERC165 DONE status"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'isBlocked(uint64)(bool)' 7)" \
  false "IERC165 not blocked"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'pathTagOf(uint64)(uint8)' 2)" \
  3 "access/extensions path tag"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'statusOf(uint64)(uint8)' 2)" \
  3 "access/extensions ABSENT status"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'isBlocked(uint64)(bool)' 2)" \
  true "access/extensions blocked"

for row in $(seq 0 31); do
  classified="$("$cast" call --rpc-url "$rpc" "$addr" "isClassified(uint64)(bool)" "$row")"
  status="$("$cast" call --rpc-url "$rpc" "$addr" "statusOf(uint64)(uint8)" "$row")"
  tag="$("$cast" call --rpc-url "$rpc" "$addr" "pathTagOf(uint64)(uint8)" "$row")"
  blocked="$("$cast" call --rpc-url "$rpc" "$addr" "isBlocked(uint64)(bool)" "$row")"
  [[ "$classified" == "true" ]] || { echo "FAIL: row $row unclassified" >&2; exit 1; }
  [[ "$tag" != "0" ]] || { echo "FAIL: row $row missing path tag" >&2; exit 1; }
  if [[ "$status" == "3" ]]; then
    [[ "$blocked" == "true" ]] || { echo "FAIL: row $row ABSENT but not blocked" >&2; exit 1; }
  else
    [[ "$blocked" == "false" ]] || { echo "FAIL: row $row DONE/PARTIAL but blocked" >&2; exit 1; }
  fi
done

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'auditOk(uint64,uint64)(bool)' 452 367)" \
  true "authority snapshot matches"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'auditOk(uint64,uint64)(bool)' 451 367)" \
  false "stale tree path count fails closed"

echo "evm-anvil-auditlink: ok (OZ audit table witness + per-row classification + fail-closed auditOk gate)"
