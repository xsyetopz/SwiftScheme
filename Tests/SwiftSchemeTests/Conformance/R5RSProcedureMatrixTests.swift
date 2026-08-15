import Foundation
import SwiftScheme
import Testing

@MainActor private func matrixEvaluate(_ source: String, input: String = "") throws -> Value {
  try Interpreter(output: { _ in }, input: input).evaluate(source)
}

private func selectorInput(_ name: String) -> String {
  var result = "1"
  for operation in name.dropFirst().dropLast() {
    result = operation == "a" ? "(\(result))" : "(0 . \(result))"
  }
  return result
}

@Suite("R5RS required procedure semantic matrix") @MainActor struct R5RSProcedureMatrixTests {
  @Test("§6.1 and §6.2 required procedures have representative valid contracts")
  func equivalenceAndNumericMatrix() throws {
    let cases: [(String, String)] = [
      ("(eq? 'a 'a)", "#t"), ("(eqv? 1 1)", "#t"), ("(equal? '(a (b)) '(a (b)))", "#t"),
      ("(number? 1)", "#t"), ("(complex? 1)", "#t"), ("(real? 1)", "#t"), ("(rational? 1/2)", "#t"),
      ("(integer? 1)", "#t"), ("(exact? 1)", "#t"), ("(inexact? 1.0)", "#t"), ("(= 1 1 1)", "#t"),
      ("(< 1 2 3)", "#t"), ("(> 3 2 1)", "#t"), ("(<= 1 1 2)", "#t"), ("(>= 2 2 1)", "#t"),
      ("(zero? 0)", "#t"), ("(positive? 1)", "#t"), ("(negative? -1)", "#t"), ("(odd? 3)", "#t"),
      ("(even? 4)", "#t"), ("(max 1 3 2)", "3"), ("(min 1 3 2)", "1"), ("(+ 1 2 3)", "6"),
      ("(*)", "1"), ("(- 3 1 1)", "1"), ("(/ 8 2 2)", "2"), ("(abs -3)", "3"),
      ("(quotient -13 4)", "-3"), ("(remainder -13 4)", "-1"), ("(modulo -13 4)", "3"),
      ("(gcd 32 -36)", "4"), ("(lcm 32 -36)", "288"), ("(numerator 6/4)", "3"),
      ("(denominator 6/4)", "2"), ("(floor -1/2)", "-1"), ("(ceiling -1/2)", "0"),
      ("(truncate -1/2)", "0"), ("(round 5/2)", "2"), ("(rationalize 3/5 1/10)", "1/2"),
      ("(= (exp 0) 1.0)", "#t"), ("(= (log 1) 0.0)", "#t"), ("(= (sin 0) 0.0)", "#t"),
      ("(= (cos 0) 1.0)", "#t"), ("(= (tan 0) 0.0)", "#t"), ("(= (asin 0) 0.0)", "#t"),
      ("(= (acos 1) 0.0)", "#t"), ("(= (atan 0) 0.0)", "#t"),
      ("(= (atan 0 -1) 3.141592653589793)", "#t"), ("(sqrt 9)", "3"), ("(expt 2 3)", "8"),
      ("(make-rectangular 1 2)", "1+2i"), ("(= (real-part 3+4i) 3)", "#t"),
      ("(= (imag-part 3+4i) 4)", "#t"), ("(= (magnitude 3+4i) 5)", "#t"),
      ("(= (angle 1) 0.0)", "#t"), ("(= (real-part (make-polar 1 0)) 1.0)", "#t"),
      ("(inexact? (exact->inexact 1))", "#t"), ("(exact? (inexact->exact 1.0))", "#t"),
      ("(number->string 42)", "\"42\""), ("(string->number \"42\")", "42"),
    ]
    for (source, expected) in cases { #expect(try matrixEvaluate(source).written == expected) }
  }

  @Test("§6.3 data, character, string, and vector procedures have valid contracts")
  func dataMatrix() throws {
    let cases: [(String, String)] = [
      ("(not #f)", "#t"), ("(boolean? #t)", "#t"), ("(pair? '(a))", "#t"), ("(null? '())", "#t"),
      ("(list? '(a b))", "#t"), ("(cons 'a 'b)", "(a . b)"), ("(car '(a . b))", "a"),
      ("(cdr '(a . b))", "b"), ("(list 'a 'b)", "(a b)"), ("(length '(a b c))", "3"),
      ("(append '(a) '(b c))", "(a b c)"), ("(reverse '(a b c))", "(c b a)"),
      ("(list-tail '(a b c) 1)", "(b c)"), ("(list-ref '(a b c) 1)", "b"),
      ("(memq 'b '(a b c))", "(b c)"), ("(memv 'b '(a b c))", "(b c)"),
      ("(member 'b '(a b c))", "(b c)"), ("(assq 'b '((a . 1) (b . 2)))", "(b . 2)"),
      ("(assv 'b '((a . 1) (b . 2)))", "(b . 2)"), ("(assoc 'b '((a . 1) (b . 2)))", "(b . 2)"),
      ("(symbol? 'a)", "#t"), ("(symbol->string 'a)", "\"a\""), ("(string->symbol \"a\")", "a"),
      ("(char? #\\a)", "#t"), ("(char=? #\\a #\\a)", "#t"), ("(char<? #\\a #\\b)", "#t"),
      ("(char>? #\\b #\\a)", "#t"), ("(char<=? #\\a #\\a)", "#t"), ("(char>=? #\\a #\\a)", "#t"),
      ("(char-ci=? #\\A #\\a)", "#t"), ("(char-ci<? #\\A #\\b)", "#t"),
      ("(char-ci>? #\\b #\\A)", "#t"), ("(char-ci<=? #\\A #\\a)", "#t"),
      ("(char-ci>=? #\\A #\\a)", "#t"), ("(char-alphabetic? #\\a)", "#t"),
      ("(char-alphabetic? #\\ß)", "#f"), ("(char-numeric? #\\1)", "#t"),
      ("(char-whitespace? #\\space)", "#t"), ("(char-upper-case? #\\A)", "#t"),
      ("(char-lower-case? #\\a)", "#t"), ("(char-lower-case? #\\ß)", "#t"),
      ("(char-upcase #\\a)", "#\\A"), ("(char-downcase #\\A)", "#\\a"),
      ("(char->integer #\\A)", "65"), ("(integer->char 65)", "#\\A"), ("(string? \"a\")", "#t"),
      ("(make-string 2 #\\x)", "\"xx\""), ("(string)", "\"\""), ("(string #\\a #\\b)", "\"ab\""),
      ("(string-length \"abc\")", "3"), ("(string-ref \"abc\" 1)", "#\\b"),
      ("(substring \"abc\" 1 3)", "\"bc\""), ("(string-append)", "\"\""),
      ("(string-append \"a\" \"b\")", "\"ab\""), ("(string->list \"ab\")", "(#\\a #\\b)"),
      ("(list->string '(#\\a #\\b))", "\"ab\""), ("(string-copy \"ab\")", "\"ab\""),
      ("(string=? \"a\" \"a\")", "#t"), ("(string<? \"a\" \"b\")", "#t"),
      ("(string>? \"b\" \"a\")", "#t"), ("(string<=? \"a\" \"a\")", "#t"),
      ("(string>=? \"a\" \"a\")", "#t"), ("(string-ci=? \"A\" \"a\")", "#t"),
      ("(string-ci<? \"a\" \"B\")", "#t"), ("(string-ci>? \"B\" \"a\")", "#t"),
      ("(string-ci<=? \"A\" \"a\")", "#t"), ("(string-ci>=? \"A\" \"a\")", "#t"),
      ("(vector? '#(a))", "#t"), ("(vector)", "#()"), ("(make-vector 2 'x)", "#(x x)"),
      ("(vector 'a 'b)", "#(a b)"), ("(vector-length '#(a b))", "2"),
      ("(vector-ref '#(a b) 1)", "b"), ("(vector->list '#(a b))", "(a b)"),
      ("(list->vector '(a b))", "#(a b)"),
    ]
    for (source, expected) in cases { #expect(try matrixEvaluate(source).written == expected) }
    var selectors: [String] = []
    for depth in 2...4 {
      for bits in 0..<(1 << depth) {
        var name = "c"
        for shift in (0..<depth).reversed() { name.append((bits >> shift) & 1 == 0 ? "a" : "d") }
        selectors.append(name + "r")
      }
    }
    for name in selectors {
      #expect(try matrixEvaluate("(\(name) '\(selectorInput(name)))").written == "1")
    }
    #expect(
      try matrixEvaluate("(let ((p (cons 'a 'b))) (set-car! p 'c) (set-cdr! p 'd) p)").written
        == "(c . d)"
    )
    #expect(
      try matrixEvaluate(
        "(let ((s (string #\\a #\\b))) (string-set! s 0 #\\z) (string-fill! s #\\x) s)"
      ).written == "\"xx\""
    )
    #expect(
      try matrixEvaluate("(let ((v (vector 1 2))) (vector-set! v 0 3) (vector-fill! v 4) v)")
        .written == "#(4 4)"
    )
  }

  @Test("required procedures reject representative arity and domain violations")
  func requiredProcedureErrors() {
    let cases = [
      "(eq?)", "(eq? 1)", "(number?)", "(+ 'x)", "(-)", "(/)", "(max)", "(quotient 1)", "(gcd 'x)",
      "(floor 'x)", "(sqrt 'x)", "(make-rectangular 1)", "(atan 1 2 3)", "(number->string 'x)",
      "(string->number 1)", "(not)", "(cons 1)", "(car 1)", "(set-car! 1 2)", "(= 1)", "(< 1)",
      "(> 1)", "(<= 1)", "(>= 1)", "(length 1)", "(list-tail '(a) 2)", "(list-ref '(a) -1)",
      "(memq 'a 1)", "(assq 'a 1)", "(symbol->string 1)", "(string->symbol 1)", "(char->integer 1)",
      "(integer->char 1.0)", "(char=? #\\a)", "(char<? #\\a)", "(char>? #\\a)", "(char<=? #\\a)",
      "(char>=? #\\a)", "(char-ci=? #\\a)", "(char-ci<? #\\a)", "(char-ci>? #\\a)",
      "(char-ci<=? #\\a)", "(char-ci>=? #\\a)", "(char=? #\\a #\\a #\\a)",
      "(char<? #\\a #\\b #\\c)", "(char-ci=? #\\a #\\a #\\a)", "(char-ci>=? #\\c #\\b #\\a)",
      "(char-upcase 1)", "(make-string -1)", "(string-ref 1 0)", "(string-set! \"a\" 0 #\\b)",
      "(substring \"a\" 1 0)", "(string=? \"a\")", "(string=? \"a\" \"a\" \"a\")",
      "(string-ci<? \"a\" \"b\" \"c\")", "(vector-ref 1 0)", "(vector-set! '#(a) 0 'b)",
      "(list->vector 1)", "(apply + 1 2)", "(map 1 '())", "(for-each 1 '())",
      "(call-with-values 1 2)", "(dynamic-wind 1 2 3)", "(force 1)", "(eval 1 1)",
      "(eval (current-input-port) (interaction-environment))",
      "(eval (read) (interaction-environment))", "(read 1)", "(read-char 1)", "(write 1 1)",
      "(newline 1 2)", "(write-char 1)", "(current-input-port 1)", "(current-output-port 1)",
      "(close-input-port 1)", "(close-input-port (current-output-port))",
      "(close-output-port (current-input-port))", "(read (current-output-port))",
      "(read-char (current-output-port))", "(peek-char (current-output-port))",
      "(char-ready? (current-output-port))", "(write 1 (current-input-port))",
      "(display 1 (current-input-port))", "(newline (current-input-port))",
      "(write-char #\\a (current-input-port))", "(load)", "(open-input-file 1)",
      "(open-output-file 1)", "(complex?)", "(real?)", "(rational?)", "(integer?)", "(exact?)",
      "(inexact?)", "(zero?)", "(positive?)", "(negative?)", "(odd?)", "(even?)", "(min)",
      "(abs 'x)", "(max 1+2i 2)", "(min 1+2i 2)", "(exp 'x)", "(log 'x)", "(sin 'x)", "(cos 'x)",
      "(tan 'x)", "(asin 'x)", "(acos 'x)", "(atan 'x)", "(sqrt 'x)", "(expt 1)", "(make-polar 1)",
      "(real-part 'x)", "(imag-part 'x)", "(magnitude 'x)", "(angle 'x)", "(exact->inexact 'x)",
      "(inexact->exact 'x)", "(number->string 1 3)", "(string->number \"x\" 3)", "(reverse 1)",
      "(list-tail 1 0)", "(list-ref 1 0)", "(memv 1 1)", "(member 1 1)", "(assv 1 1)",
      "(assoc 1 1)", "(boolean?)", "(pair?)", "(null?)", "(list?)", "(char?)", "(string?)",
      "(vector?)", "(port?)", "(input-port?)", "(output-port?)", "(procedure?)",
      "(char-alphabetic? 1)", "(char-numeric? 1)", "(char-whitespace? 1)", "(char-upper-case? 1)",
      "(char-lower-case? 1)", "(char-downcase 1)", "(char->integer 1)", "(make-string)",
      "(make-string 1 1)", "(string-length 1)", "(string-ref \"a\")", "(string-set! \"a\" 0)",
      "(string-append 1)", "(string->list 1)", "(list->string 1)", "(string-copy 1)",
      "(string<? \"a\")", "(string>? \"a\")", "(string<=? \"a\")", "(string>=? \"a\")",
      "(string-fill! \"a\")", "(string-fill! \"a\" 1)", "(string-ci=? \"a\")",
      "(string-ci<? \"a\")", "(string-ci>? \"a\")", "(string-ci<=? \"a\")", "(string-ci>=? \"a\")",
      "(make-vector)", "(make-vector 1 2 3)", "(vector-length 1)", "(vector-ref 1 0)",
      "(vector-set! 1 0 0)", "(vector->list 1)", "(vector-fill! 1 0)", "(apply + 1)",
      "(apply + 1 '(1 . 2))", "(call-with-current-continuation 1)", "(interaction-environment 1)",
      "(scheme-report-environment)", "(scheme-report-environment 4)", "(null-environment)",
      "(null-environment 4)", "(call-with-input-file 1 1)", "(call-with-output-file 1 1)",
      "(open-input-file 1)", "(open-output-file 1)", "(close-output-port 1)", "(eof-object?)",
      "(display 1 1)", "(set-cdr! 1 2)",
    ]
    let selectorErrors = [
      "caar", "cadr", "cdar", "cddr", "caaar", "caadr", "cadar", "caddr", "cdaar", "cdadr", "cddar",
      "cdddr", "caaaar", "caaadr", "caadar", "caaddr", "cadaar", "cadadr", "caddar", "cadddr",
      "cdaaar", "cdaadr", "cdadar", "cdaddr", "cddaar", "cddadr", "cdddar", "cddddr",
    ].map { "(\($0) 1)" }
    for source in cases + selectorErrors {
      do {
        _ = try matrixEvaluate(source)
        #expect(Bool(false))
      } catch is SchemeError {} catch { #expect(Bool(false)) }
    }
  }

  @Test("§6.4 map/apply/value-count boundaries are explicit") func controlBoundaryMatrix() throws {
    let result = try matrixEvaluate(
      "(list (map + '()) (for-each (lambda (x) x) '()) "
        + "(apply + 1 '(2 3)) (call-with-values (lambda () (values)) list))"
    )
    #expect(result.written == "(() #<unspecified> 6 ())")
    for source in [
      "(map + '(1) '(2 3))", "(for-each + '(1) '(2 3))", "(apply + 1 2)",
      "(call-with-values (lambda () (values 1 2)) (lambda (x) x))",
    ] {
      do {
        _ = try matrixEvaluate(source)
        #expect(Bool(false), "expected control boundary error: \(source)")
      } catch is SchemeError {} catch {
        #expect(Bool(false), "unexpected control error: \(source)")
      }
    }
  }

  @Test("§6.4–§6.6 control, environment, and I/O procedures have valid contracts")
  func controlAndIOMatrix() throws {
    let cases: [(String, String)] = [
      ("(procedure? car)", "#t"), ("(port? (current-input-port))", "#t"),
      ("(input-port? (current-input-port))", "#t"), ("(output-port? (current-output-port))", "#t"),
      ("(apply + '(1 2 3))", "6"), ("(map + '(1 2) '(3 4))", "(4 6)"),
      ("(for-each (lambda (x) x) '(1 2))", "#<unspecified>"),
      ("(call-with-current-continuation (lambda (exit) (exit 7) 8))", "7"),
      ("(call/cc (lambda (exit) (exit 7) 8))", "7"),
      ("(call-with-values (lambda () (values 1 2)) (lambda (a b) (list a b)))", "(1 2)"),
      ("(call-with-values (lambda () (values 2 3)) +)", "5"),
      ("(dynamic-wind (lambda () 1) (lambda () 2) (lambda () 3))", "2"),
      ("(force (delay (+ 1 2)))", "3"), ("(eval '(+ 1 2) (scheme-report-environment 5))", "3"),
      ("(eval '(lambda (x) (+ x 1)) (null-environment 5))", "#<procedure>"),
      ("(eof-object? (read))", "#t"), ("(char-ready?)", "#t"), ("(read-char)", "#<eof>"),
      ("(peek-char)", "#<eof>"), ("(call-with-input-string \" 42\" (lambda (p) (read p)))", "42"),
      ("(call-with-input-string \"a\" (lambda (p) (read-char p)))", "#\\a"),
      ("(call-with-input-string \"a\" (lambda (p) (peek-char p)))", "#\\a"),
      ("(call-with-output-string (lambda (p) (write 'a p) (display \"b\" p)))", "\"ab\""),
      ("(call-with-output-string (lambda (p) (newline p) (write-char #\\a p)))", "\"\na\""),
    ]
    for (source, expected) in cases { #expect(try matrixEvaluate(source).written == expected) }
    let input = try matrixEvaluate("(list (read) (read-char) (peek-char))", input: " 1 a")
    #expect(input.written == "(1 #\\space #\\a)")

    let directory = FileManager.default.temporaryDirectory
    let inputPath = directory.appendingPathComponent(
      "swiftscheme-matrix-input-\(UUID().uuidString)"
    )
    let outputPath = directory.appendingPathComponent(
      "swiftscheme-matrix-output-\(UUID().uuidString)"
    )
    defer {
      try? FileManager.default.removeItem(at: inputPath)
      try? FileManager.default.removeItem(at: outputPath)
    }
    try Data("42".utf8).write(to: inputPath)
    let inputName = String(reflecting: inputPath.path)
    let outputName = String(reflecting: outputPath.path)
    #expect(
      try matrixEvaluate("(call-with-input-file \(inputName) (lambda (p) (read p)))").written
        == "42"
    )
    #expect(
      try matrixEvaluate(
        "(let ((p (open-input-file \(inputName)))) (let ((x (read p))) (close-input-port p) x))"
      ).written == "42"
    )
    #expect(
      try matrixEvaluate("(call-with-output-file \(outputName) (lambda (p) (display \"ok\" p)))")
        .written == "#<unspecified>"
    )
    #expect(String(data: try Data(contentsOf: outputPath), encoding: .utf8) == "ok")
    #expect(
      try matrixEvaluate("(with-input-from-file \(inputName) (lambda () (read)))").written == "42"
    )
    #expect(
      try matrixEvaluate("(with-output-to-file \(outputName) (lambda () (display \"with\")))")
        .written == "#<unspecified>"
    )
    #expect(String(data: try Data(contentsOf: outputPath), encoding: .utf8) == "with")
    #expect(
      try matrixEvaluate(
        "(let ((p (open-output-file \(outputName)))) (write-char #\\z p) (close-output-port p))"
      ).written == "#<unspecified>"
    )
    #expect(String(data: try Data(contentsOf: outputPath), encoding: .utf8) == "z")
  }
}
