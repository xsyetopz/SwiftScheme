import SwiftScheme
import Testing

private func expectR5RSyntaxError(_ source: String, _ label: String) {
  do {
    _ = try Interpreter { _ in }.evaluate(source)
    #expect(Bool(false), "\(label): expected a syntax error")
  } catch let error as SchemeError {
    guard case .syntax = error else {
      #expect(Bool(false), "\(label): expected SchemeError.syntax, got \(error)")
      return
    }
  } catch { #expect(Bool(false), "\(label): expected SchemeError, got \(error)") }
}

@Suite("R5RS §4.3 and §5 definition/macro grammar") @MainActor struct R5RSMacroDefinitionTests {
  @Test("top-level definitions may be interleaved with expressions")
  func topLevelDefinitionOrdering() throws {
    let interpreter = Interpreter { _ in }
    let result = try interpreter.evaluate(
      "(define top-level-value 1) top-level-value "
        + "(define top-level-value 2) (begin (define top-level-value 3) top-level-value)"
    )
    #expect(result.written == "3")
    #expect(try interpreter.evaluate("top-level-value").written == "3")
  }

  @Test("malformed top-level definitions report syntax errors") func malformedTopLevelDefinitions()
  {
    for source in [
      "(define 1 2)", "(define value 1 2)", "(define (duplicate x x) x)",
      "(define-syntax 1 (syntax-rules () ((m) 1)))",
    ] {
      do {
        _ = try Interpreter { _ in }.evaluate(source)
        #expect(Bool(false), "malformed top-level definition unexpectedly succeeded")
      } catch is SchemeError {
        // Any SchemeError is an appropriate diagnostic for malformed syntax.
      } catch { #expect(Bool(false), "malformed top-level definition raised a non-Scheme error") }
    }
  }

  @Test("syntax-rules ellipsis remains reserved despite a definition-site binding")
  func ellipsisDefinitionSiteBinding() throws {
    let result = try Interpreter { _ in }.evaluate(
      """
      (let ((... 2))
        (let-syntax ((s (syntax-rules ()
                         ((_ x ...) 'bad)
                         ((_ . r) 'ok))))
          (s a b c)))
      """
    )
     #expect(result.written == "ok")
  }

  @Test("syntax-rules template ellipsis remains reserved despite a value binding")
  func templateEllipsisDefinitionSiteBinding() throws {
    expectR5RSyntaxError(
      """
      (let ((... 2))
        (let-syntax ((s (syntax-rules () ((_ x ...) (list x ...)))))
          (s 1 2 3)))
      """, "template ellipsis shadowing")
  }

  @Test("syntax-rules treats a non-head underscore as a pattern variable")
  func underscorePatternVariable() throws {
    let interpreter = Interpreter { _ in }
    _ = try interpreter.evaluate("(define-syntax underscore (syntax-rules () ((underscore _) _)))")
    #expect(try interpreter.evaluate("(underscore 42)").written == "42")
  }

  @Test("syntax-rules can match underscore as an explicit literal") func underscoreLiteral() throws
  {
    let result = try Interpreter { _ in }.evaluate(
      "(let-syntax ((m (syntax-rules (_) ((m _) 'ok)))) (m _))"
    )
    #expect(result.written == "ok")
  }

  @Test("top-level syntax bindings shadow existing value bindings") func syntaxShadowsValue() throws
  {
    let interpreter = Interpreter { _ in }
    _ = try interpreter.evaluate("(define-syntax + (syntax-rules () ((+ left right) left)))")
    #expect(try interpreter.evaluate("(+ 20 22)").written == "20")
  }

  @Test("syntax-rules rejects repeated pattern variables and custom ellipses")
  func malformedSyntaxRules() {
    expectR5RSyntaxError(
      "(define-syntax same (syntax-rules () ((same value value) value)))",
      "repeated pattern variable"
    )

    expectR5RSyntaxError(
      "(define-syntax invalid (syntax-rules (...) ((invalid value) value)))",
      "ellipsis literal"
    )
    expectR5RSyntaxError("(define-syntax m (syntax-rules () ((other) 1)))", "pattern keyword")
    expectR5RSyntaxError(
      "(define-syntax malformed (syntax-rules () ((malformed ... value) value)))",
      "leading ellipsis"
    )
    expectR5RSyntaxError(
      "(define-syntax malformed (syntax-rules () ((malformed value ... value) value)))",
      "non-final ellipsis"
    )
  }

  @Test("syntax-rules permits an empty rule set") func emptySyntaxRules() throws {
    let interpreter = Interpreter { _ in }
    _ = try interpreter.evaluate("(define-syntax never (syntax-rules ()))")
    do {
      _ = try interpreter.evaluate("(never)")
      #expect(Bool(false), "empty syntax-rules transformer invocation: expected an error")
    } catch let error as SchemeError {
      guard case .syntax = error else {
        #expect(Bool(false), "empty syntax-rules transformer invocation: expected syntax error")
        return
      }
    }
  }

  @Test("syntax-rules keeps core template forms hygienic") func coreTemplateHygiene() throws {
    let result = try Interpreter { _ in }.evaluate(
      """
      (define-syntax when
        (syntax-rules () ((when test body ...) (if test (begin body ...)))))
      (define-syntax quoted (syntax-rules () ((quoted) 'ok)))
      (define-syntax quasiquoted
        (syntax-rules () ((quasiquoted value) `(if ,value))))
      (list
        (let ((if (lambda args 99))) (when #t 42))
        (let ((quote (lambda args 99))) (quoted))
        (quasiquoted 42))
      """
    )
    #expect(result.written == "(42 ok (if 42))")
  }

  @Test("syntax-rules keeps quasiquote data hygienic through repetitions")
  func quasiquoteTemplateHygiene() throws {
    let result = try Interpreter { _ in }.evaluate(
      """
      (let ((x 'definition))
        (let-syntax ((quoted
                       (syntax-rules () ((quoted value ...) `(x ,value ...)))))
          (let ((x 'use)) (quoted 1 2))))
      """
    )
    #expect(result.written == "(x 1 2)")
  }

  @Test("syntax-rules preserves definition-site literal template bindings")
  func literalTemplateBinding() throws {
    let result = try Interpreter { _ in }.evaluate(
      """
      (let ((x 'definition))
        (let-syntax ((literal-reference
                       (syntax-rules (x) ((literal-reference) x))))
          (let ((x 'use)) (literal-reference))))
      """
    )
    #expect(result.written == "definition")
  }

  @Test("syntax-rules resolves literal templates through macro bindings")
  func literalTemplateMacroBinding() throws {
    let result = try Interpreter { _ in }.evaluate(
      """
      (let ((lit 'outer))
        (let-syntax ((lit (syntax-rules () ((lit) 'inner))))
          (let-syntax ((reference (syntax-rules (lit) ((reference) (lit)))))
            (reference))))
      """
    )
    #expect(result.written == "inner")
  }

  @Test("syntax-rules matches repeated literal patterns") func repeatedPatternBacktracking() throws
  {
    let interpreter = Interpreter { _ in }
    let result = try interpreter.evaluate(
      """
      (define-syntax pick
        (syntax-rules (marker stop)
          ((pick (marker ...) stop) 'ok)))
      (pick (marker marker) stop)
      """
    )
    #expect(result.written == "ok")
  }

  @Test("let-syntax bodies admit internal definitions") func syntaxBodiesAreDefinitions() throws {
    let result = try Interpreter { _ in }.evaluate("(let-syntax () (define value 1) value)")
    #expect(result.written == "1")
    do { _ = try Interpreter { _ in }.evaluate("(letrec-syntax () (define-syntax nested (syntax-rules ())) nested)"); #expect(Bool(false)) } catch { #expect(String(describing: error).contains("unbound variable")) }
  }

  @Test("syntax-rules expands vector repetitions") func vectorRepetition() throws {
    let interpreter = Interpreter { _ in }
    let result = try interpreter.evaluate(
      """
      (define-syntax collect-vector
        (syntax-rules ()
          ((collect-vector #(items ...)) '#(items ...))))
      (collect-vector #(1 2 3))
      """
    )
    #expect(result.written == "#(1 2 3)")
  }

  @Test("syntax-rules substitutes repeated variables in quoted data") func quotedRepetition() throws
  {
    let interpreter = Interpreter { _ in }
    let result = try interpreter.evaluate(
      """
      (define-syntax quote-items
        (syntax-rules ()
          ((quote-items (items ...)) '(items ...))))
      (quote-items (a b c))
      """
    )
    #expect(result.written == "(a b c)")
  }

  @Test("letrec-syntax exposes mutually recursive transformers during capture")
  func recursiveSyntaxBindings() throws {
    let result = try Interpreter { _ in }.evaluate(
      """
      (letrec-syntax
        ((a (syntax-rules (b) ((a) (b))))
         (b (syntax-rules () ((b) 'ok))))
        (a))
      """
    )
    #expect(result.written == "ok")
  }

  @Test("syntax-rules transcribes dotted templates") func dottedTemplate() throws {
    let interpreter = Interpreter { _ in }
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
    let interpreter = Interpreter { _ in }
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

  @Test("internal definitions form the initial body group") func legalInternalDefinitions() throws {
    let interpreter = Interpreter { _ in }
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
    let interpreter = Interpreter { _ in }
    let result = try interpreter.evaluate(
      "((lambda () (define read-later (lambda () later)) (define later 42) (read-later)))"
    )
    #expect(result.written == "42")
  }

  @Test("definitions after an expression are rejected") func definitionAfterExpression() {
    expectR5RSyntaxError("((lambda () 1 (define late 2) late))", "definition after expression")
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
    let interpreter = Interpreter { _ in }
    _ = try interpreter.evaluate("(define-syntax m (syntax-rules () ((m) (define shadowed 1))))")
    #expect(try interpreter.evaluate("((lambda (m) 1 (m)) (lambda () 8))").written == "8")
  }

  @Test("internal syntax definitions are rejected") func internalSyntaxDefinition() {
    expectR5RSyntaxError(
      "((lambda () (define-syntax local (syntax-rules () ((local) 1))) (local)))",
      "internal define-syntax"
    )
  }

  @Test("definitions classify keywords while lexical bindings may shadow them")
  func syntacticKeywordDefinitions() throws {
    expectR5RSyntaxError("(define define 3)", "define keyword")
    expectR5RSyntaxError("(begin (define begin list))", "begin keyword")
    let topLevel = Interpreter { _ in }
    _ = try topLevel.evaluate("(define-syntax if (syntax-rules () ((if x y) (+ x y))))")
    #expect(try topLevel.evaluate("(if 20 22)").written == "42")
    expectR5RSyntaxError("((lambda () (define x 1) (define x 2) x))", "duplicate internal")
    expectR5RSyntaxError(
      "(let-syntax ((m (syntax-rules () ((m) 1))) (m (syntax-rules () ((m) 2)))) (m))",
      "duplicate let-syntax binding"
    )
    let interpreter = Interpreter { _ in }
    #expect(try interpreter.evaluate("((lambda (if) if) 1)").written == "1")
    #expect(try interpreter.evaluate("(let ((if 1)) (set! if 2) if)").written == "2")
    #expect(
      try interpreter.evaluate("(let-syntax ((if (syntax-rules () ((if) 1)))) (if))").written == "1"
    )
  }

  @Test("a value binding named define is an ordinary operator")
  func formalNamedDefineShadowsDefinitionSyntax() throws {
    let interpreter = Interpreter { _ in }
    #expect(try interpreter.evaluate("((lambda (define) (define 20 22)) +)").written == "42")
  }

  @Test("internal definition names shadow outer macros during body expansion")
  func internalDefinitionPrebindingShadowsMacro() throws {
    let interpreter = Interpreter { _ in }
    _ = try interpreter.evaluate("(define-syntax m (syntax-rules () ((m) (define late 1))))")
    #expect(try interpreter.evaluate("((lambda () (define m (lambda () 8)) 1 (m)))").written == "8")
  }

  @Test("macro-generated leading definitions prebind before later expansion")
  func macroGeneratedLeadingDefinitionPrebinding() throws {
    let interpreter = Interpreter { _ in }
    let result = try interpreter.evaluate(
      """
      (define-syntax define-name
        (syntax-rules () ((_ name) (define name (lambda () 9)))))
      (define-syntax m (syntax-rules () ((m) 7)))
      ((lambda () (define-name m) 1 (m)))
      """
    )
    #expect(result.written == "9")
  }

  @Test("letrec initializer closures retain the enclosing binding cells")
  func letrecInitializerLexicalRegion() throws {
    let interpreter = Interpreter { _ in }
    let result = try interpreter.evaluate(
      "(letrec ((x (lambda () x)) (get (lambda () x))) " + "(define x 2) (procedure? (get)))"
    )
    #expect(result.written == "#t")
  }

  @Test("macro-generated duplicate internal definitions are rejected")
  func macroGeneratedDuplicateDefinitions() {
    expectR5RSyntaxError(
      """
      (define-syntax def
        (syntax-rules () ((_ x v) (define x v))))
      ((lambda () (def x 1) (def x 2) x))
      """,
      "macro/macro duplicate internal definitions"
    )
  }

  @Test("raw and macro-generated duplicate internal definitions are rejected")
  func rawAndMacroDuplicateDefinitions() {
    expectR5RSyntaxError(
      """
      (define-syntax def
        (syntax-rules () ((_ x v) (define x v))))
      ((lambda () (define x 1) (def x 2) x))
      """,
      "raw/macro duplicate internal definitions"
    )
  }

  @Test("macro-generated begin duplicates are not treated as raw forms")
  func macroGeneratedBeginDuplicateDefinitions() {
    expectR5RSyntaxError(
      """
      (define-syntax defs
        (syntax-rules () ((_ x v) (begin (define x v)))))
      ((lambda () (define x 1) (defs x 2) x))
      """,
      "raw/macro begin duplicate internal definitions"
    )
  }

  @Test("begin splices an initial definition group") func beginDefinitionGroup() throws {
    let interpreter = Interpreter { _ in }
    let result = try interpreter.evaluate("((lambda () (begin (define local 40)) (+ local 2)))")
    #expect(result.written == "42")
  }
}
