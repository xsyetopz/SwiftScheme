import Foundation
import SwiftScheme
import Testing

@MainActor private func r5rsEvaluate(_ source: String) throws -> Value {
  try Interpreter { _ in }.evaluate(source)
}

@MainActor private func r5rsExpectError(_ source: String, _ label: String) throws {
  do {
    _ = try r5rsEvaluate(source)
    #expect(Bool(false), "\(label): expected SchemeError")
  } catch is SchemeError {}
}

@Suite("R5RS §7.1.1 numeric and external-form grammar") struct R5RSNumericTests {
  @Test("abs accepts real numbers and rejects complex numbers") @MainActor func absDomain() throws {
    #expect(try r5rsEvaluate("(abs -3)").written == "3")
    #expect(try r5rsEvaluate("(abs -3.5)").written == "3.5")
    try r5rsExpectError("(abs 1+2i)", "abs complex domain")
    do {
      _ = try r5rsEvaluate("(/ 1 #t)")
      #expect(Bool(false), "division type error: expected SchemeError")
    } catch let error as SchemeError { #expect(error.description.contains("expected number")) }
  }

  @Test("numeric external representations preserve complex signs and specials") @MainActor
  func numericExternalBoundaries() throws {
    #expect(try r5rsEvaluate("(number->string 1-0.0i)").written == "\"1-0.0i\"")
    #expect(try r5rsEvaluate("(string->number (number->string 1-0.0i))").written == "1-0.0i")
    #expect(try r5rsEvaluate("(string->number (number->string +inf.0))").written == "+inf.0")
    #expect(try r5rsEvaluate("(string->number (number->string +nan.0))").written == "+nan.0")
    #expect(
      try r5rsEvaluate("(number->string (string->number \"1+nan.0i\"))").written == "\"1+nan.0i\""
    )
  }

  @Test("exact unit bases preserve arbitrary exact exponents") @MainActor
  func arbitraryExactExponents() throws {
    let cases = [
      ("(expt 1 9223372036854775808)", "1"), ("(expt 1 1/9223372036854775808)", "1"),
      ("(expt -1 9223372036854775808)", "1"), ("(expt -1 -9223372036854775808)", "1"),
      ("(expt -1 18446744073709551617/2)", "0+1i"),
    ]
    for (source, expected) in cases {
      #expect(try r5rsEvaluate(source).written == expected)
      #expect(try r5rsEvaluate("(exact? \(source))").written == "#t")
    }
    try r5rsExpectError("(expt 2 9223372036854775808)", "unrepresentable exact exponent")
    try r5rsExpectError("(expt 2 -9223372036854775808)", "minimum exact exponent")
  }

  @Test("exact rational accessors normalize signs and reject zero denominators") @MainActor
  func rationalAccessorBoundaries() throws {
    let result = try r5rsEvaluate(
      "(list (/ 6 -4) (numerator -3/2) (denominator -3/2) "
        + "(denominator (exact->inexact 3/2)) (string->number \"1/0\") "
        + "(string->number \"1/-2\"))"
    )
    #expect(result.written == "(-3/2 -3 2 2.0 #f #f)")
  }

  @Test("numeric tower predicates distinguish exactness and finite real values") @MainActor
  func numericPredicateCrossProduct() throws {
    let result = try r5rsEvaluate(
      "(list (number? 1+2i) (complex? 1) (real? 1+0.0i) "
        + "(rational? 1.0) (rational? +inf.0) (integer? 3.0) "
        + "(integer? 3.5) (exact? 1+2i) (inexact? 1+2.0i))"
    )
    #expect(result.written == "(#t #t #t #t #f #t #f #t #t)")
  }

  @Test("complex constructors and accessors preserve principal values") @MainActor
  func complexConstructionAccessors() throws {
    let result = try r5rsEvaluate(
      "(list (make-rectangular 3 4) (real-part 3+4i) (imag-part 3+4i) "
        + "(magnitude 3+4i) (real-part (make-polar 2 0)) " + "(complex? (make-polar 2 1/2)) "
        + "(= (angle -1) 3.141592653589793))"
    )
    #expect(result.written == "(3+4i 3 4 5 2 #t #t)")
  }

  @Test("positive and negative predicates reject NaN") @MainActor func nanSignPredicates() throws {
    let result = try r5rsEvaluate("(list (positive? +nan.0) (negative? +nan.0))")
    #expect(result.written == "(#f #f)")
  }

  @Test("radix placeholders are accepted and remain inexact") @MainActor func radixPlaceholders()
    throws
  {
    let cases: [(literal: String, written: String)] = [
      ("#b1#", "2.0"), ("#i#b1#", "2.0"), ("#b#i1#", "2.0"), ("#o7#", "56.0"), ("#d12#", "120.0"),
      ("#xF#", "240.0"), ("#xF##", "3840.0"), ("1#", "10.0"), ("1##", "100.0"), (".1#", "0.1"),
      ("1.#", "1.0"), ("1#.", "10.0"), ("1#.#", "10.0"), ("1.2#", "1.2"), ("1#e2", "1000.0"),
      ("#b1#/1", "2.0"), ("#xF#/A#", "1.5"), ("1+2#i", "1+20.0i"),
    ]
    for item in cases {
      let value = try r5rsEvaluate(item.literal)
      #expect(value.written == item.written, "\(item.literal): unexpected value \(value.written)")
      if case .real = value {
        #expect(try r5rsEvaluate("(inexact? \(item.literal))").written == "#t")
      } else if item.literal.contains("i") {
        #expect(try r5rsEvaluate("(inexact? \(item.literal))").written == "#t")
      } else {
        #expect(Bool(false), "\(item.literal): expected a real value")
      }
    }
  }

  @Test("decimal, rational, and complex placements follow the grammar") @MainActor
  func validNumericForms() throws {
    let exact: [(String, String)] = [
      ("0", "0"), ("+12", "12"), ("-12", "-12"), ("1/2", "1/2"), ("#e1.0", "1"), ("#e1e2", "100"),
      ("#e1e-2", "1/100"), ("1+2i", "1+2i"), ("1+i", "1+1i"), ("-1-i", "-1-1i"), ("+i", "0+1i"),
      ("-i", "0-1i"), ("#b1+1i", "1+1i"), ("#o7/7", "1"), ("#xF/A", "3/2"),
    ]
    for (literal, written) in exact {
      let value = try r5rsEvaluate(literal)
      #expect(value.written == written, "\(literal): unexpected value \(value.written)")
      #expect(try r5rsEvaluate("(exact? \(literal))").written == "#t")
    }

    let inexact: [(String, String)] = [
      ("1.0", "1.0"), (".5", "0.5"), ("1.", "1.0"), ("1e2", "100.0"), ("1e-2", "0.01"),
      ("1.2e+2", "120.0"), ("#i1", "1.0"), ("#i1/2", "0.5"), ("#i+i", "0+1.0i"),
      ("#i1+i", "1.0+1.0i"), ("#i1-i", "1.0-1.0i"), ("1e+2+3i", "100.0+3i"), ("1+2.0i", "1+2.0i"),
      ("+1.0i", "0+1.0i"),
    ]
    for (literal, written) in inexact {
      let value = try r5rsEvaluate(literal)
      #expect(value.written == written, "\(literal): unexpected value \(value.written)")
      #expect(try r5rsEvaluate("(inexact? \(literal))").written == "#t")
    }

    let polar = try r5rsEvaluate("1@2")
    if case .complex = polar {
      #expect(Bool(true))
    } else {
      #expect(Bool(false), "polar form must produce a complex number")
    }
  }

  @Test("invalid placeholder, exponent, and component placements are rejected") @MainActor
  func invalidNumericForms() throws {
    let invalid = [
      "1e#", "1e2#", "1e+2#", "#e1#", "#e1e#", "#e1e2#", "1#2", "1.#2", "1#.#2", ".#", "#.", "1##2",
      "1.0/2", "1/2.0", "1e2/3", "1/2e3", "1+2#3i", "1++2i", "1+-2i", "1@2@3", "1@2i", "i", "#b1.0",
      "#o7.0", "#xF.0", "#b1e2", "#b#b1", "#e#e1", "#i#i1", "#b#x1", "#e#b1#",
    ]
    for literal in invalid { try r5rsExpectError(literal, literal) }
    try r5rsExpectError("(rationalize 1 -1)", "negative rationalize tolerance")
  }

  @Test("rationalize returns simplest exact rationals in bounded intervals") @MainActor
  func rationalizeExactIntervals() throws {
    let cases: [(expression: String, written: String)] = [
      ("(rationalize (inexact->exact .3) 1/10)", "1/3"), ("(rationalize 3/5 1/10)", "1/2"),
      ("(rationalize 2/7 1/5)", "1/3"), ("(rationalize -3/5 1/10)", "-1/2"),
      ("(rationalize -2/7 1/5)", "-1/3"), ("(rationalize 0 0)", "0"), ("(rationalize 0 1/10)", "0"),
      ("(rationalize 1/3 0)", "1/3"), ("(rationalize 1/2 1/2)", "0"),
    ]
    for item in cases {
      #expect(
        try r5rsEvaluate(item.expression).written == item.written,
        "\(item.expression): unexpected value"
      )
      #expect(try r5rsEvaluate("(exact? \(item.expression))").written == "#t")
    }
  }

  @Test("rationalize preserves inexactness while staying inside its tolerance") @MainActor
  func rationalizeInexactIntervals() throws {
    let cases: [(expression: String, target: String, tolerance: String, written: String)] = [
      ("(rationalize .3 1/10)", "1/3", "1/10", "0.3333333333333333"),
      ("(rationalize 0.3 0.1)", "1/3", "0.1", "0.3333333333333333"),
      ("(rationalize -0.3 0.1)", "-1/3", "0.1", "-0.3333333333333333"),
      ("(rationalize 1 0.0)", "1", "0", "1.0"),
    ]
    for item in cases {
      let value = try r5rsEvaluate(item.expression)
      #expect(value.written == item.written, "\(item.expression): unexpected value")
      #expect(try r5rsEvaluate("(inexact? \(item.expression))").written == "#t")
      #expect(
        try r5rsEvaluate("(<= (abs (- \(item.expression) \(item.target))) \(item.tolerance))")
          .written == "#t",
        "\(item.expression): result must stay within tolerance"
      )
    }
  }

  @Test("rationalize accepts zero tolerance and rejects negative or non-real tolerance") @MainActor
  func rationalizeToleranceBoundaries() throws {
    let zeroTolerance: [(expression: String, written: String)] = [
      ("(rationalize 1 0)", "1"), ("(rationalize -1 0)", "-1"), ("(rationalize 1 0.0)", "1.0"),
    ]
    for item in zeroTolerance { #expect(try r5rsEvaluate(item.expression).written == item.written) }

    let invalid = [
      ("(rationalize 1 -1)", "negative exact tolerance"),
      ("(rationalize 1 -1/10)", "negative rational tolerance"),
      ("(rationalize 1 -0.1)", "negative inexact tolerance"),
      ("(rationalize 1+2i 1/10)", "complex value"), ("(rationalize 1 1+2i)", "complex tolerance"),
      ("(rationalize 1)", "missing tolerance"), ("(rationalize 1 1 1)", "extra tolerance"),
    ]
    for (expression, label) in invalid { try r5rsExpectError(expression, label) }
  }

  @Test("expt follows zero-base and exact-integer exponent rules") @MainActor
  func exptZeroAndExactIntegerComplexExponent() throws {
    let result = try r5rsEvaluate(
      "(list (expt 0 -1) (expt 0 1/2) (expt 0 0) (expt 0 0+0i) "
        + "(expt 0.0 1) (expt 0.0 0.0) (expt 2 3+0i) " + "(exact? (expt 2 3+0i)))"
    )
    #expect(result.written == "(0 0 1 1 0.0 1.0 8 #t)")
  }

  @Test("radix arguments accept exact complex integers") @MainActor
  func radixAcceptsExactComplexInteger() throws {
    let result = try r5rsEvaluate("(list (number->string 255 16+0i) (string->number \"ff\" 16+0i))")
    #expect(result.written == "(\"ff\" 255)")
  }

  @Test("string->number keeps the default radix after an exactness prefix") @MainActor
  func stringNumberHonorsDefaultRadixWithExactnessPrefix() throws {
    let result = try r5rsEvaluate(
      "(list (string->number \"#e11/10\" 2) " + "(string->number \"#i11/10\" 2) "
        + "(string->number \"#e1.5\" 2) " + "(string->number \"#i1.5\" 2) "
        + "(string->number \"#b11/10\" 16))"
    )
    #expect(result.written == "(3/2 1.5 #f #f 3/2)")
  }

  @Test("principal square root handles negative infinity") @MainActor
  func squareRootNegativeInfinity() throws {
    #expect(try r5rsEvaluate("(number->string (sqrt -inf.0))").written == "\"0.0+inf.0i\"")
    #expect(try r5rsEvaluate("(number->string (sqrt -inf.0-0.0i))").written == "\"0.0+inf.0i\"")
    #expect(try r5rsEvaluate("(number->string (sqrt -4.0-0.0i))").written == "\"0.0+2.0i\"")
    #expect(
      try r5rsEvaluate("(number->string (sqrt -1-2i))").written
        == "\"0.7861513777574233-1.272019649514069i\""
    )
  }

  @Test("infinite powers preserve real and principal complex limits") @MainActor
  func infinitePowerBranches() throws {
    let result = try r5rsEvaluate(
      "(list (number->string (expt +inf.0 -2)) " + "(number->string (expt -inf.0 0.5)) "
        + "(number->string (expt -inf.0 1.5)))"
    )
    #expect(result.written == "(\"0.0\" \"0.0+inf.0i\" \"0.0-inf.0i\")")
  }

  @Test("complex atan preserves principal branch signs") @MainActor func complexAtanBranches()
    throws
  {
    #expect(
      try r5rsEvaluate("(number->string (atan +2i))").written
        == "\"1.5707963267948966+0.5493061443340549i\""
    )
    #expect(
      try r5rsEvaluate("(number->string (atan -2i))").written
        == "\"-1.5707963267948966-0.5493061443340549i\""
    )
    #expect(
      try r5rsEvaluate("(number->string (asin 2+0.1i))").written
        == "\"1.5131571227434844+1.3188765472108999i\""
    )
  }

  @Test("finite complex branches avoid avoidable binary64 overflow") @MainActor
  func stableComplexBranches() throws {
    let result = try r5rsEvaluate(
      """
      (list (number->string (sqrt 1e308+1e308i))
            (number->string (log 1.7976931348623157e308+1.7976931348623157e308i))
            (number->string (tan 1e308+1e308i))
            (number->string (/ 1.0+1.0i 1e308+1e308i))
            (number->string (/ 1e308+1e308i 1e-308+1e-308i))
            (number->string (expt 1e308+1e308i 2))
            (number->string (asin 1e8+1e8i)))
      """
    )
    #expect(
      result.written == "(\"1.0986841134678101e+154+4.5508986056222734e+153i\" "
        + "\"710.1292864836639+0.7853981633974483i\" "
        + "\"0.0+1.0i\" \"1.0e-308+0.0i\" \"+inf.0+0.0i\" "
        + "\"0.0+inf.0i\" \"0.7853981633974483+19.46040151479228i\")"
    )
  }

  @Test("complex division keeps zero numerators zero when denominator products underflow")
  @MainActor func stableComplexZeroQuotient() throws {
    #expect(
      try r5rsEvaluate("(number->string (/ 0.0+0.0i 1e-308+1e-308i))").written == "\"0.0+0.0i\""
    )
    #expect(
      try r5rsEvaluate("(number->string (/ -0.0-0.0i 1e-308+1e-308i))").written == "\"-0.0-0.0i\""
    )
  }

  @Test("real-valued complex literals stay in real transcendental domains") @MainActor
  func realComplexTranscendentalDomain() throws {
    let result = try r5rsEvaluate(
      "(list (number->string (sin 1+0i)) " + "(number->string (log 1+0i)) " + "(real? (log -1+0i)))"
    )
    #expect(result.written == "(\"0.8414709848078965\" \"0.0\" #f)")
  }

  @Test("make-polar preserves inexactness from a zero angle") @MainActor
  func polarZeroAngleExactness() throws {
    #expect(try r5rsEvaluate("(exact? (make-polar 1 0))").written == "#t")
    #expect(try r5rsEvaluate("(exact? (make-polar 1 0.0))").written == "#f")
  }

  @Test("inexact integer powers preserve known real domains") @MainActor
  func inexactIntegerPowersStayReal() throws {
    let result = try r5rsEvaluate(
      "(list (real? (expt -8 2.0)) (number->string (expt -8 2.0)) "
        + "(real? (expt -8 1.0)) (number->string (expt -8 1.0)))"
    )
    #expect(result.written == "(#t \"64.0\" #t \"-8.0\")")
  }

  @Test("string->number skips atmosphere before radix and exactness prefixes") @MainActor
  func stringNumberSkipsLeadingAtmosphere() throws {
    let result = try r5rsEvaluate(
      """
      (list (string->number " 11" 2)
            (string->number " #x1" 2)
            (string->number " #e11" 2)
            (string->number ";comment
      11" 2))
      """
    )
    #expect(result.written == "(3 1 3 3)")
  }

  @Test("finite inexact number->string values round-trip in non-decimal radices") @MainActor
  func numberStringFiniteInexactNonDecimalRoundTrips() throws {
    let result = try r5rsEvaluate(
      "(let ((roundtrip (lambda (value radix) " + "(let ((text (number->string value radix))) "
        + "(list (eqv? value (string->number text radix)) "
        + "(inexact? (string->number text radix))))))) "
        + "(list (roundtrip 1.5 2) (roundtrip 1.5 8) " + "(roundtrip 1.5 16) (roundtrip 0.5 2)))"
    )
    #expect(result.written == "((#t #t) (#t #t) (#t #t) (#t #t))")
  }

  @Test("finite inexact radix output preserves binary64 boundaries") @MainActor
  func numberStringFiniteInexactBoundaryRoundTrips() throws {
    let result = try r5rsEvaluate(
      """
      (let ((roundtrip (lambda (value radix)
                         (let ((text (number->string value radix)))
                           (list (eqv? value (string->number text radix))
                                 (inexact? (string->number text radix)))))))
        (list (roundtrip 5e-324 2)
              (roundtrip -5e-324 8)
              (roundtrip 5e-324 16)
              (roundtrip 2.2250738585072014e-308 2)
              (roundtrip 1.7976931348623157e308 8)
              (roundtrip -1.7976931348623157e308 16)))
      """
    )
    #expect(result.written == "((#t #t) (#t #t) (#t #t) (#t #t) (#t #t) (#t #t))")
  }

  @Test("decimal inexact number->string output keeps a decimal point in exponent form") @MainActor
  func numberStringScientificFiniteValues() throws {
    let result = try r5rsEvaluate(
      "(let ((roundtrip (lambda (value) " + "(let ((text (number->string value))) "
        + "(list text (eqv? value (string->number text))))))) "
        + "(list (roundtrip 1e20) (roundtrip 1e-5) "
        + "(roundtrip 5e-324) (roundtrip -1.7976931348623157e308)))"
    )
    #expect(
      result.written == "((\"1.0e+20\" #t) (\"1.0e-05\" #t) "
        + "(\"5.0e-324\" #t) (\"-1.7976931348623157e+308\" #t))"
    )
  }

  @Test("exact->inexact rounds large integers to the nearest binary64 value") @MainActor
  func exactToInexactRoundsLargeIntegers() throws {
    let result = try r5rsEvaluate(
      "(list (eqv? (exact->inexact 9007199254740993) 9007199254740992.0) "
        + "(eqv? (exact->inexact 18014398509481987) 18014398509481988.0) "
        + "(eqv? (exact->inexact -18014398509481987) -18014398509481988.0))"
    )
    #expect(result.written == "(#t #t #t)")
  }

  @Test("signed-zero branch cuts stay inside the R5RS angle range") @MainActor
  func signedZeroBranchCuts() throws {
    let result = try r5rsEvaluate(
      """
      (let ((pi 3.141592653589793))
        (and (> (angle -0.0-0.0i) (- pi))
             (<= (angle -0.0-0.0i) pi)
             (> (atan -0.0 -0.0) (- pi))
             (<= (atan -0.0 -0.0) pi)
             (> (imag-part (log -0.0-0.0i)) (- pi))
             (<= (imag-part (log -0.0-0.0i)) pi)))
      """
    )
    #expect(result.written == "#t")
  }

  @Test("inverse trigonometric functions keep real arguments in their real domain") @MainActor
  func inverseTrigRealDomain() throws {
    #expect(try r5rsEvaluate("(number->string (asin 0.5))").written == "\"0.5235987755982988\"")
    #expect(try r5rsEvaluate("(number->string (acos 0.5))").written == "\"1.0471975511965976\"")
    #expect(try r5rsEvaluate("(real? (atan 0.1))").written == "#t")
    #expect(try r5rsEvaluate("(number->string (atan 0.1))").written == "\"0.09966865249116204\"")
    #expect(try r5rsEvaluate("(number->string (atan +inf.0))").written == "\"1.5707963267948966\"")
  }

  @Test("real transcendental overflow retains a real external form") @MainActor
  func transcendentalOverflowRetainsRealDomain() throws {
    let result = try r5rsEvaluate("(list (real? (exp 1000)) (number->string (exp 1000)))")
    #expect(result.written == "(#t \"+inf.0\")")
  }

  @Test("numeric-programs fixture captures its complete output") @MainActor
  func numericProgramsFixture() throws {
    let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
        "Fixtures/numeric-programs.scm"
      )
    let source = try String(contentsOf: fixtureURL, encoding: .utf8)
    var captured = ""
    let interpreter = Interpreter { captured += $0 }
    _ = try interpreter.evaluate(source)

    let expected =
      "(933262154439441526816992388562667004907159682643816214685929638952175999932299156089414"
      + "63976156518286253697920827223758251185210916864000000000000000000000000 41/42 "
      + "12345678901234567899-1493827147049382714249/77i #t #t #t 500000000000000000000 "
      + "0.3333333333333333)\n"
    #expect(captured == expected)
  }

  @Test("reserved lexical characters are not identifiers") @MainActor func reservedCharacters()
    throws
  {
    for character in ["[", "]", "{", "}", "|"] {
      try r5rsExpectError(character, character)
      try r5rsExpectError("name\(character)", "name\(character)")
    }
  }

  @Test("malformed numeric-looking tokens fail without rejecting valid identifiers") @MainActor
  func invalidVersusSymbolDiagnostics() throws {
    for token in [
      "+foo", "-foo", ".foo", ".", "..", "...foo", "@", "foo#bar", "foo\\bar", "λ", "a'b", "a`b",
      "a,b",
    ] { try r5rsExpectError(token, token) }
    for token in ["+", "-", "...", "foo+bar", "foo-bar", "foo.bar", "foo@bar", "!", "_"] {
      let value = try r5rsEvaluate("'\(token)")
      if case .symbol = value {
        #expect(Bool(true))
      } else {
        #expect(Bool(false), "\(token): expected an identifier symbol")
      }
    }
  }

  @Test("string external forms use only R5RS escapes and preserve newlines") @MainActor
  func stringExternalForms() throws {
    for control in ["\n", "\r", "\t"] {
      let source = "\"line one\(control)line two\""
      let value = try r5rsEvaluate(source)
      #expect(value.written == source, "raw string control must round-trip: \(control.utf8)")
    }

    let escaped = "\"quote: \\\" and slash: \\\\\""
    let escapedValue = try r5rsEvaluate(escaped)
    #expect(escapedValue.written == escaped)

    for escape in ["n", "r", "t"] {
      let value = try r5rsEvaluate("\"bad\\\(escape)escape\"")
      #expect(value.written == "\"bad" + String([escape == "n" ? "\n" : escape == "r" ? "\r" : "\t"]) + "escape\"")
    }
    try r5rsExpectError("\"bad\\aescape\"", "\\a escape")
  }
}
