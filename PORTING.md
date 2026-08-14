# SwiftScheme PREP map

Scope: a Swift 6.3.3 SwiftPM interpreter for the R5RS core requested by `TASK.md`. `Reference/r5rs.pdf` is normative; section numbers below refer to R5RS. No third-party dependencies.

## Shape

| Concern | Planned Swift shape | Invariant |
| --- | --- | --- |
| Package | Library target `SwiftScheme`, executable product/target `swiftscheme`, Swift Testing test target `SwiftSchemeTests` | Library is directly testable; CLI stays thin; tests use Swift 6+ Swift Testing only |
| Runtime value | `indirect enum Value` for atoms/sentinels plus reference-backed mutable objects | R5RS types remain disjoint (§3.2); only `#f` is false (§6.3.1) |
| Pair/list | Identity-bearing `PairCell` with mutable `car`/`cdr`; empty-list singleton | Preserve improper/cyclic lists and `set-car!`/`set-cdr!` semantics |
| String | Identity-bearing mutable character storage, not bare Swift `String` | Mutation and object identity survive copies (§3.4) |
| Symbol | Canonical name, preferably interned | Source identifiers are case-insensitive; strings/chars retain case (§2) |
| Number | Arbitrary `BigInt`; normalized exact `Rational`; exact/inexact rectangular `SchemeNumber` | Exact integers never overflow; rational denominator is positive and reduced; inexactness is contagious; complex components preserve exactness where mathematically possible |
| Variable | `BindingCell` stored in an `Environment` chain | Bindings denote locations, so `set!` mutates a cell rather than a dictionary copy (§3.1, §3.4) |
| Procedure | Primitive Swift closure or Scheme closure(body, formals, captured environment) | Procedures are distinct from symbols and lambda syntax |
| Evaluator | Iterative trampoline/state loop for tail positions | No Swift stack growth for unbounded active tail calls (§3.5) |
| Failure | Typed `SchemeError`: lexical, syntax, unbound, arity, type, numeric, I/O | Never use traps or `fatalError` for Scheme input |
| Non-value | Explicit `unspecified` and `eof` sentinels | Do not conflate either with empty list or `#f` |

Proposed topology: `Package.swift`, `Sources/swiftscheme/SwiftScheme.swift`, `Sources/SwiftSchemeCLI/main.swift`, and focused files under `Tests/SwiftSchemeTests/`.

## Reader mapping

| R5RS surface | Swift strategy | Boundary to preserve |
| --- | --- | --- |
| Whitespace/comments | Cursor scanner; `;` through newline | Comments become whitespace; tabs count as whitespace |
| Identifiers | Scan delimiter-terminated token, canonicalize source spelling consistently | `Foo` and `FOO` bind the same identifier (§2) |
| Lists | Recursive datum reader building pairs; accept dotted tail | Reject stray dot, missing tail, extra datum after dotted tail, and unclosed list |
| Abbreviations | `'`, backquote, `,`, `,@` become two-element forms | Equivalent to `quote`, `quasiquote`, `unquote`, `unquote-splicing` (§6.3.2) |
| Atoms | `#t/#f`, numbers, strings, then symbols | A complete token must be consumed; malformed numeric-looking input gets a diagnostic |
| Strings | Decode at least `\"` and `\\`; retain newlines only where accepted | Diagnostics identify unterminated/invalid escapes |
| Input stream | Repeated `readDatum` until clean EOF | EOF before a datum differs from EOF inside an incomplete datum (§6.6.2) |
| Printing | One cycle-aware external-representation writer | Proper/dotted lists, escaped strings, booleans, procedures, sentinels are deterministic |

Use integer UTF-8/scalar offsets or line/column values for source locations; do not retain source-dependent `String.Index` values across buffers.

## Evaluation mapping

| Scheme rule/form | Planned handling |
| --- | --- |
| Self-evaluation / reference | Atoms evaluate to themselves; symbol lookup walks lexical parents and errors if unbound |
| Application | Evaluate operator and operands left-to-right (a permitted fixed choice for R5RS's unspecified order), validate procedure/arity, invoke |
| `quote` | Return datum without evaluation; literals are treated as immutable if mutation is exposed |
| `if` | Evaluate only the selected branch; missing alternate returns `unspecified`; selected branch inherits tail position |
| `lambda` | Parse fixed, variadic symbol, and dotted formals; reject duplicate names; capture lexical environment strongly |
| `begin` / bodies | Evaluate sequentially; only the final expression inherits tail position |
| `define` | Support variable and procedure shorthand at top level/body boundary chosen by implementation; install/update a location |
| `set!` | Find an existing binding cell; error rather than implicitly define |
| `let` | Evaluate initializers in the outer environment, then bind fresh cells simultaneously |
| `let*` | Bind/evaluate sequentially in nested/current extended environments |
| `letrec` | Preallocate undefined cells, evaluate initializers in the recursive environment, then assign; detect premature reads |
| Named `let` | Expand/execute as a local recursive procedure while preserving tail calls |
| `and` / `or` / `cond` | Short-circuit; final selected expression inherits tail position |
| Quasiquote | Depth-aware traversal; evaluate unquote at depth 1 and splice only proper lists in list/vector positions |
| Truth | Exactly `#f` is false; `()`, zero, and empty strings are true |
| Internal definitions | Treat leading body definitions as mutually visible (letrec-like); reject definitions after expressions |
| Unspecified behavior | Choose deterministic behavior for implementation/testing; do not write conformance tests that require R5RS-unspecified results |

Implement derived forms with evaluator cases or expansions. `syntax-rules` supports lexical definition-site references, hygienic introduced names, literals, vectors, dotted patterns, ellipses, and custom ellipsis identifiers.

## Runtime mapping and active migration targets

| R5RS area | SwiftScheme implementation |
| --- | --- |
| Control | Explicit continuation machine; multi-shot `call/cc`; `dynamic-wind` transition stack; multiple values |
| Macros | `define-syntax`, `let-syntax`, `letrec-syntax`, hygienic `syntax-rules` |
| Data | Mutable pairs, strings, vectors; characters; cycle-safe writer/equality |
| Lazy evaluation | Memoizing promises with `delay`/`force` |
| Environments | `eval`, report/null/interaction environment specifiers |
| I/O | File/current/string ports, read/write/peek/char operations, dynamic file redirection, `load` |
| Numbers | Arbitrary exact integers, normalized exact rationals, binary64 inexact components, rectangular complex values, and the R5RS §6.2 procedure surface |
| Storage | ARC-backed nodes plus interpreter-owned weak registry and tracing safe-point cycle reclamation |
| CLI | File, piped input, and multiline terminal REPL |

## Numeric tower invariants

| Layer | Representation | Required invariant |
| --- | --- | --- |
| Exact integer | `BigInt`: normalized sign and little-endian `UInt32` limbs | Zero has no negative sign or limbs; exact operations never overflow |
| Exact rational | `Rational(BigInt, BigInt)` | Denominator positive; numerator/denominator coprime; integer values canonicalize to denominator one |
| Inexact real | binary64 | Exact-to-inexact conversion is explicit; any inexact ingredient normally makes the result inexact |
| Complex | rectangular real/imaginary components | Zero imaginary part may canonicalize to a real; exact components/results remain exact when the operation is algebraic and representable |
| Reader/writer | R5RS §7.1.1 grammar | Radix and exactness prefixes commute; decimal `#e` is converted by decimal arithmetic, not through binary64; printed numbers read back equivalently |

## Storage transition invariants

- Cycle-capable Scheme objects register weakly with one interpreter heap registry.
- Collection is explicitly triggered only between evaluations. Roots include global/report environments, their macro tables, and conservatively pinned values exported through the public Swift API; collection cannot run while evaluator control, continuations, winds, or dynamic file state are active.
- Mark traverses every Scheme-bearing field, including enum-associated continuation frames owned by captured-continuation procedures. Persistent primitive closures are reachable from rooted report/global environments. Sweep clears outgoing Scheme edges of unmarked nodes, allowing ARC to reclaim cycles while leaving reachable identities unchanged.
- Publicly exported object graphs remain conservative host roots for the interpreter lifetime; this favors safety over reclaiming host-discarded values that Swift value copies cannot report. Scheme-created graphs that never escape the public result remain collectible.
- Test instrumentation exposes counts and an explicit safe-point collection trigger to Swift tests only; no non-R5RS Scheme primitive is added.
