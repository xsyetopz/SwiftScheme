import Foundation
import SwiftScheme
import Testing

@MainActor private func contractValue(_ source: String, input: String = "") throws -> String {
  try Interpreter(output: { _ in }, input: input).evaluate(source).written
}

@MainActor private func selectorDatum(_ name: String) -> String {
  var result = "z"
  for operation in name.dropFirst().dropLast() {
    result = operation == "a" ? "(\(result) . q)" : "(q . \(result))"
  }
  return result
}

@Suite("R5RS required procedure contract coverage") @MainActor struct R5RSProcedureContractTests {
  @Test("every required procedure has a representative valid contract")
  func everyRequiredProcedureContract() throws {
    let cases: [(String, String, String)] = [
      ("eq?", "(eq? 'a 'a)", "#t"), ("eqv?", "(eqv? 'a 'a)", "#t"),
      ("equal?", "(equal? '(a (b)) '(a (b)))", "#t"), ("number?", "(number? 1)", "#t"),
      ("complex?", "(complex? 1)", "#t"), ("real?", "(real? 1)", "#t"),
      ("rational?", "(rational? 1/2)", "#t"), ("integer?", "(integer? 1)", "#t"),
      ("exact?", "(exact? 1)", "#t"), ("inexact?", "(inexact? 1.0)", "#t"),
      ("=", "(= 1 1 1)", "#t"), ("<", "(< 1 2 3)", "#t"), (">", "(> 3 2 1)", "#t"),
      ("<=", "(<= 1 1 2)", "#t"), (">=", "(>= 2 2 1)", "#t"), ("zero?", "(zero? 0)", "#t"),
      ("positive?", "(positive? 1)", "#t"), ("negative?", "(negative? -1)", "#t"),
      ("odd?", "(odd? 3)", "#t"), ("even?", "(even? 4)", "#t"), ("max", "(max 1 3 2)", "3"),
      ("min", "(min 1 3 2)", "1"), ("+", "(+ 1 2 3)", "6"), ("*", "(* 2 3 4)", "24"),
      ("-", "(- 3 1 1)", "1"), ("/", "(/ 8 2 2)", "2"), ("abs", "(abs -3)", "3"),
      ("quotient", "(quotient -13 4)", "-3"), ("remainder", "(remainder -13 4)", "-1"),
      ("modulo", "(modulo -13 4)", "3"), ("gcd", "(gcd 32 -36)", "4"),
      ("lcm", "(lcm 32 -36)", "288"), ("numerator", "(numerator 6/4)", "3"),
      ("denominator", "(denominator 6/4)", "2"), ("floor", "(floor -1/2)", "-1"),
      ("ceiling", "(ceiling -1/2)", "0"), ("truncate", "(truncate -1/2)", "0"),
      ("round", "(round 5/2)", "2"), ("rationalize", "(rationalize 3/5 1/10)", "1/2"),
      ("exp", "(number->string (exp 0))", "\"1.0\""),
      ("log", "(number->string (log 1))", "\"0.0\""),
      ("sin", "(number->string (sin 0))", "\"0.0\""),
      ("cos", "(number->string (cos 0))", "\"1.0\""),
      ("tan", "(number->string (tan 0))", "\"0.0\""),
      ("asin", "(number->string (asin 0))", "\"0.0\""),
      ("acos", "(number->string (acos 1))", "\"0.0\""),
      ("atan", "(number->string (atan 0))", "\"0.0\""), ("sqrt", "(sqrt 9)", "3"),
      ("expt", "(expt 2 3)", "8"), ("make-rectangular", "(make-rectangular 1 2)", "1+2i"),
      ("make-polar", "(make-polar 1 0)", "1"), ("real-part", "(real-part 3+4i)", "3"),
      ("imag-part", "(imag-part 3+4i)", "4"), ("magnitude", "(magnitude 3+4i)", "5"),
      ("angle", "(number->string (angle 1))", "\"0.0\""),
      ("exact->inexact", "(exact->inexact 1)", "1.0"),
      ("inexact->exact", "(inexact->exact 1.0)", "1"),
      ("number->string", "(number->string 42)", "\"42\""),
      ("string->number", "(string->number \"42\")", "42"), ("not", "(not #f)", "#t"),
      ("boolean?", "(boolean? #t)", "#t"), ("pair?", "(pair? '(a))", "#t"),
      ("cons", "(cons 'a 'b)", "(a . b)"), ("car", "(car '(a . b))", "a"),
      ("cdr", "(cdr '(a . b))", "b"), ("null?", "(null? '())", "#t"),
      ("list?", "(list? '(a b))", "#t"), ("list", "(list 'a 'b)", "(a b)"),
      ("length", "(length '(a b c))", "3"), ("append", "(append '(a) '(b c))", "(a b c)"),
      ("reverse", "(reverse '(a b c))", "(c b a)"),
      ("list-tail", "(list-tail '(a b c) 1)", "(b c)"), ("list-ref", "(list-ref '(a b c) 1)", "b"),
      ("memq", "(memq 'b '(a b c))", "(b c)"), ("memv", "(memv 'b '(a b c))", "(b c)"),
      ("member", "(member 'b '(a b c))", "(b c)"),
      ("assq", "(assq 'b '((a . 1) (b . 2)))", "(b . 2)"),
      ("assv", "(assv 'b '((a . 1) (b . 2)))", "(b . 2)"),
      ("assoc", "(assoc 'b '((a . 1) (b . 2)))", "(b . 2)"), ("symbol?", "(symbol? 'a)", "#t"),
      ("symbol->string", "(symbol->string 'a)", "\"a\""),
      ("string->symbol", "(string->symbol \"a\")", "a"), ("char?", "(char? #\\a)", "#t"),
      ("char=?", "(char=? #\\a #\\a)", "#t"), ("char<?", "(char<? #\\a #\\b)", "#t"),
      ("char>?", "(char>? #\\b #\\a)", "#t"), ("char<=?", "(char<=? #\\a #\\a)", "#t"),
      ("char>=?", "(char>=? #\\a #\\a)", "#t"), ("char-ci=?", "(char-ci=? #\\A #\\a)", "#t"),
      ("char-ci<?", "(char-ci<? #\\A #\\b)", "#t"), ("char-ci>?", "(char-ci>? #\\b #\\A)", "#t"),
      ("char-ci<=?", "(char-ci<=? #\\A #\\a)", "#t"),
      ("char-ci>=?", "(char-ci>=? #\\A #\\a)", "#t"),
      ("char-alphabetic?", "(char-alphabetic? #\\a)", "#t"),
      ("char-numeric?", "(char-numeric? #\\1)", "#t"),
      ("char-whitespace?", "(char-whitespace? #\\space)", "#t"),
      ("char-upper-case?", "(char-upper-case? #\\A)", "#t"),
      ("char-lower-case?", "(char-lower-case? #\\a)", "#t"),
      ("char-upcase", "(char-upcase #\\a)", "#\\A"),
      ("char-downcase", "(char-downcase #\\A)", "#\\a"),
      ("char->integer", "(char->integer #\\A)", "65"),
      ("integer->char", "(integer->char 65)", "#\\A"), ("string?", "(string? \"a\")", "#t"),
      ("make-string", "(make-string 2 #\\x)", "\"xx\""), ("string", "(string #\\a #\\b)", "\"ab\""),
      ("string-length", "(string-length \"abc\")", "3"),
      ("string-ref", "(string-ref \"abc\" 1)", "#\\b"),
      ("substring", "(substring \"abc\" 1 3)", "\"bc\""),
      ("string-append", "(string-append \"a\" \"b\")", "\"ab\""),
      ("string->list", "(string->list \"ab\")", "(#\\a #\\b)"),
      ("list->string", "(list->string '(#\\a #\\b))", "\"ab\""),
      ("string-copy", "(string-copy \"ab\")", "\"ab\""),
      ("string=?", "(string=? \"a\" \"a\")", "#t"), ("string<?", "(string<? \"a\" \"b\")", "#t"),
      ("string>?", "(string>? \"b\" \"a\")", "#t"), ("string<=?", "(string<=? \"a\" \"a\")", "#t"),
      ("string>=?", "(string>=? \"a\" \"a\")", "#t"),
      ("string-ci=?", "(string-ci=? \"A\" \"a\")", "#t"),
      ("string-ci<?", "(string-ci<? \"a\" \"B\")", "#t"),
      ("string-ci>?", "(string-ci>? \"B\" \"a\")", "#t"),
      ("string-ci<=?", "(string-ci<=? \"A\" \"a\")", "#t"),
      ("string-ci>=?", "(string-ci>=? \"A\" \"a\")", "#t"), ("vector?", "(vector? '#(a))", "#t"),
      ("make-vector", "(make-vector 2 'x)", "#(x x)"), ("vector", "(vector 'a 'b)", "#(a b)"),
      ("vector-length", "(vector-length '#(a b))", "2"),
      ("vector-ref", "(vector-ref '#(a b) 1)", "b"),
      ("vector->list", "(vector->list '#(a b))", "(a b)"),
      ("list->vector", "(list->vector '(a b))", "#(a b)"), ("procedure?", "(procedure? car)", "#t"),
      ("port?", "(port? (current-input-port))", "#t"),
      ("input-port?", "(input-port? (current-input-port))", "#t"),
      ("output-port?", "(output-port? (current-output-port))", "#t"),
      ("apply", "(apply + '(1 2 3))", "6"), ("map", "(map + '(1 2) '(3 4))", "(4 6)"),
      ("call-with-current-continuation", "(call/cc (lambda (exit) (exit 7) 8))", "7"),
      ("values", "(call-with-values (lambda () (values 1)) list)", "(1)"),
      ("call-with-values", "(call-with-values (lambda () (values 1 2)) list)", "(1 2)"),
      ("force", "(force (delay (+ 1 2)))", "3"),
      ("eval", "(eval '(+ 1 2) (scheme-report-environment 5))", "3"),
      ("dynamic-wind", "(dynamic-wind (lambda () 1) (lambda () 2) (lambda () 3))", "2"),
      ("scheme-report-environment", "(eval '(+ 1 2) (scheme-report-environment 5))", "3"),
      ("null-environment", "(eval '(if #t 1 2) (null-environment 5))", "1"),
      ("read", "(read)", "1"), ("read-char", "(read-char)", "#\\1"),
      ("peek-char", "(peek-char)", "#\\1"), ("eof-object?", "(eof-object? (read))", "#t"),
      ("char-ready?", "(char-ready?)", "#t"),
      ("write", "(call-with-output-string (lambda (p) (write 'a p)))", "\"a\""),
      ("display", "(call-with-output-string (lambda (p) (display \"a\" p)))", "\"a\""),
      ("newline", "(call-with-output-string (lambda (p) (newline p)))", "\"" + "\n" + "\""),
      ("write-char", "(call-with-output-string (lambda (p) (write-char #\\a p)))", "\"a\""),
    ]

    for (name, source, expected) in cases {
      let actual = try contractValue(
        source,
        input: name == "read" || name == "read-char" || name == "peek-char" ? "1" : ""
      )
      #expect(actual == expected)
    }

    var selectors: [String] = []
    for depth in 2...4 {
      for bits in 0..<(1 << depth) {
        var name = "c"
        for shift in (0..<depth).reversed() { name.append((bits >> shift) & 1 == 0 ? "a" : "d") }
        selectors.append(name + "r")
        #expect(try contractValue("(\(name)r '\(selectorDatum(name + "r")))") == "z")
      }
    }

    let mutationCases = [
      "(let ((p (cons 'a 'b))) (set-car! p 'c) (set-cdr! p 'd) p)",
      "(let ((s (string #\\a #\\b))) (string-set! s 0 #\\z) (string-fill! s #\\x) s)",
      "(let ((v (vector 1 2))) (vector-set! v 0 3) (vector-fill! v 4) v)",
      "(for-each (lambda (x) x) '(1 2))",
    ]
    #expect(try contractValue(mutationCases[0]) == "(c . d)")
    #expect(try contractValue(mutationCases[1]) == "\"xx\"")
    #expect(try contractValue(mutationCases[2]) == "#(4 4)")
    _ = try contractValue(mutationCases[3])

    let names = Set(
      cases.map(\.0) + selectors + [
        "set-car!", "set-cdr!", "string-set!", "vector-set!", "string-fill!", "vector-fill!",
        "for-each", "call-with-input-file", "call-with-output-file", "open-input-file",
        "open-output-file", "close-input-port", "close-output-port", "current-input-port",
        "current-output-port",
      ]
    )
    let required = Set([
      "eq?", "eqv?", "equal?", "number?", "complex?", "real?", "rational?", "integer?", "exact?",
      "inexact?", "=", "<", ">", "<=", ">=", "zero?", "positive?", "negative?", "odd?", "even?",
      "max", "min", "+", "*", "-", "/", "abs", "quotient", "remainder", "modulo", "gcd", "lcm",
      "numerator", "denominator", "floor", "ceiling", "truncate", "round", "rationalize", "exp",
      "log", "sin", "cos", "tan", "asin", "acos", "atan", "sqrt", "expt", "make-rectangular",
      "make-polar", "real-part", "imag-part", "magnitude", "angle", "exact->inexact",
      "inexact->exact", "number->string", "string->number", "not", "boolean?", "pair?", "cons",
      "car", "cdr", "cdddr", "set-car!", "set-cdr!", "null?", "list?", "list", "length", "append",
      "reverse", "list-tail", "list-ref", "memq", "memv", "member", "assq", "assv", "assoc",
      "symbol?", "symbol->string", "string->symbol", "char?", "char=?", "char<?", "char>?",
      "char<=?", "char>=?", "char-ci=?", "char-ci<?", "char-ci>?", "char-ci<=?", "char-ci>=?",
      "char-alphabetic?", "char-numeric?", "char-whitespace?", "char-upper-case?",
      "char-lower-case?", "char-upcase", "char-downcase", "char->integer", "integer->char",
      "string?", "make-string", "string", "string-length", "string-ref", "string-set!", "substring",
      "string-append", "string->list", "list->string", "string-copy", "string-fill!", "string=?",
      "string<?", "string>?", "string<=?", "string>=?", "string-ci=?", "string-ci<?", "string-ci>?",
      "string-ci<=?", "string-ci>=?", "vector?", "make-vector", "vector", "vector-length",
      "vector-ref", "vector-set!", "vector->list", "list->vector", "vector-fill!", "procedure?",
      "port?", "call-with-current-continuation", "apply", "map", "for-each", "values", "force",
      "eval", "call-with-values", "dynamic-wind", "scheme-report-environment", "null-environment",
      "input-port?", "output-port?", "read", "read-char", "peek-char", "eof-object?", "char-ready?",
      "write", "display", "newline", "write-char",
    ]).union(selectors).union([
      "call-with-input-file", "call-with-output-file", "open-input-file", "open-output-file",
      "close-input-port", "close-output-port", "current-input-port", "current-output-port",
    ])
    #expect(names == required)
  }

  @Test("mutators and output procedures return unspecified") func unspecifiedResultContracts()
    throws
  {
    let source = """
      (let ((p (cons 1 2)) (s (string #\\a #\\b)) (v (vector 1 2)))
        (list (set-car! p 3) (set-cdr! p 4) (string-set! s 0 #\\z)
              (string-fill! s #\\x) (vector-set! v 0 3) (vector-fill! v 4)
              (for-each (lambda (x) x) '(1 2)) (write 'a) (display "b")
              (newline) (write-char #\\c)
              (let ((p (open-input-string ""))) (close-input-port p))
              (let ((p (open-output-string))) (close-output-port p))))
      """
    #expect(
      try contractValue(source)
        == "(#<unspecified> #<unspecified> #<unspecified> #<unspecified> #<unspecified> "
        + "#<unspecified> #<unspecified> #<unspecified> #<unspecified> #<unspecified> "
        + "#<unspecified> #<unspecified> #<unspecified>)"
    )
  }

  @Test("file procedures preserve their required callback contracts") func fileProcedureContracts()
    throws
  {
    let directory = FileManager.default.temporaryDirectory
    let inputPath = directory.appendingPathComponent(
      "swiftscheme-contract-input-\(UUID().uuidString)"
    )
    let outputPath = directory.appendingPathComponent(
      "swiftscheme-contract-output-\(UUID().uuidString)"
    )
    defer {
      try? FileManager.default.removeItem(at: inputPath)
      try? FileManager.default.removeItem(at: outputPath)
    }
    try Data("42".utf8).write(to: inputPath)
    let input = String(reflecting: inputPath.path)
    let output = String(reflecting: outputPath.path)
    #expect(try contractValue("(open-input-file \(input))").hasPrefix("#<port>"))
    #expect(try contractValue("(open-output-file \(output))").hasPrefix("#<port>"))
    #expect(try contractValue("(call-with-input-file \(input) (lambda (p) (read p)))") == "42")
    #expect(
      try contractValue("(call-with-output-file \(output) (lambda (p) (display \"ok\" p)))")
        == "#<unspecified>"
    )
    #expect(String(data: try Data(contentsOf: outputPath), encoding: .utf8) == "ok")
    #expect(
      try contractValue("(let ((p (open-input-file \(input)))) (close-input-port p) #t)") == "#t"
    )
    #expect(
      try contractValue("(let ((p (open-output-file \(output)))) (close-output-port p) #t)") == "#t"
    )
    #expect(try contractValue("(current-input-port)").hasPrefix("#<port>"))
    #expect(try contractValue("(current-output-port)").hasPrefix("#<port>"))
  }
  @Test("string-created symbols preserve name identity") func symbolIdentityContract() throws {
    #expect(
      try contractValue(
        "(list (eq? (string->symbol \"a\") (string->symbol \"a\")) "
          + "(eqv? (string->symbol \"a\") (string->symbol \"a\")))"
      ) == "(#t #t)"
    )
  }

  @Test("required constructors and consumers preserve specified fresh or shared structure")
  func identityAndMutationContracts() throws {
    #expect(
      try contractValue(
        "(let* ((source (list 'a)) (tail (list 'b)) (joined (append source tail))) "
          + "(set-car! source 'changed) (set-car! joined 'joined) "
          + "(set-car! tail 'tailchanged) (list source joined tail))"
      ) == "((changed) (joined tailchanged) (tailchanged))"
    )
    #expect(
      try contractValue(
        "(let* ((source (list 'a 'b)) (reversed (reverse source))) "
          + "(set-car! source 'changed) (set-car! reversed 'reversed) " + "(list source reversed))"
      ) == "((changed b) (reversed a))"
    )
    #expect(
      try contractValue(
        "(let ((copy (string-copy \"ab\"))) (string-set! copy 0 #\\z) " + "(list copy \"ab\"))"
      ) == "(\"zb\" \"ab\")"
    )
    #expect(
      try contractValue(
        "(let ((v (list->vector '(a b)))) (vector-set! v 0 'z) " + "(list v '(a b)))"
      ) == "(#(z b) (a b))"
    )
    #expect(
      try contractValue(
        "(let ((v '#(a b)) (l (vector->list '#(a b)))) (set-car! l 'z) " + "(list l v))"
      ) == "((z b) #(a b))"
    )
    #expect(
      try contractValue(
        "(let* ((source (list 'a 'b)) (tail (list-tail source 1)) "
          + "(member (memq 'b source)) (mapped (map (lambda (x) x) source))) "
          + "(set-car! tail 'tail) (set-car! mapped 'mapped) " + "(list source tail member mapped))"
      ) == "((a tail) (tail) (tail) (mapped b))"
    )
    #expect(
      try contractValue(
        "(let* ((alist (list (cons 'a 1))) (found (assq 'a alist))) "
          + "(set-cdr! found 2) (list found alist))"
      ) == "((a . 2) ((a . 2)))"
    )
    #expect(
      try contractValue(
        "(let* ((source \"ab\") (joined (string-append source \"c\")) "
          + "(slice (substring source 0 1))) "
          + "(string-set! joined 0 #\\z) (string-set! slice 0 #\\y) "
          + "(list source joined slice))"
      ) == "(\"ab\" \"zbc\" \"y\")"
    )
  }

}
