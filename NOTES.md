# SwiftScheme PREP notes

## Normative decisions

- R5RS anchors: lexical conventions §2; types/external form/storage/tail recursion §3; core and derived expressions §4; programs/definitions §5; procedures §6; grammar §7.1.
- Use a trampoline-first evaluator. Retrofitting proper tail recursion after a recursive evaluator is the largest avoidable architecture risk.
- Scheme's storage model permits cyclic mutable graphs. Swift ARC alone is not a Scheme garbage collector. Cycle-capable runtime nodes are registered with an interpreter-owned tracer; safe-point collection marks from interpreter/evaluator/public-value roots and clears outgoing Scheme edges only on unreachable nodes. Lexical parents remain strong while their environments are reachable.
- Preserve aliasing through reference-backed pairs, strings, environments, and binding cells. Swift copy-on-write collections alone are insufficient.
- Keep the parser/evaluator API small and internal; expose enough through the library target for Swift Testing. No third-party packages.
- Use deterministic left-to-right application and initializer evaluation where R5RS leaves the order unspecified. Tests must not assert results R5RS leaves unspecified.
- Report unsupported surface explicitly: describe the implementation as a “R5RS-guided core,” not “R5RS-complete,” until every required feature is verified.

## CLI contract

- Build product: `swiftscheme`.
- `swiftscheme FILE`: read and evaluate every form in one environment; print only explicit Scheme output; diagnostics go to stderr; any read/evaluation error exits nonzero.
- No file argument: read stdin. Show `>` / continuation prompts only when stdin is a terminal; piped stdin stays machine-readable.
- REPL: print each specified result with external `write` notation, suppress `unspecified`, recover after a complete erroneous form, and continue collecting an incomplete multiline form.
- Treat more than one path or an unreadable file as a usage/I/O error. Add flags only when required.
- Smoke command: `swift run swiftscheme /tmp-or-workspace-fixture.scm`; keep fixtures inside the workspace during this lab.

## Test strategy

| Layer | Focused cases |
| --- | --- |
| Reader | comments/whitespace; identifier folding; adjacent forms; strings/escapes; quote sugar; nested and dotted lists; clean versus incomplete EOF; malformed tokens |
| Values/writer | proper/improper/cyclic pairs; string escaping; symbol spelling; `#f` truth boundary; structural equality terminates on cycles |
| Lexical state | shadowing; closure capture; mutation visible through closure; unbound `set!`; variadic/dotted formals; duplicate-formal rejection |
| Forms | branch laziness; begin order; define shorthand; let/let*/letrec distinctions; named let; short-circuiting; nested quasiquote/splicing |
| Procedures | zero/one/many-argument arithmetic; arity/type/domain errors; bignum/rational/complex operations; list and string boundaries; equality identity versus structure |
| Numeric grammar | every R5RS §7.1.1 prefix/radix/exactness/decimal/rational/rectangular/polar branch; writer/read-back equivalence |
| Numeric differential | overlapping Int64 oracle checks, huge algebraic identities, pinned Jaffer categories, and a reputable local Scheme oracle when installed |
| Storage | reachable cycles/closures/continuations and conservative public roots survive collection; non-exported unreachable cycle batches reduce live counts and stabilize under stress |
| Tail behavior | at least 200,000 tail iterations and mutual recursion without Swift stack growth |
| CLI | multi-form file, piped stdin without prompts, stdout/stderr separation, nonzero malformed-file exit |

Use table-driven Swift Testing helpers such as `eval(source) -> Value` and `assertPrinted(source, expected)`. Each supported primitive needs a success test and at least one arity/type boundary test. Run these commands at phase boundaries:

```sh
swift build
swift test
swift run swiftscheme Tests/Fixtures/smoke.scm
```

## External conformance inputs

The workspace supplied local Chibi-Scheme, Larceny/Jaffer, and Racket R5RS
trees during the audit, but they are uncommitted inputs intentionally absent from
the frozen candidate. This record therefore makes **no upstream pass/fail claim**
and does not refer to a license file that is absent from the candidate. If an
external suite becomes release evidence, add its pinned revision, license, adapter,
and unmodified-run output in a separately reviewed candidate.

No reputable Scheme executable was found in the current PATH during PREP
(`chibi-scheme`, `guile`, `racket`, `gosh`, and `scheme` were absent). Differential
evidence for this candidate is limited to native Swift Testing assertions,
fixtures explicitly marked open in the R5RS checklists, and pure-Swift
overlapping-range oracles unless that environment changes.
- Portable program fixture: iterative Fibonacci, recursive quicksort with internal definitions, hygienic macro use, and multiple values in `Tests/Fixtures/portable-programs.scm`.

## Review gates

- No Swift recursion remains on evaluator tail paths; the 200,000-call regression passes.
- Continuation jumps execute `dynamic-wind` exit/entry thunks in order.
- Macro assertions cover hygiene, definition-site references, nested/empty ellipses, and keyword-binding identity; dotted patterns and custom ellipses remain open in the R5RS checklist.
- `equal?`, `list?`, and printing terminate on cyclic pairs/vectors.
- Exact integer/rational operations are overflow-free and normalized; mixed exactness and complex branch behavior match the numeric coverage matrix.
- Reachable cycles and captured continuations survive tracing; unreachable cycle stress reduces and stabilizes the live-node count.
