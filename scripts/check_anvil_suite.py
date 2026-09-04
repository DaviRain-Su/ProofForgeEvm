#!/usr/bin/env python3
"""Fail when an Anvil gate script exists but its suite runner never runs it.

`runtime-tests/evm/anvil.sh` is the CI entry point for the solc gates and
`runtime-tests/evm/yulc.sh` for the yulc gates. A gate that is committed but
missing from its runner is silently skipped in CI.

Usage:
    python3 scripts/check_anvil_suite.py
    python3 scripts/check_anvil_suite.py --self-test
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[1]
EVM = ROOT / "runtime-tests" / "evm"


@dataclass(frozen=True)
class Suite:
    runner: str
    owns_gate: Callable[[str], bool]
    listed_cases: Callable[[str], set[str]]


def anvil_loop_cases(text: str) -> set[str]:
    match = re.search(r"for case in(.*?);\s*do", text, re.DOTALL)
    if match is None:
        return set()
    return set(re.findall(r"[a-z0-9_]+", match.group(1).replace("\\", " ")))


def yulc_gate_cases(text: str) -> set[str]:
    return {f"yulc_{name}" for name in re.findall(r"anvil_yulc_([a-z0-9_]+)\.sh", text)}


SUITES = (
    Suite("anvil.sh", lambda case: not case.startswith("yulc_"), anvil_loop_cases),
    Suite("yulc.sh", lambda case: case.startswith("yulc_"), yulc_gate_cases),
)


def gate_cases(evm_dir: Path) -> set[str]:
    return {path.name[len("anvil_") : -len(".sh")] for path in evm_dir.glob("anvil_*.sh")}


def diagnostics(evm_dir: Path) -> list[str]:
    diags: list[str] = []
    committed = gate_cases(evm_dir)
    for suite in SUITES:
        runner = evm_dir / suite.runner
        if not runner.is_file():
            diags.append(f"{suite.runner}: missing runner")
            continue
        listed = suite.listed_cases(runner.read_text(encoding="utf-8"))
        owned = {case for case in committed if suite.owns_gate(case)}
        for case in sorted(owned - listed):
            diags.append(f"{suite.runner}: anvil_{case}.sh exists but is not run")
        for case in sorted(listed - owned):
            diags.append(f"{suite.runner}: runs anvil_{case}.sh which does not exist")
    return diags


def report(diags: list[str], label: str) -> int:
    if diags:
        for diag in diags:
            print(f"check_anvil_suite: {diag}", file=sys.stderr)
        print(f"check_anvil_suite: FAIL ({len(diags)} issue(s))", file=sys.stderr)
        return 1
    print(f"check_anvil_suite: ok ({label})")
    return 0


def self_test(tmp: Path) -> int:
    evm = tmp / "evm"
    evm.mkdir()
    for case in ("counter", "pair", "yulc_counter"):
        (evm / f"anvil_{case}.sh").write_text("#!/usr/bin/env bash\n", encoding="utf-8")
    (evm / "yulc.sh").write_text('run_gate anvil-counter "$here/anvil_yulc_counter.sh"\n', encoding="utf-8")

    (evm / "anvil.sh").write_text("for case in counter \\\n    pair; do\n  :\ndone\n", encoding="utf-8")
    complete = diagnostics(evm)

    (evm / "anvil.sh").write_text("for case in counter; do\n  :\ndone\n", encoding="utf-8")
    dropped = diagnostics(evm)

    (evm / "anvil.sh").write_text("for case in counter pair ghost; do\n  :\ndone\n", encoding="utf-8")
    ghost = diagnostics(evm)

    (evm / "yulc.sh").write_text("", encoding="utf-8")
    yulc_dropped = diagnostics(evm)

    failures = [
        label
        for label, ok in (
            ("complete runner passes", complete == []),
            ("dropped case is reported", dropped == ["anvil.sh: anvil_pair.sh exists but is not run"]),
            ("ghost case is reported", ghost == ["anvil.sh: runs anvil_ghost.sh which does not exist"]),
            ("yulc gate drop is reported", "yulc.sh: anvil_yulc_counter.sh exists but is not run" in yulc_dropped),
        )
        if not ok
    ]
    return report(failures, "self-test, 4 cases")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="run built-in fixture checks")
    args = parser.parse_args()
    if args.self_test:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            return self_test(Path(tmp))
    return report(diagnostics(EVM), f"{len(gate_cases(EVM))} gates across {len(SUITES)} runners")


if __name__ == "__main__":
    raise SystemExit(main())
