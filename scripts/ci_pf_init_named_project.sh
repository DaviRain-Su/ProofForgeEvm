#!/usr/bin/env bash
# Named user-project build gate (not a mysterious "smoke").
#
# From a ProofForge EVM checkout, with `pf` on PATH after `lake build pf`:
#   pf init demo
#   cd demo
#   lake build
#   lake env pf build
#
# Asserts the template Counter artifacts exist. Removes ./demo on exit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v pf >/dev/null 2>&1; then
  if [[ -x "$ROOT/.lake/build/bin/pf" ]]; then
    export PATH="$ROOT/.lake/build/bin:$PATH"
  fi
fi
command -v pf >/dev/null || {
  echo "ci_pf_init_named_project: pf not on PATH (run lake build pf)" >&2
  exit 1
}
test -d templates/evm-counter || {
  echo "ci_pf_init_named_project: templates/evm-counter missing (run from the ProofForge EVM checkout)" >&2
  exit 1
}

# Literal project-name argument — same command a user types after cloning.
PROJECT_NAME=demo
if [[ -e "$PROJECT_NAME" ]]; then
  echo "ci_pf_init_named_project: refusing to overwrite existing ./$PROJECT_NAME" >&2
  exit 1
fi

cleanup() { rm -rf "$ROOT/$PROJECT_NAME"; }
trap cleanup EXIT

echo "ci_pf_init_named_project: pf init $PROJECT_NAME"
pf init demo

test -f demo/pf.toml
test -f demo/lakefile.lean
if grep -E 'from "\.\." / "\.\."|from "\.\./\.\."' demo/lakefile.lean; then
  echo "pf init left the template path-require unrewritten" >&2
  exit 1
fi
if grep -F 'github.com/DaviRain-Su/ProofForgeEvm.git' demo/lakefile.lean ||
   grep -F '@ "v0.1.0"' demo/lakefile.lean; then
  echo "pf init left the published git-tag require unrewritten" >&2
  exit 1
fi
grep -q 'require «proofforge» from' demo/lakefile.lean

cd demo
lake build
lake env pf build --out build/out
test -s build/out/Counter.bin
test -s build/out/Counter.yul
test -s build/out/Counter.abi.json
echo "pf init demo ok: $(wc -c < build/out/Counter.bin) byte Counter.bin"
