#!/usr/bin/env bash
# EvmChainGuard: constructor-immutable expected chainId vs Context.chainId.
# Local Anvil impersonates Base Sepolia (84532) and VibeNet (84538453).
# External RPC (PF_EVM_RPC_URL) uses PF_EVM_CHAIN_ID as-is; anvil_setStorageAt is disabled.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime-tests/evm/lib.sh
source "$here/lib.sh"

if [[ -z "${PF_EVM_RPC_URL:-}" ]]; then
  PF_EVM_CHAIN_ID="${PF_EVM_CHAIN_ID:-84532}"
fi

pf_evm_evm_init evm-anvil-chain-guard
bin="$root/build/evm/EvmChainGuard.bin"
if [[ ! -f "$bin" ]]; then
  lake build Examples.Evm.EvmChainGuard >/dev/null
  lake exe pf -- build --target evm --out "$root/build/evm" EvmChainGuard >/dev/null
fi
pf_evm_ensure_bin "$bin"
bytecode="$(tr -d '\n\r ' < "$bin")"
[[ -n "$bytecode" ]] || { echo "FAIL: empty EvmChainGuard.bin" >&2; exit 1; }

port="${PF_EVM_PORT:-18690}"
log="$root/build/evm/anvil-chain-guard.log"

run_guard_on_chain() {
  local expected="$1"
  local other="$2"
  chain_id="$expected"
  pf_evm_start_anvil "$port" "$log"
  pf_evm_require_uint "$("$cast" chain-id --rpc-url "$rpc")" "$expected" \
    "rpc chain-id $expected"

  local addr bad
  addr="$(pf_evm_deploy_ctor_u64 "$bytecode" "$expected")"
  pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'expectedChainId()(uint64)')" \
    "$expected" "immutable expectedChainId"
  pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'chainId()(uint64)')" \
    "$expected" "Context.chainId"
  pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'get()(uint64)')" \
    0 "dummy starts at 0"

  "$cast" send --rpc-url "$rpc" --private-key "$private_key" "$addr" 'ping()' >/dev/null
  pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'get()(uint64)')" \
    "$expected" "ping stores chainId"
  pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$addr" 'ping()(uint64)')" \
    "$expected" "ping returns chainId"

  bad="$(pf_evm_deploy_ctor_u64 "$bytecode" "$other")"
  sender="$("$cast" wallet address --private-key "$private_key")"
  if "$cast" send --rpc-url "$rpc" --private-key "$private_key" \
      "$bad" 'ping()' >/dev/null 2>&1; then
    echo "FAIL: ping on wrong-chain immutable unexpectedly succeeded" >&2
    exit 1
  fi
  pf_evm_require_word_revert "$bad" "$sender" \
    "$("$cast" calldata 'ping()')" 'wrongChain(uint64,uint64)' \
    "wrong-chain ping" "$other" "$expected"
  pf_evm_require_uint "$("$cast" call --rpc-url "$rpc" "$bad" 'get()(uint64)')" \
    0 "wrong-chain ping is atomic"

  local saved_mode="${anvil_mode}"
  # `exit` inside the helper would kill this script; the subshell contains it.
  if (anvil_mode=0; pf_evm_set_storage_word "$addr" 0 1) >/dev/null 2>&1; then
    echo "FAIL: anvil_setStorageAt helper unexpectedly ran off Anvil mode" >&2
    exit 1
  fi
  anvil_mode="$saved_mode"

  PF_EVM_RPC_URL="$rpc" PF_EVM_CHAIN_ID="$expected" PF_EVM_PRIVATE_KEY="$private_key" \
    "$root/scripts/deploy_evm.sh" "$bin" -- 'constructor(uint64)' "$expected" >/dev/null

  if PF_EVM_RPC_URL="$rpc" PF_EVM_CHAIN_ID="$other" PF_EVM_PRIVATE_KEY="$private_key" \
      "$root/scripts/deploy_evm.sh" "$bin" -- 'constructor(uint64)' "$expected" >/dev/null 2>&1; then
    echo "FAIL: deploy_evm.sh chain-id mismatch unexpectedly signed" >&2
    exit 1
  fi
}

if [[ "${anvil_mode}" == 1 ]]; then
  run_guard_on_chain 84532 84538453
  run_guard_on_chain 84538453 84532
else
  other="84538453"
  if [[ "$chain_id" == "84538453" ]]; then
    other="84532"
  fi
  run_guard_on_chain "$chain_id" "$other"
fi

echo "evm-anvil-chain-guard: ok (immutable chainId vs Context.chainId; engineering only)"
