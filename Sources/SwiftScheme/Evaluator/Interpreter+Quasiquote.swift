import Foundation
import SwiftSchemeFrontend
import SwiftSchemeNumeric
import SwiftSchemePrimitives
import SwiftSchemeRuntime

extension Interpreter {
  func expandQuasiquote(_ value: Value, depth: Int, _ environment: SchemeEnvironment) throws
    -> Value
  {
    if depth == 1 {
      var seen = Set<ObjectIdentifier>()
      if !containsQuasiquoteComma(value, in: environment, seen: &seen) { return quoted(value) }
    }
    if let form = try? array(from: value), form.count == 2, case .symbol(let rawName) = form[0] {
      let name = internalSyntaxName(form[0]) ?? rawName
      let active =
        internalSyntaxName(form[0]) != nil
        || (environment.cell(rawName) == nil && environment.macro(rawName) == nil)
      if name == "unquote" && active {
        return depth == 1
          ? form[1]
          : coreCall(
            "list",
            [quoted(.symbol(name)), try expandQuasiquote(form[1], depth: depth - 1, environment)]
          )
      }
      if name == "unquote-splicing" && active {
        guard depth > 1 else { throw SchemeError.syntax("unquote-splicing outside list context") }
        return coreCall(
          "list",
          [quoted(.symbol(name)), try expandQuasiquote(form[1], depth: depth - 1, environment)]
        )
      }
      if name == "quasiquote" && active {
        return coreCall(
          "list",
          [quoted(.symbol(name)), try expandQuasiquote(form[1], depth: depth + 1, environment)]
        )
      }
    }

    if let syntax = internalSyntaxName(value), syntaxKeywords.contains(syntax) {
      return quoted(.symbol(syntax))
    }
    if case .vector(let vector) = value {
      var pieces: [Value] = []
      for element in vector.elements {
        if let form = try? array(from: element), form.count == 2,
          case .symbol(let rawName) = form[0], depth == 1,
          internalSyntaxName(form[0]) == "unquote-splicing"
            || (isSymbol(form[0], "unquote-splicing") && environment.cell(rawName) == nil
              && environment.macro(rawName) == nil)
        {
          pieces.append(form[1])
        } else {
          pieces.append(
            coreCall("list", [try expandQuasiquote(element, depth: depth, environment)])
          )
        }
      }
      let list = pieces.isEmpty ? quoted(.empty) : coreCall("append", pieces)
      return coreCall("list->vector", [list])
    }
    guard case .pair(let pair) = value else { return quoted(value) }
    let head = pair.car
    if let form = try? array(from: head), form.count == 2,
      internalSyntaxName(form[0]) == "unquote-splicing"
        || (isSymbol(form[0], "unquote-splicing") && environment.cell("unquote-splicing") == nil
          && environment.macro("unquote-splicing") == nil),
      depth == 1
    {
      return coreCall(
        "append",
        [form[1], try expandQuasiquote(pair.cdr, depth: depth, environment)]
      )
    }
    let expandedHead = try expandQuasiquote(head, depth: depth, environment)
    let expandedTail = try expandQuasiquote(pair.cdr, depth: depth, environment)
    return coreCall("cons", [expandedHead, expandedTail])
  }

  func containsQuasiquoteComma(
    _ value: Value,
    in environment: SchemeEnvironment,
    seen: inout Set<ObjectIdentifier>
  ) -> Bool {
    switch value {
    case .pair(let pair):
      guard seen.insert(ObjectIdentifier(pair)).inserted else { return false }
      defer { seen.remove(ObjectIdentifier(pair)) }
      if let form = try? array(from: value), form.count == 2, case .symbol(let rawName) = form[0] {
        let name = internalSyntaxName(form[0]) ?? rawName
        let active =
          internalSyntaxName(form[0]) != nil
          || (environment.cell(rawName) == nil && environment.macro(rawName) == nil)
        if active && (name == "unquote" || name == "unquote-splicing") { return true }
        if active && name == "quasiquote" {
          return containsQuasiquoteComma(form[1], in: environment, seen: &seen)
        }
      }
      return containsQuasiquoteComma(pair.car, in: environment, seen: &seen)
        || containsQuasiquoteComma(pair.cdr, in: environment, seen: &seen)
    case .vector(let vector):
      let identifier = ObjectIdentifier(vector)
      guard seen.insert(identifier).inserted else { return false }
      defer { seen.remove(identifier) }
      return vector.elements.contains { containsQuasiquoteComma($0, in: environment, seen: &seen) }
    default: return false
    }
  }
}
