import Foundation
import SwiftSchemeNumeric
import SwiftSchemeRuntime

extension SyntaxRules {
  func transcribe(_ template: Value, _ captures: [String: Capture], path: [Int], serial: inout Int)
    throws -> Value
  {
    switch template {
    case .symbol(let name):
      if captures[name] != nil {
        guard case .value(let value)? = capture(name, at: path, in: captures) else {
          throw SchemeError.syntax("missing ellipsis for pattern variable \(name)")
        }
        return value
      }
      if name == ellipsis { throw SchemeError.syntax("misplaced ellipsis") }
      let coreSyntax: Set<String> = [
        "quote", "if", "begin", "lambda", "define", "set!", "let", "let*", "letrec", "and", "or",
        "cond", "case", "do", "delay", "quasiquote", "unquote", "unquote-splicing", "let-syntax",
        "letrec-syntax", "define-syntax", "syntax-rules", "else", "=>"
      ]
      if literals.contains(name) || name == keyword || coreSyntax.contains(name) {
        return .symbol(name)
      }
      guard let definition else { throw SchemeError.io("syntax transformer was reclaimed") }
      if let cell = definition.cell(name) {
        if let alias = aliases[name] { return .symbol(alias) }
        serial += 1
        let alias = "\(name)#macro\(serial)"
        definition.alias(alias, to: cell)
        aliases[name] = alias
        return .symbol(alias)
      }
      if let transformer = definition.macro(name) {
        if let alias = aliases[name] { return .symbol(alias) }
        serial += 1
        let alias = "\(name)#macro\(serial)"
        definition.macros[alias] = transformer
        aliases[name] = alias
        return .symbol(alias)
      }
      if let renamed = introduced[name] { return .symbol(renamed) }
      serial += 1
      let renamed = "\(name)#macro\(serial)"
      introduced[name] = renamed
      return .symbol(renamed)
    case .pair(let pair):
      let (items, tail) = try improperList(from: .pair(pair), context: "syntax template")
      if tail == nil, items.count == 2, isSymbol(items[0], "quote") {
        return makeList([.symbol("quote"), try substituteQuoted(items[1], captures, path)])
      }
      let transcribed = try transcribeSequence(items, captures, path: path, serial: &serial)
      let transcribedTail = try tail.map {
        try transcribe($0, captures, path: path, serial: &serial)
      }
      return makeList(transcribed, tail: transcribedTail ?? .empty)
    case .vector(let vector):
      return .vector(
        SchemeVector(try transcribeSequence(vector.elements, captures, path: path, serial: &serial))
      )
    default: return template
    }
  }

  func transcribeSequence(
    _ items: [Value],
    _ captures: [String: Capture],
    path: [Int],
    serial: inout Int
  ) throws -> [Value] {
    var result: [Value] = []
    var index = 0
    while index < items.count {
      var depth = 0
      while index + 1 + depth < items.count
        && ellipsis.map({ isSymbol(items[index + 1 + depth], $0) }) == true
      { depth += 1 }
      if depth > 0 {
        result += try expandRepeated(
          items[index],
          depth: depth,
          captures,
          path: path,
          serial: &serial
        )
        index += depth + 1
      } else {
        result.append(try transcribe(items[index], captures, path: path, serial: &serial))
        index += 1
      }
    }
    return result
  }

  func expandRepeated(
    _ template: Value,
    depth: Int,
    _ captures: [String: Capture],
    path: [Int],
    serial: inout Int
  ) throws -> [Value] {
    let names = captureNames(in: template, captures: captures)
    let counts = names.compactMap { name -> Int? in
      if case .sequence(let items)? = capture(name, at: path, in: captures) { return items.count }
      return nil
    }
    guard let count = counts.first else {
      throw SchemeError.syntax("ellipsis template has no repeated pattern variable")
    }
    guard counts.allSatisfy({ $0 == count }) else {
      throw SchemeError.syntax("inconsistent ellipsis lengths")
    }
    var result: [Value] = []
    for index in 0..<count {
      let next = path + [index]
      if depth == 1 {
        result.append(try transcribe(template, captures, path: next, serial: &serial))
      } else {
        result += try expandRepeated(
          template,
          depth: depth - 1,
          captures,
          path: next,
          serial: &serial
        )
      }
    }
    return result
  }

  func substituteQuoted(_ value: Value, _ captures: [String: Capture], _ path: [Int]) throws
    -> Value
  {
    switch value {
    case .symbol(let name):
      guard captures[name] != nil else { return value }
      guard case .value(let captured)? = capture(name, at: path, in: captures) else { return value }
      return captured
    case .pair(let pair):
      return .pair(
        Pair(
          try substituteQuoted(pair.car, captures, path),
          try substituteQuoted(pair.cdr, captures, path)
        )
      )
    case .vector(let vector):
      return .vector(
        SchemeVector(try vector.elements.map { try substituteQuoted($0, captures, path) })
      )
    default: return value
    }
  }

  func captureNames(in value: Value, captures: [String: Capture]) -> [String] {
    switch value {
    case .symbol(let name): return captures[name] == nil ? [] : [name]
    case .pair(let pair):
      return captureNames(in: pair.car, captures: captures)
        + captureNames(in: pair.cdr, captures: captures)
    case .vector(let vector):
      return vector.elements.flatMap { captureNames(in: $0, captures: captures) }
    default: return []
    }
  }

  func improperList(from value: Value, context: String) throws -> ([Value], Value?) {
    var items: [Value] = []
    var cursor = value
    var seen = Set<ObjectIdentifier>()
    while case .pair(let pair) = cursor {
      guard seen.insert(ObjectIdentifier(pair)).inserted else {
        throw SchemeError.type("\(context) must not be cyclic")
      }
      items.append(pair.car)
      cursor = pair.cdr
    }
    if case .empty = cursor { return (items, nil) }
    return (items, cursor)
  }
}

package func isSymbol(_ value: Value, _ name: String) -> Bool {
  if case .symbol(let actual) = value { return actual == name }
  return false
}

package func isDefinitionBoundaryKeyword(_ name: String) -> Bool {
  ["define", "begin", "define-syntax"].contains(name)
}
