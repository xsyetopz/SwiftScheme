import SwiftScheme
import Testing

@MainActor
private func expectSyntaxError(
  _ operation: () throws -> Value,
  _ label: String
) {
  do {
    _ = try operation()
    #expect(Bool(false), "\(label): expected a Scheme syntax error")
  } catch let error as SchemeError {
    guard case .syntax(let message) = error else {
      #expect(Bool(false), "\(label): expected SchemeError.syntax, got \(error)")
      return
    }
    #expect(
      message == "definitions are not allowed in this environment",
      "\(label): unexpected diagnostic: \(message)"
    )
  } catch {
    #expect(Bool(false), "\(label): expected SchemeError, got \(error)")
  }
}

@MainActor
private func expectUnbound(
  _ operation: () throws -> Value,
  _ label: String
) {
  do {
    _ = try operation()
    #expect(Bool(false), "\(label): expected an unbound-variable error")
  } catch let error as SchemeError {
    guard case .unbound = error else {
      #expect(Bool(false), "\(label): expected SchemeError.unbound, got \(error)")
      return
    }
  } catch {
    #expect(Bool(false), "\(label): expected SchemeError, got \(error)")
  }
}

@MainActor
private func expectDefinitionRejected(
  environmentExpression: String,
  definition: String,
  probe: String,
  _ label: String
) throws {
  let interpreter = Interpreter(output: { _ in })
  _ = try interpreter.evaluate("(define r5rs-target \(environmentExpression))")

  expectSyntaxError(
    { try interpreter.evaluate("(eval '\(definition) r5rs-target)") },
    "\(label) definition"
  )
  expectUnbound(
    { try interpreter.evaluate("(eval '\(probe) r5rs-target)") },
    "\(label) binding probe"
  )
}

@Suite("R5RS environment definition policy")
@MainActor
struct R5RSEnvironmentTests {
  @Test("scheme-report-environment preserves expression evaluation")
  func reportEnvironmentEvaluatesExpressions() throws {
    let interpreter = Interpreter(output: { _ in })
    _ = try interpreter.evaluate("(define r5rs-target (scheme-report-environment 5))")
    #expect(try interpreter.evaluate("(eval '(+ 20 22) r5rs-target)").written == "42")
  }

  @Test("null-environment preserves syntax and literal evaluation")
  func nullEnvironmentEvaluatesExpressions() throws {
    let interpreter = Interpreter(output: { _ in })
    _ = try interpreter.evaluate("(define r5rs-target (null-environment 5))")
    #expect(try interpreter.evaluate("(eval '(if #f 1 2) r5rs-target)").written == "2")
  }

  @Test("scheme-report-environment excludes implementation-only extensions")
  func reportEnvironmentExcludesExtensions() throws {
    let interpreter = Interpreter(output: { _ in })
    _ = try interpreter.evaluate("(define r5rs-target (scheme-report-environment 5))")
    for name in ["open-input-string", "call-with-input-string", "port?", "flush-output", "error"] {
      expectUnbound(
        { try interpreter.evaluate("(eval '\(name) r5rs-target)") },
        "report extension \(name)"
      )
    }
    #expect(try interpreter.evaluate("(eval 'values r5rs-target)").written == "#<procedure>")
    #expect(try interpreter.evaluate("(eval 'input-port? r5rs-target)").written == "#<procedure>")
  }

  @Test("scheme-report-environment rejects value definitions without a binding")
  func reportEnvironmentRejectsValueDefinition() throws {
    try expectDefinitionRejected(
      environmentExpression: "(scheme-report-environment 5)",
      definition: "(define r5rs-value-leak 42)",
      probe: "r5rs-value-leak",
      "scheme-report-environment value"
    )
  }

  @Test("null-environment rejects value definitions without a binding")
  func nullEnvironmentRejectsValueDefinition() throws {
    try expectDefinitionRejected(
      environmentExpression: "(null-environment 5)",
      definition: "(define r5rs-value-leak 42)",
      probe: "r5rs-value-leak",
      "null-environment value"
    )
  }

  @Test("scheme-report-environment rejects syntax definitions without a macro")
  func reportEnvironmentRejectsSyntaxDefinition() throws {
    try expectDefinitionRejected(
      environmentExpression: "(scheme-report-environment 5)",
      definition: "(define-syntax r5rs-syntax-leak (syntax-rules () ((r5rs-syntax-leak) 42)))",
      probe: "(r5rs-syntax-leak)",
      "scheme-report-environment syntax"
    )
  }

  @Test("null-environment rejects syntax definitions without a macro")
  func nullEnvironmentRejectsSyntaxDefinition() throws {
    try expectDefinitionRejected(
      environmentExpression: "(null-environment 5)",
      definition: "(define-syntax r5rs-syntax-leak (syntax-rules () ((r5rs-syntax-leak) 42)))",
      probe: "(r5rs-syntax-leak)",
      "null-environment syntax"
    )
  }

  @Test("optional transcript procedures are omitted")
  func transcriptProceduresAreNotAdvertised() {
    let interpreter = Interpreter(output: { _ in })
    expectUnbound({ try interpreter.evaluate("transcript-on") }, "transcript-on")
    expectUnbound({ try interpreter.evaluate("transcript-off") }, "transcript-off")
  }
}
