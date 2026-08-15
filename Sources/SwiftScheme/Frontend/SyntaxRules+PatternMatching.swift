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
    into captures: inout [String: Capture],
    head: Bool = false
  ) -> Bool {
    switch pattern {
    case .symbol(let name):
      if head && name == "_" { return true }
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
      if let patterns = try? array(from: .pair(pair)), let inputs = try? array(from: input) {
        return matchSequence(
          patterns,
          inputs,
          path: path,
          useEnvironment,
          into: &captures,
          head: head
        )
      }
      guard case .pair(let actual) = input else { return false }
      return match(pair.car, actual.car, path: path, useEnvironment, into: &captures, head: head)
        && match(pair.cdr, actual.cdr, path: path, useEnvironment, into: &captures)
    case .vector(let vector):
      guard case .vector(let actual) = input else { return false }
      return matchSequence(
        vector.elements,
        actual.elements,
        path: path,
        useEnvironment,
        into: &captures,
        head: false
      )
    default: return equal(pattern, input)
    }
  }

  func matchSequence(
    _ patterns: [Value],
    _ inputs: [Value],
    path: [Int],
    _ useEnvironment: SchemeEnvironment,
    into captures: inout [String: Capture],
    head: Bool = false
  ) -> Bool {
    func search(_ patternIndex: Int, _ inputIndex: Int, _ candidate: [String: Capture]) -> [String:
      Capture]?
    {
      if patternIndex == patterns.count { return inputIndex == inputs.count ? candidate : nil }
      let repeated =
        patternIndex + 1 < patterns.count && isSymbol(patterns[patternIndex + 1], ellipsis)
          && (ellipsis != "..." || (definition?.cell("...") == nil && definition?.macro("...") == nil))
      if repeated {
        let required = patterns.count - patternIndex - 2
        guard inputs.count - inputIndex >= required else { return nil }
        let maximum = inputs.count - inputIndex - required
        for count in stride(from: maximum, through: 0, by: -1) {
          var repeatedCaptures = candidate
          if count == 0 {
            initializeEmpty(patterns[patternIndex], path: path, captures: &repeatedCaptures)
          } else {
            var matched = true
            for offset in 0..<count
            where !match(
              patterns[patternIndex],
              inputs[inputIndex + offset],
              path: path + [offset],
              useEnvironment,
              into: &repeatedCaptures,
              head: head && patternIndex == 0
            ) {
              matched = false
              break
            }
            if !matched { continue }
          }
          if let result = search(patternIndex + 2, inputIndex + count, repeatedCaptures) {
            return result
          }
        }
        return nil
      }
      guard inputIndex < inputs.count else { return nil }
      var next = candidate
      guard
        match(
          patterns[patternIndex],
          inputs[inputIndex],
          path: path,
          useEnvironment,
          into: &next,
          head: head && patternIndex == 0
        )
      else { return nil }
      return search(patternIndex + 1, inputIndex + 1, next)
    }

    guard let result = search(0, 0, captures) else { return false }
    captures = result
    return true
  }

  func initializeEmpty(_ pattern: Value, path: [Int], captures: inout [String: Capture]) {
    var names = Set<String>()
    collectSymbols(pattern, into: &names)
    names.subtract(literals)
    names.subtract([keyword, ellipsis])
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
