#!/usr/bin/env python3
"""Fail when build artifacts drift from target registry names, kinds, or digests."""

from __future__ import annotations

import argparse
import json
import re
import sys
import tempfile
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

ENTRY_RE = re.compile(
    r'\{\s*name\s*:=\s*"([^"]+)"\s*,\s*digest\s*:=\s*"([^"]+)"\s*\}'
)
HEX_RE = re.compile(r"^[0-9a-f]+$")
DIGEST_LINE = {
    "evm": re.compile(r"^//\s*digest=([0-9a-f]+)\s*$"),
}

SUFFIXES_BY_SPECIFICITY = (".abi.json", ".bin", ".yul")


@dataclass(frozen=True)
class TargetSpec:
    key: str
    registry_rel: Path
    expected_count: int
    suffixes: tuple[str, ...]
    digest_suffix: str


EVM = TargetSpec(
    key="evm",
    registry_rel=Path("ProofForge/Evm/Registry.lean"),
    expected_count=70,
    suffixes=(".bin", ".yul", ".abi.json"),
    digest_suffix=".yul",
)
SPECS = {"evm": EVM}


def artifact_suffix(filename: str) -> str | None:
    for suffix in SUFFIXES_BY_SPECIFICITY:
        if filename.endswith(suffix):
            return suffix
    return None


def parse_registry(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    entries: dict[str, str] = {}
    for name, digest in ENTRY_RE.findall(text):
        if name in entries:
            raise ValueError(f"duplicate registry name: {name}")
        if not HEX_RE.fullmatch(digest):
            raise ValueError(f"malformed registry digest: {name}")
        entries[name] = digest
    return entries


def load_entries(root: Path, spec: TargetSpec, *, pin_count: bool) -> tuple[dict[str, str], list[str]]:
    path = root / spec.registry_rel
    diags: list[str] = []
    if not path.is_file():
        return {}, [f"missing registry: {spec.registry_rel}"]
    try:
        entries = parse_registry(path)
    except (OSError, UnicodeDecodeError, ValueError) as exc:
        return {}, [f"malformed registry: {spec.registry_rel}: {exc}"]
    if pin_count and len(entries) != spec.expected_count:
        diags.append(
            f"registry count: {spec.key} expected={spec.expected_count} found={len(entries)}"
        )
    return entries, diags


def rel_to(path: Path, root: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def iter_artifacts(out_dir: Path) -> list[tuple[Path, str, str]]:
    found: list[tuple[Path, str, str]] = []
    for path in out_dir.rglob("*"):
        if not path.is_file():
            continue
        suffix = artifact_suffix(path.name)
        if suffix is None:
            continue
        found.append((path, path.name[: -len(suffix)], suffix))
    return found


def read_digest(path: Path, spec: TargetSpec) -> str | None:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None
    pattern = DIGEST_LINE[spec.key]
    for line in text.splitlines():
        match = pattern.match(line)
        if match:
            return match.group(1)
    return None


def check_json(path: Path, rel: str, diags: list[str]) -> None:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        diags.append(f"malformed file: {rel}: not text")
        return
    try:
        json.loads(text)
    except json.JSONDecodeError:
        diags.append(f"malformed file: {rel}: invalid json")


def check_bin_hex(path: Path, rel: str, diags: list[str]) -> None:
    try:
        text = path.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeDecodeError):
        diags.append(f"malformed file: {rel}: not text")
        return
    if text == "":
        diags.append(f"malformed file: {rel}: empty hex")
        return
    # Assembler emits raw even-length hex only. Reject int()-accepted forms like 0x / +/-.
    if not re.fullmatch(r"[0-9a-fA-F]+", text):
        diags.append(f"malformed file: {rel}: not hex")
        return
    if len(text) % 2 != 0:
        diags.append(f"malformed file: {rel}: odd-length hex")


def check_expected_file(path: Path, spec: TargetSpec, suffix: str, diags: list[str], out_dir: Path) -> None:
    rel = rel_to(path, out_dir)
    if path.stat().st_size == 0:
        diags.append(f"empty file: {rel}")
        return
    if suffix == spec.digest_suffix:
        digest = read_digest(path, spec)
        if digest is None:
            diags.append(f"malformed file: {rel}: missing digest")
    elif suffix == ".abi.json":
        check_json(path, rel, diags)
    elif suffix == ".bin":
        check_bin_hex(path, rel, diags)


def check_target(
    spec: TargetSpec,
    entries: dict[str, str],
    out_dir: Path,
) -> list[str]:
    diags: list[str] = []
    if not out_dir.is_dir():
        return [f"missing out dir: {out_dir}"]

    owned_stems: set[str] = set()
    for path, stem, suffix in iter_artifacts(out_dir):
        if suffix not in spec.suffixes:
            continue
        owned_stems.add(stem)

    for stem in sorted(owned_stems - set(entries)):
        diags.append(f"orphan stem: {spec.key} {stem}")

    for name in sorted(entries):
        for suffix in spec.suffixes:
            path = out_dir / f"{name}{suffix}"
            if not path.is_file():
                diags.append(f"missing artifact: {spec.key} {name}{suffix}")
                continue
            check_expected_file(path, spec, suffix, diags, out_dir)
        digest_path = out_dir / f"{name}{spec.digest_suffix}"
        if digest_path.is_file() and digest_path.stat().st_size > 0:
            found = read_digest(digest_path, spec)
            expected = entries[name]
            if found is not None and found != expected:
                diags.append(
                    f"digest mismatch: {spec.key} {name} registry={expected} artifact={found}"
                )

    return diags


def diagnostics(
    target: str,
    out_dir: Path,
    *,
    root: Path = ROOT,
    entries_by_target: dict[str, dict[str, str]] | None = None,
    pin_count: bool = True,
) -> list[str]:
    specs = [SPECS[target]]
    diags: list[str] = []
    loaded: list[tuple[TargetSpec, dict[str, str]]] = []
    for spec in specs:
        if entries_by_target is not None:
            entries = entries_by_target[spec.key]
            load_diags: list[str] = []
        else:
            entries, load_diags = load_entries(root, spec, pin_count=pin_count)
        diags.extend(load_diags)
        loaded.append((spec, entries))
        if not entries and entries_by_target is None and not load_diags:
            diags.append(f"empty registry: {spec.key}")
    for spec, entries in loaded:
        if entries or entries_by_target is not None:
            diags.extend(
                check_target(
                    spec,
                    entries,
                    out_dir,
                )
            )
    return sorted(set(diags))


def report(diags: list[str]) -> int:
    if diags:
        print("artifact manifest errors:", file=sys.stderr)
        for item in diags:
            print(f"  {item}", file=sys.stderr)
        return 1
    print("artifact manifest: ok")
    return 0


def _write_registry(path: Path, entries: list[tuple[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    body = ",\n".join(f'  {{ name := "{name}", digest := "{digest}" }}' for name, digest in entries)
    path.write_text(f"def entries : Array Entry := #[\n{body}\n]\n", encoding="utf-8")


def _write_evm(out: Path, name: str, digest: str, *, bin_hex: str = "deadbeef") -> None:
    out.mkdir(parents=True, exist_ok=True)
    (out / f"{name}.bin").write_text(f"{bin_hex}\n", encoding="utf-8")
    (out / f"{name}.yul").write_text(f"// digest={digest}\n", encoding="utf-8")
    (out / f"{name}.abi.json").write_text("[]\n", encoding="utf-8")


def _require(diags: list[str], needle: str, label: str) -> None:
    if not any(needle in item for item in diags):
        raise AssertionError(f"{label}: expected {needle!r} in {diags}")


def self_test() -> int:
    failures: list[str] = []
    ran = 0

    def case(name: str, fn: Callable[[], None]) -> None:
        nonlocal ran
        ran += 1
        try:
            fn()
        except AssertionError as exc:
            failures.append(f"{name}: {exc}")

    evm_entries = {"Tok": "def456"}
    injected = {"evm": evm_entries}

    def parse_real() -> None:
        evm = parse_registry(ROOT / EVM.registry_rel)
        if len(evm) != EVM.expected_count:
            raise AssertionError(f"evm count {len(evm)}")
        if evm["Counter"] != "254202356ee921d6":
            raise AssertionError("evm Counter digest")

    def happy() -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            _write_evm(out, "Tok", "def456")
            diags = diagnostics("evm", out, entries_by_target=injected, pin_count=False)
            if diags:
                raise AssertionError(diags)

    def digest_mismatch() -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            _write_evm(out, "Tok", "000111")
            diags = diagnostics("evm", out, entries_by_target=injected, pin_count=False)
            if not diags:
                raise AssertionError("expected failure")
            _require(diags, "digest mismatch: evm Tok", "digest_mismatch")

    def orphan() -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            _write_evm(out, "Tok", "def456")
            _write_evm(out, "Extra", "def456")
            diags = diagnostics("evm", out, entries_by_target=injected, pin_count=False)
            if not diags:
                raise AssertionError("expected failure")
            _require(diags, "orphan stem: evm Extra", "orphan")

    def empty_tree() -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            diags = diagnostics("evm", out, entries_by_target=injected, pin_count=False)
            if not diags:
                raise AssertionError("expected failure")
            _require(diags, "missing artifact: evm Tok.bin", "empty_tree")

    def odd_hex() -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            _write_evm(out, "Tok", "def456", bin_hex="deadbee")
            diags = diagnostics("evm", out, entries_by_target=injected, pin_count=False)
            if not diags:
                raise AssertionError("expected failure")
            _require(diags, "odd-length hex", "odd_hex")

    def prefixed_hex() -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            _write_evm(out, "Tok", "def456", bin_hex="0x6080")
            diags = diagnostics("evm", out, entries_by_target=injected, pin_count=False)
            if not diags:
                raise AssertionError("expected failure")
            _require(diags, "not hex", "prefixed_hex")

    def signed_hex() -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            _write_evm(out, "Tok", "def456", bin_hex="+6080")
            diags = diagnostics("evm", out, entries_by_target=injected, pin_count=False)
            if not diags:
                raise AssertionError("expected failure")
            _require(diags, "not hex", "signed_hex")

    def synthetic_registry() -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write_registry(root / EVM.registry_rel, [("Tok", "def456")])
            out = root / "out"
            _write_evm(out, "Tok", "def456")
            loaded, load_diags = load_entries(root, EVM, pin_count=False)
            if load_diags or loaded != {"Tok": "def456"}:
                raise AssertionError((loaded, load_diags))
            diags = diagnostics("evm", out, root=root, pin_count=False)
            if diags:
                raise AssertionError(diags)

    case("parse_real", parse_real)
    case("happy", happy)
    case("digest_mismatch", digest_mismatch)
    case("orphan", orphan)
    case("empty_tree", empty_tree)
    case("odd_hex", odd_hex)
    case("prefixed_hex", prefixed_hex)
    case("signed_hex", signed_hex)
    case("synthetic_registry", synthetic_registry)

    if failures:
        print("artifact manifest self-test failures:", file=sys.stderr)
        for item in failures:
            print(f"  {item}", file=sys.stderr)
        return 1
    print(f"artifact manifest self-test: {ran} passed")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--target", choices=("evm",), default=None)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    if args.self_test:
        if args.target is not None or args.out is not None:
            print("usage: check_artifact_manifest.py --self-test", file=sys.stderr)
            return 2
        return self_test()
    if args.out is None:
        print(
            "usage: check_artifact_manifest.py --target evm --out DIR",
            file=sys.stderr,
        )
        return 2
    target = args.target if args.target is not None else "evm"
    return report(diagnostics(target, args.out))


if __name__ == "__main__":
    raise SystemExit(main())
