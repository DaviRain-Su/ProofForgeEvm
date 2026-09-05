#!/usr/bin/env bash
# Auth3009Link: bounded ERC-3009 transfer- and receive-with-authorization. Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-auth3009link
bin="$root/build/evm/Auth3009Link.bin"
abi="$root/build/evm/Auth3009Link.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building Auth3009Link.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" Auth3009Link \
    || { echo "FAIL: pf build Auth3009Link failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18701}" "$root/build/evm/anvil-auth3009link.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty Auth3009Link.bin" >&2; exit 1; }

sender="$("$cast" wallet address --private-key "$private_key")"
other_key="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
dest="$("$cast" wallet address --private-key "$other_key")"

addr="$(pf_evm_deploy_ctor_address "$bytecode" "$sender")"

got_dom="$("$cast" call --rpc-url "$rpc" "$addr" 'DOMAIN_SEPARATOR()(bytes32)')"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$sender")" \
  0 "initial sender balance"

"$cast" send --rpc-url "$rpc" --private-key "$private_key" \
  "$addr" 'mint(address,uint256)' "$sender" 100 >/dev/null
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$sender")" \
  100 "minted sender"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'totalSupply()(uint256)')" \
  100 "total supply after mint"

valid_after=0
valid_before=9999999999
nonce="0x0000000000000000000000000000000000000000000000000000000000000001"
typed="$(printf '%s' "{
  \"types\": {
    \"EIP712Domain\": [
      {\"name\":\"name\",\"type\":\"string\"},
      {\"name\":\"version\",\"type\":\"string\"},
      {\"name\":\"chainId\",\"type\":\"uint256\"},
      {\"name\":\"verifyingContract\",\"type\":\"address\"}
    ],
    \"TransferWithAuthorization\": [
      {\"name\":\"from\",\"type\":\"address\"},
      {\"name\":\"to\",\"type\":\"address\"},
      {\"name\":\"value\",\"type\":\"uint256\"},
      {\"name\":\"validAfter\",\"type\":\"uint256\"},
      {\"name\":\"validBefore\",\"type\":\"uint256\"},
      {\"name\":\"nonce\",\"type\":\"bytes32\"}
    ]
  },
  \"primaryType\": \"TransferWithAuthorization\",
  \"domain\": {
    \"name\": \"Token\",
    \"version\": \"1\",
    \"chainId\": $chain_id,
    \"verifyingContract\": \"$addr\"
  },
  \"message\": {
    \"from\": \"$sender\",
    \"to\": \"$dest\",
    \"value\": \"25\",
    \"validAfter\": \"$valid_after\",
    \"validBefore\": \"$valid_before\",
    \"nonce\": \"$nonce\"
  }
}")"
sig="$("$cast" wallet sign --data --private-key "$private_key" "$typed")"
r="0x${sig:2:64}"
s="0x${sig:66:64}"
v="$((16#${sig:130:2}))"

wrong_sig="$("$cast" wallet sign --data --private-key "$other_key" "$typed")"
wrong_r="0x${wrong_sig:2:64}"
wrong_s="0x${wrong_sig:66:64}"
wrong_v="$((16#${wrong_sig:130:2}))"
wrong_data="$("$cast" calldata \
  'transferWithAuthorization(address,address,uint256,uint256,uint256,bytes32,uint8,bytes32,bytes32)' \
  "$sender" "$dest" 25 "$valid_after" "$valid_before" "$nonce" "$wrong_v" "$wrong_r" "$wrong_s")"
pf_evm_require_unauthorized "$addr" "$dest" "$wrong_data" "$dest" \
  "transferWithAuthorization signed by recipient"

transfer_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" 'transferWithAuthorization(address,address,uint256,uint256,uint256,bytes32,uint8,bytes32,bytes32)' \
  "$sender" "$dest" 25 "$valid_after" "$valid_before" "$nonce" "$v" "$r" "$s")"
auth_used_topic="$("$cast" keccak "AuthorizationUsed(address,bytes32)")"
printf '%s' "$transfer_receipt" | "$python" -I -S -c "
import json, sys
r = json.load(sys.stdin)
want = '${auth_used_topic,,}'
hits = [lg for lg in (r.get('logs') or [])
        if (lg.get('topics') or []) and lg['topics'][0].lower() == want]
if len(hits) != 1:
    raise SystemExit(f'FAIL: expected exactly one AuthorizationUsed log, got {len(hits)}')
topics = hits[0]['topics']
if len(topics) != 3:
    raise SystemExit(f'FAIL: AuthorizationUsed should be LOG3, got {len(topics)} topics')
sender = int('${sender,,}', 16)
nonce = int('${nonce,,}', 16)
if int(topics[1], 16) != sender:
    raise SystemExit(f'FAIL: AuthorizationUsed authorizer {topics[1]} != sender')
if int(topics[2], 16) != nonce:
    raise SystemExit(f'FAIL: AuthorizationUsed nonce {topics[2]} != expected')
data = (hits[0].get('data') or '0x')[2:]
if data not in ('', '0'):
    raise SystemExit(f'FAIL: AuthorizationUsed data should be empty, got {data}')
"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$sender")" \
  75 "sender after authorized transfer"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$dest")" \
  25 "recipient after authorized transfer"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'totalSupply()(uint256)')" \
  100 "total supply after authorized transfer"

if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'transferWithAuthorization(address,address,uint256,uint256,uint256,bytes32,uint8,bytes32,bytes32)' \
    "$sender" "$dest" 25 "$valid_after" "$valid_before" "$nonce" "$v" "$r" "$s" >/dev/null 2>&1; then
  echo "FAIL: replayed authorization unexpectedly succeeded" >&2
  exit 1
fi

ts="$(printf '%s' "$("$cast" block --rpc-url "$rpc" latest --json)" |
  "$python" -I -S -c 'import json,sys; print(json.load(sys.stdin)["timestamp"])')"
edge_nonce="0x0000000000000000000000000000000000000000000000000000000000000003"
edge_typed="$(printf '%s' "{
  \"types\": {
    \"EIP712Domain\": [
      {\"name\":\"name\",\"type\":\"string\"},
      {\"name\":\"version\",\"type\":\"string\"},
      {\"name\":\"chainId\",\"type\":\"uint256\"},
      {\"name\":\"verifyingContract\",\"type\":\"address\"}
    ],
    \"TransferWithAuthorization\": [
      {\"name\":\"from\",\"type\":\"address\"},
      {\"name\":\"to\",\"type\":\"address\"},
      {\"name\":\"value\",\"type\":\"uint256\"},
      {\"name\":\"validAfter\",\"type\":\"uint256\"},
      {\"name\":\"validBefore\",\"type\":\"uint256\"},
      {\"name\":\"nonce\",\"type\":\"bytes32\"}
    ]
  },
  \"primaryType\": \"TransferWithAuthorization\",
  \"domain\": {
    \"name\": \"Token\",
    \"version\": \"1\",
    \"chainId\": $chain_id,
    \"verifyingContract\": \"$addr\"
  },
  \"message\": {
    \"from\": \"$sender\",
    \"to\": \"$dest\",
    \"value\": \"1\",
    \"validAfter\": \"$ts\",
    \"validBefore\": \"$(( ts + 1000 ))\",
    \"nonce\": \"$edge_nonce\"
  }
}")"
edge_sig="$("$cast" wallet sign --data --private-key "$private_key" "$edge_typed")"
edge_r="0x${edge_sig:2:64}"
edge_s="0x${edge_sig:66:64}"
edge_v="$((16#${edge_sig:130:2}))"
# Pin the boundary deterministically: validAfter must equal the mined block's
# timestamp regardless of wall-clock drift between `cast block` and `cast send`
# (CI runners race past it, turning the negative case into a false pass).
"$cast" rpc --rpc-url "$rpc" evm_setNextBlockTimestamp "$ts" >/dev/null
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'transferWithAuthorization(address,address,uint256,uint256,uint256,bytes32,uint8,bytes32,bytes32)' \
    "$sender" "$dest" 1 "$ts" "$(( ts + 1000 ))" "$edge_nonce" "$edge_v" "$edge_r" "$edge_s" \
    >/dev/null 2>&1; then
  echo "FAIL: validAfter == timestamp unexpectedly succeeded" >&2
  exit 1
fi

edge_before_nonce="0x0000000000000000000000000000000000000000000000000000000000000004"
edge_before_typed="$(printf '%s' "{
  \"types\": {
    \"EIP712Domain\": [
      {\"name\":\"name\",\"type\":\"string\"},
      {\"name\":\"version\",\"type\":\"string\"},
      {\"name\":\"chainId\",\"type\":\"uint256\"},
      {\"name\":\"verifyingContract\",\"type\":\"address\"}
    ],
    \"TransferWithAuthorization\": [
      {\"name\":\"from\",\"type\":\"address\"},
      {\"name\":\"to\",\"type\":\"address\"},
      {\"name\":\"value\",\"type\":\"uint256\"},
      {\"name\":\"validAfter\",\"type\":\"uint256\"},
      {\"name\":\"validBefore\",\"type\":\"uint256\"},
      {\"name\":\"nonce\",\"type\":\"bytes32\"}
    ]
  },
  \"primaryType\": \"TransferWithAuthorization\",
  \"domain\": {
    \"name\": \"Token\",
    \"version\": \"1\",
    \"chainId\": $chain_id,
    \"verifyingContract\": \"$addr\"
  },
  \"message\": {
    \"from\": \"$sender\",
    \"to\": \"$dest\",
    \"value\": \"1\",
    \"validAfter\": \"0\",
    \"validBefore\": \"$ts\",
    \"nonce\": \"$edge_before_nonce\"
  }
}")"
edge_before_sig="$("$cast" wallet sign --data --private-key "$private_key" "$edge_before_typed")"
edge_before_r="0x${edge_before_sig:2:64}"
edge_before_s="0x${edge_before_sig:66:64}"
edge_before_v="$((16#${edge_before_sig:130:2}))"
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'transferWithAuthorization(address,address,uint256,uint256,uint256,bytes32,uint8,bytes32,bytes32)' \
    "$sender" "$dest" 1 0 "$ts" "$edge_before_nonce" "$edge_before_v" "$edge_before_r" "$edge_before_s" \
    >/dev/null 2>&1; then
  echo "FAIL: validBefore == timestamp unexpectedly succeeded" >&2
  exit 1
fi

got_dom2="$("$cast" call --rpc-url "$rpc" "$addr" 'DOMAIN_SEPARATOR()(bytes32)')"
pf_evm_require_equal "${got_dom2,,}" "${got_dom,,}" "DOMAIN_SEPARATOR holds after transferWithAuthorization"

recv_nonce="0x0000000000000000000000000000000000000000000000000000000000000002"
recv_typed="$(printf '%s' "{
  \"types\": {
    \"EIP712Domain\": [
      {\"name\":\"name\",\"type\":\"string\"},
      {\"name\":\"version\",\"type\":\"string\"},
      {\"name\":\"chainId\",\"type\":\"uint256\"},
      {\"name\":\"verifyingContract\",\"type\":\"address\"}
    ],
    \"ReceiveWithAuthorization\": [
      {\"name\":\"from\",\"type\":\"address\"},
      {\"name\":\"to\",\"type\":\"address\"},
      {\"name\":\"value\",\"type\":\"uint256\"},
      {\"name\":\"validAfter\",\"type\":\"uint256\"},
      {\"name\":\"validBefore\",\"type\":\"uint256\"},
      {\"name\":\"nonce\",\"type\":\"bytes32\"}
    ]
  },
  \"primaryType\": \"ReceiveWithAuthorization\",
  \"domain\": {
    \"name\": \"Token\",
    \"version\": \"1\",
    \"chainId\": $chain_id,
    \"verifyingContract\": \"$addr\"
  },
  \"message\": {
    \"from\": \"$sender\",
    \"to\": \"$dest\",
    \"value\": \"10\",
    \"validAfter\": \"$valid_after\",
    \"validBefore\": \"$valid_before\",
    \"nonce\": \"$recv_nonce\"
  }
}")"
recv_sig="$("$cast" wallet sign --data --private-key "$private_key" "$recv_typed")"
recv_r="0x${recv_sig:2:64}"
recv_s="0x${recv_sig:66:64}"
recv_v="$((16#${recv_sig:130:2}))"

recv_wrong_data="$("$cast" calldata \
  'receiveWithAuthorization(address,address,uint256,uint256,uint256,bytes32,uint8,bytes32,bytes32)' \
  "$sender" "$dest" 10 "$valid_after" "$valid_before" "$recv_nonce" "$recv_v" "$recv_r" "$recv_s")"
pf_evm_require_unauthorized "$addr" "$sender" "$recv_wrong_data" "$sender" \
  "receiveWithAuthorization submitted by from"

mismatch_nonce="0x0000000000000000000000000000000000000000000000000000000000000005"
mismatch_typed="$(printf '%s' "{
  \"types\": {
    \"EIP712Domain\": [
      {\"name\":\"name\",\"type\":\"string\"},
      {\"name\":\"version\",\"type\":\"string\"},
      {\"name\":\"chainId\",\"type\":\"uint256\"},
      {\"name\":\"verifyingContract\",\"type\":\"address\"}
    ],
    \"TransferWithAuthorization\": [
      {\"name\":\"from\",\"type\":\"address\"},
      {\"name\":\"to\",\"type\":\"address\"},
      {\"name\":\"value\",\"type\":\"uint256\"},
      {\"name\":\"validAfter\",\"type\":\"uint256\"},
      {\"name\":\"validBefore\",\"type\":\"uint256\"},
      {\"name\":\"nonce\",\"type\":\"bytes32\"}
    ]
  },
  \"primaryType\": \"TransferWithAuthorization\",
  \"domain\": {
    \"name\": \"Token\",
    \"version\": \"1\",
    \"chainId\": $chain_id,
    \"verifyingContract\": \"$addr\"
  },
  \"message\": {
    \"from\": \"$sender\",
    \"to\": \"$dest\",
    \"value\": \"1\",
    \"validAfter\": \"$valid_after\",
    \"validBefore\": \"$valid_before\",
    \"nonce\": \"$mismatch_nonce\"
  }
}")"
mismatch_sig="$("$cast" wallet sign --data --private-key "$private_key" "$mismatch_typed")"
mismatch_r="0x${mismatch_sig:2:64}"
mismatch_s="0x${mismatch_sig:66:64}"
mismatch_v="$((16#${mismatch_sig:130:2}))"
if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'receiveWithAuthorization(address,address,uint256,uint256,uint256,bytes32,uint8,bytes32,bytes32)' \
    "$sender" "$dest" 1 "$valid_after" "$valid_before" "$mismatch_nonce" \
    "$mismatch_v" "$mismatch_r" "$mismatch_s" >/dev/null 2>&1; then
  echo "FAIL: TransferWithAuthorization typehash unexpectedly authorized receiveWithAuthorization" >&2
  exit 1
fi

third_key="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
third="$("$cast" wallet address --private-key "$third_key")"
pf_evm_require_unauthorized "$addr" "$third" "$recv_wrong_data" "$third" \
  "receiveWithAuthorization submitted by a third party"

recv_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$other_key" \
  "$addr" 'receiveWithAuthorization(address,address,uint256,uint256,uint256,bytes32,uint8,bytes32,bytes32)' \
  "$sender" "$dest" 10 "$valid_after" "$valid_before" "$recv_nonce" "$recv_v" "$recv_r" "$recv_s")"
printf '%s' "$recv_receipt" | "$python" -I -S -c "
import json, sys
r = json.load(sys.stdin)
want = '${auth_used_topic,,}'
hits = [lg for lg in (r.get('logs') or [])
        if (lg.get('topics') or []) and lg['topics'][0].lower() == want]
if len(hits) != 1:
    raise SystemExit(f'FAIL: expected exactly one AuthorizationUsed log on receive, got {len(hits)}')
"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$sender")" \
  65 "sender after receiveWithAuthorization"
pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" \
  'balanceOf(address)(uint256)' "$dest")" \
  35 "recipient after receiveWithAuthorization"

if "$cast" send --rpc-url "$rpc" --private-key "$other_key" \
    "$addr" 'receiveWithAuthorization(address,address,uint256,uint256,uint256,bytes32,uint8,bytes32,bytes32)' \
    "$sender" "$dest" 10 "$valid_after" "$valid_before" "$recv_nonce" "$recv_v" "$recv_r" "$recv_s" >/dev/null 2>&1; then
  echo "FAIL: replayed receiveWithAuthorization unexpectedly succeeded" >&2
  exit 1
fi

echo "evm-anvil-auth3009link: ok (ERC-3009 transfer- and receive-with-authorization; engineering only)"
