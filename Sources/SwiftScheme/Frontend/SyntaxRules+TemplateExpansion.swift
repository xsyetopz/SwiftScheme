import Foundation
import SwiftSchemeNumeric
import SwiftSchemeRuntime

extension SyntaxRules {
  func definitionCoreSyntax(_ name: String) -> Bool {
    guard let binding = coreBindings[name] else { return false }
    if case .unbound = binding { return true }
    return false
  }

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
      let coreSyntax = syntaxKeywords
      if literals.contains(name) { return try transcribeLiteral(name, serial: &serial) }
      if name == keyword { return .symbol(name) }
      if coreSyntax.contains(name), let binding = coreBindings[name] {
        if case .unbound = binding { return internalSyntax(name) }
        return try transcribeBinding(name, binding, serial: &serial)
      }
      return try transcribeDefinitionIdentifier(name, serial: &serial)
    case .pair(let pair):
      let (items, tail) = try improperList(from: .pair(pair), context: "syntax template")
      if tail == nil, items.count == 2, definitionCoreSyntax("quote"), isSymbol(items[0], "quote") {
        return makeList([internalSyntax("quote"), try substituteQuoted(items[1], captures, path)])
      }
      if tail == nil, items.count == 2, definitionCoreSyntax("quasiquote"),
        isSymbol(items[0], "quasiquote")
      {
        let body = try transcribeQuasiquote(
          items[1],
          captures,
          path: path,
          depth: 1,
          serial: &serial
        )
        let parts = [internalSyntax("quasiquote"), body]
        return makeList(parts)
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

  func transcribeDefinitionIdentifier(_ name: String, serial: inout Int) throws -> Value {
    guard let definition else { throw SchemeError.io("syntax transformer was reclaimed") }
    if let alias = aliases[name] { return .symbol(alias) }
    if let cell = definition.cell(name) {
      return try transcribeBinding(name, .cell(cell), serial: &serial)
    }
    if let transformer = definition.macro(name) {
      return try transcribeBinding(name, .macro(transformer), serial: &serial)
    }
    if let renamed = introduced[name] { return .symbol(renamed) }
    serial += 1
    let renamed = "\(name)#macro\(serial)"
    introduced[name] = renamed
    return .symbol(renamed)
  }

  func transcribeBinding(_ name: String, _ binding: LiteralBinding, serial: inout Int) throws
    -> Value
  {
    guard let definition else { throw SchemeError.io("syntax transformer was reclaimed") }
    if let alias = aliases[name] { return .symbol(alias) }
    serial += 1
    let alias = "\(name)#macro\(serial)"
    switch binding {
    case .cell(let cell): definition.alias(alias, to: cell)
    case .macro(let macro): definition.macros[alias] = macro
    case .unbound: definition.define(alias, .undefined)
    }
    aliases[name] = alias
    return .symbol(alias)
  }

  func transcribeLiteral(_ name: String, serial: inout Int) throws -> Value {
    guard let binding = literalBindings[name] else { return .symbol(name) }
    return try transcribeBinding(name, binding, serial: &serial)
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
      while index + 1 + depth < items.count && isSymbol(items[index + 1 + depth], ellipsis) {
        depth += 1
      }
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

  func transcribeQuasiquote(
    _ value: Value,
    _ captures: [String: Capture],
    path: [Int],
    depth: Int,
    serial: inout Int
  ) throws -> Value {
    switch value {
    case .symbol(let name):
      if name == ellipsis { throw SchemeError.syntax("misplaced ellipsis") }
      guard case .value(let captured)? = capture(name, at: path, in: captures) else { return value }
      return captured
    case .pair(let pair):
      let (items, tail) = try improperList(from: .pair(pair), context: "quasiquote syntax template")
      if tail == nil, items.count == 2 {
        if definitionCoreSyntax("quasiquote"), isSymbol(items[0], "quasiquote") {
          let body = try transcribeQuasiquote(
            items[1],
            captures,
            path: path,
            depth: depth + 1,
            serial: &serial
          )
          let parts = [internalSyntax("quasiquote"), body]
          return makeList(parts)
        }
        let isUnquote = definitionCoreSyntax("unquote") && isSymbol(items[0], "unquote")
        let isUnquoteSplicing =
          definitionCoreSyntax("unquote-splicing") && isSymbol(items[0], "unquote-splicing")
        if isUnquote || isUnquoteSplicing {
          let name: String
          if case .symbol(let value) = items[0] { name = value } else { name = "unquote" }
          if depth == 1 {
            return makeList([
              internalSyntax(name), try transcribe(items[1], captures, path: path, serial: &serial),
            ])
          }
          let body = try transcribeQuasiquote(
            items[1],
            captures,
            path: path,
            depth: depth - 1,
            serial: &serial
          )
          let parts = [internalSyntax(name), body]
          return makeList(parts)
        }
      }
      let transcribed = try transcribeQuasiquoteSequence(
        items,
        captures,
        path: path,
        depth: depth,
        serial: &serial
      )
      let transcribedTail = try tail.map {
        try transcribeQuasiquote($0, captures, path: path, depth: depth, serial: &serial)
      }
      return makeList(transcribed, tail: transcribedTail ?? .empty)
    case .vector(let vector):
      return .vector(
        SchemeVector(
          try transcribeQuasiquoteSequence(
            vector.elements,
            captures,
            path: path,
            depth: depth,
            serial: &serial
          )
        )
      )
    default: return value
    }
  }

  func transcribeQuasiquoteSequence(
    _ items: [Value],
    _ captures: [String: Capture],
    path: [Int],
    depth: Int,
    serial: inout Int
  ) throws -> [Value] {
    var result: [Value] = []
    var index = 0
    while index < items.count {
      guard index + 1 < items.count, case .symbol(let marker) = items[index + 1], marker == ellipsis
      else {
        result.append(
          try transcribeQuasiquote(
            items[index],
            captures,
            path: path,
            depth: depth,
            serial: &serial
          )
        )
        index += 1
        continue
      }
      let repeated = items[index]
      let names = captureNames(in: repeated, captures: captures)
      let counts = names.compactMap { name -> Int? in
        if case .sequence(let values)? = capture(name, at: path, in: captures) {
          return values.count
        }
        return nil
      }
      guard let count = counts.first else {
        throw SchemeError.syntax("quasiquote ellipsis has no repeated pattern variable")
      }
      guard counts.allSatisfy({ $0 == count }) else {
        throw SchemeError.syntax("inconsistent quasiquote ellipsis lengths")
      }
      for offset in 0..<count {
        result.append(
          try transcribeQuasiquote(
            repeated,
            captures,
            path: path + [offset],
            depth: depth,
            serial: &serial
          )
        )
      }
      index += 2
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
      let (items, tail) = try improperList(from: .pair(pair), context: "quoted syntax template")
      let substituted = try substituteQuotedSequence(items, captures, path)
      let substitutedTail = try tail.map { try substituteQuoted($0, captures, path) }
      return makeList(substituted, tail: substitutedTail ?? .empty)
    case .vector(let vector):
      return .vector(SchemeVector(try substituteQuotedSequence(vector.elements, captures, path)))
    default: return value
    }
  }

  func substituteQuotedSequence(_ items: [Value], _ captures: [String: Capture], _ path: [Int])
    throws -> [Value]
  {
    var result: [Value] = []
    var index = 0
    while index < items.count {
      let hasEllipsis: Bool
      if index + 1 < items.count, case .symbol(let name) = items[index + 1], name == ellipsis {
        hasEllipsis = true
      } else {
        hasEllipsis = false
      }
      guard hasEllipsis else {
        result.append(try substituteQuoted(items[index], captures, path))
        index += 1
        continue
      }
      let repeated = items[index]
      let names = captureNames(in: repeated, captures: captures)
      let counts = names.compactMap { name -> Int? in
        if case .sequence(let values)? = capture(name, at: path, in: captures) {
          return values.count
        }
        return nil
      }
      guard let count = counts.first else {
        throw SchemeError.syntax("quoted ellipsis has no repeated pattern variable")
      }
      guard counts.allSatisfy({ $0 == count }) else {
        throw SchemeError.syntax("inconsistent quoted ellipsis lengths")
      }
      for offset in 0..<count {
        result.append(try substituteQuoted(repeated, captures, path + [offset]))
      }
      index += 2
    }
    return result
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
