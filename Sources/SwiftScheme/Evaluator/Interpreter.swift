import Foundation
import SwiftSchemeFrontend
import SwiftSchemeNumeric
import SwiftSchemePrimitives
import SwiftSchemeRuntime

/// Evaluates R5RS Scheme source and owns its environments, ports, and heap.
public final class Interpreter {
  /// Receives text emitted by display and related output procedures.
  public typealias Output = (String) -> Void

  let heap: SchemeHeap
  let global: SchemeEnvironment
  let report: SchemeEnvironment
  let output: Output
  var currentInput: SchemePort
  var currentOutput: SchemePort
  var macroSerial = 0
  var windSerial = 0
  var exportedRoots: [Value] = []

  /// Creates an interpreter with optional output and initial input text.
  public init(output: @escaping Output = { print($0, terminator: "") }, input: String = "") {
    self.output = output
    let heap = SchemeHeap()
    self.heap = heap
    self.global = heap.withActive { SchemeEnvironment() }
    self.report = heap.withActive { SchemeEnvironment() }
    currentInput = SchemePort(input: input, defaultReady: true)
    currentOutput = SchemePort { output($0) }
    heap.withActive {
      installPrimitives(in: report)
      for (name, cell) in report.values { global.define(name, cell.value) }
    }
    global.symbolSpellings = report.symbolSpellings
  }

  /// Evaluates all top-level forms in source and returns the last value.
  @discardableResult public func evaluate(_ source: String) throws -> Value {
    try heap.withActive {
      var reader = Reader(source)
      let forms = try reader.readAll()
      noteReaderSpellings(reader)
      var result: Value = .unspecified
      for form in forms {
        let values = try run(.expression(form, global))
        guard values.count == 1 else {
          throw SchemeError.arity("top-level expression returned \(values.count) values")
        }
        result = values[0]
      }
      if containsSchemeNode(result) { exportedRoots.append(result) }
      return result
    }
  }

  /// Parses source into external-form values without evaluating them.
  public func read(_ source: String) throws -> [Value] {
    try heap.withActive {
      var reader = Reader(source)
      let values = try reader.readAll()
      exportedRoots.append(contentsOf: values.filter(containsSchemeNode))
      return values
    }
  }

  /// Reports allocation and collection counters for the interpreter heap.
  public var heapStatistics: HeapStatistics { heap.statistics }

  /// Collects unreachable Scheme objects while retaining the supplied values.
  @discardableResult public func collectGarbage(retaining values: [Value] = []) -> HeapStatistics {
    var roots: [any SchemeHeapNode] = [global, report]
    for value in exportedRoots + values { traceValue(value) { roots.append($0) } }
    return heap.collect(roots: roots)
  }

  /// Returns whether source is complete enough for interactive evaluation.
  public func isComplete(_ source: String) -> Bool {
    do {
      var reader = Reader(source)
      _ = try reader.readAll()
      return true
    } catch let SchemeError.lexical(message, _, _) {
      return
        !(message.contains("unterminated") || message.contains("unexpected end")
        || message.contains("incomplete"))
    } catch { return true }
  }

  /// Returns the R5RS external representation of a value.
  public func write(_ value: Value) -> String { value.written }

  func noteReaderSpellings(_ reader: Reader) {
    for (canonical, spelling) in reader.spellings {
      global.noteSymbol(canonical, spelling: spelling)
      report.noteSymbol(canonical, spelling: spelling)
    }
  }

  func recordSymbols(_ value: Value, in environment: SchemeEnvironment) throws {
    var active = Set<ObjectIdentifier>()
    try recordSymbols(value, in: environment, active: &active)
  }

  private func recordSymbols(
    _ value: Value,
    in environment: SchemeEnvironment,
    active: inout Set<ObjectIdentifier>
  ) throws {
    switch value {
    case .symbol(let name): _ = name
    case .pair(let pair):
      guard active.insert(ObjectIdentifier(pair)).inserted else {
        throw SchemeError.syntax("cyclic expression")
      }
      defer { active.remove(ObjectIdentifier(pair)) }
      try recordSymbols(pair.car, in: environment, active: &active)
      try recordSymbols(pair.cdr, in: environment, active: &active)
    case .vector(let vector):
      guard active.insert(ObjectIdentifier(vector)).inserted else {
        throw SchemeError.syntax("cyclic expression")
      }
      defer { active.remove(ObjectIdentifier(vector)) }
      for item in vector.elements { try recordSymbols(item, in: environment, active: &active) }
    default: break
    }
  }

  func coreProcedure(_ name: String) -> Value {
    guard let value = report.cell(name)?.value else {
      preconditionFailure("missing R5RS core procedure \(name)")
    }
    return value
  }

  func coreCall(_ name: String, _ arguments: [Value]) -> Value {
    makeList([coreProcedure(name)] + arguments)
  }

  func coreKeyword(_ value: Value, in environment: SchemeEnvironment) -> String? {
    if let name = internalSyntaxName(value) { return name }
    guard case .symbol(let name) = value,
      environment.cell(name) == nil && environment.macro(name) == nil
    else { return nil }
    return name
  }

  func finishDynamicFile(
    _ state: DynamicFilePort,
    updatePosition: (SchemePort) -> Void,
    restore: (SchemePort) -> Void
  ) throws -> [Value] {
    if let opened = state.opened {
      updatePosition(opened)
      try closePortHandle(opened)
    }
    if let previous = state.previous { restore(previous) }
    state.opened = nil
    state.previous = nil
    return [.unspecified]
  }
}
