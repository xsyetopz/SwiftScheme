# SwiftScheme R5RS coverage checklist

**Audit date:** 2026-08-14
**Normative source:** [`Reference/r5rs.pdf`](../../Reference/r5rs.pdf), SHA-256
`09b71fe4373610d763e86a728ec80146e391a1cd9c00341364200ce3b2e2bc97`
**Implementation scope:** Swift 6.3.3, Swift Package Manager, macOS 14+, no third-party
packages.
**Claim:** This is an evidence-backed footprint of a **R5RS-guided core**, not a
claim of R5RS completeness.

## Status key and method

- `[x] Supported` - source path and focused behavioral evidence cover the surface.
- `[~] Partial` - the headline surface exists, but a specified edge, domain, error,
  portability, or test matrix is incomplete.
- `[ ] Missing/contradicted` - a required contract is absent or the repository
  constraint is violated.
- `[N/A]` - outside the current language/UI scope; never used to hide a language gap.

The audit maps the printed page and section in the local PDF to source symbols and
named Swift Testing evidence. R5RS-required and R5RS-library procedures are listed
separately from optional procedures and local extensions. Unspecified or
implementation-dependent behavior is not treated as a passing assertion.

## Footprint matrix

| Check | R5RS surface | Current status | Footprint in this workspace | Evidence / remaining work |
|---|---|---|---|---|
| `[~]` | Lexical conventions, datum reader, and external representations (2.1-2.3, pp. 5-8; 7.1.2) | Partial | `Reader` and `Writer` in `Sources/swiftscheme/SwiftScheme.swift`; comments, case-folded identifiers, booleans, strings, characters, lists, dotted lists, vectors, quote/quasiquote abbreviations, and radix/exactness number forms are present. | Swift Testing reader tests cover representative forms. A complete malformed-token/grammar matrix and all external-representation round trips remain open. |
| `[x]` | Core expressions: variable reference, literal, call, `quote`, `lambda`, `if`, `set!`, `begin` (4.1, pp. 8-10) | Supported | `Interpreter.run`, `SchemeEnvironment`, `Procedure`, `parseFormals`. | Closure mutation, variadic formals, branch laziness, sequencing, unbound `set!`, and duplicate-formal tests. |
| `[x]` | Derived expressions: `cond`, `case`, `and`, `or`, `let`, `let*`, `letrec`, named `let`, `do`, `delay`, `quasiquote` (4.2, pp. 10-13) | Supported | `expandCond`, `expandCase`, `expandAnd`, `expandOr`, `expandLet`, `expandLetStar`, `expandDo`, `expandQuasiquote`; `Promise` and `force`. | Named-let iteration, short-circuiting, arrow `cond`, `do`, quasiquote/splicing, and delay memoization are exercised. Add malformed and unspecified-result cases. |
| `[~]` | Programs, top-level definitions, internal definitions (5.1-5.2, pp. 16-17) | Partial | Top-level `evaluate` loop and `define`/procedure shorthand in `Interpreter.run`. | Definitions work in existing fixtures; legal internal-definition grouping/order and rejection of definitions after expressions are not independently proven. |
| `[x]` | Hygienic macros: `syntax-rules`, `define-syntax`, `let-syntax`, `letrec-syntax` (4.3, 5.3, pp. 13-17; 7.1.5) | Supported | `SyntaxRules`, macro environments, and evaluator macro dispatch. | Hygiene, definition-site references, literals, nested/empty ellipses, and local macro tests exist. Expand dotted-pattern/custom-ellipsis diagnostics. |
| `[x]` | Proper tail recursion and first-class continuations (3.5, p. 7; 6.4, pp. 31-35) | Supported | Iterative `Control`/`Continuation` machine; `call/cc`, `dynamic-wind`, and continuation wind transitions. | 100,000-step tail loop, multi-shot continuation, and `dynamic-wind` re-entry tests pass in the isolated baseline; rerun under Swift Testing. |
| `[x]` | Booleans, pairs/lists, symbols, and equivalence predicates (6.1, 6.3.1-6.3.3, pp. 17-19, 25-29) | Supported | `Value`, `Pair`, list helpers, symbol folding, `eq?`, `eqv?`, and cycle-aware `equal?`. | Mutation, improper lists, selectors, membership/association, structural equality, and cycle termination are covered; add direct unspecified `eq?`/`eqv?` corner cases. |
| `[~]` | Characters and strings (6.3.4-6.3.5, pp. 29-31) | Partial | Character reader and character/string primitives backed by Swift `Character`. | Basic mutation/conversion/comparison tests exist. Unicode repertoire, case mapping/order, and index/error boundaries need a linked matrix. |
| `[x]` | Vectors (6.3.6, pp. 31-33) | Supported | `SchemeVector`, vector reader/writer, mutation and list conversion primitives. | Mutable/cyclic vector writer/equality tests exist; add every fill/ref/conversion boundary. |
| `[~]` | Numeric tower, exactness, arithmetic, and numeric I/O (6.2.1-6.2.6, pp. 19-25; 7.1.1) | Partial | `BigInt`, `Rational`, `RealComponent`, `SchemeNumber`, numeric reader, arithmetic/comparison/rounding/transcendental/complex primitives. | Large exact integer, rational, complex, exactness, radix, and round-trip evidence is strong. `#` placeholders, infinities/NaN conventions, all branch/domain/error cases, and full per-procedure tests remain open. |
| `[x]` | Control features, multiple values, promises, `eval` (6.4-6.5, pp. 31-35) | Supported | Special procedures for `apply`, `call/cc`, `values`, `call-with-values`, `dynamic-wind`, `force`, and `eval`; environment constructors. | Existing tests cover escapes, multiple values, wind transitions, promise memoization, and report-environment evaluation. Add value-count/error matrix. |
| `[~]` | Report/null/interaction environments (6.5, p. 35) | Partial | `scheme-report-environment`, `null-environment`, and `interaction-environment`. | Version 5 acceptance and report evaluation are tested. Assignment/environment mutability semantics are intentionally not overclaimed. |
| `[~]` | Ports, files, `read`, `write`, `display`, and character I/O (6.6.1-6.6.3, pp. 35-37) | Partial | `SchemePort`, file/string ports, current ports, open/close, read/read-char/peek-char, write/display/newline/write-char. | File continuation exit/re-entry and output separation are tested. Closed-port, EOF, readiness, I/O-error, and complete reader integration matrices remain open; `char-ready?` is currently conservative. |
| `[~]` | `load`, transcript/system interface (6.6.4, pp. 37-38) | Partial | `load` is implemented; `transcript-on` and `transcript-off` are installed as no-op procedures. | `load` needs direct coverage. Transcript procedures are optional in R5RS and are **not** counted as implemented merely because stubs are bound. |
| `[~]` | R5RS-required/library procedure inventory (6.1-6.6, pp. 17-38) | Partial | 134 named primitive/special registrations were extracted from the interpreter dispatch, including helper and extension names. | Registration proves discoverability only. Every required/library name still needs a section-linked Swift Testing signature, domain, exactness, error, and unspecified-result check. |
| `[~]` | R5RS optional procedures (1.3.1, 6.5-6.6, pp. 3, 35-38) | Partial | Optional `load`, `interaction-environment`, `with-{input,output}-from-file`, string-port helpers, and transcript names are present. | Omission is permitted; supplied transcript no-ops are not implementations. Keep optional coverage and implementation status separate from required procedures. |
| `[x]` | Repository test-framework contract | Supported after migration | **Historical baseline:** the pre-migration package declared a local `XCTest` target, shim, plugin, and XCTest imports. **Current candidate:** `Package.swift` has one `SwiftSchemeTests` target using `import Testing`, `@Test`/`@Suite`, `#expect`/`#require`; authored package/source/test paths contain no XCTest targets, imports, files, or plugin/tool paths. | Keep a zero-XCTest search and Swift Testing run in the merge gate; the historical baseline remains recorded for audit traceability. |
| `[N/A]` | Apple HIG | Not applicable to the current language surface | `Package.swift` and `Sources/SwiftSchemeCLI` expose a macOS library/terminal CLI with no SwiftUI, UIKit, or AppKit surface. | Applicability and future native-surface contract: [`Architecture/APPLE-HIG.md`](../../Architecture/APPLE-HIG.md). No UI conformance is inferred. |

**Audit-start snapshot (before the Swift Testing migration):** 18 reviewed
surfaces — 7 Supported, 9 Partial, 1 Missing (the explicit no-XCTest constraint),
and 1 Not applicable. **Post-migration confirmation:** the test-framework row is
now Supported, so the current row count is 8 Supported, 9 Partial, 0 Missing, and
1 Not applicable. These are row counts, not feature or conformance percentages.

## Required and library procedure footprint

The following names are present in the interpreter registration/dispatch surface or
are derived by the evaluator. Presence is not proof of every signature, domain,
error, exactness, or unspecified-result rule; each family therefore remains linked
to focused Swift Testing coverage before it can be called complete.

| R5RS family | Registered/implemented names observed | Checklist |
|---|---|---|
| Equivalence | `eqv?`, `eq?`, `equal?` | `[~]` Add direct corner-case and identity matrix. |
| Numeric predicates/comparison | `number?`, `complex?`, `real?`, `rational?`, `integer?`, `exact?`, `inexact?`, `=`, `<`, `>`, `<=`, `>=`, `zero?`, `positive?`, `negative?`, `odd?`, `even?` | `[~]` Numeric reader and mixed exact/inexact cases are covered; expand domains/errors. |
| Numeric arithmetic | `max`, `min`, `+`, `*`, `-`, `/`, `quotient`, `remainder`, `modulo`, `gcd`, `lcm`, `numerator`, `denominator`, `floor`, `ceiling`, `truncate`, `round`, `rationalize` | `[~]` Exactness and sign laws need per-entry tests. |
| Numeric transcendental/complex | `exp`, `log`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `sqrt`, `expt`, `make-rectangular`, `make-polar`, `real-part`, `imag-part`, `magnitude`, `angle` | `[~]` Real/complex branch and domain cases need explicit evidence. |
| Numeric conversion/I/O | `exact->inexact`, `inexact->exact`, `number->string`, `string->number` | `[~]` Radix/read-back is covered; placeholder and special-value grammar remain open. |
| Pairs/lists | `cons`, `car`, `cdr`, `set-car!`, `set-cdr!`, `list`, `length`, `append`, `reverse`, `list-tail`, `list-ref`, `pair?`, `null?`, `list?`, `caar` through `cddddr`, `memq`, `memv`, `member`, `assq`, `assv`, `assoc` | `[~]` Core behavior is covered; boundary and cyclic-list domains need expansion. |
| Other data | `not`, `boolean?`, `symbol?`, `char?`, `string?`, `vector?`, `port?`, `input-port?`, `output-port?`, `procedure?` | `[~]` Add disjointness table across every `Value` case. |
| Symbols/chars | `symbol->string`, `string->symbol`, `char->integer`, `integer->char`, character comparison/predicate/case procedures | `[~]` Unicode and spelling policy require explicit portable tests. |
| Strings | `string`, `make-string`, `string-length`, `string-ref`, `string-set!`, `substring`, `string-append`, `string->list`, `list->string`, `string-copy`, `string-fill!`, string comparison/case procedures | `[~]` Mutation is covered; error/index/case boundaries remain. |
| Vectors | `vector`, `make-vector`, `vector-length`, `vector-ref`, `vector-set!`, `vector->list`, `list->vector`, `vector-fill!` | `[~]` Add fill/ref/conversion edge cases. |
| Control/eval | `apply`, `call-with-current-continuation`/`call/cc`, `values`, `call-with-values`, `dynamic-wind`, `force`, `eval` | `[~]` Existing difficult paths are strong; add arity/value-count matrix. |
| I/O/system | `call-with-input-file`, `call-with-output-file`, `current-input-port`, `current-output-port`, `open-input-file`, `open-output-file`, `close-input-port`, `close-output-port`, `read`, `read-char`, `peek-char`, `eof-object?`, `char-ready?`, `write`, `display`, `newline`, `write-char`, `load` | `[~]` Add direct load, EOF, closed-port, and error evidence. |
| Optional/extension surface | `interaction-environment`, `with-input-from-file`, `with-output-to-file`, string-port helpers, `transcript-on`, `transcript-off`, `error` | `[~]` Keep optional status explicit; transcript no-ops are not implementations. |

## Concrete conformance gaps to keep visible

- The reader currently accepts `#` digit placeholders by substituting zero in some
  numeric paths. R5RS restricts placeholders to inexact constants; add positive and
  negative cases before changing the parser.
- `transcript-on`/`transcript-off` are no-op stubs. Either implement their specified
  effect or document them as intentionally omitted optional procedures; do not mark
  them Supported.
- Immutable literal mutation, internal-definition grouping/order, Unicode character
  semantics, `char-ready?` at EOF, closed-port behavior, and every required
  procedure's arity/type/domain errors need direct tests.
- R5RS leaves some `eq?`, `eqv?`, literal sharing, evaluation order, and external
  representations unspecified or implementation-dependent. Tests must assert only
  permitted behavior.
- The vendored Chibi/Larceny/Racket material under `Tests/Conformance/` is reference
  evidence, not a substitute for Swift Testing tests and must remain unmodified.

## Evidence ledger and next slices

- Triage report and extracted PDF evidence: `/tmp/skizzles-orchestration/swiftscheme-r5rs-20260814/triage/triage__r5rs_footprint/`.
- Architecture decision and long-term topology/enforcement plan:
  [`Architecture/ADR-0001-r5rs-runtime-topology.md`](../../Architecture/ADR-0001-r5rs-runtime-topology.md).
- Apple HIG applicability boundary:
  [`Architecture/APPLE-HIG.md`](../../Architecture/APPLE-HIG.md).
- Swift Testing migration owner: `/root/worker__swift_testing_migration`.
- Follow-up conformance owner (not started in this campaign): add section-linked Swift
  Testing cases for the concrete gaps above, then repair only the owning semantic
  boundary when a new test fails.

**Campaign goal:** leave this checklist, the two architecture records, and the Swift
Testing-only package topology as a validated, reviewable baseline. Continue the
section-linked conformance slices rather than claiming completion from registration
counts.
