import SwiftScheme
import Testing

@MainActor private func evaluateDerived(_ source: String) throws -> Value {
  try Interpreter { _ in }.evaluate(source)
}

@MainActor private func expectDerivedError(_ source: String, _ label: String) {
  do {
    _ = try evaluateDerived(source)
    #expect(Bool(false), "\(label): expected SchemeError")
  } catch is SchemeError {} catch {
    #expect(Bool(false), "\(label): expected SchemeError, got \(error)")
  }
}

@Suite("R5RS §4.2 derived expressions and §6.4 control domains") @MainActor
struct R5RSDerivedControlTests {
  @Test("derived syntax and helper procedures resist lexical shadowing") func derivedHygiene()
    throws
  {
    let result = try evaluateDerived(
      """
      (list
        (let ((if (lambda args 99))) (and #t 42))
        (let ((if (lambda args 99))) (cond (#t 42)))
        (let ((eqv? (lambda args #f))) (case 1 ((1) 42) (else 99)))
        (let ((cons (lambda args 0))) `(1 2))
        (let ((append (lambda args 0))) `(1 ,@(list 2 3)))
        (let ((list->vector (lambda args 0))) `#(1 2))
        (let ((items '(2 3))) `#(1 ,@items 4))
        (let ((let (lambda args 99))) (let* ((x 1)) x))
        (let ((begin (lambda args 99))) (let* ((x 1)) x))
        (let ((letrec (lambda args 99)))
          (let loop ((i 0)) (if (= i 1) i (loop (+ i 1)))))
        (let ((if (lambda args 99)))
          (do ((i 0 (+ i 1))) ((= i 1) i))))
      """
    )
    #expect(result.written == "(42 42 42 (1 2) (1 2 3) #(1 2) #(1 2 3 4) 1 1 1 1)")
  }

  @Test("derived forms evaluate only selected branches and iterate lazily")
  func derivedEvaluationLaziness() throws {
    let result = try evaluateDerived(
      """
      (let ((x 0))
        (list (and #f (set! x 1))
              (or #t (set! x 2))
              (cond (#f (set! x 3)) (else x))
              (case 1 ((2) (set! x 4)) ((1) (set! x 5)) (else (set! x 6)))
              x))
      """
    )
    #expect(result.written == "(#f #t 0 #<unspecified> 5)")
    #expect(
      try evaluateDerived("(let ((x 0)) (do ((i 0 (+ i 1))) ((= i 2) x) (set! x (+ x 1))))").written
        == "2"
    )
  }

  @Test("named let expands recursive bindings with parallel initializers") func namedLetBoundaries()
    throws
  {
    #expect(
      try evaluateDerived(
        "(let loop ((i 0) (sum 0)) " + "(if (= i 4) sum (loop (+ i 1) (+ sum i))))"
      ).written == "6"
    )
    #expect(try evaluateDerived("(let* ((x 1) (x (+ x 1))) x)").written == "2")
    expectDerivedError("(let loop ((x 1) (x 2)) x)", "duplicate named-let binding")
  }

  @Test("derived forms reject malformed clauses, duplicate keys, and expression definitions")
  func malformedDerivedForms() throws {
    expectDerivedError("(cond)", "empty cond")
    expectDerivedError("(case 1)", "empty case")
    expectDerivedError("(cond (else))", "empty cond else body")
    expectDerivedError("(begin)", "empty begin")
    expectDerivedError("(if #t (define x 1) 2)", "expression definition")
    expectDerivedError("(cond (#t (define x 1) x))", "cond definition")
    expectDerivedError("(case 1 ((1) (define x 1) x))", "case definition")
    expectDerivedError("(do () (#t) (define x 1))", "do command definition")
    expectDerivedError("(do () (#t (define x 1)))", "do result definition")
    #expect(try evaluateDerived("(case 1 ((1 1) 42))").written == "42")
    #expect(
      try evaluateDerived("(case 1 ((1) 'first) ((1) 'second) (else 'ok))").written == "first"
    )
    expectDerivedError("(let ((else #f)) (case 2 ((1) 42) (else 99)))", "lexically bound case else")
    expectDerivedError("(do ((x 0) (x 1)) ((= x 0) x))", "duplicate do variable")
  }

  @Test("case returns unspecified when no clause matches") func caseGrammarBoundaries() throws {
    expectDerivedError("(case 1)", "empty case")
    #expect(try evaluateDerived("(case 1 ((2) 42))").written == "#<unspecified>")
    #expect(try evaluateDerived("(cond (#f 42))").written == "#<unspecified>")
    #expect(try evaluateDerived("(if #f 42)").written == "#<unspecified>")
    #expect(try evaluateDerived("(case 1 ((1 1) 'ok))").written == "ok")
  }

  @Test("dynamic-wind discards all before and after values") func dynamicWindHookValues() throws {
    let result = try evaluateDerived(
      "(dynamic-wind (lambda () (values 1 2)) " + "(lambda () 42) (lambda () (values 3 4)))"
    )
    #expect(result.written == "42")
  }

  @Test("for-each discards all procedure values") func forEachProcedureValues() throws {
    let result = try evaluateDerived(
      "(call-with-output-string (lambda (p) " + "(for-each (lambda (x) (values x (+ x 1))) '(1 2)) "
        + "(display (symbol->string 'done) p)))"
    )
    #expect(result.written == "\"done\"")
  }

  @Test("control procedures validate procedure domains before side effects")
  func procedureDomainErrors() {
    expectDerivedError("(call-with-current-continuation 1)", "call/cc procedure")
    expectDerivedError("(call-with-values 1 (lambda () 1))", "call-with-values producer")
    expectDerivedError("(call-with-values (lambda () 1) 1)", "call-with-values consumer")
    expectDerivedError("(dynamic-wind 1 (lambda () 1) (lambda () 1))", "dynamic-wind before")
    expectDerivedError("(dynamic-wind (lambda () 1) 1 (lambda () 1))", "dynamic-wind thunk")
    expectDerivedError("(call-with-input-string \"\" 1)", "input-string procedure")
    expectDerivedError("(call-with-output-string 1)", "output-string procedure")
  }

  @Test("map and for-each validate procedures on empty lists") func emptyListProcedureDomains() {
    expectDerivedError("(map 1 '())", "map procedure")
    expectDerivedError("(for-each 1 '())", "for-each procedure")
  }

  @Test("R5RS §6.5 eval rejects non-expression data") func evalExpressionDomains() {
    expectDerivedError("(eval '() (null-environment 5))", "eval empty list")
    expectDerivedError("(eval '#(1 2) (null-environment 5))", "eval vector datum")
    expectDerivedError("(eval '(define eval-leak 1) (interaction-environment))", "eval definition")
    expectDerivedError(
      "(eval '(begin (define eval-leak 1) eval-leak) (interaction-environment))",
      "eval begin definition"
    )
    expectDerivedError("()", "empty application")
    expectDerivedError("#(1 2)", "vector expression")
  }

  @Test("generated syntax and temporary identifiers remain opaque through eval")
  func generatedTokensRemainOpaque() throws {
    let result = try evaluateDerived(
      """
      (let ((s (string->symbol
                 (string-append (string (integer->char 2)) "r5rs:temp:or#1"))))
        (eval (list 'let (list (list s 42)) (list 'or #f s))
              (interaction-environment)))
      """
    )
    #expect(result.written == "42")
    expectDerivedError(
      """
      (eval
        (list (string->symbol
                (string-append (string (integer->char 2)) "r5rs:syntax:if"))
              #t 1 2)
        (interaction-environment))
      """,
      "forged internal syntax marker"
    )
  }
}
