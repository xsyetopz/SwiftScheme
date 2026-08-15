import Foundation
import SwiftSchemeNumeric
import SwiftSchemeRuntime

package let internalSyntaxPrefix = internalSymbolPrefix + "syntax:"
package let internalTemporaryPrefix = internalSymbolPrefix + "temp:"

package func internalSyntax(_ name: String) -> Value { .symbol(internalSyntaxPrefix + name) }

package func internalSyntaxName(_ value: Value) -> String? {
  guard case .symbol(let name) = value, name.hasPrefix(internalSyntaxPrefix) else { return nil }
  return String(name.dropFirst(internalSyntaxPrefix.count))
}

package func internalTemporary(_ name: String) -> Value { .symbol(internalTemporaryPrefix + name) }

package func markLiteral(_ value: Value, _ seen: inout Set<ObjectIdentifier>) {
  switch value {
  case .pair(let pair):
    guard seen.insert(ObjectIdentifier(pair)).inserted else { return }
    pair.isLiteral = true
    markLiteral(pair.car, &seen)
    markLiteral(pair.cdr, &seen)
  case .vector(let vector):
    guard seen.insert(ObjectIdentifier(vector)).inserted else { return }
    vector.isLiteral = true
    vector.elements.forEach { markLiteral($0, &seen) }
  case .string(let string): string.isLiteral = true
  default: break
  }
}

package func array(from list: Value, context: String = "list") throws -> [Value] {
  var values: [Value] = []
  var cursor = list
  var seen = Set<ObjectIdentifier>()
  while case .pair(let pair) = cursor {
    guard seen.insert(ObjectIdentifier(pair)).inserted else {
      throw SchemeError.type("\(context) must not be cyclic")
    }
    values.append(pair.car)
    cursor = pair.cdr
  }
  guard case .empty = cursor else { throw SchemeError.type("\(context) must be a proper list") }
  return values
}

package func identifier(_ value: Value, _ context: String) throws -> String {
  guard case .symbol(let name) = value else {
    throw SchemeError.syntax("\(context) requires an identifier")
  }
  return name
}

package func isFalse(_ value: Value) -> Bool {
  if case .boolean(false) = value { return true }
  return false
}

indirect enum Capture {
  case value(Value)
  case sequence([Self])
}

package final class SyntaxRules: SchemeMacro {
  enum LiteralBinding {
    case cell(Cell)
    case macro(any SchemeMacro)
    case unbound
  }
  let keyword: String
  let literals: Set<String>
  var rules: [(Value, Value)]
  var definition: SchemeEnvironment?
  let ellipsis: String?
  var literalBindings: [String: LiteralBinding] = [:]
  var aliases: [String: String] = [:]
  var introduced: [String: String] = [:]

  package init(keyword: String, spec: Value, definition: SchemeEnvironment) throws {
    let form = try array(from: spec, context: "syntax-rules")
    guard form.count >= 3, case .symbol("syntax-rules") = form[0] else {
      throw SchemeError.syntax("transformer must be syntax-rules")
    }
    self.keyword = keyword
    self.ellipsis = "..."
    guard form.count >= 2 else { throw SchemeError.syntax("syntax-rules requires a literals list") }
    let literalValues: [Value]
    do { literalValues = try array(from: form[1], context: "syntax-rules literals") } catch {
      throw SchemeError.syntax("syntax-rules literals must be a proper list")
    }
    let literalNames = try literalValues.map { try identifier($0, "syntax-rules literal") }
    guard !literalNames.contains("...") else {
      throw SchemeError.syntax("ellipsis cannot be a syntax-rules literal")
    }
    self.literals = Set(literalNames)
    self.rules = try form.dropFirst(2).map {
      let rule = try array(from: $0, context: "syntax rule")
      guard rule.count == 2 else {
        throw SchemeError.syntax("syntax rule requires pattern and template")
      }
      return (rule[0], rule[1])
    }
    for (pattern, _) in rules {
      var patternVariables = Set<String>()
      try validatePattern(pattern, into: &patternVariables)
    }
    self.definition = definition
    for name in literals {
      if let cell = definition.cell(name) {
        literalBindings[name] = .cell(cell)
      } else if let macro = definition.macro(name) {
        literalBindings[name] = .macro(macro)
      } else {
        literalBindings[name] = .unbound
      }
    }
    for name in freeIdentifiers()
    where definition.cell(name) == nil && definition.macro(name) == nil {
      definition.define(name, .undefined)
    }
    registerSchemeNode(self)
  }

  package func traceSchemeChildren(_ visit: (any SchemeHeapNode) -> Void) {
    if let definition { visit(definition) }
    for (pattern, template) in rules {
      traceValue(pattern, visit)
      traceValue(template, visit)
    }
    for binding in literalBindings.values {
      switch binding {
      case .cell(let cell): visit(cell)
      case .macro(let macro): visit(macro)
      case .unbound: break
      }
    }
  }
  package func breakSchemeCycles() {
    definition = nil
    rules.removeAll()
    literalBindings.removeAll()
    aliases.removeAll()
    introduced.removeAll()
  }

  private func validatePattern(_ pattern: Value, into variables: inout Set<String>) throws {
    guard case .pair = pattern else {
      throw SchemeError.syntax("syntax-rules pattern requires a keyword")
    }
    try validatePatternSequence(pattern, head: true, into: &variables)
  }

  private func validatePatternSequence(
    _ value: Value,
    head: Bool,
    into variables: inout Set<String>
  ) throws {
    var cursor = value
    var first = true
    var previousWasPattern = false
    while case .pair(let pair) = cursor {
      if first && head {
        guard case .symbol(let name) = pair.car, name != ellipsis else {
          throw SchemeError.syntax("syntax-rules pattern requires a keyword")
        }
        try walkPattern(pair.car, head: true, into: &variables)
      } else if isEllipsis(pair.car) {
        guard previousWasPattern, case .empty = pair.cdr else {
          throw SchemeError.syntax("ellipsis must terminate a nonempty pattern sequence")
        }
        previousWasPattern = false
      } else {
        try walkPattern(pair.car, head: false, into: &variables)
        previousWasPattern = true
      }
      first = false
      cursor = pair.cdr
    }
    if case .empty = cursor { return }
    guard !isEllipsis(cursor) else {
      throw SchemeError.syntax("ellipsis cannot be a dotted pattern tail")
    }
    try walkPattern(cursor, head: false, into: &variables)
  }

  private func isEllipsis(_ value: Value) -> Bool {
    guard case .symbol(let name) = value else { return false }
    return name == ellipsis
  }

  private func walkPattern(_ value: Value, head: Bool, into variables: inout Set<String>) throws {
    switch value {
    case .symbol(let name):
      guard !head, name != "_", !literals.contains(name), name != keyword, !isEllipsis(value) else {
        return
      }
      guard variables.insert(name).inserted else {
        throw SchemeError.syntax("duplicate syntax-rules pattern variable \(name)")
      }
    case .pair: try validatePatternSequence(value, head: false, into: &variables)
    case .vector(let vector): try validateVectorPatternSequence(vector.elements, into: &variables)
    default: break
    }
  }

  private func validateVectorPatternSequence(_ elements: [Value], into variables: inout Set<String>)
    throws
  {
    var previousWasPattern = false
    for (index, element) in elements.enumerated() {
      if isEllipsis(element) {
        guard previousWasPattern, index == elements.index(before: elements.endIndex) else {
          throw SchemeError.syntax("ellipsis must terminate a nonempty pattern sequence")
        }
        previousWasPattern = false
      } else {
        try walkPattern(element, head: false, into: &variables)
        previousWasPattern = true
      }
    }
  }

  private func freeIdentifiers() -> Set<String> {
    let core: Set<String> = [
      "quote", "if", "begin", "lambda", "define", "set!", "let", "let*", "letrec", "and", "or",
      "cond", "case", "do", "delay", "quasiquote", "unquote", "unquote-splicing", "let-syntax",
      "letrec-syntax", "define-syntax", "syntax-rules", "else", "=>",
    ]
    var result = Set<String>()
    for (pattern, template) in rules {
      var variables = Set<String>()
      collectSymbols(pattern, into: &variables)
      if case .pair(let head) = pattern, case .symbol(let patternKeyword) = head.car {
        variables.remove(patternKeyword)
      }
      variables.subtract(literals)
      variables.remove(keyword)
      variables.remove("_")
      variables.remove("...")
      variables.remove("else")
      variables.remove("=>")
      var symbols = Set<String>()
      collectSymbols(template, into: &symbols)
      result.formUnion(
        symbols.subtracting(variables).subtracting(literals).subtracting(core).subtracting([
          "...", keyword
        ])
      )
    }
    return result
  }

  func collectSymbols(_ value: Value, into symbols: inout Set<String>) {
    switch value {
    case .symbol(let name): symbols.insert(name)
    case .pair(let pair):
      collectSymbols(pair.car, into: &symbols)
      collectSymbols(pair.cdr, into: &symbols)
    case .vector(let vector): for value in vector.elements { collectSymbols(value, into: &symbols) }
    default: break
    }
  }

  package func expand(_ use: Value, in useEnvironment: SchemeEnvironment, serial: inout Int) throws
    -> Value
  {
    let matchedUse: Value
    if case .pair(let pair) = use {
      matchedUse = .pair(Pair(.symbol(keyword), pair.cdr))
    } else {
      matchedUse = use
    }
    for (pattern, template) in rules {
      var captures: [String: Capture] = [:]
      if match(pattern, matchedUse, path: [], useEnvironment, into: &captures) {
        aliases.removeAll()
        introduced.removeAll()
        return try transcribe(template, captures, path: [], serial: &serial)
      }
    }
    throw SchemeError.syntax("no matching syntax-rules pattern for \(keyword)")
  }
}
