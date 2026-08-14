# R5RS numeric coverage checklist

**Normative source:** `Reference/r5rs.pdf`, §§6.2 and 7.1.1 (printed pp. 19-25
and 38-39). Its SHA-256 is
`09b71fe4373610d763e86a728ec80146e391a1cd9c00341364200ce3b2e2bc97`.

This is an evidence map, not a completeness claim. The current package has the
broad Swift Testing suites plus the focused `R5RSNumericTests` grammar matrix.
The labels below are assertion labels inside those tests or explicitly named open
fixtures; they are not invented test identifiers.

| Status | R5RS surface | Current Swift Testing evidence | Remaining footprint / decision |
|---|---|---|---|
| `[~]` | Exact integers: signs, arbitrary decimal magnitude, `#b/#o/#d/#x`, prefix order | `R5RSNumericTests.radixPlaceholders` and `validNumericForms`; `numeric library`; `arbitrary exact integer`; BigInt kernel `arithmetic, division, radix, and conversion invariants` | Full arbitrary-radix boundary/error matrix remains open. |
| `[~]` | Exact rationals: normalization, negative denominator, zero rejection, arbitrary operands | `rational and complex arithmetic`; `exact literals` | Add direct denominator/sign/zero and reader error cases. |
| `[~]` | Exact decimals: `#e1.25`, exponents, leading/trailing decimal point | `exact literals` | Exponent and decimal-point branches are not separately asserted. |
| `[~]` | Inexact reals: decimal point, `e/s/f/d/l` suffixes, `#i`, placeholders, signed zero | `R5RSNumericTests.radixPlaceholders`, `validNumericForms`, and malformed forms; `round ties to even`; `integer procedures accept inexact integers` | Signed zero, infinity, and NaN conventions remain open; do not infer coverage from the parser alone. |
| `[~]` | Rectangular complex: `a+bi`, `a-bi`, `+i`, `-i`, exact/inexact parts | `R5RSNumericTests.validNumericForms`; `rational and complex arithmetic`; `numeric reader consumes complete datum`; `exact complex number string round trip` | Add full mixed-component and malformed-token branches. |
| `[~]` | Polar complex: `m@a`, exact/inexact components | `R5RSNumericTests.validNumericForms` asserts a polar datum is a complex value | Add writer/construction/accessor and domain cases. |
| `[~]` | Writer/string conversion and radix 2/8/10/16 read-back | `R5RSNumericTests` grammar tables; `numeric library`; `bignum number string round trip`; BigInt kernel radix invariants | Add a complete round-trip matrix for every numeric kind. |
| `[~]` | Tower predicates: `number?` through `integer?`, `exact?`, `inexact?` | `integer procedures accept inexact integers`; `exact numeric result tags` | Add the full predicate cross-product and disjointness cases. |
| `[~]` | Equality/order: exact cross-products, mixed exact/inexact, complex equality, real-only ordering | `mixed exact binary64 comparisons`; numeric assertions in `rational and complex arithmetic` | Add complex equality and non-real ordering rejection cases. |
| `[~]` | Arithmetic: `+`, `-`, `*`, `/` over integer/rational/real/complex; zero division | `numeric library`; `rational and complex arithmetic`; `division by zero` | Add arity, type, domain, and all exactness combinations. |
| `[~]` | Numeric predicates: `zero?`, `positive?`, `negative?`, `odd?`, `even?` | `integer procedures accept inexact integers` | Add negative, zero, non-integer, and complex-domain cases. |
| `[~]` | Extremes/absolute: `max`, `min`, exactness, complex `abs`/magnitude | `exact square roots and magnitudes` | Add `max`/`min` exactness and mixed-domain cases. |
| `[~]` | Integer division: `quotient`, `remainder`, `modulo` sign laws | `numeric library`; `integer procedures accept inexact integers`; BigInt kernel division invariants | Add the complete sign/zero/arity matrix. |
| `[~]` | Number theory: `gcd`, `lcm`, zero/sign/large operands | `numeric library`; BigInt kernel `huge gcd` assertion | Add zero and mixed exactness cases. |
| `[~]` | Rational access: `numerator`, `denominator` exactness/error behavior | Numeric library paths plus procedure inventory | Add accessor normalization, type, and arity cases. |
| `[~]` | Approximation: `rationalize` examples and boundary intervals | `R5RSNumericTests.rationalizeExactIntervals`, `rationalizeInexactIntervals`, and `rationalizeToleranceBoundaries` | Broaden the interval matrix, including additional exactness and boundary cases, before claiming complete coverage. |
| `[~]` | Rounding: `floor`, `ceiling`, `truncate`, `round`, exactness | `round ties to even`; `exact numeric results` | Add negative, inexact, and complex-domain cases. |
| `[~]` | Transcendentals: `exp`, `log`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan` | Registered and implemented numeric primitive paths; procedure inventory | Add real/complex branch, domain, and special-value cases. |
| `[~]` | Roots/powers: exact perfect roots, integer powers, complex branches | `exact square roots and magnitudes`; `exact numeric results`; `R5RSNumericTests.exptZeroAndExactIntegerComplexExponent` (zero-base rule and exact complex integer exponent) | Add non-perfect roots, negative powers, and complex branch cases. |
| `[~]` | Complex construction/accessors: `make-rectangular`, `make-polar`, `real-part`, `imag-part`, `magnitude`, `angle` | `exact square roots and magnitudes` covers magnitude only | Add constructor/accessor and polar angle coverage. |
| `[~]` | Exactness conversion: `exact->inexact`, `inexact->exact` for real/complex values | Registered and implemented numeric primitive paths; procedure inventory | Add binary64 boundary, complex, and error cases. |
| `[N/A]` | External upstream suites | Chibi/Larceny/Racket trees were local uncommitted audit inputs and are intentionally absent from this frozen candidate; no upstream result is claimed here | If these suites become release evidence, add them in a separately reviewed/vetted candidate with license and revision records. |
| `[~]` | Numeric real programs: factorial, rational approximation, complex iteration | `R5RSNumericTests.numericProgramsFixture` executes `Tests/Fixtures/numeric-programs.scm` and asserts its complete captured output | This fixture is executable evidence for one program; add independent programs and edge-case outputs before claiming complete coverage. |

## Reader grammar page anchors

- R5RS §7.1.1, **Lexical structure**, starts on printed p. 38 and continues on
  p. 39; numeric prefixes, decimal forms, and complex forms are in this grammar.
- R5RS §7.1.2, **External representations**, is on printed p. 39.
- The language-library procedure descriptions remain in §6.2, printed pp. 19-25.

## Evidence policy

A registered procedure or a fixture is not a passing conformance assertion. Each
required procedure needs a Swift Testing assertion that checks permitted result,
exactness, arity/type/domain errors, and any unspecified behavior without
asserting an R5RS-unspecified value. Vendored suites, when present only as local
uncommitted inputs, are audit context and never substitute for native tests.
