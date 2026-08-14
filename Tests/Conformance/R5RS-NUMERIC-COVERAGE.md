# R5RS numeric coverage matrix

Normative source: `Reference/r5rs.pdf`, R5RS §6.2 and §7.1.1. Named regressions are in `Tests/SwiftSchemeTests/SwiftSchemeRegressionTests.swift`, `Tests/SwiftSchemeTests/BigIntKernelSelfTests.swift`, and `Tests/Fixtures/numeric-programs.scm`; `NOTES.md` records external revisions and exact outcomes.

| R5RS surface | Required cases | Regression/evidence |
|---|---|---|
| Exact integers | signs, arbitrary decimal magnitude, #b/#o/#d/#x, prefix order | `numeric-reader-integers`, BigInt overlap/huge identity tests |
| Exact rationals | normalization, negative denominator, zero rejection, arbitrary operands | `numeric-reader-rationals`, Jaffer number sections |
| Exact decimals | `#e1.25`, exponents, leading/trailing decimal point | `numeric-reader-exact-decimals` |
| Inexact reals | decimal point, `e/s/f/d/l` exponent markers, `#i`, digit placeholders, signed zero | `numeric-reader-inexact` |
| Rectangular complex | `a+bi`, `a-bi`, `+i`, `-i`, exact/inexact parts | `numeric-reader-rectangular` |
| Polar complex | `m@a`, exact/inexact components | `numeric-reader-polar` |
| Writer/string conversion | read-back equivalence in radices 2/8/10/16 | `numeric-roundtrip` |
| Tower predicates | number?/complex?/real?/rational?/integer?, exact?/inexact? | `numeric-predicates`, Chibi/Jaffer |
| Equality/order | exact cross-products, mixed exact/inexact, complex equality; real-only ordering | `numeric-comparison` |
| Arithmetic | +, -, *, / over integer/rational/real/complex; zero division | `numeric-arithmetic` |
| Numeric predicates | zero?, positive?, negative?, odd?, even? | `numeric-sign-parity` |
| Extremes/absolute | max, min exactness, abs complex magnitude | `numeric-extremes` |
| Integer division | quotient, remainder, modulo sign laws | `numeric-integer-division`, Jaffer |
| Number theory | gcd/lcm zero/sign/large operands | `numeric-gcd-lcm` |
| Rational access | numerator, denominator exactness behavior | `numeric-rational-accessors` |
| Approximation | rationalize exact/inexact examples and boundary intervals | `numeric-rationalize` |
| Rounding | floor, ceiling, truncate, round; exactness preserved | `numeric-rounding` |
| Transcendentals | exp/log/sin/cos/tan/asin/acos/atan real and complex | `numeric-transcendentals` |
| Roots/powers | exact perfect roots, exact integer powers, complex branches | `numeric-sqrt-expt` |
| Complex construction | make-rectangular/polar, real/imag, magnitude/angle | `numeric-complex-accessors` |
| Exactness conversion | exact->inexact and binary64 inexact->exact rationals/complex | `numeric-exactness-conversion` |
| External suites | no expectation edits | pinned Chibi 189; `NOTES.md` records the Larceny/Jaffer revision |
| Real programs | huge factorial/binomial/modular arithmetic, rational approximation, complex iteration | `Tests/Fixtures/numeric-programs.scm` |
