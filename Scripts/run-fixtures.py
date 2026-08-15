#!/usr/bin/env python3
"""Run the checked-in Scheme fixtures and compare complete stdout.

The fixture manifest pins the exact source and expected-output bytes. This
runner intentionally covers only the small, tracked fixtures under
Tests/Fixtures. It does not execute vendored Chibi, Larceny, or Racket trees:
those are audit context until their source, revision, adapter, and license are
reviewed separately.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests" / "Fixtures"
MANIFEST = FIXTURES / "manifest.json"
_MANIFEST_SCHEMA = 1
_SHA256 = re.compile(r"^[0-9a-f]{64}$")


@dataclass(frozen=True)
class Fixture:
    name: str
    expected: str
    source_sha256: str
    expected_sha256: str
    source_bytes: int
    expected_bytes: int

    @property
    def source_path(self) -> Path:
        return FIXTURES / self.name

    @property
    def expected_path(self) -> Path:
        return FIXTURES / self.expected


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fixture_file(name: object, suffix: str, label: str) -> str:
    if not isinstance(name, str):
        raise TypeError(f"manifest {label} must be a filename")
    path = Path(name)
    if path.is_absolute() or path.parent != Path(".") or path.suffix != suffix:
        raise ValueError(f"manifest {label} must be a {suffix} filename: {name!r}")
    return name


def manifest_fixture(entry: object, index: int) -> Fixture:
    if not isinstance(entry, dict):
        raise TypeError(f"manifest fixture {index} must be an object")
    try:
        name = fixture_file(entry["name"], ".scm", "source")
        expected = fixture_file(entry["expected"], ".out", "expected output")
        source_sha256 = entry["source_sha256"]
        expected_sha256 = entry["expected_sha256"]
        source_bytes = entry["source_bytes"]
        expected_bytes = entry["expected_bytes"]
    except KeyError as error:
        raise ValueError(
            f"manifest fixture {index} is missing {error.args[0]!r}"
        ) from error
    if not isinstance(source_sha256, str) or not _SHA256.fullmatch(source_sha256):
        raise ValueError(f"manifest fixture {name!r} has invalid source_sha256")
    if not isinstance(expected_sha256, str) or not _SHA256.fullmatch(expected_sha256):
        raise ValueError(f"manifest fixture {name!r} has invalid expected_sha256")
    if not isinstance(source_bytes, int) or source_bytes < 0:
        raise ValueError(f"manifest fixture {name!r} has invalid source_bytes")
    if not isinstance(expected_bytes, int) or expected_bytes < 0:
        raise ValueError(f"manifest fixture {name!r} has invalid expected_bytes")
    return Fixture(
        name, expected, source_sha256, expected_sha256, source_bytes, expected_bytes
    )


def load_manifest(path: Path) -> dict[str, Fixture]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"unable to read fixture manifest {path}: {error}") from error
    if not isinstance(payload, dict) or payload.get("schema") != _MANIFEST_SCHEMA:
        raise ValueError(f"fixture manifest must declare schema {_MANIFEST_SCHEMA}")
    entries = payload.get("fixtures")
    if not isinstance(entries, list) or not entries:
        raise ValueError("fixture manifest must contain a non-empty fixtures array")
    fixtures = [manifest_fixture(entry, index) for index, entry in enumerate(entries)]
    names = [fixture.name for fixture in fixtures]
    if names != sorted(names) or len(set(names)) != len(names):
        raise ValueError("fixture manifest names must be unique and sorted")
    available = sorted(path.name for path in FIXTURES.glob("*.scm"))
    if names != available:
        missing = sorted(set(available) - set(names))
        extra = sorted(set(names) - set(available))
        details = []
        if missing:
            details.append("unlisted source(s): " + ", ".join(missing))
        if extra:
            details.append("missing source(s): " + ", ".join(extra))
        raise ValueError(
            "fixture manifest does not match tracked sources ("
            + "; ".join(details)
            + ")"
        )
    for fixture in fixtures:
        source = fixture.source_path
        expected = fixture.expected_path
        if not source.is_file():
            raise ValueError(f"manifest source is missing: {source}")
        if not expected.is_file():
            raise ValueError(f"manifest expected output is missing: {expected}")
        source_data = source.read_bytes()
        expected_data = expected.read_bytes()
        if (
            len(source_data) != fixture.source_bytes
            or sha256(source_data) != fixture.source_sha256
        ):
            raise ValueError(
                f"manifest source checksum/length mismatch: {fixture.name}"
            )
        if (
            len(expected_data) != fixture.expected_bytes
            or sha256(expected_data) != fixture.expected_sha256
        ):
            raise ValueError(
                f"manifest expected-output checksum/length mismatch: {fixture.expected}"
            )
    return {fixture.name: fixture for fixture in fixtures}


def executable_from_swift(swift: str, configuration: str) -> Path:
    build = [swift, "build"]
    if configuration != "debug":
        build.extend(["--configuration", configuration])
    result = subprocess.run(
        build, cwd=ROOT, capture_output=True, text=True, check=False
    )
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip() or "swift build failed"
        raise RuntimeError(detail)

    show_bin = [swift, "build", "--show-bin-path"]
    if configuration != "debug":
        show_bin.extend(["--configuration", configuration])
    result = subprocess.run(
        show_bin, cwd=ROOT, capture_output=True, text=True, check=False
    )
    if result.returncode:
        detail = result.stderr.strip() or "unable to locate SwiftPM products"
        raise RuntimeError(detail)
    return Path(result.stdout.strip()) / "swiftscheme"


def fixture_names(requested: list[str], fixtures: dict[str, Fixture]) -> list[str]:
    available = sorted(fixtures)
    if not requested:
        return available
    unknown = sorted(set(requested) - set(available))
    if unknown:
        raise ValueError("unknown fixture(s): " + ", ".join(unknown))
    return requested


def run_fixture(executable: Path, fixture: Fixture) -> tuple[bool, str]:
    source = fixture.source_path
    expected = fixture.expected_path.read_bytes()
    result = subprocess.run(
        [str(executable), str(source)],
        cwd=ROOT,
        capture_output=True,
        text=False,
        check=False,
    )
    stderr = result.stderr.decode("utf-8", errors="replace")
    if result.returncode:
        detail = stderr.strip() or f"exit status {result.returncode}"
        return False, f"{fixture.name}: interpreter failed: {detail}"
    if result.stderr:
        return False, f"{fixture.name}: unexpected stderr: {stderr!r}"
    if result.stdout != expected:
        return False, (
            f"{fixture.name}: stdout differs (expected {len(expected)} bytes, "
            f"got {len(result.stdout)} bytes)"
        )
    return True, f"{fixture.name}: passed ({len(expected)} bytes)"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--executable",
        type=Path,
        help="already-built swiftscheme executable (otherwise build with SwiftPM)",
    )
    parser.add_argument(
        "--configuration",
        choices=("debug", "release"),
        default="debug",
        help="SwiftPM build configuration when --executable is omitted",
    )
    parser.add_argument(
        "--swift-bin",
        default=os.environ.get("SWIFT_BIN", "swift"),
        help="Swift executable used for the fallback build",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=MANIFEST,
        help="fixture manifest (default: Tests/Fixtures/manifest.json)",
    )
    parser.add_argument(
        "fixture", nargs="*", help="fixture filename(s), or all by default"
    )
    arguments = parser.parse_args()

    try:
        manifest = arguments.manifest.expanduser()
        if not manifest.is_absolute():
            manifest = ROOT / manifest
        fixtures = load_manifest(manifest)
        names = fixture_names(arguments.fixture, fixtures)
        if arguments.executable is not None:
            executable = arguments.executable.expanduser()
            if not executable.is_absolute():
                executable = Path.cwd() / executable
        else:
            executable = executable_from_swift(
                arguments.swift_bin, arguments.configuration
            )
        if not executable.is_file():
            raise RuntimeError(f"swiftscheme executable not found: {executable}")
        if not os.access(executable, os.X_OK):
            raise RuntimeError(
                f"swiftscheme executable is not executable: {executable}"
            )
    except (OSError, RuntimeError, ValueError) as error:
        print(f"fixture runner failed: {error}", file=sys.stderr)
        return 1

    print(f"fixture manifest validated: {len(fixtures)} tracked fixture(s)")
    failures = []
    for name in names:
        passed, message = run_fixture(executable, fixtures[name])
        print(message)
        if not passed:
            failures.append(message)
    if failures:
        print(f"fixture runner failed: {len(failures)} fixture(s)", file=sys.stderr)
        return 1
    print(f"fixture runner passed: {len(names)} tracked fixture(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
