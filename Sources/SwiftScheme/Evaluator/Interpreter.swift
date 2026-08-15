import Foundation
import SwiftSchemeFrontend
import SwiftSchemeNumeric
import SwiftSchemePrimitives
import SwiftSchemeRuntime

public final class Interpreter {
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

  public init(output: @escaping Output = { print($0, terminator: "") }) {
    self.output = output
    let heap = SchemeHeap()
    self.heap = heap
    self.global = heap.withActive { SchemeEnvironment() }
    self.report = heap.withActive { SchemeEnvironment() }
    currentInput = SchemePort(input: "")
    currentOutput = SchemePort { output($0) }
    heap.withActive {
      installPrimitives(in: report)
      for (name, cell) in report.values { global.define(name, cell.value) }
    }
    global.symbolSpellings = report.symbolSpellings
  }

  @discardableResult public func evaluate(_ source: String) throws -> Value {
    try heap.withActive {
      var reader = Reader(source)
      let forms = try reader.readAll()
      for (canonical, spelling) in reader.spellings {
        global.noteSymbol(canonical, spelling: spelling)
        report.noteSymbol(canonical, spelling: spelling)
      }
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

  public func read(_ source: String) throws -> [Value] {
    try heap.withActive {
      var reader = Reader(source)
      let values = try reader.readAll()
      exportedRoots.append(contentsOf: values.filter(containsSchemeNode))
      return values
    }
  }

  public var heapStatistics: HeapStatistics { heap.statistics }

  @discardableResult public func collectGarbage(retaining values: [Value] = []) -> HeapStatistics {
    var roots: [any SchemeHeapNode] = [global, report]
    (exportedRoots + values).forEach { traceValue($0) { roots.append($0) } }
    return heap.collect(roots: roots)
  }

  public func isComplete(_ source: String) -> Bool {
    do {
      _ = try read(source)
      return true
    } catch let SchemeError.lexical(message, _, _) {
      return
        !(message.contains("unterminated") || message.contains("unexpected end")
        || message.contains("incomplete"))
    } catch { return true }
  }

  public func write(_ value: Value) -> String { value.written }

  func recordSymbols(_ value: Value, in environment: SchemeEnvironment) {
    switch value {
    case .symbol(let name): _ = name
    case .pair(let pair):
      recordSymbols(pair.car, in: environment)
      recordSymbols(pair.cdr, in: environment)
    case .vector(let vector): for item in vector.elements { recordSymbols(item, in: environment) }
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
