import SwiftSchemeRuntime

extension Interpreter {

  func validateBody(_ body: [Value], context: String, in environment: SchemeEnvironment) throws {
    let expanded = try expandedBody(body, in: environment)
    var sawExpression = false
    for form in expanded {
      if isDefinitionForm(form, "define", in: environment)
        || isDefinitionForm(form, "define-syntax", in: environment)
      {
        if sawExpression { throw SchemeError.syntax("definition after expression in \(context)") }
        if isDefinitionForm(form, "define-syntax", in: environment) {
          throw SchemeError.syntax("define-syntax is only valid at top level")
        }
      } else {
        sawExpression = true
      }
    }
    guard sawExpression else { throw SchemeError.syntax("\(context) requires an expression") }
  }

  func validateExpressionBody(_ body: [Value], context: String, in environment: SchemeEnvironment)
    throws
  {
    let expanded = try expandedBody(body, in: environment)
    guard !expanded.isEmpty else { throw SchemeError.syntax("\(context) requires an expression") }
    guard
      !expanded.contains(where: {
        isDefinitionForm($0, "define", in: environment)
          || isDefinitionForm($0, "define-syntax", in: environment)
      })
    else { throw SchemeError.syntax("\(context) accepts expressions only") }
  }

  func validateExpressionSequence(
    _ forms: [Value],
    context: String,
    in environment: SchemeEnvironment,
    requireOne: Bool = true
  ) throws {
    let expanded = try expandedBody(forms, in: environment)
    if requireOne, expanded.isEmpty {
      throw SchemeError.syntax("\(context) requires an expression")
    }
    guard
      !expanded.contains(where: {
        isDefinitionForm($0, "define", in: environment)
          || isDefinitionForm($0, "define-syntax", in: environment)
      })
    else { throw SchemeError.syntax("\(context) accepts expressions only") }
  }
}
