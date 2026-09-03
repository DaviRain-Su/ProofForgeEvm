#!/usr/bin/env bash
# Deploy a ProofForge `.bin` with `cast send --create`.
#
# Network selection is an execution contract, not a compiler special case:
#   PF_EVM_RPC_URL      JSON-RPC URL (default http://127.0.0.1:8545)
#   PF_EVM_CHAIN_ID     Expected chain id. Required when PF_EVM_RPC_URL is set
#                       (fail-closed). Local default: 31338.
#   PF_EVM_PRIVATE_KEY  Signing key. Never written to disk. Default: Anvil account 0.
#
# No GitHub secrets are required. A funded key is an operator input for public RPCs.
#
# Usage:
#   scripts/deploy_evm.sh path/to/Name.bin
#   scripts/deploy_evm.sh path/to/Name.bin -- 'constructor(uint64)' 84532
#
# Prints chain-id, address, tx hash, and sha256 of the artifact. Refuses to sign
# when the observed chain id differs from PF_EVM_CHAIN_ID.
set -euo pipefail

usage() {
  echo "Usage: scripts/deploy_evm.sh <artifact.bin> [-- <cast abi-encode args>]" >&2
  echo "  PF_EVM_RPC_URL      JSON-RPC URL (default http://127.0.0.1:8545)" >&2
  echo "  PF_EVM_CHAIN_ID     expected chain id (required when PF_EVM_RPC_URL is set)" >&2
  echo "  PF_EVM_PRIVATE_KEY  signing key (default: Anvil account 0; never persisted)" >&2
  exit 2
}

pf_deploy_find_tool() {
  local name="$1"
  local dir candidate
  if [[ -n "${FOUNDRY_BIN:-}" ]]; then
    candidate="${FOUNDRY_BIN%/}/$name"
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  fi
  if [[ -n "${HOME:-}" ]]; then
    candidate="$HOME/.foundry/bin/$name"
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  fi
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  for dir in /usr/local/bin /opt/homebrew/bin /usr/bin; do
    candidate="$dir/$name"
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

[[ $# -ge 1 ]] || usage
bin_path="$1"
shift

if [[ ! -f "$bin_path" ]]; then
  echo "FAIL: missing artifact $bin_path" >&2
  exit 1
fi

rpc="${PF_EVM_RPC_URL:-http://127.0.0.1:8545}"
if [[ -n "${PF_EVM_RPC_URL:-}" ]]; then
  if [[ -z "${PF_EVM_CHAIN_ID:-}" ]]; then
    echo "FAIL: PF_EVM_RPC_URL is set but PF_EVM_CHAIN_ID is missing (fail-closed)" >&2
    exit 1
  fi
  expected="$PF_EVM_CHAIN_ID"
else
  expected="${PF_EVM_CHAIN_ID:-31338}"
fi
private_key="${PF_EVM_PRIVATE_KEY:-ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

cast="$(pf_deploy_find_tool cast)" || {
  echo "FAIL: cast not found (install foundryup, or set FOUNDRY_BIN)" >&2
  exit 1
}

observed="$("$cast" chain-id --rpc-url "$rpc")" || {
  echo "FAIL: cannot read chain-id from $rpc" >&2
  exit 1
}
if [[ "$observed" != "$expected" ]]; then
  echo "FAIL: chain-id mismatch (expected '$expected', got '$observed'); not signing" >&2
  exit 1
fi

bytecode="$(tr -d '\n\r ' < "$bin_path")"
bytecode="${bytecode#0x}"
bytecode="${bytecode#0X}"
[[ -n "$bytecode" ]] || { echo "FAIL: empty bytecode in $bin_path" >&2; exit 1; }

if [[ "${1:-}" == "--" ]]; then
  shift
  [[ $# -ge 1 ]] || { echo "FAIL: expected abi-encode arguments after --" >&2; exit 1; }
  encoded="$("$cast" abi-encode "$@")"
  bytecode="${bytecode}${encoded#0x}"
fi

if command -v sha256sum >/dev/null 2>&1; then
  digest="$(sha256sum "$bin_path" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  digest="$(shasum -a 256 "$bin_path" | awk '{print $1}')"
else
  echo "FAIL: sha256sum/shasum not found" >&2
  exit 1
fi

receipt="$("$cast" send --json --rpc-url "$rpc" --private-key "$private_key" \
  --create "0x${bytecode}")"
address="$(printf '%s' "$receipt" | python3 -I -S -c 'import json,sys; print(json.load(sys.stdin)["contractAddress"])')"
tx="$(printf '%s' "$receipt" | python3 -I -S -c 'import json,sys; r=json.load(sys.stdin); print(r.get("transactionHash") or r.get("hash") or "")')"

echo "chain-id: $observed"
echo "address: $address"
echo "tx: $tx"
echo "digest: sha256:$digest"
