import SwiftScheme
import Testing

@MainActor
private func expectR5RSyntaxError(_ source: String, _ label: String) {
  do {
    _ = try Interpreter(output: { _ in }).evaluate(source)
    #expect(Bool(false), "(label): expected a syntax error")
  } catch let error as SchemeError {
    guard case .syntax = error else {
      #expect(Bool(false), "(label): expected SchemeError.syntax, got (error)")
      return
    }
  } catch {
    #expect(Bool(false), "(label): expected SchemeError, got (error)")
  }
}

@Suite("R5RS §4.3 and §5 definition/macro grammar")
@MainActor
struct R5RSMacroDefinitionTests {
  @Test("syntax-rules transcribes dotted templates")
  func dottedTemplate() throws {
    let interpreter = Interpreter(output: { _ in })
    let result = try interpreter.evaluate(
      """
      (define-syntax make-dotted
        (syntax-rules ()
          ((make-dotted head tail) '(head . tail))))
      (make-dotted 1 2)
      """
    )
    #expect(result.written == "(1 . 2)")
  }

  @Test("syntax-rules matches dotted patterns and letrec-syntax binds locally")
  func dottedPatternAndLetrecSyntax() throws {
    let interpreter = Interpreter(output: { _ in })
    let result = try interpreter.evaluate(
      """
      (define-syntax capture-tail
        (syntax-rules ()
          ((capture-tail head . tail) '(head . tail))))
      (list (capture-tail 1 2 3)
        (letrec-syntax ((identity
          (syntax-rules () ((identity value) value))))
          (identity 42)))
      """
    )
    #expect(result.written == "((1 2 3) 42)")
  }

  @Test("internal definitions form the initial body group")
  func legalInternalDefinitions() throws {
    let interpreter = Interpreter(output: { _ in })
    let result = try interpreter.evaluate(
      """
      ((lambda ()
         (define (answer) 41)
         (define increment 1)
         (+ (answer) increment)))
      """
    )
    #expect(result.written == "42")
  }

  @Test("internal definition initializers use the shared body region")
  func internalDefinitionRegion() throws {
    let interpreter = Interpreter(output: { _ in })
    let result = try interpreter.evaluate(
      "((lambda () (define read-later (lambda () later)) (define later 42) (read-later)))"
    )
    #expect(result.written == "42")
  }

  @Test("definitions after an expression are rejected")
  func definitionAfterExpression() {
    expectR5RSyntaxError(
      "((lambda () 1 (define late 2) late))",
      "definition after expression"
    )
  }

  @Test("internal syntax definitions are rejected")
  func internalSyntaxDefinition() {
    expectR5RSyntaxError(
      "((lambda () (define-syntax local (syntax-rules () ((local) 1))) (local)))",
      "internal define-syntax"
    )
  }

  @Test("definitions cannot shadow syntactic keywords")
  func syntacticKeywordDefinitions() {
    expectR5RSyntaxError("(define define 3)", "define keyword")
    expectR5RSyntaxError("(begin (define begin list))", "begin keyword")
    expectR5RSyntaxError("(define-syntax if (syntax-rules () ((if) 1)))", "if keyword")
    expectR5RSyntaxError("((lambda () (define x 1) (define x 2) x))", "duplicate internal")
    expectR5RSyntaxError("((lambda (if) if) 1)", "lambda keyword parameter")
    expectR5RSyntaxError("(let ((if 1)) if)", "let keyword binding")
    expectR5RSyntaxError("(set! if 1)", "set keyword target")
    expectR5RSyntaxError(
      "(let-syntax ((if (syntax-rules () ((if) 1)))) (if))", "let-syntax keyword binding"
    )
    expectR5RSyntaxError(
      "(let-syntax ((m (syntax-rules () ((m) 1))) (m (syntax-rules () ((m) 2)))) (m))",
      "duplicate let-syntax binding"
    )
  }

  @Test("begin splices an initial definition group")
  func beginDefinitionGroup() throws {
    let interpreter = Interpreter(output: { _ in })
    let result = try interpreter.evaluate(
      "((lambda () (begin (define local 40)) (+ local 2)))"
    )
    #expect(result.written == "42")
  }
}
