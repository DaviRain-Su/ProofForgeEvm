#!/usr/bin/env bash
# SignerLink: Ierc1271.checkSignature (1271-only) and checkNow (EOA or 1271). Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-signerlink
echo "building SignerLink.bin" >&2
lake exe pf -- build --target evm --out "$root/build/evm" SignerLink \
  || { echo "FAIL: pf build SignerLink failed" >&2; exit 1; }
bin="$root/build/evm/SignerLink.bin"
abi="$root/build/evm/SignerLink.abi.json"
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
solc_bin="$(pf_evm_find_tool solc)" || {
  echo "evm-anvil-signerlink: skip: solc not found, the ERC-1271 wallet cannot be compiled" >&2
  exit 0
}
pf_evm_start_anvil "${PF_EVM_PORT:-18718}" "$root/build/evm/anvil-signerlink.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty SignerLink.bin" >&2; exit 1; }

sender="$("$cast" wallet address --private-key "$private_key")"
other_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
other="$("$cast" wallet address --private-key "$other_key")"
addr="$(pf_evm_deploy_ctor_address "$bytecode" "$sender")"

# The wallet's owner is the sender, so a signature from the sender's key is the one it accepts.
"$solc_bin" --bin --optimize --overwrite -o "$root/build/evm" "$here/Erc1271WalletMock.sol" >/dev/null
wallet_bin="$root/build/evm/Erc1271WalletMock.bin"
[[ -f "$wallet_bin" ]] || { echo "FAIL: missing Erc1271WalletMock.bin" >&2; exit 1; }
wallet="$(pf_evm_deploy_ctor_address "$(tr -d '\n\r ' < "$wallet_bin")" "$sender")"

sig_of='requireSigner(address,bytes32,bytes)'
magic_word="$("$python" -I -S -c \
  "print(int('$("$cast" sig 'isValidSignature(bytes32,bytes)')', 16) << 224)")"
digest="$("$cast" keccak "SignerLink-test")"
good_sig="$("$cast" wallet sign --no-hash --private-key "$private_key" "$digest")"
foreign_sig="$("$cast" wallet sign --no-hash --private-key "$other_key" "$digest")"
[[ ${#good_sig} -eq 132 ]] || { echo "FAIL: signature is not 65 bytes: $good_sig" >&2; exit 1; }

accepted() { "$cast" call --rpc-url "$rpc" "$addr" 'accepted()(uint64)'; }
seen() { "$cast" call --rpc-url "$rpc" "$wallet" "$1"; }
require() { # signer hash signature
  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" "$sig_of" "$1" "$2" "$3" >/dev/null
}
refuse() { # signer hash signature label
  pf_evm_require_empty_revert "$addr" "$sender" \
    "$("$cast" calldata "$sig_of" "$1" "$2" "$3")" "$4"
  if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
      "$addr" "$sig_of" "$1" "$2" "$3" >/dev/null 2>&1; then
    echo "FAIL: $4 passed the signer check" >&2
    exit 1
  fi
}
set_frame() { # word size reverts
  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$wallet" 'setFrame(uint256,uint256,bool)' "$1" "$2" "$3" >/dev/null
}

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" --from "$sender" "$addr" \
  "$sig_of(bool)" "$wallet" "$digest" "$good_sig")" true "requireSigner answers true"
require "$wallet" "$digest" "$good_sig"
pf_evm_require_equal "$(accepted)" 1 "accepted counts the passed check"
pf_evm_require_equal "$(seen 'seenHash()(bytes32)')" "$digest" "wallet saw the hash"
pf_evm_require_equal "$(seen 'seenSignatureHash()(bytes32)')" "$("$cast" keccak "$good_sig")" \
  "wallet saw the 65 signature bytes"
pf_evm_require_equal "$(seen 'seenLength()(uint256)')" 65 "wallet saw the runtime length 65"
pf_evm_require_equal "$(seen 'calls()(uint256)')" 1 "wallet was called once"

refuse "$wallet" "$digest" "$foreign_sig" "a signature from another key"
tampered="${good_sig:0:20}$(printf '%02x' $(( (16#${good_sig:20:2} ^ 1) )))${good_sig:22}"
refuse "$wallet" "$digest" "$tampered" "a tampered signature byte"
refuse "$wallet" "$digest" "${good_sig:0:130}" "a 64-byte signature"
refuse "$wallet" "$("$cast" keccak "SignerLink-other")" "$good_sig" "a different hash"
refuse "$wallet" "$digest" 0x "an empty signature"
pf_evm_require_equal "$(accepted)" 1 "refusals left the counter in place"

refuse "$wallet" "$digest" "${good_sig}ff" "66 bytes exceed the bound"
pf_evm_require_equal "$(seen 'calls()(uint256)')" 1 "the over-bound signature did not reach the wallet"

refuse "$other" "$digest" "$good_sig" "an EOA signer"
refuse "0x00000000000000000000000000000000000000ee" "$digest" "$good_sig" "a signer with no code"

set_frame "$magic_word" 32 false
require "$wallet" "$digest" 0xdeadbeef
pf_evm_require_equal "$(accepted)" 2 "a fixed magic frame passes whatever the bytes are"
pf_evm_require_equal "$(seen 'seenLength()(uint256)')" 4 "wallet saw the 4-byte payload"
refuse_frame() { # word size reverts label
  set_frame "$1" "$2" "$3"
  refuse "$wallet" "$digest" "$good_sig" "$4"
}
refuse_frame "$("$python" -I -S -c "print(0xdeadbeef << 224)")" 32 false "a wrong selector"
refuse_frame "$("$python" -I -S -c "print(($magic_word) | 1)")" 32 false "a dirty low byte"
refuse_frame "$magic_word" 0 false "an empty frame"
refuse_frame "$magic_word" 64 false "a two-word frame"
refuse_frame "$magic_word" 32 true "a wallet reverting with the magic word"
pf_evm_require_equal "$(accepted)" 2 "frame refusals left the counter in place"
"$cast" send --rpc-url "$rpc" --private-key "$private_key" "$wallet" 'clearFrame()' >/dev/null
require "$wallet" "$digest" "$good_sig"
pf_evm_require_equal "$(accepted)" 3 "the real wallet accepts again once the frame is cleared"

now_of='requireNow(address,bytes32,bytes)'
require_now() {
  "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$addr" "$now_of" "$1" "$2" "$3" >/dev/null
}
refuse_now_empty() {
  pf_evm_require_empty_revert "$addr" "$sender" \
    "$("$cast" calldata "$now_of" "$1" "$2" "$3")" "$4"
  if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
      "$addr" "$now_of" "$1" "$2" "$3" >/dev/null 2>&1; then
    echo "FAIL: $4 passed requireNow" >&2
    exit 1
  fi
}
refuse_now_unauth() {
  pf_evm_require_unauthorized "$addr" "$sender" \
    "$("$cast" calldata "$now_of" "$1" "$2" "$3")" "$1" "$4"
  if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
      "$addr" "$now_of" "$1" "$2" "$3" >/dev/null 2>&1; then
    echo "FAIL: $4 passed requireNow" >&2
    exit 1
  fi
}

wallet_calls="$(seen 'calls()(uint256)')"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" --from "$sender" "$addr" \
  "$now_of(bool)" "$sender" "$digest" "$good_sig")" true "requireNow accepts an EOA signer"
require_now "$sender" "$digest" "$good_sig"
pf_evm_require_equal "$(accepted)" 4 "accepted counts the EOA check"
pf_evm_require_equal "$(seen 'calls()(uint256)')" "$wallet_calls" "the EOA check did not call the wallet"

refuse_now_unauth "$sender" "$digest" "$foreign_sig" "requireNow rejects another key on an EOA"
refuse_now_unauth "$sender" "$digest" "${good_sig:0:130}" "requireNow rejects a 64-byte EOA frame"
refuse_now_unauth "$sender" "$digest" 0x "requireNow rejects an empty EOA frame"
pf_evm_require_equal "$(accepted)" 4 "EOA refusals left the counter in place"
pf_evm_require_equal "$(seen 'calls()(uint256)')" "$wallet_calls" "EOA refusals did not call the wallet"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" --from "$sender" "$addr" \
  "$now_of(bool)" "$wallet" "$digest" "$good_sig")" true \
  "requireNow accepts a contract signer through ERC-1271"
require_now "$wallet" "$digest" "$good_sig"
pf_evm_require_equal "$(accepted)" 5 "accepted counts the 1271 arm of requireNow"
pf_evm_require_equal "$(seen 'calls()(uint256)')" "$((wallet_calls + 1))" "requireNow called the wallet"

refuse_now_empty "$wallet" "$digest" "$foreign_sig" \
  "requireNow on a wallet still empty-reverts a foreign 1271 answer"

yul="$root/build/evm/SignerLink.yul"
[[ -f "$yul" ]] || { echo "FAIL: missing $yul" >&2; exit 1; }
mut_dir="$root/build/evm/signerlink-extcodesize-mut"
rm -rf "$mut_dir"
mkdir -p "$mut_dir"
"$python" -I -S -c "
from pathlib import Path
import re, sys
src = Path('$yul').read_text()
n = src.count('extcodesize(')
if n != 1:
    sys.stderr.write(f'FAIL: expected one extcodesize(, got {n}\\n')
    sys.exit(1)
out, k = re.subn(r'extcodesize\\([^)]*\\)', '0', src, count=1)
if k != 1:
    sys.stderr.write('FAIL: extcodesize rewrite missed\\n')
    sys.exit(1)
Path('$mut_dir/SignerLink.yul').write_text(out)
"
mut_code="$("$solc_bin" --strict-assembly --optimize --evm-version cancun --bin \
  "$mut_dir/SignerLink.yul" | "$python" -I -S -c "
import sys
lines=[ln.strip() for ln in sys.stdin.read().splitlines() if ln.strip()]
hexes=[ln for ln in lines if len(ln)>100 and all(c in '0123456789abcdefABCDEF' for c in ln)]
if not hexes:
    raise SystemExit('FAIL: solc --strict-assembly wrote no bytecode')
print(hexes[-1])
")"
[[ -n "$mut_code" ]] || { echo "FAIL: empty mutated SignerLink bytecode" >&2; exit 1; }
mut_addr="$(pf_evm_deploy_ctor_address "$mut_code" "$sender")"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" --from "$sender" "$mut_addr" \
  "$now_of(bool)" "$sender" "$digest" "$good_sig")" true \
  "extcodesize forced to 0 still accepts an EOA through ecrecover"
pf_evm_require_unauthorized "$mut_addr" "$sender" \
  "$("$cast" calldata "$now_of" "$wallet" "$digest" "$good_sig")" "$wallet" \
  "extcodesize forced to 0 treats the wallet as an EOA"
if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
    "$mut_addr" "$now_of" "$wallet" "$digest" "$good_sig" >/dev/null 2>&1; then
  echo "FAIL: mutated requireNow accepted the wallet as an EOA" >&2
  exit 1
fi

echo "evm-anvil-signerlink: ok (ERC-1271 isValidSignature via callMagic; checkNow EOA + wallet; extcodesize mutation)"
