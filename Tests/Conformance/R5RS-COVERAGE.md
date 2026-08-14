# SwiftScheme R5RS coverage checklist

**Audit date:** 2026-08-15
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
current Swift Testing assertion labels. R5RS-required and R5RS-library procedures
are listed separately from optional procedures and local extensions. An open row
is not rescued by a registration count, fixture, or campaign-temp report.
Unspecified or implementation-dependent behavior is not treated as a passing
assertion.

## Footprint matrix

| Check | R5RS surface | Current status | Footprint in this workspace | Evidence / remaining work |
|---|---|---|---|---|
| `[~]` | Lexical conventions, datum reader, and external representations (2.1-2.3, pp. 5-8; 7.1.2, p. 39) | Partial | `Reader` and `Writer` in `Sources/swiftscheme/SwiftScheme.swift`; comments, case-folded ASCII identifiers, booleans, strings, characters, lists, dotted lists, vectors, quote/quasiquote abbreviations, reserved-character diagnostics, and radix/exactness number forms are present. | `R5RSNumericTests` covers strict string escapes, raw controls, reserved characters, malformed identifiers, and numeric grammar placements; `SwiftSchemeRegressionTests` covers reader/writer forms. A complete malformed-token/grammar matrix and all external-representation round trips remain open. |
| `[x]` | Core expressions: variable reference, literal, call, `quote`, `lambda`, `if`, `set!`, `begin` (4.1, pp. 8-10) | Supported | `Interpreter.run`, `SchemeEnvironment`, `Procedure`, `parseFormals`. | Current labels cover `reader/writer`, `closure mutation`, `variadic lambda`, `if`, `unbound set`, and `duplicate formals`; sequencing also appears in the multi-form evaluator cases. |
| `[~]` | Derived expressions: `cond`, `case`, `and`, `or`, `let`, `let*`, `letrec`, named `let`, `do`, `delay`, `quasiquote` (4.2, pp. 10-13) | Partial | `expandCond`, `expandCase`, `expandAnd`, `expandOr`, `expandLet`, `expandLetStar`, `expandDo`, `expandQuasiquote`; `Promise` and `force`. | `R5RSDerivedControlTests` now proves generated syntax and quasiquote helpers resist lexical shadowing, rejects malformed `cond`/`begin`/`case`/`do`, and checks empty-list `map`/`for-each` domains. Explicit side-effect laziness, named-let boundaries, and unspecified-result cases remain open. |
| `[~]` | Programs, top-level definitions, internal definitions (5.1-5.2, pp. 16-17) | Partial | Top-level `evaluate` loop and `define`/procedure shorthand in `Interpreter.run`; body validation/prebinding enforces an initial internal-definition group and rejects duplicate/late definitions. | `R5RSMacroDefinitionTests` proves legal grouped definitions, shared binding regions, begin splicing, duplicate rejection, and definition-after-expression diagnostics. Full top-level ordering and all malformed-definition forms remain open. |
| `[~]` | Hygienic macros: `syntax-rules`, `define-syntax`, `let-syntax`, `letrec-syntax` (4.3, 5.3, pp. 13-17; 7.1.5, p. 40) | Partial | `SyntaxRules`, macro environments, and evaluator macro dispatch; improper template tails are transcribed without requiring a proper list. | Existing labels cover `syntax-rules` ellipsis, hygiene, quoted macro data/pattern variables, referential transparency, `let-syntax`, nested ellipses, dotted templates/patterns, and local `letrec-syntax`; malformed transformer diagnostics and full repetition-shape matrices remain open. |
| `[x]` | Proper tail recursion and first-class continuations (3.5, p. 7; 6.4, pp. 31-35) | Supported | Iterative `Control`/`Continuation` machine with tail-continuation normalization; `call/cc`, `dynamic-wind`, and continuation wind transitions. | The `proper tail recursion`, `multi-shot continuation`, `dynamic-wind`, and `dynamic-wind continuation transitions` assertions run in the native Swift Testing suite; the tail loop is 200,000 iterations and the accepted control audit measured constant RSS at 150,000 iterations. |
| `[~]` | Booleans, pairs/lists, symbols, and equivalence predicates (6.1, 6.3.1-6.3.3, pp. 17-19, 25-29) | Partial | `Value`, `Pair`, list helpers, symbol conversion, and cycle-aware `equal?`; source symbols are case-folded while `string->symbol` preserves string-created spelling identity. | Mutation, improper-list domain errors, selectors, membership/association, structural equality, symbol conversion case, immutable `symbol->string` results, and cycle termination are covered by `R5RSIODataTests`; the §6.3.2 list-consumer test covers `list-tail`/`memq`/`memv`/`member` non-list and improper-list rejection. Direct unspecified `eq?`/`eqv?` corner cases and full identity matrix remain open. |
| `[~]` | Characters and strings (6.3.4-6.3.5, pp. 29-31) | Partial | Character reader and character/string primitives backed by scalar-normalized Swift `Character` values. | `R5RSIODataTests.characterCaseConversion` covers ASCII case invariants, scalar-safe `char-upcase`/`char-downcase`, case-insensitive comparison, and integer round trips; the §6.3.5 `string-ci` tests prove strings extend §6.3.4 `char-ci` case classes across equality/order while preserving stored combining-character boundaries. `stringConstructorsPreserveCharacterBoundaries` checks `string`, `substring`, `string-append`, `list->string`, and `string-copy` preserve a separately stored combining scalar. `scalarCharacterLiteralDomain` rejects multi-scalar `#\\é` and verifies scalar-accurate lexical columns, while `scalarCharacterBoundariesAndIntegerRoundTrips` checks scalar string/port reads, `char?`/`char->integer`, and integer↔character round trips. `publicScalarValueBoundary` covers public `SchemeString.characters` normalization and safe writer/read fallbacks for host-injected multi-scalar values and quote/backslash-plus-combining boundaries. The compact scalar policy preserves expansion-prone Unicode mappings (for example `ß`/`İ`) as scalar-safe characters; Unicode repertoire/order and index/error boundaries still need a linked matrix. |
| `[x]` | Vectors (6.3.6, pp. 31-33) | Supported | `SchemeVector`, vector reader/writer, mutation and list conversion primitives. | Mutable/cyclic vector writer/equality tests exist; add every fill/ref/conversion boundary. |
| `[~]` | Numeric tower, exactness, arithmetic, and numeric I/O (6.2.1-6.2.6, pp. 19-25; 7.1.1, pp. 38-39) | Partial | `BigInt`, `Rational`, `RealComponent`, `SchemeNumber`, strict numeric reader, arithmetic/comparison/rounding/transcendental/complex primitives. | `R5RSNumericTests` now proves radix/exactness prefix order, trailing placeholders, signs, exponent/component placement, malformed forms, string grammar, finite inexact radix round-trips through binary64 subnormal/normal/extreme boundaries, and nearest-even exact-to-inexact integer conversion. Infinities/NaN conventions, complete polar/transcendental branches, all domain/error cases, and full per-procedure result matrices remain open. |
| `[~]` | Control features, multiple values, promises, `eval` (6.4-6.5, pp. 31-35) | Partial | Special procedures for `apply`, `call/cc`, `values`, `call-with-values`, `dynamic-wind`, `force`, and `eval`; environment constructors. | Existing tests cover escapes, multiple values, wind transitions, promise memoization, and report-environment evaluation. `R5RSDerivedControlTests.emptyListProcedureDomains` proves empty-list `map`/`for-each` procedure validation, and `evalExpressionDomains` rejects empty-list/vector data as expressions. The value-count/error matrix remains open. |
| `[~]` | Report/null/interaction environments (6.5, p. 35) | Partial | `scheme-report-environment`, `null-environment`, and `interaction-environment`; fixed report/null policies reject definitions while preserving expression evaluation, and report copies only the explicit R5RS procedure inventory. | `R5RSEnvironmentTests` proves version 5, expression evaluation, rejected value/syntax definitions, extension exclusion, unbound probes, and omitted transcript names. Assignment semantics are intentionally not overclaimed because R5RS leaves them unspecified. |
| `[~]` | Ports, files, `read`, `write`, `display`, and character I/O (6.6.1-6.6.3, pp. 35-37) | Partial | `SchemePort`, file/string ports, current ports, open/close, read/read-char/peek-char, write/display/newline/write-char. | `R5RSIODataTests` proves mutable read values, immutable source literals, explicit and omitted-current closed-port errors, idempotent close, stable port predicates, EOF/readiness, raw output, and vector boundaries; continuation file paths remain in `SwiftSchemeRegressionTests`. Full I/O-error and interactive readiness matrices remain open. |
| `[~]` | `load`, transcript/system interface (6.6.4, pp. 37-38) | Partial | `load` evaluates source in the interaction environment and discards its final result; optional transcript bindings are deliberately omitted. | `R5RSIODataTests` proves load side effects and `#<unspecified>` result. Transcript support is optional and is represented by omission, not no-op stubs. |
| `[~]` | R5RS-required/library procedure inventory (6.1-6.6, pp. 17-38) | Partial | Required names are dispatched by the interpreter and enumerated in `R5RSProcedureInventoryTests`; required and supported-optional bindings are checked in separate tests. | Binding proves discoverability only. Every required/library name still needs a section-linked Swift Testing signature, domain, exactness, error, and unspecified-result check. |
| `[~]` | R5RS optional procedures (1.3.1, 6.5-6.6, pp. 3, 35-38) | Partial | Optional `load`, `interaction-environment`, and `with-{input,output}-from-file` are present; transcript names are intentionally omitted. String-port helpers and other local extensions are tracked separately, not presented as R5RS optionals. | Omission is permitted. Keep optional coverage and implementation-extension status separate from required procedures. |
| `[x]` | Repository test-framework contract | Supported after migration | **Historical baseline:** the pre-migration package declared a local `XCTest` target, shim, plugin, and XCTest imports. **Current candidate:** `Package.swift` has one `SwiftSchemeTests` target using `import Testing`, `@Test`/`@Suite`, `#expect`/`#require`; authored package/source/test paths contain no XCTest targets, imports, files, or plugin/tool paths. | Keep a zero-XCTest search and Swift Testing run in the merge gate; the historical baseline remains recorded for audit traceability. |
| `[N/A]` | Apple HIG | Not applicable to the current language surface | `Package.swift` and `Sources/SwiftSchemeCLI` expose a macOS library/terminal CLI with no SwiftUI, UIKit, or AppKit surface. | Applicability and future native-surface contract: [`Architecture/APPLE-HIG.md`](../../Architecture/APPLE-HIG.md). No UI conformance is inferred. |

**Audit-start snapshot (before the Swift Testing migration):** 18 reviewed
surfaces — 7 Supported, 9 Partial, 1 Missing (the explicit no-XCTest constraint),
and 1 Not applicable. **Post-migration confirmation:** the test-framework row is
now Supported, while derived-expression, symbols/equivalence, numeric, macro,
environment, control/eval, and I/O evidence remain Partial. The current row count
is 4 Supported, 13 Partial, 0 Missing, and 1 Not applicable. These are
row counts, not feature or conformance percentages.

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
| Numeric conversion/I/O | `exact->inexact`, `inexact->exact`, `number->string`, `string->number` | `[~]` Radix/read-back, exactness-prefix default-radix behavior, finite inexact non-decimal round trips, and malformed complete-datum behavior are covered; special-value and broader conversion-boundary cases remain open. |
| Pairs/lists | `cons`, `car`, `cdr`, `set-car!`, `set-cdr!`, `list`, `length`, `append`, `reverse`, `list-tail`, `list-ref`, `pair?`, `null?`, `list?`, `caar` through `cddddr`, `memq`, `memv`, `member`, `assq`, `assv`, `assoc` | `[~]` Core behavior is covered; boundary and cyclic-list domains need expansion. |
| Other data | `not`, `boolean?`, `symbol?`, `char?`, `string?`, `vector?`, `port?`, `input-port?`, `output-port?`, `procedure?` | `[~]` Add disjointness table across every `Value` case. |
| Symbols/chars | `symbol->string`, `string->symbol`, `char->integer`, `integer->char`, character comparison/predicate/case procedures | `[~]` Unicode and spelling policy require explicit portable tests. |
| Strings | `string`, `make-string`, `string-length`, `string-ref`, `string-set!`, `substring`, `string-append`, `string->list`, `list->string`, `string-copy`, `string-fill!`, string comparison/case procedures | `[~]` Mutation is covered; error/index/case boundaries remain. |
| Vectors | `vector`, `make-vector`, `vector-length`, `vector-ref`, `vector-set!`, `vector->list`, `list->vector`, `vector-fill!` | `[~]` Add fill/ref/conversion edge cases. |
| Control/eval | `apply`, `call-with-current-continuation`/`call/cc`, `values`, `call-with-values`, `dynamic-wind`, `force`, `eval` | `[~]` Existing difficult paths plus `evalExpressionDomains` are covered; add arity/value-count matrix. |
| I/O/system | `call-with-input-file`, `call-with-output-file`, `current-input-port`, `current-output-port`, `open-input-file`, `open-output-file`, `close-input-port`, `close-output-port`, `read`, `read-char`, `peek-char`, `eof-object?`, `char-ready?`, `write`, `display`, `newline`, `write-char`, `load` | `[~]` `R5RSIODataTests` now covers load, EOF, explicit and omitted-current closed-port errors, idempotent close, stable predicates, raw output, vectors, and error evidence; full file-error and interactive matrices remain open. |
| Optional/extension surface | `interaction-environment`, `with-input-from-file`, `with-output-to-file`, string-port helpers, `error` | `[~]` Keep optional status explicit; transcript procedures are intentionally omitted rather than represented by no-op bindings. |

## Concrete conformance gaps to keep visible

- Numeric placeholders are now checked by `R5RSNumericTests`; the parser normalizes
  trailing placeholders conservatively and rejects placeholders in exact/exponent
  positions. Special-value conventions and the complete numeric domain matrix remain
  open.
- `transcript-on`/`transcript-off` are intentionally omitted optional procedures;
  no no-op bindings remain and no transcript support is claimed.
- Immutable literal mutation, definition-group keyword classification,
  internal-definition grouping/order, derived-form hygiene/malformed boundaries,
  load's unspecified result, EOF/closed-port behavior, and vector/list boundaries
  have direct tests in `R5RSMacroDefinitionTests`, `R5RSDerivedControlTests`, and
  `R5RSIODataTests`. Unicode character ordering, interactive readiness, and every
  required procedure's full arity/type/domain matrix still need evidence.
- R5RS leaves some `eq?`, `eqv?`, literal sharing, evaluation order, and external
  representations unspecified or implementation-dependent. Tests must assert only
  permitted behavior.
- The workspace supplied local Chibi/Larceny/Racket material under
  `Tests/Conformance/`, but those uncommitted audit inputs are intentionally absent
  from the frozen candidate. They are reference context, not release evidence or a
  substitute for Swift Testing tests; if promoted, add them in a separately reviewed
  and licensed candidate.

## Evidence ledger and next slices

- Triage report and extracted PDF evidence were campaign-temp inputs at
  `/tmp/skizzles-orchestration/swiftscheme-r5rs-20260814/triage/triage__r5rs_footprint/`;
  they are not part of the candidate and are not required to interpret this
  self-contained checklist.
- Architecture decision and long-term topology/enforcement plan:
  [`Architecture/ADR-0001-r5rs-runtime-topology.md`](../../Architecture/ADR-0001-r5rs-runtime-topology.md).
- Apple HIG applicability boundary:
  [`Architecture/APPLE-HIG.md`](../../Architecture/APPLE-HIG.md).
- Current native evidence includes the broad regression/BigInt suites plus focused
  `R5RSNumericTests`, `R5RSEnvironmentTests`, `R5RSMacroDefinitionTests`,
  `R5RSIODataTests`, and `R5RSProcedureInventoryTests`; it must not be generalized
  into per-procedure semantic proof.
- Follow-up conformance slices should add section-linked Swift Testing cases for the
  concrete gaps above, then repair only the owning semantic boundary when a new test
  fails. Do not promote the local vendor trees to release evidence without a separate
  license/revision review.

**Campaign goal:** leave this checklist, the two architecture records, and the Swift
Testing-only package topology as a validated, reviewable baseline. Continue the
section-linked conformance slices rather than claiming completion from registration
counts.
