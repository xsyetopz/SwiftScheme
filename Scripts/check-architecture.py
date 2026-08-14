#!/usr/bin/env python3
"""Blocking SwiftScheme topology and authored-path preflight.

The check deliberately has no repository-wide ignore list or advisory mode.
Its scope is the authored package surface: ``Package.swift``, ``Sources``,
``Tests/SwiftSchemeTests``, and ``Tests/Fixtures``.  Historical and vendored
conformance material under ``Architecture`` and ``Tests/Conformance`` is not a
runtime dependency and is therefore outside this gate.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
AUTHORED_ROOTS = (
    ROOT / "Package.swift",
    ROOT / "Sources",
    ROOT / "Tests" / "SwiftSchemeTests",
    ROOT / "Tests" / "Fixtures",
)
EXPECTED_PRODUCTS = {
    "SwiftScheme": ("library", ("SwiftScheme",)),
    "swiftscheme": ("executable", ("SwiftSchemeCLI",)),
}
EXPECTED_TARGETS = {
    "SwiftScheme": ("regular", "Sources/swiftscheme", ()),
    "SwiftSchemeCLI": ("executable", "Sources/SwiftSchemeCLI", ("SwiftScheme",)),
    "SwiftSchemeTests": (
        "test",
        "Tests/SwiftSchemeTests",
        ("SwiftScheme",),
    ),
}
FORBIDDEN_TEXT = (
    re.compile(r"\bXCTest\b", re.IGNORECASE),
    re.compile(r"\bXCT[A-Za-z0-9_]*\b"),
    re.compile(r"SwiftScheme(?:TestPlugin|TestTool|PackageTestTarget|SelfTests)"),
    re.compile(r"(?:^|[\\/])Plugins(?:[\\/]|$)"),
    re.compile(r"(?:^|[\\/])Sources[\\/]XCTest(?:[\\/]|$)"),
)
# Swift permits declaration attributes before imports and an import-kind before
# a module member (for example ``@preconcurrency import SwiftUI`` or
# ``import struct SwiftUI.Text``). Keep the match anchored to a declaration
# line and require the complete module root so identifiers such as
# ``SwiftUICompatibility`` are not false positives.
NATIVE_UI_IMPORT = re.compile(
    r"^[ \t]*(?:(?:@[A-Za-z_][A-Za-z0-9_]*"
    r"(?:[ \t]*\([^()\n]*\))?)[ \t]*(?:\n[ \t]*)?)*"
    r"import[ \t]+"
    r"(?:(?:class|enum|func|let|protocol|struct|typealias|var)[ \t]+)?"
    r"(?P<module>SwiftUI|UIKit|AppKit|WatchKit|TVMLKit|RealityKit|SceneKit|SpriteKit)"
    r"(?=\.|\b)",
    re.MULTILINE,
)
NATIVE_UI_MANIFEST = re.compile(
    r"\b(?:SwiftUI|UIKit|AppKit|WatchKit|TVMLKit|RealityKit|SceneKit|SpriteKit)\b"
)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Run the blocking SwiftScheme authored-path, Swift 6.3.3, "
            "Swift Testing, package-graph, and no-native-UI preflight."
        ),
        epilog=(
            "The repository root is derived from this script; there is no "
            "ignore, advisory, or allow-failure mode."
        ),
    )
    return parser


def _run_version() -> tuple[int, str]:
    try:
        result = subprocess.run(
            ["swift", "--version"],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as error:
        return 127, f"unable to execute swift --version: {error}"
    output = (result.stdout + result.stderr).strip()
    return result.returncode, output


def _read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(encoding="utf-8", errors="replace")


def _authored_files() -> list[Path]:
    files: list[Path] = []
    for root in AUTHORED_ROOTS:
        if root.is_file():
            files.append(root)
            continue
        if not root.is_dir():
            continue
        files.extend(path for path in root.rglob("*") if path.is_file())
    return sorted(set(files))


def _dependency_names(raw: list[dict[str, Any]]) -> tuple[str, ...] | None:
    names: list[str] = []
    for dependency in raw:
        by_name = dependency.get("byName")
        if isinstance(by_name, list) and by_name and isinstance(by_name[0], str):
            names.append(by_name[0])
            continue
        product = dependency.get("product")
        if isinstance(product, list) and product and isinstance(product[0], str):
            names.append(product[0])
            continue
        return None
    return tuple(names)


def _dump_package() -> tuple[int, dict[str, Any] | None, str]:
    try:
        result = subprocess.run(
            ["swift", "package", "dump-package"],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as error:
        return 127, None, f"unable to execute swift package dump-package: {error}"
    if result.returncode != 0:
        diagnostics = (result.stdout + result.stderr).strip()
        return result.returncode, None, diagnostics
    try:
        return 0, json.loads(result.stdout), ""
    except json.JSONDecodeError as error:
        return 1, None, f"dump-package returned invalid JSON: {error}"


def _check_toolchain(errors: list[str]) -> None:
    version_file = ROOT / ".swift-version"
    if not version_file.is_file():
        errors.append("missing .swift-version (required exact provider: 6.3.3)")
    else:
        lines = [line.strip() for line in _read(version_file).splitlines() if line.strip()]
        if lines != ["6.3.3"]:
            errors.append(
                f".swift-version must contain exactly 6.3.3 (found {lines!r})"
            )

    returncode, output = _run_version()
    if returncode != 0:
        errors.append(f"swift --version failed with exit {returncode}: {output}")
    elif not re.search(r"(?:Apple )?Swift version 6\.3\.3\b", output):
        errors.append(
            "swift --version did not report exact Swift 6.3.3 "
            f"(output: {output!r})"
        )


def _check_authored_text(errors: list[str]) -> None:
    for path in _authored_files():
        relative = path.relative_to(ROOT).as_posix()
        text = _read(path)
        for pattern in FORBIDDEN_TEXT:
            match = pattern.search(text)
            if match:
                line = text.count("\n", 0, match.start()) + 1
                errors.append(
                    f"forbidden XCTest/plugin/tool reference in {relative}:{line} "
                    f"({match.group(0)!r})"
                )
                break

        if path.suffix == ".swift":
            match = NATIVE_UI_IMPORT.search(text)
            if match:
                line = text.count("\n", 0, match.start()) + 1
                errors.append(
                    f"native UI import is outside the current no-UI boundary in "
                    f"{relative}:{line} ({match.group(0).strip()!r})"
                )


def _check_package_graph(errors: list[str]) -> None:
    returncode, package, diagnostics = _dump_package()
    if returncode != 0 or package is None:
        errors.append(
            "swift package dump-package failed with exit "
            f"{returncode}: {diagnostics}"
        )
        return

    products = package.get("products")
    if not isinstance(products, list):
        errors.append("dump-package has no products array")
    else:
        actual_products: dict[str, tuple[str, tuple[str, ...]]] = {}
        for product in products:
            if not isinstance(product, dict):
                errors.append(f"invalid product entry: {product!r}")
                continue
            name = product.get("name")
            product_type = product.get("type")
            targets = product.get("targets")
            if not isinstance(name, str) or not isinstance(product_type, dict):
                errors.append(f"invalid product metadata: {product!r}")
                continue
            type_names = tuple(str(key) for key in product_type)
            if len(type_names) != 1 or not isinstance(targets, list):
                errors.append(f"invalid product shape for {name!r}: {product!r}")
                continue
            actual_products[name] = (type_names[0], tuple(str(target) for target in targets))
        if actual_products != EXPECTED_PRODUCTS:
            errors.append(
                "package products must be exactly library SwiftScheme and "
                f"executable swiftscheme (found {actual_products!r})"
            )

    targets = package.get("targets")
    if not isinstance(targets, list):
        errors.append("dump-package has no targets array")
        return

    actual_targets: dict[str, tuple[str, str, tuple[str, ...]]] = {}
    for target in targets:
        if not isinstance(target, dict):
            errors.append(f"invalid target entry: {target!r}")
            continue
        name = target.get("name")
        target_type = target.get("type")
        path = target.get("path")
        dependencies = target.get("dependencies")
        if not all(isinstance(value, str) for value in (name, target_type, path)):
            errors.append(f"invalid target metadata: {target!r}")
            continue
        if not isinstance(dependencies, list):
            errors.append(f"invalid dependency list for target {name!r}")
            continue
        names = _dependency_names(dependencies)
        if names is None:
            errors.append(f"unsupported dependency shape for target {name!r}")
            continue
        actual_targets[name] = (target_type, path, names)

    if actual_targets != EXPECTED_TARGETS:
        errors.append(
            "package targets must be exactly SwiftScheme (library), "
            "SwiftSchemeCLI -> SwiftScheme (executable), and "
            f"SwiftSchemeTests -> SwiftScheme (test); found {actual_targets!r}"
        )

    manifest = ROOT / "Package.swift"
    if manifest.is_file() and NATIVE_UI_MANIFEST.search(_read(manifest)):
        errors.append("Package.swift references a native UI framework outside the current boundary")


def main(argv: list[str] | None = None) -> int:
    _parser().parse_args(argv)
    errors: list[str] = []
    _check_toolchain(errors)
    _check_authored_text(errors)
    _check_package_graph(errors)

    if errors:
        print("[architecture] FAILED: blocking preflight diagnostics", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print("[architecture] PASS: Swift 6.3.3, Swift Testing-only authored paths, "
          "exact package graph, and no native UI boundary")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
