#!/usr/bin/env bash
# SignerLink: Sdk.Ierc1271.checkSignature against a Solidity ERC-1271 wallet. Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-signerlink
bin="$root/build/evm/SignerLink.bin"
abi="$root/build/evm/SignerLink.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building SignerLink.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" SignerLink \
    || { echo "FAIL: pf build SignerLink failed" >&2; exit 1; }
fi
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

echo "evm-anvil-signerlink: ok (ERC-1271 isValidSignature via callMagic: owner signature, five signature refusals, the 65-byte bound, two no-code signers, five frame refusals)"
