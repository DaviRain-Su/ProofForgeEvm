#!/usr/bin/env bash
# Shared UInt64 math EVM consumer: bounded helpers, saturation, and rounded integer math.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-math-price-band
bin="$root/build/evm/EvmPriceBand.bin"
pf_evm_ensure_bin "$bin"
pf_evm_start_anvil "${PF_EVM_PORT:-18700}" "$root/build/evm/anvil-math-price-band.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
addr="$(pf_evm_deploy_ctor_u64 "$bytecode" 7)"
max=18446744073709551615
half=9223372036854775807
half_up=9223372036854775808
sender="$("$cast" wallet address --private-key "$private_key")"

pf_evm_require_storage "$addr" 0 7 "constructor quote"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'lower(uint64,uint64)(uint64)' "$max" 7)" 7 "minimum boundary"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'upper(uint64,uint64)(uint64)' "$max" 7)" "$max" "maximum boundary"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'midpoint(uint64,uint64)(uint64)' 0 "$max")" "$half" "overflow-safe midpoint"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'binaryBand(uint64)(uint64)' 0)" 0 "binary log zero policy"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'binaryBand(uint64)(uint64)' 2)" 1 "binary log exact power"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'binaryBand(uint64)(uint64)' "$max")" 63 "binary log maximum"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'decimalBand(uint64)(uint64)' 9)" 0 "decimal log below first power"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'decimalBand(uint64)(uint64)' 10000000000000000000)" 19 "decimal log 10^19"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'byteBand(uint64)(uint64)' 255)" 0 "byte log below first power"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'byteBand(uint64)(uint64)' 256)" 1 "byte log exact power"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'byteBand(uint64)(uint64)' "$max")" 7 "byte log maximum"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'binaryBandUp(uint64)(uint64)' 3)" 2 "binary log ceiling"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'binaryBandUp(uint64)(uint64)' "$max")" 64 "binary log ceiling maximum"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'decimalBandUp(uint64)(uint64)' 10)" 1 "decimal log ceiling exact power"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'decimalBandUp(uint64)(uint64)' 11)" 2 "decimal log ceiling"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'byteBandUp(uint64)(uint64)' 256)" 1 "byte log ceiling exact power"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'byteBandUp(uint64)(uint64)' "$max")" 8 "byte log ceiling maximum"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'quoteRoot(uint64)(uint64)' 0)" 0 "square root zero"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'quoteRoot(uint64)(uint64)' 3)" 1 "square root nonsquare floor"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'quoteRoot(uint64)(uint64)' 16)" 4 "square root exact square"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'quoteRoot(uint64)(uint64)' 18446744065119617025)" 4294967295 "largest UInt64 square"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'quoteRoot(uint64)(uint64)' "$max")" 4294967295 "square root maximum"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'quoteRootUp(uint64)(uint64)' 0)" 0 "square root ceiling zero"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'quoteRootUp(uint64)(uint64)' 2)" 2 "square root ceiling nonsquare"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'quoteRootUp(uint64)(uint64)' 16)" 4 "square root ceiling exact square"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'quoteRootUp(uint64)(uint64)' "$max")" 4294967296 "square root ceiling maximum"

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'roundUp(uint64,uint64)(uint64)' "$max" 2)" "$half_up" "maximum ceil-div by two"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'roundUp(uint64,uint64)' "$max" 2 >/dev/null
pf_evm_require_storage "$addr" 0 "$half_up" "ceil-div persists"

pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'roundUp(uint64,uint64)' "$max" 0)" 'zeroTick()' \
  "zero denominator"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'roundUp(uint64,uint64)' "$max" 0 >/dev/null 2>&1; then
  echo "FAIL: zero denominator unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_storage "$addr" 0 "$half_up" "zero denominator is atomic"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'roundUp(uint64,uint64)' "$max" 1 >/dev/null
pf_evm_require_storage "$addr" 0 "$max" "ceil-div maximum by one"

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'weighted(uint64,uint64,uint64)(uint64)' "$max" 2 2)" "$max" \
  "full-precision product divided back to maximum"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'weighted(uint64,uint64,uint64)' "$max" 2 2 >/dev/null
pf_evm_require_storage "$addr" 0 "$max" "full-precision ratio persists"

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'weightedUp(uint64,uint64,uint64)(uint64)' 10 20 3)" 67 \
  "full-precision ceiling ratio"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'weightedUp(uint64,uint64,uint64)' 10 20 3 >/dev/null
pf_evm_require_storage "$addr" 0 67 "full-precision ceiling ratio persists"

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'weightedUp(uint64,uint64,uint64)(uint64)' "$max" 2 2)" "$max" \
  "full-precision ceiling preserves exact maximum"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'weightedUp(uint64,uint64,uint64)' "$max" 2 2 >/dev/null
pf_evm_require_storage "$addr" 0 "$max" "exact ceiling maximum persists"

pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'weighted(uint64,uint64,uint64)' 7 9 0)" 'zeroTick()' \
  "full-precision zero denominator"
pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'weighted(uint64,uint64,uint64)' "$half_up" 2 1)" \
  'quoteOverflow()' "full-precision quotient overflow"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'weighted(uint64,uint64,uint64)' "$half_up" 2 1 >/dev/null 2>&1; then
  echo "FAIL: overflowing full-precision quotient unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_storage "$addr" 0 "$max" "full-precision failure is atomic"

pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'weightedUp(uint64,uint64,uint64)' 7 9 0)" 'zeroTick()' \
  "full-precision ceiling zero denominator"
pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'weightedUp(uint64,uint64,uint64)' 6 15372286728091293013 5)" \
  'quoteOverflow()' "full-precision ceiling overflow"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'weightedUp(uint64,uint64,uint64)' 6 15372286728091293013 5 >/dev/null 2>&1; then
  echo "FAIL: overflowing full-precision ceiling unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_storage "$addr" 0 "$max" "full-precision ceiling failure is atomic"

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'fixedMulDown(uint64,uint64,uint64)(uint64)' 150 25 100)" 37 \
  "fixed-point multiply floor"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'fixedMulUp(uint64,uint64,uint64)(uint64)' 150 25 100)" 38 \
  "fixed-point multiply ceiling"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'fixedDivDown(uint64,uint64,uint64)(uint64)' 101 30 100)" 336 \
  "fixed-point divide floor"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'fixedDivUp(uint64,uint64,uint64)(uint64)' 101 30 100)" 337 \
  "fixed-point divide ceiling"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'fixedDivUp(uint64,uint64,uint64)' 101 30 100 >/dev/null
pf_evm_require_storage "$addr" 0 337 "fixed-point result persists"

pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'fixedMulDown(uint64,uint64,uint64)' 150 25 0)" 'zeroTick()' \
  "fixed-point zero scale"
pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'fixedDivDown(uint64,uint64,uint64)' 101 0 0)" 'zeroTick()' \
  "fixed-point scale validation precedes divisor"
pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'fixedDivDown(uint64,uint64,uint64)' 101 0 100)" 'zeroRate()' \
  "fixed-point zero divisor"
pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'fixedMulDown(uint64,uint64,uint64)' "$max" "$max" 1)" \
  'quoteOverflow()' "fixed-point multiply overflow"
pf_evm_require_named_revert "$addr" "$sender" \
  "$("$cast" calldata 'fixedDivUp(uint64,uint64,uint64)' "$half_up" 1 2)" \
  'quoteOverflow()' "fixed-point divide overflow"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'fixedDivUp(uint64,uint64,uint64)' "$half_up" 1 2 >/dev/null 2>&1; then
  echo "FAIL: overflowing fixed-point division unexpectedly succeeded" >&2
  exit 1
fi
pf_evm_require_storage "$addr" 0 337 "fixed-point failure is atomic"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'fixedMulDown(uint64,uint64,uint64)' "$max" 1 1 >/dev/null
pf_evm_require_storage "$addr" 0 "$max" "exact fixed-point maximum persists"

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'increase(uint64)(uint64)' 1)" "$max" "saturating increase at maximum"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'discount(uint64)' "$max" >/dev/null
pf_evm_require_storage "$addr" 0 0 "saturating discount floors at zero"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'scale(uint64)(uint64)' "$max")" 0 "zero scale avoids division"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'increase(uint64)' "$half_up" >/dev/null
pf_evm_require_storage "$addr" 0 "$half_up" "exact increase after zero"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'scale(uint64)(uint64)' 2)" "$max" "saturating scale preview"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'scale(uint64)' 2 >/dev/null
pf_evm_require_storage "$addr" 0 "$max" "saturating scale persists"

echo "evm-anvil-math-price-band: ok (bounded/saturating/full-precision/fixed-point UInt64 math; engineering only)"
