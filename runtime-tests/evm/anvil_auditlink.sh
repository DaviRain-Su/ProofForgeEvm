#!/usr/bin/env bash
# AuditLink: OZ completion-audit table (path tag + status + blocker + non-goal evidence per row). Darwin + Linux.
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
  9 "blocked row count"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'temporaryGapCount()(uint64)')" \
  0 "temporary gap count"
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
  2 "access/extensions PARTIAL status"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'isBlocked(uint64)(bool)' 2)" \
  false "access/extensions not blocked"

# Every ABSENT row is either blocked by a tagged permanent non-goal or a temporary gap with no
# tag, never both and never neither; DONE/PARTIAL rows are neither.
gaps=0
for row in $(seq 0 31); do
  classified="$("$cast" call --rpc-url "$rpc" "$addr" "isClassified(uint64)(bool)" "$row")"
  status="$("$cast" call --rpc-url "$rpc" "$addr" "statusOf(uint64)(uint8)" "$row")"
  tag="$("$cast" call --rpc-url "$rpc" "$addr" "pathTagOf(uint64)(uint8)" "$row")"
  blocked="$("$cast" call --rpc-url "$rpc" "$addr" "isBlocked(uint64)(bool)" "$row")"
  gap="$("$cast" call --rpc-url "$rpc" "$addr" "isTemporaryGap(uint64)(bool)" "$row")"
  ngtag="$("$cast" call --rpc-url "$rpc" "$addr" "nonGoalTagOf(uint64)(uint8)" "$row")"
  [[ "$classified" == "true" ]] || { echo "FAIL: row $row unclassified" >&2; exit 1; }
  [[ "$tag" != "0" ]] || { echo "FAIL: row $row missing path tag" >&2; exit 1; }
  if [[ "$status" == "3" ]]; then
    if [[ "$blocked" == "true" ]]; then
      [[ "$gap" == "false" ]] || { echo "FAIL: row $row blocked and a temporary gap" >&2; exit 1; }
      [[ "$ngtag" != "0" ]] || { echo "FAIL: row $row blocked but missing non-goal tag" >&2; exit 1; }
    else
      [[ "$gap" == "true" ]] || { echo "FAIL: row $row ABSENT, not blocked, not a temporary gap" >&2; exit 1; }
      [[ "$ngtag" == "0" ]] || { echo "FAIL: row $row temporary gap but carries non-goal tag" >&2; exit 1; }
      gaps=$((gaps + 1))
    fi
  else
    [[ "$blocked" == "false" ]] || { echo "FAIL: row $row DONE/PARTIAL but blocked" >&2; exit 1; }
    [[ "$gap" == "false" ]] || { echo "FAIL: row $row DONE/PARTIAL but a temporary gap" >&2; exit 1; }
    [[ "$ngtag" == "0" ]] || { echo "FAIL: row $row DONE/PARTIAL but carries non-goal tag" >&2; exit 1; }
  fi
done
pf_evm_require_equal "$gaps" 0 "temporary gaps counted row by row"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'statusOf(uint64)(uint8)' 12)" 2 "IERC1271 row is PARTIAL"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'isTemporaryGap(uint64)(bool)' 12)" false "IERC1271 row is no longer a temporary gap"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'isBlocked(uint64)(bool)' 12)" false "IERC1271 row not blocked"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'nonGoalTagOf(uint64)(uint8)' 12)" 0 "IERC1271 row carries no non-goal tag"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'nonGoalTagOf(uint64)(uint8)' 18)" \
  1 "proxy row non-goal tag"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'nonGoalTagOf(uint64)(uint8)' 3)" \
  3 "account row non-goal tag"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'nonGoalTagOf(uint64)(uint8)' 7)" \
  0 "IERC165 row has no non-goal tag"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'auditOk(uint64,uint64)(bool)' 452 367)" \
  true "authority snapshot matches"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'auditOk(uint64,uint64)(bool)' 451 367)" \
  false "stale tree path count fails closed"

echo "evm-anvil-auditlink: ok (OZ audit table witness + per-row classification + non-goal evidence + one temporary gap + fail-closed auditOk gate)"
