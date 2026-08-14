import SwiftScheme
import Testing

@MainActor
private func expectR5RSyntaxError(_ source: String, _ label: String) {
  do {
    _ = try Interpreter(output: { _ in }).evaluate(source)
    #expect(Bool(false), "\(label): expected a syntax error")
  } catch let error as SchemeError {
    guard case .syntax = error else {
      #expect(Bool(false), "\(label): expected SchemeError.syntax, got \(error)")
      return
    }
  } catch {
    #expect(Bool(false), "\(label): expected SchemeError, got \(error)")
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

  @Test("macro-expanded definitions obey body ordering")
  func macroExpandedDefinitionAfterExpression() {
    expectR5RSyntaxError(
      """
      (define-syntax define-late
        (syntax-rules () ((define-late name value) (define name value))))
      ((lambda () 1 (define-late late 42) late))
      """,
      "macro-expanded definition after expression"
    )
  }

  @Test("lexical variables shadow macros during body classification")
  func lexicalVariableShadowsMacroDuringValidation() throws {
    let interpreter = Interpreter(output: { _ in })
    _ = try interpreter.evaluate(
      "(define-syntax m (syntax-rules () ((m) (define shadowed 1))))"
    )
    #expect(
      try interpreter.evaluate("((lambda (m) 1 (m)) (lambda () 8))").written == "8"
    )
  }

  @Test("internal syntax definitions are rejected")
  func internalSyntaxDefinition() {
    expectR5RSyntaxError(
      "((lambda () (define-syntax local (syntax-rules () ((local) 1))) (local)))",
      "internal define-syntax"
    )
  }

  @Test("definitions classify keywords while lexical bindings may shadow them")
  func syntacticKeywordDefinitions() throws {
    expectR5RSyntaxError("(define define 3)", "define keyword")
    expectR5RSyntaxError("(begin (define begin list))", "begin keyword")
    expectR5RSyntaxError("(define-syntax if (syntax-rules () ((if) 1)))", "if keyword")
    expectR5RSyntaxError("((lambda () (define x 1) (define x 2) x))", "duplicate internal")
    expectR5RSyntaxError(
      "(let-syntax ((m (syntax-rules () ((m) 1))) (m (syntax-rules () ((m) 2)))) (m))",
      "duplicate let-syntax binding"
    )
    let interpreter = Interpreter(output: { _ in })
    #expect(try interpreter.evaluate("((lambda (if) if) 1)").written == "1")
    #expect(try interpreter.evaluate("(let ((if 1)) (set! if 2) if)").written == "2")
    #expect(
      try interpreter.evaluate("(let-syntax ((if (syntax-rules () ((if) 1)))) (if))").written
        == "1"
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
