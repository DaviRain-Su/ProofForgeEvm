#!/usr/bin/env bash
# EvmScoreMap: permissionless capacity-3 enumerable UInt64-to-UInt64 map. Covers key/value zero,
# insert/update/full/absent behavior, dual-map swap-remove repair/clearing, non-reverting malformed
# view fallbacks, and fail-closed mutation atomicity.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-score-map
bin="$root/build/evm/EvmScoreMap.bin"
if [[ ! -f "$bin" ]]; then
  echo "building registered EvmScoreMap.bin" >&2
  lake build Examples.EvmScoreMap >/dev/null \
    || { echo "FAIL: lake build Examples.EvmScoreMap failed" >&2; exit 1; }
  lake exe pf -- build --target evm --out "$root/build/evm" EvmScoreMap >/dev/null \
    || { echo "FAIL: build registered EvmScoreMap failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18589}" "$root/build/evm/anvil-score-map.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty EvmScoreMap.bin" >&2; exit 1; }
sender="$("$cast" wallet address --private-key "$private_key")"
addr="$(pf_evm_deploy_ctor_u64 "$bytecode" 0)"

map_payload_slot() {
  local key="$1" base="$2" raw
  raw="$("$cast" index uint256 "$key" "$base")"
  "$python" -I -S -c "print(int('$raw', 16) + 1)"
}

for slot in 0 1 2 3; do
  pf_evm_require_storage "$addr" "$slot" 0 "constructor zero score state"
done
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'sizeOf()(uint64)')" 0 \
  "empty size"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'scoreOf(uint64)(uint64)' 0)" 0 "player zero starts absent"

# Fill [10→100, 0→0, 30→300]. Player and score zero are ordinary data. Updating player zero at
# full capacity succeeds without growth; adding a fourth player fails with typed full().
for pair in '10 100' '0 0' '30 300'; do
  player="${pair%% *}"
  score="${pair#* }"
  pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
    'put(uint64,uint64)(bool)' "$player" "$score")" true "put $player returns true"
  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'put(uint64,uint64)' "$player" "$score" >/dev/null
done
pf_evm_require_storage "$addr" 0 10 "players[0]"
pf_evm_require_storage "$addr" 1 0 "player zero occupies players[1]"
pf_evm_require_storage "$addr" 2 30 "players[2]"
pf_evm_require_storage "$addr" 3 3 "full count"
for triple in '0 10 100' '1 0 0' '2 30 300'; do
  index="${triple%% *}"
  tail="${triple#* }"
  player="${tail%% *}"
  score="${tail#* }"
  pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
    'playerAt(uint64)(uint64)' "$index")" "$player" "player enumeration index $index"
  pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
    'scoreAt(uint64)(uint64)' "$index")" "$score" "score enumeration index $index"
done
pf_evm_require_storage "$addr" "$(map_payload_slot 0 0)" 2 \
  "player-zero position distinguishes presence"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'put(uint64,uint64)' 0 7 >/dev/null
pf_evm_require_storage "$addr" 3 3 "full update does not grow count"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'scoreOf(uint64)(uint64)' 0)" 7 "full update replaces zero score"
pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'put(uint64,uint64)' 40 400)" 'full()' "full score-map growth"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'put(uint64,uint64)' 40 400 >/dev/null 2>&1; then
  echo "FAIL: full score-map growth unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_storage "$addr" 3 3 "full growth failure holds count"
pf_evm_require_storage "$addr" "$(map_payload_slot 40 0)" 0 \
  "full growth writes no position"
pf_evm_require_storage "$addr" "$(map_payload_slot 40 1)" 0 \
  "full growth writes no score"

# Middle erase of player zero moves 30 into index 1, repairs its position, clears both zero-key
# map payloads, and leaves the moved player's score untouched.
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$addr" 'erase(uint64)' 0 >/dev/null
pf_evm_require_storage "$addr" 1 30 "middle erase moves final player"
pf_evm_require_storage "$addr" 3 2 "middle erase decrements count"
pf_evm_require_storage "$addr" "$(map_payload_slot 0 0)" 0 \
  "middle erase clears removed position"
pf_evm_require_storage "$addr" "$(map_payload_slot 0 1)" 0 \
  "middle erase clears removed score"
pf_evm_require_storage "$addr" "$(map_payload_slot 30 0)" 2 \
  "middle erase repairs moved position"
pf_evm_require_storage "$addr" "$(map_payload_slot 30 1)" 300 \
  "middle erase preserves moved score"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'scoreAt(uint64)(uint64)' 1)" 300 "enumeration observes moved score"

# Last and only erase leave stale backing lanes unreachable while clearing position and score.
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$addr" 'erase(uint64)' 30 >/dev/null
pf_evm_require_storage "$addr" 1 30 "last erase keeps stale backing player"
pf_evm_require_storage "$addr" 3 1 "last erase decrements count"
pf_evm_require_storage "$addr" "$(map_payload_slot 30 0)" 0 \
  "last erase clears position"
pf_evm_require_storage "$addr" "$(map_payload_slot 30 1)" 0 \
  "last erase clears score"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'erase(uint64)(bool)' 999)" false "absent erase returns false"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$addr" 'erase(uint64)' 999 >/dev/null
pf_evm_require_storage "$addr" 3 1 "absent erase holds count"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$addr" 'erase(uint64)' 10 >/dev/null
pf_evm_require_storage "$addr" 3 0 "only erase reaches empty"
pf_evm_require_storage "$addr" "$(map_payload_slot 10 0)" 0 \
  "only erase clears position"
pf_evm_require_storage "$addr" "$(map_payload_slot 10 1)" 0 \
  "only erase clears score"

# Forge one live player's position beyond count. Views use their non-reverting zero fallback,
# while update and erase fail malformed and preserve all forged evidence.
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'put(uint64,uint64)' 7 70 >/dev/null
position_slot="$(map_payload_slot 7 0)"
score_slot="$(map_payload_slot 7 1)"
pf_evm_set_storage_word "$addr" "$position_slot" 3
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'scoreOf(uint64)(uint64)' 7)" 0 "forged position uses lookup fallback"
pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'put(uint64,uint64)' 7 71)" 'malformed()' "forged-position update"
pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'erase(uint64)' 7)" 'malformed()' "forged-position erase"
pf_evm_require_storage "$addr" 0 7 "forged failures hold backing"
pf_evm_require_storage "$addr" 3 1 "forged failures hold count"
pf_evm_require_storage "$addr" "$position_slot" 3 "forged position is not repaired"
pf_evm_require_storage "$addr" "$score_slot" 70 "forged failures hold score"

# Restore position, corrupt backing, then corrupt count. Views close to zero and mutations remain
# atomic typed failures rather than repairing or exposing stale hashed values.
pf_evm_set_storage_word "$addr" "$position_slot" 1
pf_evm_set_storage_word "$addr" 0 8
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'scoreOf(uint64)(uint64)' 7)" 0 "backing mismatch uses lookup fallback"
pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'erase(uint64)' 7)" 'malformed()' "backing mismatch erase"
pf_evm_require_storage "$addr" 0 8 "backing mismatch is not repaired"
pf_evm_require_storage "$addr" "$score_slot" 70 "backing mismatch holds score"

pf_evm_set_storage_word "$addr" 3 4
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'playerAt(uint64)(uint64)' 0)" 0 "malformed count closes player enumeration"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'scoreAt(uint64)(uint64)' 0)" 0 "malformed count closes score enumeration"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'scoreOf(uint64)(uint64)' 7)" 0 "malformed count closes lookup"
pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'put(uint64,uint64)' 9 90)" 'malformed()' "malformed-count put"
pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'erase(uint64)' 7)" 'malformed()' "malformed-count erase"
pf_evm_require_storage "$addr" 3 4 "malformed mutations do not repair count"

echo "evm-anvil-score-map: ok (key/value zero + insert/update/full/absent + dual-map middle/last/only erase + malformed fallback/atomicity; engineering only)"
