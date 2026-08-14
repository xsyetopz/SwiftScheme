import Foundation
import SwiftScheme
import Testing

@MainActor private func printed(_ source: String) throws -> String {
  try Interpreter(output: { _ in }).evaluate(source).written
}

@MainActor private func expect(_ source: String, _ expected: String, _ label: String) throws {
  let actual = try printed(source)
  #expect(actual == expected, "\(label): expected \(expected), got \(actual)")
}

@MainActor private func expectError(_ source: String, _ label: String) throws {
  do {
    _ = try printed(source)
    #expect(Bool(false), "\(label): expected SchemeError")
  } catch is SchemeError {}
}

@Suite("SwiftScheme evaluator regressions") struct SwiftSchemeEvaluatorTests {
  @Test("R5RS evaluator, heap, continuation, and file regressions") @MainActor
  func evaluatorRegressions() throws {
    try expect("; comment\n'(a 1 #t \"x\\n\" . z)", "(a 1 #t \"x\\n\" . z)", "reader/writer")
    try expect(
      "(list 'Foo 'FOO #\\space #\\newline #x10 #b11 3/2)",
      "(foo foo #\\space #\\newline 16 3 3/2)",
      "lexical forms"
    )
    try expect("'#(a #\\b \"c\")", "#(a #\\b \"c\")", "vector reader/writer")
    try expectError("(a . b c)", "bad dotted list")
    try expectError("\"unterminated", "unterminated string")

    try expect(
      """
      (define (counter n) (lambda () (set! n (+ n 1)) n))
      (define c (counter 40))
      (list (c) (c))
      """,
      "(41 42)",
      "closure mutation"
    )
    try expect("((lambda (x . xs) (cons x xs)) 1 2 3)", "(1 2 3)", "variadic lambda")
    try expectError("(set! missing 1)", "unbound set")
    try expectError("((lambda (x x) x) 1 2)", "duplicate formals")

    try expect("(if #f 1 2)", "2", "if")
    try expect("(and 1 2 3)", "3", "and")
    try expect("(or #f #f 'ok)", "ok", "or")
    try expect("(let ((x 1)) (let* ((x (+ x 1)) (y (+ x 1))) (list x y)))", "(2 3)", "let family")
    try expect(
      "(letrec ((even? (lambda (n) (if (= n 0) #t (odd? (- n 1))))) (odd? (lambda (n) (if (= n 0) #f (even? (- n 1)))))) (even? 20))",
      "#t",
      "letrec"
    )
    try expect(
      "(cond ((> 1 2) 'no) ((< 1 2) => (lambda (x) (if x 'yes 'no))) (else 'bad))",
      "yes",
      "cond arrow"
    )
    try expect("(case (* 2 3) ((2 3 5 7) 'prime) ((1 4 6 8) 'composite))", "composite", "case")
    try expect("(do ((i 0 (+ i 1)) (x '() (cons i x))) ((= i 5) x))", "(4 3 2 1 0)", "do")
    try expect("(let ((x 2) (ys '(3 4))) `(1 ,x ,@ys 5))", "(1 2 3 4 5)", "quasiquote")

    try expect("(append '(1 2) '(3 . 4))", "(1 2 3 . 4)", "append")
    try expect("(map (lambda (x) (* x x)) '(1 2 3))", "(1 4 9)", "map")
    try expect("(apply + 1 2 '(3 4))", "10", "apply")
    try expect(
      "(let ((p (cons 1 2))) (set-car! p 3) (set-cdr! p '(4)) p)",
      "(3 4)",
      "pair mutation"
    )
    try expect(
      "(let ((s (string-append \"a\" \"b\"))) (string-set! s 1 #\\c) s)",
      "\"ac\"",
      "string mutation"
    )
    try expect(
      "(list (string-ref \"abc\" 1) (char-ci=? #\\A #\\a) (char->integer #\\A))",
      "(#\\b #t 65)",
      "characters"
    )
    try expect(
      "(let ((v (vector 1 2 3))) (vector-set! v 1 9) (list v (vector->list v)))",
      "(#(1 9 3) (1 9 3))",
      "vectors"
    )
    try expect(
      "(let ((v (vector #f))) (vector-set! v 0 v) v)",
      "#(#<cycle>)",
      "cyclic vector writer"
    )
    try expect(
      "(let ((a (vector #f)) (b (vector #f))) (vector-set! a 0 a) (vector-set! b 0 b) (equal? a b))",
      "#t",
      "cyclic vector equality"
    )
    try expect("(equal? '(1 (2)) '(1 (2)))", "#t", "structural equality")
    try expect("(let ((p (cons 1 '()))) (set-cdr! p p) (list? p))", "#f", "cyclic list")
    try expect(
      "(list (caddr '(1 2 3)) (memv 2 '(1 2 3)) (assoc 'b '((a . 1) (b . 2))))",
      "(3 (2 3) (b . 2))",
      "list library"
    )

    try expect("(= 9007199254740992 9007199254740993)", "#f", "exact integer comparison")
    try expect(
      "(list (gcd 32 -36) (lcm 4 6) (modulo -13 4) (quotient -13 4) (number->string 255 16) (string->number \"ff\" 16))",
      "(4 12 3 -3 \"ff\" 255)",
      "numeric library"
    )
    try expect(
      "(list (round 2.5) (round 3.5) (round -2.5))",
      "(2.0 4.0 -2.0)",
      "round ties to even"
    )
    try expect(
      "(list (odd? 3.0) (even? 4.0) (quotient 7.0 2) (remainder 7 2.0) (modulo -13.0 4) (gcd 32.0 -36) (lcm 4 6.0))",
      "(#t #t 3.0 1.0 3.0 4.0 12.0)",
      "integer procedures accept inexact integers"
    )
    try expect(
      "(list (/ 4 2) (expt 2 3) (floor 3) (ceiling 3) (truncate 3) (round 3))",
      "(2 8 3 3 3 3)",
      "exact numeric results"
    )
    try expect(
      "(list (exact? (/ 4 2)) (exact? (expt 2 3)) (exact? (floor 3)))",
      "(#t #t #t)",
      "exact numeric result tags"
    )
    try expect("(list #e4 #e4.0 #e4/2 #e1.5 #e3/2)", "(4 4 2 3/2 3/2)", "exact literals")
    try expect("(+ 9223372036854775807 1)", "9223372036854775808", "arbitrary exact integer")
    try expect(
      "(list (+ 1/3 1/6) (/ 3 2) (* 1+2i 3-4i))",
      "(1/2 3/2 11+2i)",
      "rational and complex arithmetic"
    )
    try expect(
      "(list (sqrt 81) (sqrt 81/16) (sqrt -9) (magnitude 3+4i) (magnitude -7/3))",
      "(9 9/4 0+3i 5 7/3)",
      "exact square roots and magnitudes"
    )
    try expect(
      "(list (= 9007199254740993 9007199254740992.0) (> 9007199254740993 9007199254740992.0) (< -9007199254740993 -9007199254740992.0))",
      "(#f #t #t)",
      "mixed exact binary64 comparisons"
    )
    try expect(
      "(list (string->number \"1 2\") (string->number \"3/2junk\") (string->number \"+i\") (string->number \"-i\"))",
      "(#f #f 0+1i 0-1i)",
      "numeric reader consumes complete datum"
    )
    try expect(
      "(let ((n 123456789012345678901234567890123456789)) (= n (string->number (number->string n))))",
      "#t",
      "bignum number string round trip"
    )
    try expect(
      "(let ((z 12345678901234567890/7+9/11i)) (= z (string->number (number->string z))))",
      "#t",
      "exact complex number string round trip"
    )
    try expectError("(/ 1 0)", "division by zero")
    try expectError("(car 1)", "type error")

    try expect("(call/cc (lambda (k) (+ 1 (k 9))))", "9", "call/cc escape")
    try expect(
      """
      (let ((saved #f) (visits 0))
        (let ((result (call/cc (lambda (k) (set! saved k) 1))))
          (set! visits (+ visits 1))
          (if (< visits 3) (saved (+ result 1)) (list result visits))))
      """,
      "(3 3)",
      "multi-shot continuation"
    )
    try expect("(call-with-values (lambda () (values 1 2 3)) list)", "(1 2 3)", "multiple values")
    try expect(
      """
      (define log '())
      (define result
        (dynamic-wind
          (lambda () (set! log (cons 'before log)))
          (lambda () 7)
          (lambda () (set! log (cons 'after log)))))
      (list result log)
      """,
      "(7 (after before))",
      "dynamic-wind"
    )
    try expect(
      """
      (let ((path '()) (saved #f) (jumped #f))
        (let ((result
          (call/cc
            (lambda (escape)
              (dynamic-wind
                (lambda () (set! path (cons 'before path)))
                (lambda ()
                  (call/cc (lambda (k) (set! saved k)))
                  (if jumped (escape 'done) 'first))
                (lambda () (set! path (cons 'after path))))))))
          (if (not jumped)
              (begin (set! jumped #t) (saved 'again))
              (list result path))))
      """,
      "(done (after before after before))",
      "dynamic-wind continuation transitions"
    )
    try expect(
      """
      (define count 0)
      (define p (delay (begin (set! count (+ count 1)) 42)))
      (list (force p) (force p) count)
      """,
      "(42 42 1)",
      "delay/force"
    )

    try expect(
      """
      (define-syntax when
        (syntax-rules ()
          ((when test body ...) (if test (begin body ...)))))
      (when #t 1 2 3)
      """,
      "3",
      "syntax-rules ellipsis"
    )
    try expect(
      """
      (define-syntax swap!
        (syntax-rules ()
          ((swap! a b)
           (let ((tmp a)) (set! a b) (set! b tmp)))))
      (let ((tmp 99) (x 1) (y 2))
        (swap! x y)
        (list tmp x y))
      """,
      "(99 2 1)",
      "macro hygiene"
    )
    try expect(
      "(define-syntax literal (syntax-rules () ((literal) 'ok))) (literal)",
      "ok",
      "quoted macro data"
    )
    try expect(
      "(define-syntax quote-one (syntax-rules () ((quote-one x) 'x))) (quote-one hello)",
      "hello",
      "quoted pattern variable"
    )
    try expect(
      """
      (define-syntax inner (syntax-rules () ((inner x) (+ x 1))))
      (define-syntax outer (syntax-rules () ((outer x) (inner x))))
      (let-syntax ((inner (syntax-rules () ((inner x) 99)))) (outer 4))
      """,
      "5",
      "referentially transparent macro reference"
    )
    try expect(
      "(let-syntax ((twice (syntax-rules () ((twice x) (+ x x))))) (twice 6))",
      "12",
      "let-syntax"
    )
    try expect(
      "(define-syntax flatten (syntax-rules () ((flatten ((x ...) ...)) (list x ... ...)))) (flatten ((1 2) (3 4)))",
      "(1 2 3 4)",
      "nested syntax-rules ellipses"
    )
    try expect(
      "(define-syntax flatten (syntax-rules () ((flatten ((x ...) ...)) (list x ... ...)))) (flatten (() (1) ()))",
      "(1)",
      "nested syntax-rules empty repetitions"
    )
    try expect(
      """
      (let ((lit 'outer))
        (define-syntax select
          (syntax-rules (lit) ((select lit) 'literal) ((select x) 'other)))
        (let ((lit 'shadowed)) (select lit)))
      """,
      "other",
      "syntax-rules literal binding identity"
    )
    try expect("(eval '(+ 20 22) (scheme-report-environment 5))", "42", "eval environment")

    try expect(
      """
      (let loop ((n 200000) (acc 0))
        (if (= n 0) acc (loop (- n 1) (+ acc 1))))
      """,
      "200000",
      "proper tail recursion"
    )

    var output = ""
    let interpreter = Interpreter { output += $0 }
    _ = try interpreter.evaluate("(display \"hello\") (write '(1 2)) (write-char #\\!) (newline)")
    #expect(output == "hello(1 2)!\n", "output procedures")

    let multiline = Interpreter(output: { _ in })
    #expect(!multiline.isComplete("(let ((x 1))"), "incomplete multiline form")
    #expect(multiline.isComplete("(let ((x 1))\n(+ x 2))"), "complete multiline form")

    let heapInterpreter = Interpreter(output: { _ in })
    let baseline = heapInterpreter.heapStatistics
    _ = try heapInterpreter.evaluate(
      "(define survivor (let ((v (vector #f))) (vector-set! v 0 v) v))"
    )
    for _ in 0..<200 {
      _ = try heapInterpreter.evaluate("(let ((v (vector #f))) (vector-set! v 0 v) #f)")
    }
    let beforeCollection = heapInterpreter.heapStatistics
    let afterCollection = heapInterpreter.collectGarbage()
    #expect(afterCollection.collected >= 200, "cycle collector reclaims unreachable cycles")
    #expect(afterCollection.live < beforeCollection.live, "cycle collector reduces live heap")
    #expect(
      try heapInterpreter.evaluate("(eq? survivor (vector-ref survivor 0))").written == "#t",
      "cycle collector retains reachable survivor"
    )
    #expect(afterCollection.live >= baseline.live, "cycle collector preserves baseline roots")

    let continuationHeap = Interpreter(output: { _ in })
    _ = try continuationHeap.evaluate(
      "(define saved #f) (define phase 0) (define result #f) (set! result (call/cc (lambda (k) (set! saved k) 'initial)))"
    )
    _ = continuationHeap.collectGarbage()
    _ = try continuationHeap.evaluate(
      "(if (= phase 0) (begin (set! phase 1) (saved 'resumed)) result)"
    )
    #expect(
      try continuationHeap.evaluate("result").written == "resumed",
      "captured continuation survives collection"
    )

    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
      "swiftscheme-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let inputPath = temporary.appendingPathComponent("input.scm").path
    let outputPath = temporary.appendingPathComponent("output.txt").path
    try "a b".write(toFile: inputPath, atomically: true, encoding: .utf8)
    func quotedPath(_ path: String) -> String {
      "\""
        + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
          of: "\"",
          with: "\\\""
        ) + "\""
    }
    try expect(
      """
      (define saved #f)
      (define phase 0)
      (define observed #f)
      (define escaped #f)
      (define (run)
        (call/cc (lambda (escape)
          (set! escaped escape)
          (with-input-from-file \(quotedPath(inputPath))
            (lambda ()
              (read)
              (call/cc (lambda (k) (set! saved k)))
              (if (= phase 0) (escaped 'left) (set! observed (read))))))))
      (run)
      (if (= phase 0) (begin (set! phase 1) (saved 'again)))
      observed
      """,
      "b",
      "with-input-from-file continuation exit/re-entry"
    )
    try expect(
      """
      (define saved #f)
      (define phase 0)
      (define result #f)
      (define escaped #f)
      (define (run)
        (set! result
          (call/cc (lambda (escape)
            (set! escaped escape)
            (with-output-to-file \(quotedPath(outputPath))
              (lambda ()
                (display "a")
                (call/cc (lambda (k) (set! saved k)))
                (if (= phase 0) (escaped 'left) (display "b"))))))))
      (run)
      (if (= phase 0) (begin (set! phase 1) (saved 'again)))
      result
      """,
      "#<unspecified>",
      "with-output-to-file continuation exit/re-entry"
    )
    let fileOutput = try String(contentsOfFile: outputPath, encoding: .utf8)
    #expect(fileOutput == "ab", "with-output-to-file re-entry")
  }
}

@Suite("SwiftScheme BigInt kernel") struct SwiftSchemeBigIntTests {
  @Test("arithmetic, division, radix, and conversion invariants") func bigIntKernel() throws {
    try runBigIntKernelChecks()
  }
}
