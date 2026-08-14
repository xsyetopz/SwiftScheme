# ADR-0001: SwiftScheme runtime topology

- Status: accepted
- Scope: `SwiftScheme` library, CLI, tests
- Normative language source: `Reference/r5rs.pdf`
- Runtime contract: Swift 6.3+, SwiftPM, no third-party dependencies

## Decision

Keep one public façade target over acyclic SwiftPM implementation targets:

| Owner | Responsibility |
|---|---|
| `Numeric/` | pure exact/inexact number values |
| `Runtime/` | object graph, heap, control frames, writer, equality, macro contract |
| `Frontend/` | reader, numeric grammar, syntax-rules matching/templates |
| `Primitives/` | runtime coercions, data/port/numeric primitive helpers |
| `Evaluator/` | interpreter, derived forms, primitive installation, trampoline |
| `API/` | public façade and source-compatible type aliases |
| `Tests/SwiftSchemeTests/<capability>/` | capability-mapped Swift Testing evidence |
| `SwiftSchemeCLI/main.swift` | process, files, terminal streams only |

### Allowed dependency edges

| Layer | May depend on |
|---|---|
| `Numeric` | none |
| `Runtime` | `Numeric` |
| `Frontend` | `Runtime`, `Numeric` |
| `Primitives` | `Runtime`, `Numeric` |
| `Evaluator` | `Runtime`, `Frontend`, `Primitives`, `Numeric` |
| `API` | `Evaluator`, `Runtime`, `Numeric` |
| `CLI` | `API` |
| `Tests` | `API` |


Dependencies point from numeric/runtime data to syntax/control; the CLI depends
on the library. Public names and signatures remain unchanged. Tail evaluation,
heap tracing, object identity, diagnostics, and deterministic evaluation order
are preserved.

Each capability may use same-type extensions, but no source file exceeds 500
formatted lines. Extensions preserve static dispatch and avoid hot-loop
indirection; the trampoline remains the evaluator's control authority.

## Alternatives

| Option | Result |
| --- | --- |
| Keep the monolith | rejected: mixed ownership and high review surface |
| Capability files in one target | rejected: source-level cycles remain hidden and boundaries are unenforced |
| Multiple SwiftPM targets | selected: package-private contracts preserve encapsulation while SwiftPM enforces the DAG |

## Evidence

- `DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer swift build`
- same environment: `swift test` — 72 tests, 8 suites
- same environment: `swift run swiftscheme Tests/Fixtures/smoke.scm` — `sum=30`
- `npx jscpd --reporters ai --min-lines 10 Sources` — 0 clones
- `python3 Scripts/check-architecture.py` — 38 Swift files, maximum 500 lines, acyclic source and SwiftPM target graphs
- `swift package dump-package` — Numeric → Runtime → Frontend/Primitives → Evaluator → API → CLI/Tests

The façade remains the only public library product; package-scoped contracts are
not exported to clients. Rollback is a target/file move with the façade aliases
unchanged.
