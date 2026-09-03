#!/usr/bin/env bash
# Local CI mirror for ProofForge EVM — run the same lane gates *before* pushing.
#
# Usage:
#   scripts/ci_local.sh                  # auto lanes from git diff vs origin/main
#   scripts/ci_local.sh --fast           # python guards only
#   scripts/ci_local.sh --lane lean
#   scripts/ci_local.sh --lane evm
#   scripts/ci_local.sh --all            # every lane
#   scripts/ci_local.sh --base origin/main
#
# Env: CI_LOCAL_BASE, SKIP_SETUP=1
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BASE="${CI_LOCAL_BASE:-origin/main}"
FAST=0
ALL=0
declare -a LANES=()

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fast) FAST=1 ;;
    --all) ALL=1 ;;
    --lane) shift; LANES+=("$1") ;;
    --base) shift; BASE="$1" ;;
    -h|--help) usage 0 ;;
    *) echo "unknown arg: $1" >&2; usage 1 ;;
  esac
  shift
done

log() { printf '\n==> %s\n' "$*"; }

have_lane() {
  local want="$1" l
  for l in "${LANES[@]:-}"; do [[ "$l" == "$want" ]] && return 0; done
  return 1
}

matches_any() {
  local f="$1" pat
  shift
  for pat in "$@"; do
    case "$f" in $pat) return 0 ;; esac
  done
  return 1
}

detect_lanes() {
  git rev-parse --verify "$BASE" >/dev/null 2>&1 || git fetch origin main 2>/dev/null || true
  local mb
  mb="$(git merge-base HEAD "$BASE" 2>/dev/null || git rev-parse HEAD)"
  mapfile -t CHANGED < <({
    git diff --name-only "$mb" HEAD
    git diff --name-only --cached
    git diff --name-only
  } | awk 'NF && !seen[$0]++')

  if ((${#CHANGED[@]} == 0)); then
    log "no changed files vs $BASE — defaulting to lean+evm"
    LANES=(lean evm)
    return
  fi
  printf 'changed files (merge-base %s):\n' "$mb" >&2
  printf '  %s\n' "${CHANGED[@]}" >&2

  local lean=0 evm=0 shared=0 f
  for f in "${CHANGED[@]}"; do
    matches_any "$f" \
      '.github/workflows/ci.yml' '.agents/setup' 'lakefile.lean' 'lean-toolchain' 'lake-manifest.json' \
      'ProofForge/Cli.lean' 'ProofForge/Attr.lean' 'ProofForge/Extract.lean' 'ProofForge/Extract/**' \
      'ProofForge/Core/**' 'ProofForge/Crypto/**' 'ProofForge/Profile.lean' && shared=1
    matches_any "$f" \
      'ProofForge/**' 'Tests/**' 'Tests.lean' 'Examples/**' 'Examples.lean' \
      'scripts/check_*.py' 'lakefile.lean' 'lean-toolchain' 'lake-manifest.json' \
      '.github/workflows/ci.yml' '.agents/setup' && lean=1
    matches_any "$f" \
      'ProofForge/Evm/**' 'Examples/Evm/**' \
      'runtime-tests/evm/**' 'scripts/check_artifact_manifest.py' \
      'scripts/ci_pf_init_named_project.sh' \
      'lakefile.lean' 'lean-toolchain' 'lake-manifest.json' '.github/workflows/ci.yml' '.agents/setup' \
      'ProofForge/Cli.lean' 'ProofForge/Extract.lean' 'ProofForge/Extract/**' 'ProofForge/Core/**' \
      'templates/**' && evm=1
  done
  if (( shared )); then lean=1; evm=1; fi
  LANES=()
  (( lean )) && LANES+=(lean)
  (( evm )) && LANES+=(evm)
  if ((${#LANES[@]} == 0)); then
    log "docs only — running --fast guards"
    FAST=1
    LANES=(guards)
  fi
}

if (( FAST )); then
  LANES=(guards)
elif (( ALL )); then
  LANES=(lean evm)
elif ((${#LANES[@]} == 0)); then
  detect_lanes
fi

log "lanes: ${LANES[*]-none}  fast=${FAST}"

if [[ "${SKIP_SETUP:-0}" != "1" && "$FAST" != "1" ]]; then
  if [[ -x .agents/setup ]]; then
    log "Prepare pinned toolchains (.agents/setup)"
    ./.agents/setup
    export PATH="$HOME/.local/bin:$HOME/.foundry/bin:$HOME/.elan/bin:${PATH:-}"
  fi
fi

run_guards() {
  log "Python ownership / SDK / manifest / no-sorry guards"
  python3 scripts/check_ownership.py
  python3 scripts/check_sdk_import_closure.py
  python3 scripts/check_artifact_manifest.py --self-test
  python3 scripts/check_no_sorry.py
}

run_lean() {
  run_guards
  log "lake build + formalization gates + Tests"
  lake build
  lake build ProofForgeEvmSdk
  lake build Tests.ProofSpec
  lake build Tests
}

run_evm() {
  log "EVM lane"
  lake build Examples
  lake exe pf -- build --out build/evm
  python3 scripts/check_artifact_manifest.py --target evm --out build/evm
  log "Named user-project gate (pf init demo)"
  ./scripts/ci_pf_init_named_project.sh
  runtime-tests/evm/anvil.sh
}

if (( FAST )) || have_lane guards; then
  run_guards
fi
have_lane lean && run_lean
have_lane evm && run_evm

log "ci_local: OK (lanes: ${LANES[*]-none})"
