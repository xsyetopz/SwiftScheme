import SwiftScheme
import Testing

@MainActor
private func evaluateDerived(_ source: String) throws -> Value {
  try Interpreter(output: { _ in }).evaluate(source)
}

@MainActor
private func expectDerivedError(_ source: String, _ label: String) {
  do {
    _ = try evaluateDerived(source)
    #expect(Bool(false), "\(label): expected SchemeError")
  } catch is SchemeError {
    // R5RS specifies the error condition, not host diagnostic wording.
  } catch {
    #expect(Bool(false), "\(label): expected SchemeError, got \(error)")
  }
}

@Suite("R5RS §4.2 derived expressions and §6.4 control domains")
@MainActor
struct R5RSDerivedControlTests {
  @Test("derived syntax and helper procedures resist lexical shadowing")
  func derivedHygiene() throws {
    let result = try evaluateDerived(
      """
      (list
        (let ((if (lambda args 99))) (and #t 42))
        (let ((if (lambda args 99))) (cond (#t 42)))
        (let ((eqv? (lambda args #f))) (case 1 ((1) 42) (else 99)))
        (let ((cons (lambda args 0))) `(1 2))
        (let ((append (lambda args 0))) `(1 ,@(list 2 3)))
        (let ((list->vector (lambda args 0))) `#(1 2))
        (let ((let (lambda args 99))) (let* ((x 1)) x))
        (let ((begin (lambda args 99))) (let* ((x 1)) x))
        (let ((letrec (lambda args 99)))
          (let loop ((i 0)) (if (= i 1) i (loop (+ i 1)))))
        (let ((if (lambda args 99)))
          (do ((i 0 (+ i 1))) ((= i 1) i))))
      """
    )
    #expect(result.written == "(42 42 42 (1 2) (1 2 3) #(1 2) 1 1 1 1)")
  }

  @Test("derived forms reject malformed clauses, duplicate keys, and expression definitions")
  func malformedDerivedForms() {
    expectDerivedError("(cond)", "empty cond")
    expectDerivedError("(cond (else))", "empty cond else body")
    expectDerivedError("(begin)", "empty begin")
    expectDerivedError("(if #t (define x 1) 2)", "expression definition")
    expectDerivedError("(case 1 ((1 1) 42))", "duplicate case datum")
    expectDerivedError(
      "(case 2 ((1) 'first) ((1) 'second) (else 'ok))", "cross-clause case datum"
    )
    expectDerivedError(
      "(let ((else #f)) (case 2 ((1) 42) (else 99)))", "lexically bound case else"
    )
    expectDerivedError(
      "(do ((x 0) (x 1)) ((= x 0) x))", "duplicate do variable"
    )
  }

  @Test("map and for-each validate procedures on empty lists")
  func emptyListProcedureDomains() {
    expectDerivedError("(map 1 '())", "map procedure")
    expectDerivedError("(for-each 1 '())", "for-each procedure")
  }

  @Test("R5RS §6.5 eval rejects non-expression data")
  func evalExpressionDomains() {
    expectDerivedError("(eval '() (null-environment 5))", "eval empty list")
    expectDerivedError("(eval '#(1 2) (null-environment 5))", "eval vector datum")
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
