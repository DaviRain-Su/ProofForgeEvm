#!/usr/bin/env bash
# ProofLink: bounded Merkle proof verification (sorted pair keccak256). Darwin + Linux.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

pf_evm_evm_init evm-anvil-prooflink
bin="$root/build/evm/ProofLink.bin"
abi="$root/build/evm/ProofLink.abi.json"
if [[ ! -f "$bin" || ! -f "$abi" ]]; then
  echo "building ProofLink.bin" >&2
  lake exe pf -- build --target evm --out "$root/build/evm" ProofLink \
    || { echo "FAIL: pf build ProofLink failed" >&2; exit 1; }
fi
[[ -f "$bin" ]] || { echo "FAIL: missing $bin" >&2; exit 1; }
[[ -f "$abi" ]] || { echo "FAIL: missing $abi" >&2; exit 1; }
pf_evm_start_anvil "${PF_EVM_PORT:-18697}" "$root/build/evm/anvil-prooflink.log"

bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty ProofLink.bin" >&2; exit 1; }

leaf_a="$("$cast" keccak "pf-leaf-a")"
leaf_b="$("$cast" keccak "pf-leaf-b")"
if [[ "$leaf_a" < "$leaf_b" ]]; then
  pair_root="$("$cast" keccak "$("$cast" concat-hex "$leaf_a" "$leaf_b")")"
else
  pair_root="$("$cast" keccak "$("$cast" concat-hex "$leaf_b" "$leaf_a")")"
fi

encoded="$("$cast" abi-encode 'constructor(bytes32)' "$pair_root")"
receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${encoded#0x}")"
addr="$(printf '%s' "$receipt" | pf_evm_contract_address)"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" 'rootOf()(bytes32)')" \
  "$pair_root" "constructor root"

raw_verify="$("$cast" call --rpc-url "$rpc" "$addr" \
  'verify(bytes32[],bytes32)(bool)' "[$leaf_b]" "$leaf_a")"
echo "debug verify=$raw_verify rootOf=$("$cast" call --rpc-url "$rpc" "$addr" 'rootOf()(bytes32)')" >&2

# Prove leaf_a with sibling leaf_b.
pf_evm_require_equal "$raw_verify" \
  true "valid single-element proof"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'verify(bytes32[],bytes32)(bool)' "[$leaf_a]" "$leaf_b")" \
  true "valid proof for sibling leaf"

pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$addr" \
  'verify(bytes32[],bytes32)(bool)' "[$leaf_b]" "$leaf_b")" \
  false "leaf without sibling fails"

# Exercise all eight bounded proof slots against an independently folded OZ-style root.
deep_root="$leaf_a"
proof_items=()
for i in {0..7}; do
  sibling="$("$cast" keccak "pf-sibling-$i")"
  proof_items+=("$sibling")
  if [[ "$deep_root" < "$sibling" ]]; then
    deep_root="$("$cast" keccak "$("$cast" concat-hex "$deep_root" "$sibling")")"
  else
    deep_root="$("$cast" keccak "$("$cast" concat-hex "$sibling" "$deep_root")")"
  fi
done
deep_encoded="$("$cast" abi-encode 'constructor(bytes32)' "$deep_root")"
deep_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${deep_encoded#0x}")"
deep_addr="$(printf '%s' "$deep_receipt" | pf_evm_contract_address)"
proof_arg="[$(IFS=,; echo "${proof_items[*]}")]"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$deep_addr" \
  'verify(bytes32[],bytes32)(bool)' "$proof_arg" "$leaf_a")" \
  true "valid depth-eight proof"

# A ninth element exceeds the ABI profile capacity and must revert before source execution.
proof9="$proof_arg"
proof9="${proof9%]},$leaf_b]"
if "$cast" call --rpc-url "$rpc" "$deep_addr" \
    'verify(bytes32[],bytes32)(bool)' "$proof9" "$leaf_a" >/dev/null 2>&1; then
  echo "FAIL: depth-nine proof unexpectedly succeeded" >&2
  exit 1
fi

# Empty proofs are valid exactly when the leaf itself is the root.
leaf_encoded="$("$cast" abi-encode 'constructor(bytes32)' "$leaf_a")"
leaf_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${leaf_encoded#0x}")"
leaf_addr="$(printf '%s' "$leaf_receipt" | pf_evm_contract_address)"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$leaf_addr" \
  'verify(bytes32[],bytes32)(bool)' "[]" "$leaf_a")" \
  true "empty proof accepts its root leaf"

# Zero root fails closed on rootOf and verify.
zero="0x0000000000000000000000000000000000000000000000000000000000000000"
zero_encoded="$("$cast" abi-encode 'constructor(bytes32)' "$zero")"
zero_receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}${zero_encoded#0x}")"
zero_addr="$(printf '%s' "$zero_receipt" | pf_evm_contract_address)"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$zero_addr" 'rootOf()(bytes32)')" \
  "$zero" "zero root fails closed on rootOf"
pf_evm_require_equal "$("$cast" call --rpc-url "$rpc" "$zero_addr" \
  'verify(bytes32[],bytes32)(bool)' "[$leaf_b]" "$leaf_a")" \
  false "zero root fails closed on verify"

echo "evm-anvil-prooflink: ok (bounded Merkle proof verify + fail-closed root gate)"
