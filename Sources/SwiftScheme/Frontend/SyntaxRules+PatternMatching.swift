import Foundation
import SwiftSchemeNumeric
import SwiftSchemeRuntime

extension SyntaxRules {
  func literalMatches(_ name: String, _ actual: String, _ useEnvironment: SchemeEnvironment) -> Bool
  {
    guard name == actual, let binding = literalBindings[name] else { return false }
    switch binding {
    case .cell(let cell): return useEnvironment.cell(actual) === cell
    case .macro(let macro): return useEnvironment.macro(actual) === macro
    case .unbound: return useEnvironment.cell(actual) == nil && useEnvironment.macro(actual) == nil
    }
  }

  func inserting(_ capture: Capture?, path: ArraySlice<Int>, value: Value) -> Capture? {
    insertCapture(capture, path: path) { capture in
      if case .value(let old)? = capture { return equal(old, value) ? capture : nil }
      return capture == nil ? .value(value) : nil
    }
  }

  func insertingEmpty(_ capture: Capture?, path: ArraySlice<Int>) -> Capture? {
    insertCapture(capture, path: path) { capture in
      if case .sequence? = capture { return capture }
      return capture == nil ? .sequence([]) : nil
    }
  }

  func insertCapture(_ capture: Capture?, path: ArraySlice<Int>, leaf: (Capture?) -> Capture?)
    -> Capture?
  {
    guard let index = path.first else { return leaf(capture) }
    var children: [Capture]
    if case .sequence(let existing)? = capture {
      children = existing
    } else if capture == nil {
      children = []
    } else {
      return nil
    }
    guard index <= children.count else { return nil }
    let child = insertCapture(
      index == children.count ? nil : children[index],
      path: path.dropFirst(),
      leaf: leaf
    )
    guard let child else { return nil }
    if index == children.count { children.append(child) } else { children[index] = child }
    return .sequence(children)
  }

  func bind(_ name: String, _ value: Value, path: [Int], into captures: inout [String: Capture])
    -> Bool
  {
    guard let capture = inserting(captures[name], path: path[...], value: value) else {
      return false
    }
    captures[name] = capture
    return true
  }

  func match(
    _ pattern: Value,
    _ input: Value,
    path: [Int],
    _ useEnvironment: SchemeEnvironment,
    into captures: inout [String: Capture]
  ) -> Bool {
    switch pattern {
    case .symbol(let name):
      if name == "_" { return true }
      if name == keyword {
        guard case .symbol(let actual) = input else { return false }
        return actual == name
      }
      if literals.contains(name) {
        guard case .symbol(let actual) = input else { return false }
        return literalMatches(name, actual, useEnvironment)
      }
      if ellipsis == name { return false }
      return bind(name, input, path: path, into: &captures)
    case .pair(let pair):
      if ellipsis != nil, let patterns = try? array(from: .pair(pair)),
        let inputs = try? array(from: input)
      {
        return matchSequence(patterns, inputs, path: path, useEnvironment, into: &captures)
      }
      guard case .pair(let actual) = input else { return false }
      return match(pair.car, actual.car, path: path, useEnvironment, into: &captures)
        && match(pair.cdr, actual.cdr, path: path, useEnvironment, into: &captures)
    case .vector(let vector):
      guard case .vector(let actual) = input else { return false }
      return matchSequence(
        vector.elements,
        actual.elements,
        path: path,
        useEnvironment,
        into: &captures
      )
    default: return equal(pattern, input)
    }
  }

  func matchSequence(
    _ patterns: [Value],
    _ inputs: [Value],
    path: [Int],
    _ useEnvironment: SchemeEnvironment,
    into captures: inout [String: Capture]
  ) -> Bool {
    var pi = 0
    var ii = 0
    while pi < patterns.count {
      let repeated =
        pi + 1 < patterns.count && ellipsis.map { isSymbol(patterns[pi + 1], $0) } == true
      if repeated {
        let required = patterns.count - pi - 2
        guard inputs.count - ii >= required else { return false }
        let count = inputs.count - ii - required
        if count == 0 { initializeEmpty(patterns[pi], path: path, captures: &captures) }
        for offset in 0..<count
        where !match(
          patterns[pi],
          inputs[ii + offset],
          path: path + [offset],
          useEnvironment,
          into: &captures
        ) { return false }
        ii += count
        pi += 2
      } else {
        guard ii < inputs.count,
          match(patterns[pi], inputs[ii], path: path, useEnvironment, into: &captures)
        else { return false }
        pi += 1
        ii += 1
      }
    }
    return ii == inputs.count
  }

  func initializeEmpty(_ pattern: Value, path: [Int], captures: inout [String: Capture]) {
    var names = Set<String>()
    collectSymbols(pattern, into: &names)
    names.subtract(literals)
    names.subtract([keyword, "_", ellipsis ?? ""])
    for name in names {
      if let capture = insertingEmpty(captures[name], path: path[...]) { captures[name] = capture }
    }
  }

  func capture(_ name: String, at path: [Int], in captures: [String: Capture]) -> Capture? {
    var node = captures[name]
    for index in path {
      guard case .sequence(let children)? = node, index < children.count else { return nil }
      node = children[index]
    }
    return node
  }

}
