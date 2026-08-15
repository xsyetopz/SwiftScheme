import SwiftScheme
import Testing

@Suite("R5RS §6 required procedure inventory") @MainActor struct R5RSProcedureInventoryTests {
  @Test("every required procedure name is bound as a procedure") func requiredProcedureBindings()
    throws
  {
    let names = r5rsRequiredProcedureNames
    let interpreter = Interpreter { _ in }
    for name in Set(names) {
      #expect(
        try interpreter.evaluate("(procedure? \(name))").written == "#t",
        "missing required procedure binding: \(name)"
      )
    }
  }

  @Test("supported optional procedure names are bound separately")
  func supportedOptionalProcedureBindings() throws {
    let names = ["interaction-environment", "with-input-from-file", "with-output-to-file", "load"]
    let interpreter = Interpreter { _ in }
    for name in names {
      #expect(
        try interpreter.evaluate("(procedure? \(name))").written == "#t",
        "missing supported optional procedure binding: \(name)"
      )
    }
  }
}
