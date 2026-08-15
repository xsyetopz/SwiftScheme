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
current Swift Testing assertion labels. The native suite currently lists 159 tests (`swift test --list-tests` at audit time),
including the section-linked `R5RSProcedureMatrixTests` and the focused
numeric, control, macro, environment, and I/O suites. R5RS-required and R5RS-library procedures
are listed separately from optional procedures and local extensions. An open row
is not rescued by a registration count, fixture, or campaign-temp report.
Unspecified or implementation-dependent behavior is not treated as a passing
assertion.

## Footprint matrix

| Check | R5RS surface | Current status | Footprint in this workspace | Evidence / remaining work |
| --- | --- | --- | --- | --- |
| `[~]` | Lexical conventions, datum reader, and external representations (2.1-2.3, pp. 5-8; 7.1.2, p. 39) | Partial | `Reader` and `Writer` in `Sources/SwiftScheme/Frontend/ExternalForms.swift`, `Reader+Numbers.swift`, and `Sources/SwiftScheme/Evaluator/Interpreter.swift`; comments (including CR/CRLF diagnostic locations), case-folded ASCII identifiers, booleans, strings, characters, lists, dotted lists, vectors, quote/quasiquote abbreviations, reserved-character diagnostics, and radix/exactness number forms are present. | `R5RSNumericTests` covers strict string escapes, raw controls, reserved characters, malformed identifiers, and numeric grammar placements; `R5RSReaderBoundaryTests` covers malformed complete forms, LF/CR/CRLF comments, dotted-tail EOF completeness, nonalphabetic character-literal termination, interactive incomplete-versus-invalid distinctions, and read/write round trips; `SwiftSchemeRegressionTests` covers reader/writer forms. A complete malformed-token/grammar matrix remains open. |
| `[x]` | Core expressions: variable reference, literal, call, `quote`, `lambda`, `if`, `set!`, `begin` (4.1, pp. 8-10) | Supported | `Interpreter.run`, `SchemeEnvironment`, `Procedure`, `parseFormals`. | Current labels cover `reader/writer`, `closure mutation`, `variadic lambda`, `if`, `unbound set`, and `duplicate formals`; sequencing also appears in the multi-form evaluator cases. |
| `[~]` | Derived expressions: `cond`, `case`, `and`, `or`, `let`, `let*`, `letrec`, named `let`, `do`, `delay`, `quasiquote` (4.2, pp. 10-13) | Partial | `expandCond`, `expandCase`, `expandAnd`, `expandOr`, `expandLet`, `expandLetStar`, `expandDo`, `expandQuasiquote`; `Promise` and `force`. Expression-only sequence validation now covers `cond`, `case`, and `do` command/result regions. | `R5RSDerivedControlTests` and the deterministic `control-data.scm` fixture now prove generated syntax and quasiquote helpers resist lexical shadowing, supports vector unquote-splicing, accepts repeated `case` datums with first-clause precedence, rejects malformed `cond`/empty `case`/`begin`/`do`, checks comma-free quasiquote constants remain immutable, checks selected-branch/`do` laziness, and checks empty-list `map`/`for-each` domains. Broader malformed-binding and unspecified-result cases remain open. |
| `[~]` | Programs, top-level definitions, internal definitions (5.1-5.2, pp. 16-17) | Partial | Top-level `evaluate` loop and `define`/procedure shorthand in `Interpreter.run`; body validation/prebinding enforces an initial internal-definition group and rejects duplicate/late definitions. | `R5RSMacroDefinitionTests` proves legal grouped definitions, shared binding regions, begin splicing, duplicate rejection, top-level definition interleaving, and definition-after-expression diagnostics; it also exercises representative malformed top-level definitions. Full malformed-definition and top-level ordering matrices remain open. |
| `[~]` | Hygienic macros: `syntax-rules`, `define-syntax`, `let-syntax`, `letrec-syntax` (4.3, 5.3, pp. 13-17; 7.1.5, p. 40) | Partial | `SyntaxRules`, macro environments, and evaluator macro dispatch; improper template tails are transcribed without requiring a proper list. Empty rule sets are accepted, repeated pattern variables/custom ellipses are diagnosed, and expression-only `let-syntax` bodies are enforced. | Existing labels cover `syntax-rules` ellipsis (including its reservation against definition-site value shadowing), non-head underscore pattern variables, explicit underscore literals, macro-keyword validation, hygiene, definition-site literal template bindings, core template hygiene, quoted and quasiquoted macro data/pattern variables, referential transparency, `let-syntax`, nested ellipses, dotted templates/patterns, and mutually recursive local `letrec-syntax`; malformed transformer diagnostics and full repetition-shape matrices remain open. |
| `[x]` | Proper tail recursion and first-class continuations (3.5, p. 7; 6.4, pp. 31-35) | Supported | Iterative `Control`/`Continuation` machine with tail-continuation normalization; `call/cc`, `dynamic-wind`, and continuation wind transitions. | The `proper tail recursion`, `multi-shot continuation`, `dynamic-wind`, and `dynamic-wind continuation transitions` assertions run in the native Swift Testing suite; the tail loop is 200,000 iterations and the accepted control audit measured constant RSS at 150,000 iterations. |
| `[~]` | Booleans, pairs/lists, symbols, and equivalence predicates (6.1, 6.3.1-6.3.3, pp. 17-19, 25-29) | Partial | `Value`, `Pair`, list helpers, symbol conversion, and cycle-aware `equal?`; source symbols are case-folded while `string->symbol` preserves string-created spelling identity. | Mutation, improper-list domain errors, selectors, membership/association, structural equality, symbol conversion case, string-created symbol evaluation, immutable `symbol->string` results, and cycle termination are covered by `R5RSIODataTests`; the §6.3.2 list-consumer test covers `list-tail`/`memq`/`memv`/`member` non-list and improper-list rejection. `R5RSProcedureSemanticsTests.unspecifiedEquivalenceCases` confirms implementation-dependent `eq?`/`eqv?` cases remain boolean; the full identity matrix remains open. |
| `[~]` | Characters and strings (6.3.4-6.3.5, pp. 29-31) | Partial | Character reader and character/string primitives backed by scalar-normalized Swift `Character` values. | `R5RSIODataTests.characterCaseConversion` covers ASCII case invariants, scalar-safe `char-upcase`/`char-downcase`, case-insensitive comparison, and integer round trips; the §6.3.5 `string-ci` tests prove strings extend §6.3.4 `char-ci` case classes across equality/order while preserving stored combining-character boundaries. `stringConstructorsPreserveCharacterBoundaries` checks `string`, `substring`, `string-append`, `list->string`, and `string-copy` preserve a separately stored combining scalar. `scalarCharacterLiteralDomain` rejects multi-scalar `#\\é` and verifies scalar-accurate lexical columns, while `scalarCharacterBoundariesAndIntegerRoundTrips` checks scalar string/port reads, `char?`/`char->integer`, and integer↔character round trips. `publicScalarValueBoundary` covers public `SchemeString.characters` normalization and safe writer/read fallbacks for host-injected multi-scalar values and quote/backslash-plus-combining boundaries. The compact scalar policy preserves expansion-prone Unicode values as characters but deliberately excludes one-to-many case mappings (for example `ß`/`İ`) from `char-alphabetic?`, so the §6.3.4 case-result invariants remain true; Unicode repertoire/order and index/error boundaries still need a linked matrix. |
| `[x]` | Vectors (6.3.6, pp. 31-33) | Supported | `SchemeVector`, vector reader/writer, mutation and list conversion primitives. | `R5RSIODataTests.vectorMatrix` covers mutable fill/ref, length, list/vector conversion, and index/size errors; cyclic writer/equality behavior is also covered. Broader malformed and aliasing matrices remain open. |
| `[~]` | Numeric tower, exactness, arithmetic, and numeric I/O (6.2.1-6.2.6, pp. 19-25; 7.1.1, pp. 38-39) | Partial | `BigInt`, `Rational`, `RealComponent`, `SchemeNumber`, strict numeric reader, arithmetic/comparison/rounding/transcendental/complex primitives. | `R5RSNumericTests` now proves radix/exactness prefix order, trailing placeholders, signs, exponent/component placement, malformed forms, strict token termination, string grammar, finite inexact radix-10/radix round-trips through binary64 subnormal/normal/extreme boundaries, nearest-even exact-to-inexact integer conversion, and decimal-point preservation in scientific output. Native procedure evidence also preserves exact representable rational exponents, nearest-even rounding and exactness classes, real-valued complex-literal transcendental domains, real-domain and complex principal-branch `atan`, known-real inexact integer powers, zero-angle polar exactness, NaN sign-predicate behavior, zero-numerator tiny-denominator complex division, stable finite-extreme complex arithmetic, infinite power limits, and complex square-root branches. Infinities/NaN conventions, complete polar/transcendental branches, all domain/error cases, and full per-procedure result matrices remain open. |
| `[~]` | Control features, multiple values, promises, `eval` (6.4-6.5, pp. 31-35) | Partial | Special procedures for `apply`, `call/cc`, `values`, `call-with-values`, `dynamic-wind`, `force`, and `eval`; environment constructors. | Existing tests and the deterministic `control-data.scm` fixture cover escapes, multiple values, wind transitions, promise memoization, report-environment evaluation, rejection of non-expression `eval` inputs, and cycle-safe rejection of self-referential eval data. `R5RSDerivedControlTests.emptyListProcedureDomains` proves empty-list `map`/`for-each` procedure validation, `R5RSProcedureSemanticsTests.multipleValueContracts` proves producer/consumer arity, ignored wind results, and callback value-count errors, and `evalExpressionDomains` rejects empty-list/vector data as expressions. Broader continuation and value-count/error matrices remain open. |
| `[~]` | Report/null/interaction environments (6.5, p. 35) | Partial | `scheme-report-environment`, `null-environment`, and `interaction-environment`; fixed report/null policies reject definitions while preserving expression evaluation, and report copies only the explicit R5RS procedure inventory. | `R5RSEnvironmentTests` proves version 5, expression evaluation, and an inventory-wide report binding check (including the previously missing report-bound selector `cdddr`), plus rejected value/syntax definitions, extension exclusion, unbound probes, and omitted transcript names. Assignment semantics are intentionally not overclaimed because R5RS leaves them unspecified. |
| `[~]` | Ports, files, `read`, `write`, `display`, and character I/O (6.6.1-6.6.3, pp. 35-37) | Partial | `SchemePort`, file/string ports, current ports, open/close, read/read-char/peek-char, write/display/newline/write-char. | `R5RSIODataTests` and `R5RSIODataEdgeTests` prove mutable read values, immutable source literals, cyclic-data rejection by `eval`, configured current-input behavior, explicit and omitted-current closed-port errors, missing/uncreatable file diagnostics, invalid UTF-8 file diagnostics, idempotent close, stable port predicates, EOF/readiness, recursive raw `display` output for nested strings/chars, vector boundaries, and restoration after callback errors; continuation file paths remain in `SwiftSchemeRegressionTests`. Full I/O-error and interactive readiness matrices remain open. |
| `[~]` | `load`, transcript/system interface (6.6.4, pp. 37-38) | Partial | `load` evaluates source in the interaction environment and discards its final result; optional transcript bindings are deliberately omitted. | `R5RSIODataTests` proves sequential load side effects, preservation of earlier definitions when a later form is malformed, and the `#<unspecified>` result. Transcript support is optional and is represented by omission, not no-op stubs. |
| `[~]` | R5RS-required/library procedure inventory (6.1-6.6, pp. 17-38) | Partial | Required names are dispatched by the interpreter and enumerated in shared `R5RSProcedureNames` data used by `R5RSProcedureInventoryTests`; `R5RSProcedureMatrixTests` exercises valid contracts across the core equivalence, numeric, pair/list, selector, character/string/vector, control, eval, port, and file-I/O matrices. | `R5RSProcedureContractTests` now executes one representative valid contract for every required name (including all 28 composed selectors and file-port callbacks), while `R5RSProcedureMatrixTests` adds the expanded arity/domain rejection table, including every composed-selector non-pair domain. The inventory includes the full `caar`–`cddddr` family, including `cdddr`. These tests cover representative signatures, domains, exactness, and errors across every required family, and its identity-and-mutation tests cover symbol interning, list-tail/membership/association sharing, and specified fresh/shared structure for list, string, and vector constructors; the unspecified-result contract covers mutators, `for-each`, output procedures, and close-port operations. A separately labeled assertion is still needed for every procedure's complete result, identity, and malformed-input matrix. |
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
| --- | --- | --- |
| Equivalence | `eqv?`, `eq?`, `equal?` | `[~]` Add direct corner-case and identity matrix. |
| Numeric predicates/comparison | `number?`, `complex?`, `real?`, `rational?`, `integer?`, `exact?`, `inexact?`, `=`, `<`, `>`, `<=`, `>=`, `zero?`, `positive?`, `negative?`, `odd?`, `even?` | `[~]` Numeric reader and mixed exact/inexact cases are covered; expand domains/errors. |
| Numeric arithmetic | `max`, `min`, `+`, `*`, `-`, `/`, `quotient`, `remainder`, `modulo`, `gcd`, `lcm`, `numerator`, `denominator`, `floor`, `ceiling`, `truncate`, `round`, `rationalize` | `[~]` Exactness and sign laws need per-entry tests. |
| Numeric transcendental/complex | `exp`, `log`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `sqrt`, `expt`, `make-rectangular`, `make-polar`, `real-part`, `imag-part`, `magnitude`, `angle` | `[~]` Real/complex branch and domain cases need explicit evidence. |
| Numeric conversion/I/O | `exact->inexact`, `inexact->exact`, `number->string`, `string->number` | `[~]` Radix 2/8/10/16 read-back, leading-atmosphere handling, exactness-prefix default-radix behavior, finite inexact non-decimal round trips, and malformed complete-datum behavior are covered; special-value and broader conversion-boundary cases remain open. |
| Pairs/lists | `cons`, `car`, `cdr`, `set-car!`, `set-cdr!`, `list`, `length`, `append`, `reverse`, `list-tail`, `list-ref`, `pair?`, `null?`, `list?`, `caar` through `cddddr`, `memq`, `memv`, `member`, `assq`, `assv`, `assoc` | `[~]` Core behavior is covered; cyclic-list consumers and boundary domains have focused tests, while broader malformed-input matrices remain open. |
| Other data | `not`, `boolean?`, `symbol?`, `char?`, `string?`, `vector?`, `port?`, `input-port?`, `output-port?`, `procedure?` | `[~]` `R5RSIODataTests.predicateDomainMatrix` covers the principal disjoint domains and port/procedure predicates; add explicit false cross-product and environment/promise cases. |
| Symbols/chars | `symbol->string`, `string->symbol`, `char->integer`, `integer->char`, character comparison/predicate/case procedures | `[~]` Symbol spelling and Unicode policies have focused tests; broader portable repertoire/order matrices remain open. |
| Strings | `string`, `make-string`, `string-length`, `string-ref`, `string-set!`, `substring`, `string-append`, `string->list`, `list->string`, `string-copy`, `string-fill!`, string comparison/case procedures | `[~]` Mutation, zero-arity constructors, and exact-two comparison arities are covered; error/index/case boundaries remain. |
| Vectors | `vector`, `make-vector`, `vector-length`, `vector-ref`, `vector-set!`, `vector->list`, `list->vector`, `vector-fill!` | `[~]` Add fill/ref/conversion edge cases. |
| Control/eval | `apply`, `call-with-current-continuation`/`call/cc`, `values`, `call-with-values`, `dynamic-wind`, `force`, `eval` | `[~]` Existing difficult paths plus `evalExpressionDomains`, empty-list map/for-each, apply final-list, and value-count/unequal-list boundaries are covered; continuation and dynamic-wind edge matrices remain open. |
| I/O/system | `call-with-input-file`, `call-with-output-file`, `current-input-port`, `current-output-port`, `open-input-file`, `open-output-file`, `close-input-port`, `close-output-port`, `read`, `read-char`, `peek-char`, `eof-object?`, `char-ready?`, `write`, `display`, `newline`, `write-char`, `load` | `[~]` `R5RSIODataTests` now covers sequential load effects (including a later parse error), EOF, explicit and omitted-current closed-port errors, idempotent close, callback-error port restoration, stable predicates, raw output, vectors, and error evidence; full file-error and interactive matrices remain open. |
| Optional/extension surface | `interaction-environment`, `with-input-from-file`, `with-output-to-file`, string-port helpers, `error` | `[~]` Keep optional status explicit; transcript procedures are intentionally omitted rather than represented by no-op bindings. |

## Concrete conformance gaps to keep visible

- Numeric placeholders are now checked by `R5RSNumericTests`; the parser normalizes
  trailing placeholders conservatively and rejects placeholders in exact/exponent
  positions. Special-value conventions and the complete numeric domain matrix remain
  open.
- `transcript-on`/`transcript-off` are intentionally omitted optional procedures;
  no no-op bindings remain and no transcript support is claimed.
- Immutable literal mutation, non-expression `eval` rejection, definition-group keyword classification,
  internal-definition grouping/order, derived-form hygiene/malformed boundaries,
  load's unspecified result, EOF/closed-port behavior, and vector/list boundaries
  have direct tests in `R5RSMacroDefinitionTests`, `R5RSDerivedControlTests`, and
  `R5RSIODataTests`. Unicode character ordering, interactive readiness, and every
  required procedure's full arity/type/domain matrix still need evidence.
- R5RS leaves some `eq?`, `eqv?`, literal sharing, evaluation order, and external
  representations unspecified or implementation-dependent. Tests must assert only
  permitted behavior. Cyclic `write`/`display` output uses the diagnostic marker
  `#<cycle>` and is intentionally not claimed as an R5RS external-form round trip. A prior audit note referred to an adapted 184-case Chibi
  fixture and a `symbol->string 'Martin` expected-value normalization, but no
  adapted fixture or runner is present in this workspace, so a 184/184 result is
  not reproducible evidence. Keep that result open until the exact fixture,
  revision, license, adapter, command, and captured output are checked in.
- Temporary Chibi/Larceny/Racket checkouts used during audit are reference
  context only, not release evidence or a substitute for Swift Testing tests.
  If promoted, add a separately reviewed and licensed source snapshot with a
  deterministic runner.

## Validation caveats

The strict `swift-format lint` gate remains non-clean because the public numeric/runtime API has approximately 95 `AllPublicDeclarationsHaveDocumentation` diagnostics. Build, Swift Testing, SwiftLint, architecture, duplication, and whitespace checks are clean; this formatting/documentation debt is not conformance evidence.

## Evidence ledger and next slices

- Architecture decision and long-term topology/enforcement plan:
  [`Architecture/ADR-0001-r5rs-runtime-topology.md`](../../Architecture/ADR-0001-r5rs-runtime-topology.md).
- Apple HIG applicability boundary:
  [`Architecture/APPLE-HIG.md`](../../Architecture/APPLE-HIG.md).
- Current native evidence includes the broad regression/BigInt suites plus focused
  `R5RSProcedureMatrixTests`, `R5RSNumericTests`, `R5RSEnvironmentTests`, `R5RSMacroDefinitionTests`,
  `R5RSIODataTests`, `R5RSProcedureInventoryTests`, and
  `R5RSProcedureContractTests`; it must not be generalized into per-procedure
  semantic proof. `just fixtures` runs the three checked-in
  deterministic programs described in [`EXTERNAL-EVIDENCE.md`](EXTERNAL-EVIDENCE.md)
  and compares complete stdout captures byte-for-byte. The fixture manifest pins
  source/output hashes and lengths and rejects unlisted or modified fixtures before
  execution; use `--configuration release` when retaining release evidence.
- Follow-up conformance slices should add section-linked Swift Testing cases for the
  concrete gaps above, then repair only the owning semantic boundary when a new test
  fails. Do not promote the local vendor trees to release evidence without a separate
  license/revision review.

**Campaign goal:** leave this checklist, the two architecture records, and the Swift
Testing-only package topology as a validated, reviewable baseline. Continue the
section-linked conformance slices rather than claiming completion from registration
counts.
