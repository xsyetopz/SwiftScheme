#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources"
TESTS = ROOT / "Tests"
MAX_LINES = 500

LAYERS = {
    "Numeric": set(),
    "Runtime": {"Numeric"},
    "Frontend": {"Runtime", "Numeric"},
    "Primitives": {"Runtime", "Numeric"},
    "Evaluator": {"Runtime", "Frontend", "Primitives", "Numeric"},
    "API": {"Evaluator", "Runtime", "Numeric"},
    "CLI": {"API"},
    "Tests": {"API"},
}


TARGET_LAYERS = {
    "SwiftSchemeNumeric": "Numeric",
    "SwiftSchemeRuntime": "Runtime",
    "SwiftSchemeFrontend": "Frontend",
    "SwiftSchemePrimitives": "Primitives",
    "SwiftSchemeEvaluator": "Evaluator",
    "SwiftScheme": "API",
    "SwiftSchemeCLI": "CLI",
    "SwiftSchemeTests": "Tests",
}


def package_graph() -> dict[str, set[str]]:
    result = subprocess.run(
        ["swift", "package", "dump-package"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "swift package dump-package failed")
    manifest = json.loads(result.stdout)
    graph = {}
    for target in manifest["targets"]:
        dependencies = set()
        for dependency in target["dependencies"]:
            if "byName" in dependency:
                dependencies.add(dependency["byName"][0])
            elif "target" in dependency:
                dependencies.add(dependency["target"][0])
        graph[target["name"]] = dependencies
    return graph


def actual_graph_failures() -> list[str]:
    try:
        graph = package_graph()
    except (OSError, RuntimeError, json.JSONDecodeError) as error:
        return [f"unable to inspect SwiftPM target graph: {error}"]
    failures = []
    failures.extend(
        f"unmapped SwiftPM target: {target}"
        for target in graph
        if target not in TARGET_LAYERS
    )
    visiting = set()
    visited = set()

    def visit(target: str) -> None:
        if target in visiting:
            failures.append("SwiftPM target dependency graph contains a cycle")
            return
        if target in visited:
            return
        visiting.add(target)
        for dependency in graph.get(target, ()):
            visit(dependency)
        visiting.remove(target)
        visited.add(target)

    for target in graph:
        visit(target)
    for target, layer in TARGET_LAYERS.items():
        dependencies = graph.get(target, set())
        actual = {TARGET_LAYERS[name] for name in dependencies if name in TARGET_LAYERS}
        if any(name not in TARGET_LAYERS for name in dependencies) or actual != LAYERS[layer]:
            failures.append(
                f"{target}: expected {sorted(LAYERS[layer])}, got {sorted(actual)}"
            )
    return failures


def has_cycle() -> bool:
    visiting = set()
    visited = set()

    def visit(layer: str) -> bool:
        if layer in visiting:
            return True
        if layer in visited:
            return False
        visiting.add(layer)
        if any(visit(dependency) for dependency in LAYERS[layer]):
            return True
        visiting.remove(layer)
        visited.add(layer)
        return False

    return any(visit(layer) for layer in LAYERS)


files = sorted([*SOURCE.rglob("*.swift"), *TESTS.rglob("*.swift")])
failures = []
for path in files:
    source = path.read_text(encoding="utf-8")
    lines = len(source.splitlines())
    if lines > MAX_LINES:
        failures.append(f"{path.relative_to(ROOT)}: {lines} lines")
    for line in source.splitlines():
        if line.startswith("extension "):
            owner = (
                line.removeprefix("extension ")
                .split(":", 1)[0]
                .split("<", 1)[0]
                .replace("{", "")
                .strip()
            )
            if "+" not in path.stem or not path.stem.startswith(f"{owner}+"):
                failures.append(
                    f"{path.relative_to(ROOT)}: extension file must start with {owner}+"
                )
if (SOURCE / "SwiftScheme" / "SwiftScheme.swift").exists():
    failures.append("Sources/SwiftScheme/SwiftScheme.swift: monolith is not allowed")
if has_cycle():
    failures.append("capability dependency graph contains a cycle")
failures.extend(actual_graph_failures())
for path in SOURCE.joinpath("SwiftScheme").rglob("*.swift"):
    relative = path.relative_to(SOURCE / "SwiftScheme")
    if relative.parts and relative.parts[0] not in LAYERS:
        failures.append(f"{path.relative_to(ROOT)}: unowned capability directory")
if failures:
    print("architecture check failed")
    print("\n".join(failures))
    sys.exit(1)
print(f"architecture check passed: {len(files)} Swift files, max {MAX_LINES} lines, acyclic layers and SwiftPM targets")
