#!/usr/bin/env bash
# OpenCall S3: parameter- and state-supplied targets, one- to four-word, bool, and address
# STATICCALL reads with their fail-closed frames, reads deciding a guard, compared, and passed
# as another call's argument, one bounded bytes argument through CALL and STATICCALL, CALL
# value, EOA rejection, malformed returndata, CALL-before-sstore effect order, the
# compile-time refusal of a CALL carrier anywhere but the result word, and a receiver hook
# through CALL whose one returned word must be the hook's own selector.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-opencall
bin="$root/build/evm/EvmOpenCall.bin"
pf_evm_ensure_bin "$bin"

# A CALL's UInt64 anywhere but the entry's result word must not compile. Before the refusal a
# compared carrier lowered to the CALL followed by the constant 0, so `callSuccess t ping == 0`
# answered false on chain where the Lean function answers true, and a carrier dropped by `let`
# above an `if` lost the `if` and its stores. The pin sits on the `pf build` surface users hit,
# and it must refuse for the carrier reason. The output dir stays outside build/evm so a
# regression cannot also trip the artifact manifest.
misuse_out="$root/build/opencall-misuse"
rm -rf "$misuse_out"
lake build Tests.EvmOpenCallMisuse >/dev/null 2>&1 \
  || { echo "FAIL: Tests.EvmOpenCallMisuse must elaborate; the refusal is the extractor's" >&2; exit 1; }
if misuse_log="$(lake exe pf -- build --module Tests.EvmOpenCallMisuse --out "$misuse_out" 2>&1)"; then
  echo "FAIL: pf build compiled Tests.EvmOpenCallMisuse; a CALL carrier out of place must be refused" >&2
  exit 1
fi
grep -q "CALL carrier" <<<"$misuse_log" \
  || { echo "FAIL: pf build refused Tests.EvmOpenCallMisuse for another reason: $misuse_log" >&2; exit 1; }
if [[ -n "$(ls -A "$misuse_out" 2>/dev/null)" ]]; then
  echo "FAIL: pf build wrote artifacts for the refused module" >&2
  exit 1
fi

pf_evm_start_anvil "${PF_EVM_PORT:-18691}" "$root/build/evm/anvil-opencall.log"

solc_bin=""
for c in /opt/homebrew/bin/solc /usr/local/bin/solc solc; do
  if command -v "$c" >/dev/null 2>&1 || [[ -x "$c" ]]; then
    solc_bin="$c"
    break
  fi
done
if [[ -z "$solc_bin" ]]; then
  echo "evm-anvil-opencall: skip: solc not found" >&2
  exit 0
fi

mock_out="$root/build/evm/OpenCallTarget.bin"
"$solc_bin" --bin --optimize --overwrite -o "$root/build/evm" \
  "$here/OpenCallTarget.sol" >/dev/null
[[ -f "$mock_out" ]] || { echo "FAIL: missing OpenCallTarget.bin" >&2; exit 1; }

bytecode="$(tr -d '\n\r ' < "$bin")"
addr="$(pf_evm_deploy_ctor_u64 "$bytecode" 0)"

mock_hex="$(tr -d '\n\r ' < "$mock_out")"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" --create "0x$mock_hex")"
target="$(printf '%s' "$receipt" | pf_evm_contract_address)"

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'flagOf()(uint64)')" 0 \
  "initial flag"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'pingTarget(address)' "$target" >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$target" 'pings()(uint256)')" 1 \
  "parameter-supplied ping"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'setTarget(address)' "$target" >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'pingStored()' >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$target" 'pings()(uint256)')" 2 \
  "state-supplied ping"

eoa="$("$cast" wallet address --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d)"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'pingTarget(address)' "$eoa" >/dev/null 2>&1; then
  echo "FAIL: callSuccess to EOA unexpectedly succeeded" >&2
  exit 1
fi

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'readEcho(address,uint256)(uint256)' \
  "$target" 7)" 7 "echo one word"
if "$cast" call --rpc-url "$rpc" "$addr" 'readEcho(address,uint256)(uint256)' \
    "$target" 0 >/dev/null 2>&1; then
  echo "FAIL: malformed two-word echo unexpectedly succeeded" >&2
  exit 1
fi

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'readPair(address)(uint256)' \
  "$target")" 1 "getPair first word"

pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'readTriple(address)(uint256)' \
  "$target")" 1 "getTriple first word (exact three words)"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'readQuad(address)(uint256)' \
  "$target")" 1 "getQuad first word (exact four words)"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$target" 'setTripleWords(uint256)' 2 >/dev/null
if "$cast" call --rpc-url "$rpc" "$addr" 'readTriple(address)(uint256)' "$target" >/dev/null 2>&1; then
  echo "FAIL: two-word frame passed the exact-three-word gate" >&2
  exit 1
fi
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$target" 'setQuadWords(uint256)' 5 >/dev/null
if "$cast" call --rpc-url "$rpc" "$addr" 'readQuad(address)(uint256)' "$target" >/dev/null 2>&1; then
  echo "FAIL: five-word frame passed the exact-four-word gate" >&2
  exit 1
fi

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'readOn(address)(bool)' "$target")" \
  true "strict bool reads canonical true"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$target" 'setOnWord(uint256)' 0 >/dev/null
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'readOn(address)(bool)' "$target")" \
  false "strict bool reads canonical false"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$target" 'setOnWord(uint256)' 2 >/dev/null
if "$cast" call --rpc-url "$rpc" "$addr" 'readOn(address)(bool)' "$target" >/dev/null 2>&1; then
  echo "FAIL: bool word 2 passed the strict-bool gate" >&2
  exit 1
fi

owner="$("$cast" call --rpc-url "$rpc" "$addr" 'readOwner(address)(address)' "$target")"
pf_evm_require_equal "$(tr 'A-F' 'a-f' <<<"$owner")" "$(tr 'A-F' 'a-f' <<<"$target")" \
  "canonical address read through STATICCALL"
dirty="$("$python" -I -S -c "print(hex((1 << 160) | int('$target', 16)))")"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$target" 'setOwnerWord(uint256)' "$dirty" >/dev/null
if "$cast" call --rpc-url "$rpc" "$addr" 'readOwner(address)(address)' "$target" >/dev/null 2>&1; then
  echo "FAIL: dirty high bytes passed the canonical-address gate" >&2
  exit 1
fi
if "$cast" call --rpc-url "$rpc" "$addr" 'readOwner(address)(address)' "$eoa" >/dev/null 2>&1; then
  echo "FAIL: empty EOA returndata passed the canonical-address gate" >&2
  exit 1
fi

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'openTransfer(address,address,uint256)' "$target" "$eoa" 1 >/dev/null

before="$(pf_evm_to_dec "$("$cast" balance --rpc-url "$rpc" "$target")")"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" --value 5 \
  "$addr" 'payTarget(address,uint256)' "$target" 5 >/dev/null
after="$(pf_evm_to_dec "$("$cast" balance --rpc-url "$rpc" "$target")")"
want="$("$python" -I -S -c "print(int('$before') + 5)")"
pf_evm_require_equal "$after" "$want" "CALL value must credit target"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'markThenPing(address)' "$target" >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'flagOf()(uint64)')" 1 \
  "flag stored after CALL"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$target" 'seenFlag()(uint256)')" 0 \
  "CALL observed pre-store flag (effect before sstore)"

# Bounded bytes argument. The callee must decode the runtime length and content, and the whole
# calldata of both the CALL and the STATICCALL must hash to the canonical encoding `cast`
# produces, for lengths 0, 3, and 8.
sink_case() {
  local data="$1" want_len="$2"
  local want_hash want_calldata want_static
  want_hash="$("$cast" keccak "$data")"
  want_calldata="$("$cast" keccak "$("$cast" calldata 'sink(uint256,bytes)' 7 "$data")")"
  want_static="$("$cast" keccak "$("$cast" calldata 'calldataHash(bytes)' "$data")")"
  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'sinkBytes(address,uint256,bytes)' "$target" 7 "$data" >/dev/null
  pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$target" 'sunkTag()(uint256)')" 7 \
    "sink tag (len $want_len)"
  pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$target" 'sunkLength()(uint256)')" \
    "$want_len" "sink length"
  pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$target" 'sunkHash()(bytes32)')" \
    "$want_hash" "sink payload keccak (len $want_len)"
  pf_evm_require_equal \
    "$("$cast" call --rpc-url "$rpc" "$target" 'sunkCalldataHash()(bytes32)')" \
    "$want_calldata" "sink calldata is the canonical encoding (len $want_len)"
  pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
    'hashBytes(address,bytes)(bytes32)' "$target" "$data")" "$want_static" \
    "STATICCALL calldata is the canonical encoding (len $want_len)"
}
sink_case 0x 0
sink_case 0x616263 3
sink_case 0x0001020304050607 8
if "$cast" call --rpc-url "$rpc" "$addr" 'hashBytes(address,bytes)(bytes32)' \
    "$target" 0x000102030405060708 >/dev/null 2>&1; then
  echo "FAIL: nine bytes passed the BoundedBytes 8 entry" >&2
  exit 1
fi

# Reads in value position. Each guard is observed on both sides against the mock's state, the
# call inside an untaken branch is proven absent through echo(0)'s two-word frame, and the
# fail-closed frames still hold when the read feeds a guard, a comparison, or an argument.
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$target" 'setOnWord(uint256)' 1 >/dev/null
pings="$(pf_evm_to_dec "$("$cast" call --rpc-url "$rpc" "$target" 'pings()(uint256)')")"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'pingIfOn(address)' "$target" >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$target" 'pings()(uint256)')" \
  "$((pings + 1))" "isOn true runs the guarded CALL"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'echoIfOn(address,uint256)(uint256)' "$target" 7)" 7 "isOn true selects the echoed word"
if "$cast" call --rpc-url "$rpc" "$addr" 'echoIfOn(address,uint256)(uint256)' \
    "$target" 0 >/dev/null 2>&1; then
  echo "FAIL: two-word echo(0) frame passed the gate inside the taken branch" >&2
  exit 1
fi
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$target" 'setOnWord(uint256)' 0 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'pingIfOn(address)' "$target" >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$target" 'pings()(uint256)')" \
  "$((pings + 1))" "isOn false skips the guarded CALL"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'echoIfOn(address,uint256)(uint256)' "$target" 7)" 0 "isOn false selects zero"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'echoIfOn(address,uint256)(uint256)' "$target" 0)" 0 \
  "isOn false never reaches echo(0)"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$target" 'setOnWord(uint256)' 2 >/dev/null
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" 'pingIfOn(address)' "$target" >/dev/null 2>&1; then
  echo "FAIL: bool word 2 passed the strict-bool gate feeding a guard" >&2
  exit 1
fi

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'covers(address,address,uint256)(bool)' "$target" "$eoa" 1000)" true \
  "balanceOf 1000 covers 1000"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'covers(address,address,uint256)(bool)' "$target" "$eoa" 1001)" false \
  "balanceOf 1000 does not cover 1001"
big="$("$python" -I -S -c "print((1 << 200) + 12345)")"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$target" 'setBalanceWord(uint256)' "$big" >/dev/null
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'covers(address,address,uint256)(bool)' "$target" "$eoa" "$big")" true \
  "a four-limb balance covers itself"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'echoBalance(address,address)(uint256)' "$target" "$eoa")" "$big" \
  "echo(balanceOf(who)) forwards all four limbs of the inner read"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$target" 'setBalanceWord(uint256)' 0 >/dev/null
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'covers(address,address,uint256)(bool)' "$target" "$eoa" 1)" false \
  "balanceOf 0 does not cover 1"
if "$cast" call --rpc-url "$rpc" "$addr" 'echoBalance(address,address)(uint256)' \
    "$target" "$eoa" >/dev/null 2>&1; then
  echo "FAIL: echo(0) two-word frame passed the gate when the inner read was zero" >&2
  exit 1
fi

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$target" 'setOwnerWord(uint256)' "$target" >/dev/null
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'ownedBy(address,address)(bool)' "$target" "$target")" true "ownerOf names the target"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'ownedBy(address,address)(bool)' "$target" "$eoa")" false "ownerOf does not name the EOA"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$target" 'setOwnerWord(uint256)' "$dirty" >/dev/null
if "$cast" call --rpc-url "$rpc" "$addr" 'ownedBy(address,address)(bool)' \
    "$target" "$target" >/dev/null 2>&1; then
  echo "FAIL: dirty high bytes passed the canonical-address gate inside a comparison" >&2
  exit 1
fi

# Receiver hook through CALL with the magic policy. The callee must answer with exactly one
# word equal to onERC721Received's own selector; the mock's frame is settable so every other
# answer is driven: a wrong selector, a dirty low byte, an empty frame, a two-word frame, an EOA.
hook_magic="$(pf_evm_to_dec "$("$cast" sig 'onERC721Received(address,address,uint256,bytes)')")"
hook_word="$("$python" -I -S -c "print(int('$hook_magic') << 224)")"
hook_case() {
  local word="$1" size="$2" label="$3"
  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$target" 'setHookWord(uint256)' "$word" >/dev/null
  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$target" 'setHookSize(uint256)' "$size" >/dev/null
  if "$cast" send --rpc-url "$rpc" --private-key "$private_key" "$addr" \
      'notifyReceiver(address,address,address,uint256,bytes)' \
      "$target" "$addr" "$eoa" 7 0x616263 >/dev/null 2>&1; then
    echo "FAIL: $label passed the magic gate" >&2
    exit 1
  fi
}
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$addr" \
  'notifyReceiver(address,address,address,uint256,bytes)' "$target" "$addr" "$eoa" 7 0x616263 \
  >/dev/null
pf_evm_require_equal "$(tr 'A-F' 'a-f' <<<"$("$cast" call --rpc-url "$rpc" "$target" \
  'hookOperator()(address)')")" "$(tr 'A-F' 'a-f' <<<"$addr")" "hook saw the operator"
pf_evm_require_equal "$(tr 'A-F' 'a-f' <<<"$("$cast" call --rpc-url "$rpc" "$target" \
  'hookFrom()(address)')")" "$(tr 'A-F' 'a-f' <<<"$eoa")" "hook saw from"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$target" 'hookTokenId()(uint256)')" 7 \
  "hook saw the token id"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$target" 'hookDataHash()(bytes32)')" \
  "$("$cast" keccak 0x616263)" "hook saw the bytes payload"
hook_case "$("$python" -I -S -c "print(0xdeadbeef << 224)")" 32 "a wrong selector"
hook_case "$("$python" -I -S -c "print(($hook_word) | 1)")" 32 "a dirty low byte"
hook_case "$hook_word" 0 "an empty frame"
hook_case "$hook_word" 64 "a two-word frame"
hook_case "$hook_word" 4 "a four-byte frame"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" "$addr" \
    'notifyReceiver(address,address,address,uint256,bytes)' \
    "$eoa" "$addr" "$eoa" 7 0x616263 >/dev/null 2>&1; then
  echo "FAIL: an EOA receiver passed the magic gate" >&2
  exit 1
fi
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$target" 'setHookWord(uint256)' "$hook_word" >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$target" 'setHookSize(uint256)' 32 >/dev/null
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$addr" \
  'notifyReceiver(address,address,address,uint256,bytes)' "$target" "$addr" "$eoa" 8 0x \
  >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$target" 'hookTokenId()(uint256)')" 8 \
  "hook accepted again once the magic frame is restored"

echo "evm-anvil-opencall: ok (typed CALL/STATICCALL + bool/address/3-4-word reads + reads in guards/comparisons/arguments + bytes arg + value + EOA + malformed + effect-order + CALL-carrier refusal + magic receiver hook; engineering only)"
