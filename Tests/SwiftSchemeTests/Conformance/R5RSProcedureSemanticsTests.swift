import SwiftScheme
import Testing

@MainActor private func r5rsValue(_ source: String) throws -> String {
  try Interpreter { _ in }.evaluate(source).written
}

@MainActor private func expectR5RSError(_ source: String, _ label: String) {
  do {
    _ = try Interpreter { _ in }.evaluate(source)
    #expect(Bool(false), "\(label): expected an error")
  } catch {
    // R5RS specifies the domain as erroneous, not a particular diagnostic.
  }
}

@Suite("R5RS required procedure semantics") @MainActor struct R5RSProcedureSemanticsTests {
  @Test("§6.1 equivalence predicates and §6.3 type predicates") func equivalenceAndTypes() throws {
    let result = try r5rsValue(
      """
      (list
        (eqv? #t #t) (eqv? 'a 'a) (eqv? 'a 'b) (eqv? 1 1.0)
        (eq? '() '()) (eq? car car) (eq? (list 'a) (list 'a))
        (equal? '(a (b) c) '(a (b) c)) (equal? "a" "a")
        (boolean? #f) (boolean? 0) (pair? '(a . b)) (null? '())
        (list? '(a b)) (list? '(a . b)) (symbol? 'a) (symbol? "a")
        (string? "a") (vector? '#(a)) (procedure? car))
      """
    )
    #expect(result == "(#t #t #f #f #t #t #f #t #t #t #f #t #t #t #f #t #f #t #t #t)")
  }

  @Test("§6.1 unspecified equivalence cases still return booleans")
  func unspecifiedEquivalenceCases() throws {
    #expect(
      try r5rsValue(
        "(and (boolean? (eqv? \"\" \"\")) " + "(boolean? (eqv? '#() '#())) "
          + "(boolean? (eqv? (lambda (x) x) (lambda (x) x))) "
          + "(boolean? (eq? 1 1)) (boolean? (eq? #\\a #\\a)))"
      ) == "#t"
    )
  }

  @Test("§6.5 eval rejects non-expression values with a syntax diagnostic")
  func evalRejectsNonExpressions() {
    do {
      _ = try Interpreter { _ in }.evaluate("(eval (current-input-port) (interaction-environment))")
      #expect(Bool(false), "eval unexpectedly accepted a port value")
    } catch let error as SchemeError {
      guard case .syntax(let message) = error else {
        #expect(Bool(false), "expected syntax error, got \(error)")
        return
      }
      #expect(message == "eval expects an expression")
    } catch { #expect(Bool(false), "expected SchemeError, got \(error)") }
  }

  @Test("§6.2 arithmetic, exactness, and numeric result classes") func arithmeticAndExactness()
    throws
  {
    let result = try r5rsValue(
      """
      (list
        (+) (*) (- 3) (/ 3) (+ 1/3 1/6) (/ 3 2)
        (max 3 4.0) (min 3 4.0) (quotient -13 4) (remainder -13 4)
        (modulo -13 4) (gcd) (lcm) (gcd 32 -36) (lcm 32 -36)
        (numerator 6/4) (denominator 6/4)
        (floor -1/2) (ceiling -1/2) (truncate -1/2) (round 5/2)
        (number->string (abs -0.0))
        (number? 1) (complex? 1) (real? 1) (rational? 1) (integer? 1)
        (exact? 1) (inexact? 1.0) (exact? 1+0i) (real? 1+0i))
      """
    )
    #expect(
      result == "(0 1 -3 1/3 1/2 3/2 4.0 3.0 -3 -1 3 0 1 4 288 3 2 -1 0 0 2 "
        + "\"0.0\" #t #t #t #t #t #t #t #t #t)"
    )
  }

  @Test("§6.2 numeric tower predicates are transitive") func numericTowerPredicates() throws {
    let result = try r5rsValue(
      """
      (list
        (complex? 1+2i) (real? 1+0i) (rational? 1+0i) (integer? 1+0i)
        (complex? 1.0+2.0i) (real? 1.0) (rational? 1.0) (integer? 1.0)
        (exact? 1/2) (inexact? (/ 1 2.0)) (exact? 1+2i) (inexact? 1.0+2.0i))
      """
    )
    #expect(result == "(#t #t #t #t #t #t #t #t #t #t #t #t)")
  }

  @Test("§6.2 rounding preserves exactness and uses nearest-even ties") func roundingContracts()
    throws
  {
    #expect(
      try r5rsValue("(list (round 1.5) (round 2.5) (round 3.5) (round -2.5))")
        == "(2.0 2.0 4.0 -2.0)"
    )
    #expect(
      try r5rsValue(
        "(list (inexact? (floor 1.5)) (inexact? (ceiling 1/2)) "
          + "(inexact? (truncate 1.5)) (inexact? (round 1.5)))"
      ) == "(#t #f #t #t)"
    )
  }

  @Test("§6.2 numeric domains and arities are diagnosed") func numericDomains() {
    let invalid = [
      "(+ 1 'x)", "(-)", "(/)", "(= 1)", "(< 1 2i)", "(positive? 1+2i)", "(odd? 1/2)", "(abs 1+2i)",
      "(quotient 1 0)", "(remainder 1 0)", "(modulo 1 0)", "(numerator 1+2i)",
      "(denominator 1/2.0)", "(floor 1+2i)", "(number->string 1 3)", "(string->number \"1\" 3)",
    ]
    for (index, source) in invalid.enumerated() {
      expectR5RSError(source, "numeric domain \(index)")
    }
  }

  @Test("§6.2 expt follows principal branches while preserving exact roots")
  func exactRationalExponent() throws {
    let result = try r5rsValue(
      "(list (expt 4 1/2) (expt 16 3/2) (expt -4 1/2) "
        + "(expt -8 1/3) (expt 27 2/3) (exact? (expt 4 1/2)))"
    )
    #expect(result == "(2 64 0+2i 1.0+1.732050807568877i 9 #t)")
  }

  @Test("§6.2 negative rational powers are principal complex values")
  func negativeRationalPowerBranches() throws {
    let result = try r5rsValue(
      "(list (real? (expt -8 1/3)) (exact? (expt -8 1/3)) " + "(number->string (expt -8 1/3)) "
        + "(number->string (expt -8 2/3)))"
    )
    #expect(
      result == "(#f #f \"1.0+1.732050807568877i\" " + "\"-1.999999999999999+3.464101615137754i\")"
    )
  }

  @Test("§6.2 complex and transcendental procedures") func complexProcedures() throws {
    let result = try r5rsValue(
      """
      (list
        (sqrt -9) (expt 2 -2) (make-rectangular 1 2)
        (real-part 3+4i) (imag-part 3+4i) (magnitude 3+4i)
        (= (exp 0) 1.0) (= (log 1) 0.0) (= (sin 0) 0.0)
        (= (cos 0) 1.0) (= (tan 0) 0.0) (= (asin 0) 0.0)
        (= (acos 1) 0.0) (= (atan 0) 0.0))
      """
    )
    #expect(result == "(0+3i 1/4 1+2i 3 4 5 #t #t #t #t #t #t #t #t)")
  }

  @Test("§6.3.3 symbol spelling follows the lower-case standard case") func symbolSpellingCase()
    throws
  {
    let result = try r5rsValue(
      "(list (symbol->string 'Martin) (symbol->string (string->symbol \"Malvina\")))"
    )
    #expect(result == "(\"Martin\" \"Malvina\")")
  }

  @Test("§6.3 pairs, lists, symbols, and mutation") func pairAndListProcedures() throws {
    let result = try r5rsValue(
      """
      (let ((p (cons 'a (list 'b 'c))))
        (set-car! p 'z)
        (set-cdr! p (list 'x 'y))
        (list (car p) (cdr p) (length p) (list-ref p 1)
          (append '(a) '(b c)) (reverse '(a b c))
          (memv 'b '(a b c)) (assoc 'b '((a . 1) (b . 2)))))
      """
    )
    #expect(result == "(z (x y) 3 x (a b c) (c b a) (b c) (b . 2))")
  }

  @Test("§6.3 list, string, and vector index domains") func aggregateDomains() {
    let invalid = [
      "(append)", "(length '(a . b))", "(reverse '(a . b))", "(append '(a . b) '())",
      "(list-tail '(a) -1)", "(list-tail '(a) 1/2)", "(list-tail '(a) 2)", "(list-ref '(a) -1)",
      "(list-ref '(a) 1/2)", "(list-ref '(a) 1)", "(memq 'a '(a . b))", "(assq 'a '((a . 1) . b))",
      "(make-string -1)", "(make-string 1/2)", "(string-ref \"a\" -1)", "(string-ref \"a\" 1/2)",
      "(string-ref \"a\" 1)", "(substring \"a\" 1 0)", "(substring \"a\" 0 2)",
      "(list->string '(#\\a . #\\b))", "(make-vector -1)", "(make-vector 1/2)",
      "(vector-ref '#(a) -1)", "(vector-ref '#(a) 1/2)", "(vector-ref '#(a) 1)",
      "(list->vector '(a . b))",
    ]
    for (index, source) in invalid.enumerated() {
      expectR5RSError(source, "aggregate domain \(index)")
    }
  }

  @Test("§6.3 composed pair selectors cover every required shape") func composedSelectors() throws {
    let selectors = [
      "caar", "cadr", "cdar", "cddr", "caaar", "caadr", "cadar", "caddr", "cdaar", "cdadr", "cddar",
      "cdddr", "caaaar", "caaadr", "caadar", "caaddr", "cadaar", "cadadr", "caddar", "cadddr",
      "cdaaar", "cdaadr", "cdadar", "cdaddr", "cddaar", "cddadr", "cdddar", "cddddr",
    ]
    for selector in selectors {
      var datum = "z"
      for operation in selector.dropFirst().dropLast() {
        datum = operation == "a" ? "(\(datum) . q)" : "(q . \(datum))"
      }
      #expect(try r5rsValue("(\(selector) '\(datum))") == "z")
    }
  }

  @Test("§6.3 character, string, and vector procedures") func characterStringVectorProcedures()
    throws
  {
    let result = try r5rsValue(
      """
      (let ((s (string #\\a #\\b)) (v (vector 1 2)))
        (string-set! s 1 #\\c)
        (vector-set! v 0 9)
        (list (char=? #\\A #\\A) (char-ci=? #\\A #\\a)
          (char-alphabetic? #\\a) (char-numeric? #\\1)
          (string-ref s 1) (string->list s) (list->string '(#\\x #\\y))
          (string-append s "d") (vector-length v) (vector-ref v 0)
          (vector->list v) (list->vector '(x y))))
      """
    )
    #expect(result == "(#t #t #t #t #\\c (#\\a #\\c) \"xy\" \"acd\" 2 9 (9 2) #(x y))")
  }

  @Test("§6.4 control, eval, and multiple values") func controlProcedures() throws {
    let result = try r5rsValue(
      """
      (list
        (apply + '(1 2 3))
        (map + '(1 2) '(3 4))
        (let ((v (vector 0 0)))
          (for-each (lambda (x) (vector-set! v x x)) '(0 1)) v)
        (call-with-values (lambda () (values 2 3)) +)
        (eval '(+ 20 22) (scheme-report-environment 5))
        (force (delay (+ 1 2))))
      """
    )
    #expect(result == "(6 (4 6) #(0 1) 5 42 3)")
  }

  @Test("§6.4 multiple-value arity and ignored wind results") func multipleValueContracts() throws {
    #expect(
      try r5rsValue(
        "(list (call-with-values (lambda () (values)) (lambda () 7)) "
          + "(call-with-values (lambda () (values 1 2)) (lambda (a b) (list b a))) "
          + "(for-each (lambda (x) (values x (+ x 1))) '(1 2)) "
          + "(dynamic-wind (lambda () (values 1 2)) (lambda () 9) " + "(lambda () (values 3 4))))"
      ) == "(7 (2 1) #<unspecified> 9)"
    )
    expectR5RSError("(map (lambda (x) (values x (+ x 1))) '(1 2))", "map callback multiple values")
    expectR5RSError("(let ((x (values 1 2))) x)", "multiple values in single-value context")
  }

  @Test("§6.6 ports and external representations") func portProcedures() throws {
    let result = try r5rsValue(
      """
      (list
        (call-with-input-string " 1" (lambda (p) (read p)))
        (call-with-input-string "ab" (lambda (p) (list (read-char p) (peek-char p) (read-char p))))
        (call-with-output-string
          (lambda (p) (write 'a p) (display "b" p) (newline p)))
        (eof-object? (call-with-input-string "" read)))
      """
    )
    #expect(result == "(1 (#\\a #\\b #\\b) \"ab\n\" #t)")
  }
}
