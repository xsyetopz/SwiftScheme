import Foundation
import SwiftSchemeNumeric

public enum SchemeError: Error, Equatable, CustomStringConvertible {
  case lexical(String, line: Int, column: Int)
  case syntax(String)
  case unbound(String)
  case arity(String)
  case type(String)
  case numeric(String)
  case io(String)

  public var description: String {
    switch self {
    case .lexical(let message, let line, let column):
      "lexical error at \(line):\(column): \(message)"
    case .syntax(let message): "syntax error: \(message)"
    case .unbound(let name): "unbound variable: \(name)"
    case .arity(let message): "arity error: \(message)"
    case .type(let message): "type error: \(message)"
    case .numeric(let message): "numeric error: \(message)"
    case .io(let message): "I/O error: \(message)"
    }
  }
}

public final class Pair: SchemeHeapNode {
  public var car: Value
  public var cdr: Value
  package var isLiteral = false
  public init(_ car: Value, _ cdr: Value) {
    self.car = car
    self.cdr = cdr
    registerSchemeNode(self)
  }
  package func traceSchemeChildren(_ visit: (any SchemeHeapNode) -> Void) {
    traceValue(car, visit)
    traceValue(cdr, visit)
  }
  package func breakSchemeCycles() {
    car = .undefined
    cdr = .undefined
  }
}

public final class SchemeString {
  private var storedCharacters: [Character]
  package var isLiteral = false
  public var characters: [Character] {
    get { storedCharacters }
    set { storedCharacters = scalarCharacters(newValue) }
  }
  public init(_ value: String) { storedCharacters = scalarCharacters(value) }
  package init(characters: [Character]) { storedCharacters = scalarCharacters(characters) }
  public var string: String { String(characters) }
}

package func scalarCharacters(_ value: String) -> [Character] {
  value.unicodeScalars.map { Character(String($0)) }
}

package func scalarCharacters(_ value: [Character]) -> [Character] {
  value.flatMap { $0.unicodeScalars.map { Character(String($0)) } }
}

public final class SchemeVector: SchemeHeapNode {
  public var elements: [Value]
  package var isLiteral = false
  public init(_ elements: [Value]) {
    self.elements = elements
    registerSchemeNode(self)
  }
  package func traceSchemeChildren(_ visit: (any SchemeHeapNode) -> Void) {
    elements.forEach { traceValue($0, visit) }
  }
  package func breakSchemeCycles() { elements.removeAll() }
}

public final class SchemePort {
  package enum Mode { case input, output }
  package let mode: Mode
  package var input: [Character] = []
  package var position = 0
  package var sink: ((String) throws -> Void)?
  package var output = ""
  package var handle: FileHandle?
  package var closed = false
  package var defaultInputReady = false

  package init(input: String, defaultReady: Bool = false) {
    mode = .input
    self.input = scalarCharacters(input)
    self.defaultInputReady = defaultReady
  }
  package init(output: Bool) { mode = .output }
  package init(sink: @escaping (String) throws -> Void) {
    mode = .output
    self.sink = sink
  }
  package init(handle: FileHandle, mode: Mode) throws {
    self.mode = mode
    self.handle = handle
    if mode == .input {
      let data = handle.readDataToEndOfFile()
      guard let text = String(data: data, encoding: .utf8) else {
        throw SchemeError.io("invalid UTF-8 input")
      }
      input = scalarCharacters(text)
    } else {
      sink = { text in
        do { try handle.write(contentsOf: Data(text.utf8)) } catch {
          throw SchemeError.io(error.localizedDescription)
        }
      }
    }
  }
}

package final class DynamicFilePort {
  package let path: String
  package let mode: SchemePort.Mode
  package var previous: SchemePort?
  package var opened: SchemePort?
  package var position = 0
  package var offset: UInt64 = 0
  package var firstEntry = true

  package init(_ path: String, _ mode: SchemePort.Mode) {
    self.path = path
    self.mode = mode
  }
}

package final class Cell: SchemeHeapNode {
  package var value: Value
  package init(_ value: Value) {
    self.value = value
    registerSchemeNode(self)
  }
  package func traceSchemeChildren(_ visit: (any SchemeHeapNode) -> Void) {
    traceValue(value, visit)
  }
  package func breakSchemeCycles() { value = .undefined }
}

package enum DefinitionPolicy {
  case mutable
  case fixed
}

public final class SchemeEnvironment: SchemeHeapNode {
  package var parent: SchemeEnvironment?
  package let definitionPolicy: DefinitionPolicy
  package var values: [String: Cell] = [:]
  package var symbolSpellings: [String: String] = [:]
  package var aliases: [String: Cell] = [:]
  package var macros: [String: any SchemeMacro] = [:]

  package init(parent: SchemeEnvironment? = nil, definitionPolicy: DefinitionPolicy = .mutable) {
    self.parent = parent
    self.definitionPolicy = definitionPolicy
    registerSchemeNode(self)
  }
  package func traceSchemeChildren(_ visit: (any SchemeHeapNode) -> Void) {
    if let parent { visit(parent) }
    values.values.forEach(visit)
    aliases.values.forEach(visit)
    macros.values.forEach(visit)
  }
  package func breakSchemeCycles() {
    parent = nil
    values.removeAll()
    aliases.removeAll()
    macros.removeAll()
  }
  package func noteSymbol(_ canonical: String, spelling: String) {
    if spelling != canonical { symbolSpellings[canonical] = spelling }
  }
  package func define(_ name: String, _ value: Value) {
    let canonical = name.lowercased()
    if name != canonical { symbolSpellings[canonical] = name }
    if let cell = values[canonical] { cell.value = value } else { values[canonical] = Cell(value) }
  }
  package func requireDefinitionAllowed() throws {
    if case .fixed = definitionPolicy {
      throw SchemeError.syntax("definitions are not allowed in this environment")
    }
  }
  package func fillPlaceholder(_ name: String, _ value: Value) -> Bool {
    if let cell = values[name], case .undefined = cell.value {
      cell.value = value
      return true
    }
    return parent?.fillPlaceholder(name, value) ?? false
  }
  package func alias(_ name: String, to cell: Cell) { aliases[name] = cell }
  package func localCell(_ name: String) -> Cell? { values[name] }
  package func spelling(_ name: String) -> String? {
    symbolSpellings[name] ?? parent?.spelling(name)
  }
  package func cell(_ name: String) -> Cell? { aliases[name] ?? values[name] ?? parent?.cell(name) }
  package func get(_ name: String) throws -> Value {
    guard let cell = cell(name) else { throw SchemeError.unbound(name) }
    guard case .undefined = cell.value else { return cell.value }
    throw SchemeError.unbound("\(name) used before initialization")
  }
  package func set(_ name: String, _ value: Value) throws {
    guard let cell = cell(name) else { throw SchemeError.unbound(name) }
    cell.value = value
  }
  package func macro(_ name: String) -> (any SchemeMacro)? {
    if values[name] != nil { return nil }
    return macros[name] ?? parent?.macro(name)
  }
}

package struct Formals {
  package let fixed: [String]
  package let rest: String?
  package init(fixed: [String], rest: String?) {
    self.fixed = fixed
    self.rest = rest
  }
}

package enum Special {
  case apply, callCC, values, callWithValues, dynamicWind, force, eval, map, forEach, load
  case callWithInputFile, callWithOutputFile, withInputFromFile, withOutputToFile
  case callWithInputString, callWithOutputString
}

public final class Procedure: SchemeHeapNode {
  package enum Implementation {
    case primitive(String, ([Value]) throws -> [Value])
    case closure(Formals, [Value], SchemeEnvironment)
    case continuation(Captured)
    case special(Special)
  }
  package var implementation: Implementation?
  package init(_ implementation: Implementation) {
    self.implementation = implementation
    registerSchemeNode(self)
  }
  package func traceSchemeChildren(_ visit: (any SchemeHeapNode) -> Void) {
    guard let implementation else { return }
    switch implementation {
    case .closure(_, let body, let environment):
      body.forEach { traceValue($0, visit) }
      visit(environment)
    case .continuation(let captured):
      traceContinuation(captured.continuation, visit)
      captured.winds.forEach(visit)
    case .primitive, .special: break
    }
  }
  package func breakSchemeCycles() { implementation = nil }
}

public final class Promise: SchemeHeapNode {
  package enum State {
    case pending(Value, SchemeEnvironment)
    case forcing(Value, SchemeEnvironment)
    case done([Value])
  }
  package var state: State
  package init(_ expression: Value, _ environment: SchemeEnvironment) {
    state = .pending(expression, environment)
    registerSchemeNode(self)
  }
  package func traceSchemeChildren(_ visit: (any SchemeHeapNode) -> Void) {
    switch state {
    case .pending(let value, let environment), .forcing(let value, let environment):
      traceValue(value, visit)
      visit(environment)
    case .done(let values): values.forEach { traceValue($0, visit) }
    }
  }
  package func breakSchemeCycles() { state = .done([]) }
}

public indirect enum Value {
  case integer(BigInt)
  case rational(Rational)
  case real(Double)
  case complex(real: RealComponent, imaginary: RealComponent)
  case boolean(Bool)
  case character(Character)
  case symbol(String)
  case string(SchemeString)
  case vector(SchemeVector)
  case pair(Pair)
  case procedure(Procedure)
  case promise(Promise)
  case port(SchemePort)
  case environment(SchemeEnvironment)
  case empty, unspecified, eof, undefined

  public var written: String { Writer.write(self) }
  public var displayed: String {
    switch self {
    case .string(let value): value.string
    case .character(let value): String(value)
    default: Writer.display(self)
    }
  }
}
