import Foundation

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
  fileprivate var isLiteral = false
  public init(_ car: Value, _ cdr: Value) {
    self.car = car
    self.cdr = cdr
    registerSchemeNode(self)
  }
  func traceSchemeChildren(_ visit: (any SchemeHeapNode) -> Void) {
    traceValue(car, visit)
    traceValue(cdr, visit)
  }
  func breakSchemeCycles() {
    car = .undefined
    cdr = .undefined
  }
}

public final class SchemeString {
  public var characters: [Character]
  fileprivate var isLiteral = false
  public init(_ value: String) { characters = Array(value) }
  public var string: String { String(characters) }
}

public final class SchemeVector: SchemeHeapNode {
  public var elements: [Value]
  fileprivate var isLiteral = false
  public init(_ elements: [Value]) {
    self.elements = elements
    registerSchemeNode(self)
  }
  func traceSchemeChildren(_ visit: (any SchemeHeapNode) -> Void) {
    elements.forEach { traceValue($0, visit) }
  }
  func breakSchemeCycles() { elements.removeAll() }
}

public final class SchemePort {
  fileprivate enum Mode { case input, output }
  fileprivate let mode: Mode
  fileprivate var input: [Character] = []
  fileprivate var position = 0
  fileprivate var sink: ((String) throws -> Void)?
  fileprivate var output = ""
  fileprivate var handle: FileHandle?
  fileprivate var closed = false

  fileprivate init(input: String) {
    mode = .input
    self.input = Array(input)
  }
  fileprivate init(output: Bool) { mode = .output }
  fileprivate init(sink: @escaping (String) throws -> Void) {
    mode = .output
    self.sink = sink
  }
  fileprivate init(handle: FileHandle, mode: Mode) {
    self.mode = mode
    self.handle = handle
    if mode == .input {
      input = Array(String(decoding: handle.readDataToEndOfFile(), as: UTF8.self))
    } else {
      sink = { text in
        do { try handle.write(contentsOf: Data(text.utf8)) } catch {
          throw SchemeError.io(error.localizedDescription)
        }
      }
    }
  }
}

private final class DynamicFilePort {
  let path: String
  let mode: SchemePort.Mode
  var previous: SchemePort?
  var opened: SchemePort?
  var position = 0
  var offset: UInt64 = 0
  var firstEntry = true

  init(_ path: String, _ mode: SchemePort.Mode) {
    self.path = path
    self.mode = mode
  }
}

private final class Cell: SchemeHeapNode {
  var value: Value
  init(_ value: Value) {
    self.value = value
    registerSchemeNode(self)
  }
  func traceSchemeChildren(_ visit: (any SchemeHeapNode) -> Void) { traceValue(value, visit) }
  func breakSchemeCycles() { value = .undefined }
}

fileprivate enum DefinitionPolicy {
  case mutable
  case fixed
}

public final class SchemeEnvironment: SchemeHeapNode {
  fileprivate var parent: SchemeEnvironment?
  fileprivate let definitionPolicy: DefinitionPolicy
  fileprivate var values: [String: Cell] = [:]
  fileprivate var symbolSpellings: [String: String] = [:]
  fileprivate var aliases: [String: Cell] = [:]
  fileprivate var macros: [String: SyntaxRules] = [:]

  fileprivate init(
    parent: SchemeEnvironment? = nil,
    definitionPolicy: DefinitionPolicy = .mutable
  ) {
    self.parent = parent
    self.definitionPolicy = definitionPolicy
    registerSchemeNode(self)
  }
  func traceSchemeChildren(_ visit: (any SchemeHeapNode) -> Void) {
    if let parent { visit(parent) }
    values.values.forEach(visit)
    aliases.values.forEach(visit)
    macros.values.forEach(visit)
  }
  func breakSchemeCycles() {
    parent = nil
    values.removeAll()
    aliases.removeAll()
    macros.removeAll()
  }
  fileprivate func noteSymbol(_ canonical: String, spelling: String) {
    if spelling != canonical { symbolSpellings[canonical] = spelling }
  }
  fileprivate func define(_ name: String, _ value: Value) {
    let canonical = name.lowercased()
    if name != canonical { symbolSpellings[canonical] = name }
    if let cell = values[canonical] { cell.value = value } else { values[canonical] = Cell(value) }
  }
  fileprivate func requireDefinitionAllowed() throws {
    if case .fixed = definitionPolicy {
      throw SchemeError.syntax("definitions are not allowed in this environment")
    }
  }
  fileprivate func fillPlaceholder(_ name: String, _ value: Value) -> Bool {
    if let cell = values[name], case .undefined = cell.value {
      cell.value = value
      return true
    }
    return parent?.fillPlaceholder(name, value) ?? false
  }
  fileprivate func alias(_ name: String, to cell: Cell) { aliases[name] = cell }
  fileprivate func localCell(_ name: String) -> Cell? { values[name] }
  fileprivate func spelling(_ name: String) -> String? {
    symbolSpellings[name] ?? parent?.spelling(name)
  }
  fileprivate func cell(_ name: String) -> Cell? {
    aliases[name] ?? values[name] ?? parent?.cell(name)
  }
  fileprivate func get(_ name: String) throws -> Value {
    guard let cell = cell(name) else { throw SchemeError.unbound(name) }
    guard case .undefined = cell.value else { return cell.value }
    throw SchemeError.unbound("\(name) used before initialization")
  }
  fileprivate func set(_ name: String, _ value: Value) throws {
    guard let cell = cell(name) else { throw SchemeError.unbound(name) }
    cell.value = value
  }
  fileprivate func macro(_ name: String) -> SyntaxRules? {
    if values[name] != nil { return nil }
    return macros[name] ?? parent?.macro(name)
  }
}

private struct Formals {
  let fixed: [String]
  let rest: String?
}

private enum Special {
  case apply, callCC, values, callWithValues, dynamicWind, force, eval, map, forEach, load
  case callWithInputFile, callWithOutputFile, withInputFromFile, withOutputToFile
  case callWithInputString, callWithOutputString
}

public final class Procedure: SchemeHeapNode {
  fileprivate enum Implementation {
    case primitive(String, ([Value]) throws -> [Value])
    case closure(Formals, [Value], SchemeEnvironment)
    case continuation(Captured)
    case special(Special)
  }
  fileprivate var implementation: Implementation?
  fileprivate init(_ implementation: Implementation) {
    self.implementation = implementation
    registerSchemeNode(self)
  }
  func traceSchemeChildren(_ visit: (any SchemeHeapNode) -> Void) {
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
  func breakSchemeCycles() { implementation = nil }
}

public final class Promise: SchemeHeapNode {
  fileprivate enum State {
    case pending(Value, SchemeEnvironment)
    case forcing(Value, SchemeEnvironment)
    case done([Value])
  }
  fileprivate var state: State
  fileprivate init(_ expression: Value, _ environment: SchemeEnvironment) {
    state = .pending(expression, environment)
    registerSchemeNode(self)
  }
  func traceSchemeChildren(_ visit: (any SchemeHeapNode) -> Void) {
    switch state {
    case .pending(let value, let environment), .forcing(let value, let environment):
      traceValue(value, visit)
      visit(environment)
    case .done(let values): values.forEach { traceValue($0, visit) }
    }
  }
  func breakSchemeCycles() { state = .done([]) }
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
    default: written
    }
  }
}

extension Value: CustomStringConvertible { public var description: String { written } }

private struct Reader {
  private let input: [Character]
  private(set) var spellings: [String: String] = [:]
  private(set) var index: Int
  private var line = 1
  private var column = 1

  init(_ source: String, start: Int = 0) {
    input = Array(source)
    index = start
    if start > 0 {
      for character in input[..<min(start, input.count)] {
        if character == "\n" {
          line += 1
          column = 1
        } else {
          column += 1
        }
      }
    }
  }

  init(_ characters: [Character], start: Int = 0) {
    input = characters
    index = start
    if start > 0 {
      for character in input[..<min(start, input.count)] {
        if character == "\n" {
          line += 1
          column = 1
        } else {
          column += 1
        }
      }
    }
  }

  mutating func readAll() throws -> [Value] {
    var result: [Value] = []
    while let value = try readOne() { result.append(value) }
    return result
  }

  mutating func readOne() throws -> Value? {
    skipSpace()
    guard !isAtEnd else { return nil }
    return try datum()
  }

  private var isAtEnd: Bool { index >= input.count }
  private var current: Character? { isAtEnd ? nil : input[index] }

  private mutating func advance() -> Character? {
    guard !isAtEnd else { return nil }
    let character = input[index]
    index += 1
    if character == "\n" {
      line += 1
      column = 1
    } else {
      column += 1
    }
    return character
  }

  private mutating func skipSpace() {
    while let character = current {
      if character.isWhitespace {
        _ = advance()
      } else if character == ";" {
        while let next = current, next != "\n" { _ = advance() }
      } else {
        return
      }
    }
  }

  private mutating func datum() throws -> Value {
    skipSpace()
    guard let character = advance() else {
      throw SchemeError.lexical("unexpected end of input", line: line, column: column)
    }
    switch character {
    case "(": return try list()
    case ")": throw SchemeError.lexical("unexpected ')'", line: line, column: column - 1)
    case "'": return abbreviation("quote", try datum())
    case "`": return abbreviation("quasiquote", try datum())
    case ",":
      if current == "@" {
        _ = advance()
        return abbreviation("unquote-splicing", try datum())
      }
      return abbreviation("unquote", try datum())
    case "\"": return try string()
    case "#":
      if current == "(" {
        _ = advance()
        return .vector(SchemeVector(try listElements()))
      }
      if current == "\\" {
        _ = advance()
        return try readCharacter()
      }
      return try atom(starting: character)
    default: return try atom(starting: character)
    }
  }

  private func abbreviation(_ name: String, _ value: Value) -> Value {
    makeList([.symbol(name), value])
  }

  private mutating func listElements() throws -> [Value] {
    var elements: [Value] = []
    while true {
      skipSpace()
      guard let character = current else {
        throw SchemeError.lexical("unterminated vector", line: line, column: column)
      }
      if character == ")" {
        _ = advance()
        return elements
      }
      elements.append(try datum())
    }
  }

  private mutating func list() throws -> Value {
    var elements: [Value] = []
    while true {
      skipSpace()
      guard let character = current else {
        throw SchemeError.lexical("unterminated list", line: line, column: column)
      }
      if character == ")" {
        _ = advance()
        return makeList(elements)
      }
      if character == "." && isDelimiter(peek(1)) {
        guard !elements.isEmpty else {
          throw SchemeError.lexical("dot cannot start a list", line: line, column: column)
        }
        _ = advance()
        skipSpace()
        guard current != ")" && current != nil else {
          throw SchemeError.lexical("missing dotted-list tail", line: line, column: column)
        }
        let tail = try datum()
        skipSpace()
        guard current == ")" else {
          throw SchemeError.lexical("dotted list must have one tail", line: line, column: column)
        }
        _ = advance()
        return makeList(elements, tail: tail)
      }
      elements.append(try datum())
    }
  }

  private mutating func string() throws -> Value {
    var result = ""
    while let character = advance() {
      if character == "\"" { return .string(SchemeString(result)) }
      if character == "\\" {
        guard let escaped = advance() else {
          throw SchemeError.lexical("unterminated string escape", line: line, column: column)
        }
        switch escaped {
        case "\"", "\\": result.append(escaped)
        default:
          throw SchemeError.lexical(
            "invalid string escape \\\(escaped)",
            line: line,
            column: column - 1
          )
        }
      } else {
        result.append(character)
      }
    }
    throw SchemeError.lexical("unterminated string", line: line, column: column)
  }

  private mutating func readCharacter() throws -> Value {
    guard let first = advance() else {
      throw SchemeError.lexical("incomplete character literal", line: line, column: column)
    }
    var token = String(first)
    while let character = current, !isDelimiter(character) { token.append(advance()!) }
    switch token.lowercased() {
    case "space": return .character(" ")
    case "newline": return .character("\n")
    default:
      guard token.count == 1, let character = token.first else {
        throw SchemeError.lexical(
          "invalid character literal #\\\(token)",
          line: line,
          column: column - token.count
        )
      }
      return .character(character)
    }
  }

  private mutating func atom(starting first: Character) throws -> Value {
    var token = String(first)
    while let character = current, !isDelimiter(character) { token.append(advance()!) }
    if token.contains(where: { "[]{}|".contains($0) }) {
      throw SchemeError.lexical(
        "reserved character in token \(token)",
        line: line,
        column: column - token.count
      )
    }
    let folded = token.lowercased()
    if folded == "#t" { return .boolean(true) }
    if folded == "#f" { return .boolean(false) }
    if let number = parseNumber(token) { return number }
    if folded.hasPrefix("#e") {
      throw SchemeError.lexical(
        "unsupported exact numeric literal \(token)",
        line: line,
        column: column - token.count
      )
    }
    if folded.hasPrefix("#") {
      throw SchemeError.lexical(
        "unsupported or invalid token \(token)",
        line: line,
        column: column - token.count
      )
    }
    if looksNumeric(token) {
      throw SchemeError.lexical(
        "invalid numeric literal \(token)",
        line: line,
        column: column - token.count
      )
    }
    guard isIdentifier(token) else {
      throw SchemeError.lexical(
        "invalid identifier \(token)",
        line: line,
        column: column - token.count
      )
    }
    if token != folded { spellings[folded] = token }
    return .symbol(folded)
  }

  private enum NumericExactness {
    case unspecified
    case exact
    case inexact
  }

  private struct ParsedInteger {
    let value: BigInt
    let hasPlaceholder: Bool
  }

  private func parseNumber(_ raw: String) -> Value? {
    var token = raw.lowercased()
    var radix = 10
    var exactness = NumericExactness.unspecified
    var radixSeen = false
    var exactnessSeen = false
    while token.hasPrefix("#") {
      guard token.count >= 2 else { return nil }
      switch token[token.index(after: token.startIndex)] {
      case "b", "o", "d", "x":
        guard !radixSeen else { return nil }
        radix =
          token.hasPrefix("#b") ? 2 : token.hasPrefix("#o") ? 8 : token.hasPrefix("#d") ? 10 : 16
        radixSeen = true
      case "e", "i":
        guard !exactnessSeen else { return nil }
        exactness = token.hasPrefix("#e") ? .exact : .inexact
        exactnessSeen = true
      default: return nil
      }
      token.removeFirst(2)
    }
    guard !token.isEmpty else { return nil }
    guard let parsed = parseComplex(token, radix: radix, exactness: exactness) else { return nil }
    return value(from: parsed)
  }

  private func parseComplex(
    _ token: String, radix: Int, exactness: NumericExactness
  ) -> SchemeNumber? {
    if let at = token.firstIndex(of: "@") {
      guard token[token.index(after: at)...].firstIndex(of: "@") == nil,
        let magnitude = parseReal(String(token[..<at]), radix: radix, exactness: exactness),
        let angle = parseReal(String(token[token.index(after: at)...]), radix: radix, exactness: exactness)
      else { return nil }
      var number = SchemeNumber.polar(magnitude: magnitude, angle: angle)
      if exactness == .inexact { number = number.inexact() }
      return number
    }

    guard token.last == "i" else {
      return parseReal(token, radix: radix, exactness: exactness).map(SchemeNumber.real)
    }

    let body = String(token.dropLast())
    guard !body.isEmpty else { return nil }
    if body == "+" || body == "-" {
      return .complex(
        real: .exact(Rational(0)),
        imaginary: implicitImaginaryUnit(body.first!, exactness: exactness)
      )
    }

    let characters = Array(body)
    guard characters.count > 1 else { return nil }
    for index in 1..<characters.count where characters[index] == "+" || characters[index] == "-" {
      let realText = String(characters[..<index])
      let imaginaryText = String(characters[(index + 1)...])
      guard let real = parseReal(realText, radix: radix, exactness: exactness) else { continue }
      let imaginary: RealComponent?
      if imaginaryText.isEmpty {
        imaginary = implicitImaginaryUnit(characters[index], exactness: exactness)
      } else {
        imaginary = parseUnsignedReal(imaginaryText, radix: radix, exactness: exactness).map {
          characters[index] == "+" ? $0 : -$0
        }
      }
      if let imaginary { return .complex(real: real, imaginary: imaginary) }
    }

    if characters.first == "+" || characters.first == "-" {
      let sign = characters[0]
      let magnitude = String(characters.dropFirst())
      guard let imaginary = parseUnsignedReal(magnitude, radix: radix, exactness: exactness)
      else { return nil }
      return .complex(
        real: .exact(Rational(0)),
        imaginary: sign == "+" ? imaginary : -imaginary
      )
    }
    return nil
  }

  private func implicitImaginaryUnit(
    _ sign: Character, exactness: NumericExactness
  ) -> RealComponent {
    let value = sign == "+" ? 1.0 : -1.0
    return exactness == .inexact ? .inexact(value) : .exact(Rational(Int64(value)))
  }

  private func parseReal(
    _ text: String, radix: Int, exactness: NumericExactness
  ) -> RealComponent? {
    guard let first = text.first else { return nil }
    if first == "+" || first == "-" {
      let magnitude = String(text.dropFirst())
      guard let value = parseUnsignedReal(magnitude, radix: radix, exactness: exactness) else {
        return nil
      }
      return first == "-" ? -value : value
    }
    return parseUnsignedReal(text, radix: radix, exactness: exactness)
  }

  private func parseUnsignedReal(
    _ text: String, radix: Int, exactness: NumericExactness
  ) -> RealComponent? {
    guard !text.isEmpty else { return nil }
    let slashParts = text.split(separator: "/", omittingEmptySubsequences: false)
    if text.contains("/") {
      guard slashParts.count == 2,
        let numerator = parseUnsignedInteger(String(slashParts[0]), radix: radix),
        let denominator = parseUnsignedInteger(String(slashParts[1]), radix: radix),
        let rational = Rational(numerator.value, denominator.value)
      else { return nil }
      guard exactness != .exact || (!numerator.hasPlaceholder && !denominator.hasPlaceholder) else {
        return nil
      }
      let inexact = exactness == .inexact || numerator.hasPlaceholder || denominator.hasPlaceholder
      return inexact ? .inexact(rational.doubleValue) : .exact(rational)
    }

    if radix != 10 {
      guard let integer = parseUnsignedInteger(text, radix: radix) else { return nil }
      guard exactness != .exact || !integer.hasPlaceholder else { return nil }
      return exactness == .inexact || integer.hasPlaceholder
        ? .inexact(integer.value.doubleValue)
        : .exact(Rational(integer.value)!)
    }

    return parseDecimalReal(text, exactness: exactness)
  }

  private func parseUnsignedInteger(_ text: String, radix: Int) -> ParsedInteger? {
    guard !text.isEmpty else { return nil }
    var sawDigit = false
    var sawPlaceholder = false
    for character in text {
      if character == "#" {
        sawPlaceholder = true
      } else {
        guard isDigit(character, radix: radix), !sawPlaceholder else { return nil }
        sawDigit = true
      }
    }
    guard sawDigit else { return nil }
    let normalized = text.replacingOccurrences(of: "#", with: "0")
    guard let value = BigInt(normalized, radix: radix) else { return nil }
    return ParsedInteger(value: value, hasPlaceholder: sawPlaceholder)
  }

  private func parseDecimalReal(
    _ text: String, exactness: NumericExactness
  ) -> RealComponent? {
    let characters = Array(text)
    var exponentIndex: Int?
    for index in characters.indices where "esfdl".contains(characters[index]) {
      guard exponentIndex == nil else { return nil }
      exponentIndex = index
    }

    let mantissa: String
    let exponentText: String?
    let exponentMarker: Character?
    if let exponentIndex {
      guard exponentIndex > 0, exponentIndex + 1 < characters.count else { return nil }
      mantissa = String(characters[..<exponentIndex])
      exponentMarker = characters[exponentIndex]
      exponentText = String(characters[(exponentIndex + 1)...])
      guard validExponent(exponentText!) else { return nil }
    } else {
      mantissa = text
      exponentText = nil
      exponentMarker = nil
    }

    guard let decimal = parseDecimalMantissa(mantissa) else { return nil }
    let hasExponent = exponentText != nil
    let inexactSyntax = decimal.hasPlaceholder || hasExponent || decimal.hasDot
    guard exactness != .exact || !decimal.hasPlaceholder else { return nil }

    let normalizedMantissa = decimal.normalized
    let normalized = normalizedMantissa + (exponentMarker.map { String($0) } ?? "")
      + (exponentText ?? "")
    if exactness == .exact {
      guard let rational = exactDecimal(normalized) else { return nil }
      return .exact(rational)
    }
    if !inexactSyntax, let integer = BigInt(normalized, radix: 10) {
      return exactness == .inexact
        ? .inexact(integer.doubleValue)
        : .exact(Rational(integer)!)
    }
    let doubleText = normalized
      .replacingOccurrences(of: "s", with: "e")
      .replacingOccurrences(of: "f", with: "e")
      .replacingOccurrences(of: "d", with: "e")
      .replacingOccurrences(of: "l", with: "e")
    guard let real = Double(doubleText) else { return nil }
    return .inexact(real)
  }

  private struct DecimalMantissa {
    let normalized: String
    let hasPlaceholder: Bool
    let hasDot: Bool
  }

  private func parseDecimalMantissa(_ text: String) -> DecimalMantissa? {
    let characters = Array(text)
    let dots = characters.indices.filter { characters[$0] == "." }
    guard dots.count <= 1 else { return nil }
    if dots.isEmpty {
      guard let integer = parseUnsignedInteger(text, radix: 10) else { return nil }
      return DecimalMantissa(
        normalized: integer.value.description,
        hasPlaceholder: integer.hasPlaceholder,
        hasDot: false
      )
    }

    let dot = dots[0]
    let before = String(characters[..<dot])
    let after = String(characters[(dot + 1)...])
    if before.isEmpty {
      guard let right = decimalDigitHashRun(after, requireDigit: true) else { return nil }
      return DecimalMantissa(
        normalized: "." + right.normalized,
        hasPlaceholder: right.hasPlaceholder,
        hasDot: true
      )
    }

    guard let left = decimalDigitHashRun(before, requireDigit: true),
      let right = decimalDigitHashRun(after, requireDigit: false),
      !left.hasPlaceholder || right.digitCount == 0
    else { return nil }
    return DecimalMantissa(
      normalized: left.normalized + "." + right.normalized,
      hasPlaceholder: left.hasPlaceholder || right.hasPlaceholder,
      hasDot: true
    )
  }

  private struct DecimalDigitHashRun {
    let normalized: String
    let digitCount: Int
    let hasPlaceholder: Bool
  }

  private func decimalDigitHashRun(_ text: String, requireDigit: Bool) -> DecimalDigitHashRun? {
    guard !requireDigit || !text.isEmpty else { return nil }
    var sawPlaceholder = false
    var digitCount = 0
    for character in text {
      if character == "#" {
        sawPlaceholder = true
      } else {
        guard character.isASCII, character.isNumber, !sawPlaceholder else { return nil }
        digitCount += 1
      }
    }
    guard !requireDigit || digitCount > 0 else { return nil }
    return DecimalDigitHashRun(
      normalized: text.replacingOccurrences(of: "#", with: "0"),
      digitCount: digitCount,
      hasPlaceholder: sawPlaceholder
    )
  }

  private func validExponent(_ text: String) -> Bool {
    let characters = Array(text)
    guard !characters.isEmpty else { return false }
    let start = characters.first == "+" || characters.first == "-" ? 1 : 0
    guard start < characters.count else { return false }
    return characters[start...].allSatisfy { $0.isASCII && $0.isNumber }
  }

  private func isDigit(_ character: Character, radix: Int) -> Bool {
    guard character.isASCII else { return false }
    switch character {
    case "0"..."9": return Int(String(character))! < radix
    case "a"..."f": return radix == 16
    default: return false
    }
  }

  private func exactDecimal(_ text: String) -> Rational? {
    let exponentIndex = text.firstIndex(where: { "esfdl".contains($0) })
    let mantissa = exponentIndex.map { String(text[..<$0]) } ?? text
    let exponent: Int
    if let exponentIndex {
      guard let parsed = Int(text[text.index(after: exponentIndex)...]), parsed != Int.min else {
        return nil
      }
      exponent = parsed
    } else {
      exponent = 0
    }
    let negative = mantissa.hasPrefix("-")
    let unsigned =
      mantissa.first == "+" || mantissa.first == "-" ? String(mantissa.dropFirst()) : mantissa
    let pieces = unsigned.split(separator: ".", omittingEmptySubsequences: false)
    guard pieces.count <= 2, pieces.contains(where: { !$0.isEmpty }) else { return nil }
    let digits = pieces.joined()
    guard var significand = BigInt(digits) else { return nil }
    if negative { significand = -significand }
    let fractionalDigits = pieces.count == 2 ? pieces[1].count : 0
    if exponent < 0 && fractionalDigits > Int.max + exponent { return nil }
    return Rational.exactDecimal(
      significand: significand,
      fractionalDigits: fractionalDigits,
      exponent: exponent
    )
  }

  private func value(from number: SchemeNumber) -> Value {
    switch number {
    case .real(.exact(let rational)):
      return rational.isInteger ? .integer(rational.numerator) : .rational(rational)
    case .real(.inexact(let real)): return .real(real)
    case .complex(let real, let imaginary): return .complex(real: real, imaginary: imaginary)
    }
  }

  private func looksNumeric(_ token: String) -> Bool {
    guard let first = token.first else { return false }
    if first.isNumber { return true }
    if first == "+" || first == "-", token.count > 1 {
      return token.dropFirst().first?.isNumber == true || token.dropFirst().first == "."
    }
    return first == "." && token.dropFirst().first?.isNumber == true
  }

  private func isIdentifier(_ token: String) -> Bool {
    if token == "+" || token == "-" || token == "..." { return true }
    guard let first = token.first, isIdentifierInitial(first) else { return false }
    return token.dropFirst().allSatisfy(isIdentifierSubsequent)
  }

  private func isIdentifierInitial(_ character: Character) -> Bool {
    switch character {
    case "a"..."z", "A"..."Z": return true
    default: return "!$%&*/:<=>?^_~".contains(character)
    }
  }

  private func isIdentifierSubsequent(_ character: Character) -> Bool {
    isIdentifierInitial(character)
      || (character.isASCII && character.isNumber)
      || "+-.@".contains(character)
  }

  private func peek(_ distance: Int) -> Character? {
    let position = index + distance
    return position < input.count ? input[position] : nil
  }

  private func isDelimiter(_ character: Character?) -> Bool {
    guard let character else { return true }
    return character.isWhitespace || ["(", ")", "\"", ";", "'", "`", ","].contains(character)
  }
}

private enum Writer {
  static func write(_ value: Value) -> String {
    var active = Set<ObjectIdentifier>()
    return render(value, &active)
  }

  private static func render(_ value: Value, _ active: inout Set<ObjectIdentifier>) -> String {
    switch value {
    case .integer(let number): return number.description
    case .rational(let number): return number.description
    case .real(let number): return SchemeNumber(number).description
    case .complex(let real, let imaginary):
      return SchemeNumber.complex(real: real, imaginary: imaginary).description
    case .boolean(let value): return value ? "#t" : "#f"
    case .character(let value):
      if value == " " { return "#\\space" }
      if value == "\n" { return "#\\newline" }
      return "#\\\(value)"
    case .symbol(let name): return symbolSpelling(name)
    case .string(let value):
      return "\""
        + value.string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
          of: "\"",
          with: "\\\""
        ) + "\""
    case .vector(let vector):
      let identifier = ObjectIdentifier(vector)
      guard active.insert(identifier).inserted else { return "#<cycle>" }
      defer { active.remove(identifier) }
      return "#(" + vector.elements.map { render($0, &active) }.joined(separator: " ") + ")"
    case .pair(let pair): return renderPair(pair, &active)
    case .procedure: return "#<procedure>"
    case .promise: return "#<promise>"
    case .port: return "#<port>"
    case .environment: return "#<environment>"
    case .empty: return "()"
    case .unspecified: return "#<unspecified>"
    case .eof: return "#<eof>"
    case .undefined: return "#<undefined>"
    }
  }

  private static func renderPair(_ pair: Pair, _ active: inout Set<ObjectIdentifier>) -> String {
    let root = ObjectIdentifier(pair)
    guard active.insert(root).inserted else { return "#<cycle>" }
    defer { active.remove(root) }
    var pieces: [String] = []
    var cursor: Value = .pair(pair)
    var chain = Set<ObjectIdentifier>()
    while case .pair(let cell) = cursor {
      guard chain.insert(ObjectIdentifier(cell)).inserted else {
        pieces.append(". #<cycle>")
        cursor = .empty
        break
      }
      pieces.append(render(cell.car, &active))
      cursor = cell.cdr
    }
    if case .empty = cursor {} else { pieces.append(". " + render(cursor, &active)) }
    return "(" + pieces.joined(separator: " ") + ")"
  }
}

private func makeList<S: Sequence>(_ values: S, tail: Value = .empty) -> Value
where S.Element == Value { Array(values).reversed().reduce(tail) { .pair(Pair($1, $0)) } }

private let nonstandardSymbolPrefix = "\u{1}"
private let internalSymbolPrefix = "\u{2}r5rs:"
private let internalSyntaxPrefix = internalSymbolPrefix + "syntax:"
private let internalTemporaryPrefix = internalSymbolPrefix + "temp:"

private func internalSyntax(_ name: String) -> Value {
  .symbol(internalSyntaxPrefix + name)
}

private func internalSyntaxName(_ value: Value) -> String? {
  guard case .symbol(let name) = value, name.hasPrefix(internalSyntaxPrefix) else { return nil }
  return String(name.dropFirst(internalSyntaxPrefix.count))
}

private func internalTemporary(_ name: String) -> Value {
  .symbol(internalTemporaryPrefix + name)
}

private func symbolToken(_ spelling: String) -> String {
  let canonical = spelling.lowercased()
  return spelling == canonical && !spelling.hasPrefix(nonstandardSymbolPrefix)
    && !spelling.hasPrefix(internalSymbolPrefix)
    ? canonical
    : nonstandardSymbolPrefix + spelling
}

private func symbolSpelling(_ token: String) -> String {
  token.hasPrefix(nonstandardSymbolPrefix) ? String(token.dropFirst()) : token
}

private func markLiteral(_ value: Value, _ seen: inout Set<ObjectIdentifier>) {
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

private func array(from list: Value, context: String = "list") throws -> [Value] {
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

private func identifier(_ value: Value, _ context: String) throws -> String {
  guard case .symbol(let name) = value else {
    throw SchemeError.syntax("\(context) requires an identifier")
  }
  return name
}

private func isFalse(_ value: Value) -> Bool {
  if case .boolean(false) = value { return true }
  return false
}

private indirect enum Capture {
  case value(Value)
  case sequence([Capture])
}

private final class SyntaxRules: SchemeHeapNode {
  private enum LiteralBinding {
    case cell(Cell)
    case macro(SyntaxRules)
    case unbound
  }
  let keyword: String
  let literals: Set<String>
  var rules: [(Value, Value)]
  var definition: SchemeEnvironment?
  let ellipsis: String?
  private var literalBindings: [String: LiteralBinding] = [:]
  private var aliases: [String: String] = [:]
  private var introduced: [String: String] = [:]

  init(keyword: String, spec: Value, definition: SchemeEnvironment) throws {
    let form = try array(from: spec, context: "syntax-rules")
    guard form.count >= 3, case .symbol("syntax-rules") = form[0] else {
      throw SchemeError.syntax("transformer must be syntax-rules")
    }
    self.keyword = keyword
    let literalIndex: Int
    if case .symbol(let marker) = form[1] {
      self.ellipsis = marker
      literalIndex = 2
    } else {
      self.ellipsis = definition.cell("...") == nil && definition.macro("...") == nil ? "..." : nil
      literalIndex = 1
    }
    guard form.count >= literalIndex + 2 else {
      throw SchemeError.syntax("syntax-rules requires literals and rules")
    }
    self.literals = Set(
      try array(from: form[literalIndex], context: "syntax-rules literals").map {
        try identifier($0, "syntax-rules literal")
      }
    )
    self.rules = try form.dropFirst(literalIndex + 1).map {
      let rule = try array(from: $0, context: "syntax rule")
      guard rule.count == 2 else {
        throw SchemeError.syntax("syntax rule requires pattern and template")
      }
      return (rule[0], rule[1])
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

  func traceSchemeChildren(_ visit: (any SchemeHeapNode) -> Void) {
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
  func breakSchemeCycles() {
    definition = nil
    rules.removeAll()
    literalBindings.removeAll()
    aliases.removeAll()
    introduced.removeAll()
  }

  private func freeIdentifiers() -> Set<String> {
    let core: Set<String> = [
      "quote", "if", "begin", "lambda", "define", "set!", "let", "let*", "letrec", "and", "or",
      "cond", "case", "do", "delay", "quasiquote", "unquote", "unquote-splicing", "let-syntax",
      "letrec-syntax", "define-syntax", "syntax-rules", "else", "=>"
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

  private func collectSymbols(_ value: Value, into symbols: inout Set<String>) {
    switch value {
    case .symbol(let name): symbols.insert(name)
    case .pair(let pair):
      collectSymbols(pair.car, into: &symbols)
      collectSymbols(pair.cdr, into: &symbols)
    case .vector(let vector): for value in vector.elements { collectSymbols(value, into: &symbols) }
    default: break
    }
  }

  func expand(_ use: Value, in useEnvironment: SchemeEnvironment, serial: inout Int) throws -> Value
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

  private func literalMatches(_ name: String, _ actual: String, _ useEnvironment: SchemeEnvironment)
    -> Bool
  {
    guard name == actual, let binding = literalBindings[name] else { return false }
    switch binding {
    case .cell(let cell): return useEnvironment.cell(actual) === cell
    case .macro(let macro): return useEnvironment.macro(actual) === macro
    case .unbound: return useEnvironment.cell(actual) == nil && useEnvironment.macro(actual) == nil
    }
  }

  private func inserting(_ capture: Capture?, path: ArraySlice<Int>, value: Value) -> Capture? {
    guard let index = path.first else {
      if case .value(let old)? = capture { return equal(old, value) ? capture : nil }
      return capture == nil ? .value(value) : nil
    }
    var children: [Capture]
    if case .sequence(let existing)? = capture {
      children = existing
    } else if capture == nil {
      children = []
    } else {
      return nil
    }
    guard index <= children.count else { return nil }
    let child: Capture?
    if index == children.count {
      child = inserting(nil, path: path.dropFirst(), value: value)
    } else {
      child = inserting(children[index], path: path.dropFirst(), value: value)
    }
    guard let child else { return nil }
    if index == children.count { children.append(child) } else { children[index] = child }
    return .sequence(children)
  }

  private func insertingEmpty(_ capture: Capture?, path: ArraySlice<Int>) -> Capture? {
    guard let index = path.first else {
      if case .sequence? = capture { return capture }
      return capture == nil ? .sequence([]) : nil
    }
    var children: [Capture]
    if case .sequence(let existing)? = capture {
      children = existing
    } else if capture == nil {
      children = []
    } else {
      return nil
    }
    guard index <= children.count else { return nil }
    let child = insertingEmpty(
      index == children.count ? nil : children[index],
      path: path.dropFirst()
    )
    guard let child else { return nil }
    if index == children.count { children.append(child) } else { children[index] = child }
    return .sequence(children)
  }

  private func bind(
    _ name: String,
    _ value: Value,
    path: [Int],
    into captures: inout [String: Capture]
  ) -> Bool {
    guard let capture = inserting(captures[name], path: path[...], value: value) else {
      return false
    }
    captures[name] = capture
    return true
  }

  private func match(
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

  private func matchSequence(
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

  private func initializeEmpty(_ pattern: Value, path: [Int], captures: inout [String: Capture]) {
    var names = Set<String>()
    collectSymbols(pattern, into: &names)
    names.subtract(literals)
    names.subtract([keyword, "_", ellipsis ?? ""])
    for name in names {
      if let capture = insertingEmpty(captures[name], path: path[...]) { captures[name] = capture }
    }
  }

  private func capture(_ name: String, at path: [Int], in captures: [String: Capture]) -> Capture? {
    var node = captures[name]
    for index in path {
      guard case .sequence(let children)? = node, index < children.count else { return nil }
      node = children[index]
    }
    return node
  }

  private func transcribe(
    _ template: Value,
    _ captures: [String: Capture],
    path: [Int],
    serial: inout Int
  ) throws -> Value {
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
      let transcribedTail = try tail.map { try transcribe($0, captures, path: path, serial: &serial) }
      return makeList(transcribed, tail: transcribedTail ?? .empty)
    case .vector(let vector):
      return .vector(
        SchemeVector(try transcribeSequence(vector.elements, captures, path: path, serial: &serial))
      )
    default: return template
    }
  }

  private func transcribeSequence(
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

  private func expandRepeated(
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

  private func substituteQuoted(_ value: Value, _ captures: [String: Capture], _ path: [Int]) throws
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

  private func captureNames(in value: Value, captures: [String: Capture]) -> [String] {
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

  private func improperList(from value: Value, context: String) throws -> ([Value], Value?) {
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

private func isSymbol(_ value: Value, _ name: String) -> Bool {
  if case .symbol(let actual) = value { return actual == name }
  return false
}

private func isDefinitionBoundaryKeyword(_ name: String) -> Bool {
  ["define", "begin", "define-syntax"].contains(name)
}

private let r5rsReportProcedureNames: Set<String> = [
  "eq?", "eqv?", "equal?", "number?", "complex?", "real?", "rational?", "integer?", "exact?",
  "inexact?", "=", "<", ">", "<=", ">=", "zero?", "positive?", "negative?", "odd?", "even?",
  "max", "min", "+", "*", "-", "/", "abs", "quotient", "remainder", "modulo", "gcd", "lcm",
  "numerator", "denominator", "floor", "ceiling", "truncate", "round", "rationalize", "exp", "log",
  "sin", "cos", "tan", "asin", "acos", "atan", "sqrt", "expt", "make-rectangular", "make-polar",
  "real-part", "imag-part", "magnitude", "angle", "exact->inexact", "inexact->exact", "number->string",
  "string->number", "not", "boolean?", "pair?", "cons", "car", "cdr", "set-car!", "set-cdr!",
  "caar", "cadr", "cdar", "cddr", "caaar", "caadr", "cadar", "caddr", "cdaar", "cdadr", "cddar",
  "caaaar", "caaadr", "caadar", "caaddr", "cadaar", "cadadr", "caddar", "cadddr", "cdaaar",
  "cdaadr", "cdadar", "cdaddr", "cddaar", "cddadr", "cdddar", "cddddr", "null?", "list?", "list",
  "length", "append", "reverse", "list-tail", "list-ref", "memq", "memv", "member", "assq", "assv",
  "assoc", "symbol?", "symbol->string", "string->symbol", "char?", "char=?", "char<?", "char>?",
  "char<=?", "char>=?", "char-ci=?", "char-ci<?", "char-ci>?", "char-ci<=?", "char-ci>=?",
  "char-alphabetic?", "char-numeric?", "char-whitespace?", "char-upper-case?", "char-lower-case?",
  "char-upcase", "char-downcase", "char->integer", "integer->char", "string?", "make-string", "string",
  "string-length", "string-ref", "string-set!", "substring", "string-append", "string->list", "list->string",
  "string-copy", "string-fill!", "string=?", "string<?", "string>?", "string<=?", "string>=?",
  "string-ci=?", "string-ci<?", "string-ci>?", "string-ci<=?", "string-ci>=?", "vector?", "make-vector",
  "vector", "vector-length", "vector-ref", "vector-set!", "vector->list", "list->vector", "vector-fill!",
  "procedure?", "port?", "apply", "call-with-current-continuation", "map", "for-each", "values", "call-with-values",
  "dynamic-wind", "force", "eval", "scheme-report-environment", "null-environment", "input-port?",
  "output-port?", "current-input-port", "current-output-port", "call-with-input-file", "call-with-output-file",
  "open-input-file", "open-output-file", "close-input-port", "close-output-port", "read", "read-char",
  "peek-char", "eof-object?", "char-ready?", "write", "display", "newline", "write-char",
  // Supported R5RS optional procedures included by scheme-report-environment.
  "interaction-environment", "with-input-from-file", "with-output-to-file", "load"
]

private final class Wind: SchemeHeapNode {
  let id: Int
  var before: Value
  var after: Value
  init(_ id: Int, _ before: Value, _ after: Value) {
    self.id = id
    self.before = before
    self.after = after
    registerSchemeNode(self)
  }
  func traceSchemeChildren(_ visit: (any SchemeHeapNode) -> Void) {
    traceValue(before, visit)
    traceValue(after, visit)
  }
  func breakSchemeCycles() {
    before = .undefined
    after = .undefined
  }
}

private struct Captured {
  let continuation: Continuation
  let winds: [Wind]
}

private enum WindAction {
  case exit(Wind)
  case enter(Wind)
}

private indirect enum Continuation {
  case halt
  case ifFrame(Value, Value, SchemeEnvironment, Continuation)
  case beginFrame([Value], SchemeEnvironment, Bool, Continuation)
  case expressionContext(Continuation)
  case discardFrame(Continuation)
  case setFrame(String, SchemeEnvironment, Continuation)
  case defineFrame(String, SchemeEnvironment, Continuation)
  case operatorFrame([Value], SchemeEnvironment, Continuation)
  case operandFrame(Value, [Value], [Value], SchemeEnvironment, Continuation)
  case letrecFrame(
    [(String, Value)], Int, SchemeEnvironment, [Value], SchemeEnvironment, Continuation
  )
  case callValuesFrame(Value, Continuation)
  case promiseFrame(Promise, Continuation)
  case windBeforeFrame(Value, Value, Wind, Continuation)
  case windBodyFrame(Wind, Value, Continuation)
  case windAfterFrame([Value], Continuation)
  case transitionFrame([WindAction], Captured, [Value])
  case enteredFrame(Wind, [WindAction], Captured, [Value])
  case mapFrame(Value, [[Value]], Int, [Value], Bool, Continuation)
  case closePortFrame(SchemePort, Continuation)
  case restoreInputFrame(SchemePort, SchemePort, Continuation)
  case restoreOutputFrame(SchemePort, SchemePort, Continuation)
  case outputStringFrame(SchemePort, Continuation)
}

private enum Control {
  case expression(Value, SchemeEnvironment)
  case values([Value])
  case apply(Value, [Value])
}

private func traceValue(_ value: Value, _ visit: (any SchemeHeapNode) -> Void) {
  switch value {
  case .pair(let node): visit(node)
  case .vector(let node): visit(node)
  case .procedure(let node): visit(node)
  case .promise(let node): visit(node)
  case .environment(let node): visit(node)
  default: break
  }
}

private func containsSchemeNode(_ value: Value) -> Bool {
  switch value {
  case .pair, .vector, .procedure, .promise, .environment: true
  default: false
  }
}

private func traceValues(_ values: [Value], _ visit: (any SchemeHeapNode) -> Void) {
  values.forEach { traceValue($0, visit) }
}

private func traceContinuation(_ continuation: Continuation, _ visit: (any SchemeHeapNode) -> Void)
{
  switch continuation {
  case .halt: break
  case .ifFrame(let a, let b, let environment, let next):
    traceValue(a, visit)
    traceValue(b, visit)
    visit(environment)
    traceContinuation(next, visit)
  case .beginFrame(let values, let environment, _, let next):
    traceValues(values, visit)
    visit(environment)
    traceContinuation(next, visit)
  case .expressionContext(let next):
    traceContinuation(next, visit)
  case .discardFrame(let next):
    traceContinuation(next, visit)
  case .setFrame(_, let environment, let next), .defineFrame(_, let environment, let next):
    visit(environment)
    traceContinuation(next, visit)
  case .operatorFrame(let values, let environment, let next):
    traceValues(values, visit)
    visit(environment)
    traceContinuation(next, visit)
  case .operandFrame(let value, let a, let b, let environment, let next):
    traceValue(value, visit)
    traceValues(a, visit)
    traceValues(b, visit)
    visit(environment)
    traceContinuation(next, visit)
  case .letrecFrame(let bindings, _, let environment, let values, let bodyEnvironment, let next):
    bindings.forEach { traceValue($0.1, visit) }
    visit(environment)
    traceValues(values, visit)
    visit(bodyEnvironment)
    traceContinuation(next, visit)
  case .callValuesFrame(let value, let next):
    traceValue(value, visit)
    traceContinuation(next, visit)
  case .promiseFrame(let promise, let next):
    visit(promise)
    traceContinuation(next, visit)
  case .windBeforeFrame(let a, let b, let wind, let next):
    traceValue(a, visit)
    traceValue(b, visit)
    visit(wind)
    traceContinuation(next, visit)
  case .windBodyFrame(let wind, let value, let next):
    visit(wind)
    traceValue(value, visit)
    traceContinuation(next, visit)
  case .windAfterFrame(let values, let next):
    traceValues(values, visit)
    traceContinuation(next, visit)
  case .transitionFrame(let actions, let captured, let values),
    .enteredFrame(_, let actions, let captured, let values):
    actions.forEach { action in
      switch action {
      case .exit(let wind), .enter(let wind): visit(wind)
      }
    }
    traceContinuation(captured.continuation, visit)
    captured.winds.forEach(visit)
    traceValues(values, visit)
  case .mapFrame(let value, let lists, _, let values, _, let next):
    traceValue(value, visit)
    lists.forEach { traceValues($0, visit) }
    traceValues(values, visit)
    traceContinuation(next, visit)
  case .closePortFrame(_, let next), .restoreInputFrame(_, _, let next),
    .restoreOutputFrame(_, _, let next), .outputStringFrame(_, let next):
    traceContinuation(next, visit)
  }
}

public final class Interpreter {
  public typealias Output = (String) -> Void

  private let heap: SchemeHeap
  private let global: SchemeEnvironment
  private let report: SchemeEnvironment
  private let output: Output
  private var currentInput: SchemePort
  private var currentOutput: SchemePort
  private var macroSerial = 0
  private var windSerial = 0
  private var exportedRoots: [Value] = []

  public init(output: @escaping Output = { print($0, terminator: "") }) {
    self.output = output
    let heap = SchemeHeap()
    self.heap = heap
    self.global = heap.withActive { SchemeEnvironment() }
    self.report = heap.withActive { SchemeEnvironment() }
    currentInput = SchemePort(input: "")
    currentOutput = SchemePort(sink: { output($0) })
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

  private func recordSymbols(_ value: Value, in environment: SchemeEnvironment) {
    switch value {
    case .symbol(let name): _ = name
    case .pair(let pair):
      recordSymbols(pair.car, in: environment)
      recordSymbols(pair.cdr, in: environment)
    case .vector(let vector): for item in vector.elements { recordSymbols(item, in: environment) }
    default: break
    }
  }

  private func coreProcedure(_ name: String) -> Value {
    guard let value = report.cell(name)?.value else {
      preconditionFailure("missing R5RS core procedure \(name)")
    }
    return value
  }

  private func coreCall(_ name: String, _ arguments: [Value]) -> Value {
    makeList([coreProcedure(name)] + arguments)
  }

  private func coreKeyword(_ value: Value, in environment: SchemeEnvironment) -> String? {
    if let name = internalSyntaxName(value) { return name }
    guard case .symbol(let name) = value,
      environment.cell(name) == nil && environment.macro(name) == nil
    else { return nil }
    return name
  }

  private func expandMacros(_ rawExpression: Value, in environment: SchemeEnvironment) throws -> Value {
    var expression = rawExpression
    while case .pair(let pair) = expression, case .symbol(let head) = pair.car,
      let transformer = environment.macro(head)
    { expression = try transformer.expand(expression, in: environment, serial: &macroSerial) }
    return expression
  }

  private func isCoreForm(
    _ value: Value, _ name: String, in environment: SchemeEnvironment
  ) -> Bool {
    guard case .pair(let pair) = value else { return false }
    if internalSyntaxName(pair.car) == name { return true }
    guard isSymbol(pair.car, name) else { return false }
    // A value binding shadows a syntactic keyword. The macro check keeps raw
    // body forms consistent with the already-expanded expression path.
    return environment.cell(name) == nil && environment.macro(name) == nil
  }

  private func isDefinitionForm(
    _ value: Value, _ name: String, in environment: SchemeEnvironment
  ) -> Bool { isCoreForm(value, name, in: environment) }

  private func leadingBodyForms(
    _ body: [Value], in environment: SchemeEnvironment
  ) throws -> [Value] {
    var pending = body
    var result: [Value] = []
    var leading = true
    while !pending.isEmpty {
      let form = pending.removeFirst()
      if leading, isCoreForm(form, "begin", in: environment) {
        let elements = try array(from: form, context: "begin")
        pending.insert(contentsOf: elements.dropFirst(), at: 0)
        continue
      }
      result.append(form)
      if !isDefinitionForm(form, "define", in: environment),
        !isDefinitionForm(form, "define-syntax", in: environment)
      { leading = false }
    }
    return result
  }

  private func expandedBody(_ body: [Value], in environment: SchemeEnvironment) throws -> [Value] {
    var pending = body
    var expanded: [Value] = []
    while !pending.isEmpty {
      let form = try expandMacros(pending.removeFirst(), in: environment)
      if isCoreForm(form, "begin", in: environment) {
        let elements = try array(from: form, context: "begin")
        pending.insert(contentsOf: elements.dropFirst(), at: 0)
      } else {
        expanded.append(form)
      }
    }
    return expanded
  }

  private func validateBody(
    _ body: [Value], context: String, in environment: SchemeEnvironment
  ) throws {
    let expanded = try expandedBody(body, in: environment)
    var sawExpression = false
    for form in expanded {
      if isDefinitionForm(form, "define", in: environment)
        || isDefinitionForm(form, "define-syntax", in: environment) {
        if sawExpression {
          throw SchemeError.syntax("definition after expression in \(context)")
        }
        if isDefinitionForm(form, "define-syntax", in: environment) {
          throw SchemeError.syntax("define-syntax is only valid at top level")
        }
      } else {
        sawExpression = true
      }
    }
    guard sawExpression else {
      throw SchemeError.syntax("\(context) requires an expression")
    }
  }

  private func prepareInternalDefinitions(_ body: [Value], in environment: SchemeEnvironment) throws {
    var names = Set<String>()
    let raw = try leadingBodyForms(body, in: environment)
    try prebindDefinitions(raw, in: environment, names: &names)
    let rawNames = names

    // A leading macro may expand to a definition. Expand only after raw
    // definition names are installed so later forms cannot invoke an outer
    // macro with a name that is local to this body.
    _ = try expandedBodyWithPrebinding(
      body, in: environment, names: &names, rawNames: rawNames
    )
  }

  private func expandedBodyWithPrebinding(
    _ body: [Value], in environment: SchemeEnvironment, names: inout Set<String>,
    rawNames: Set<String>
  ) throws -> [Value] {
    var pending = body.map { ($0, true) }
    var expanded: [Value] = []
    var leading = true
    while !pending.isEmpty {
      let (rawForm, isRaw) = pending.removeFirst()
      let rawWasDefinition = isDefinitionForm(rawForm, "define", in: environment)
      let form = try expandMacros(rawForm, in: environment)
      if isCoreForm(form, "begin", in: environment) {
        let elements = try array(from: form, context: "begin")
        let literalRawBegin = isRaw && isCoreForm(rawForm, "begin", in: environment)
        pending.insert(
          contentsOf: elements.dropFirst().map { ($0, literalRawBegin) }, at: 0
        )
        continue
      }
      expanded.append(form)
      if leading, isDefinitionForm(form, "define", in: environment) {
        try prebindDefinitions(
          [form], in: environment, names: &names,
          allowExistingNames: isRaw && rawWasDefinition ? rawNames : []
        )
      } else if !isDefinitionForm(form, "define-syntax", in: environment) {
        leading = false
      }
    }
    return expanded
  }

  private func prebindDefinitions(
    _ forms: [Value], in environment: SchemeEnvironment, names: inout Set<String>,
    allowExistingNames: Set<String> = []
  ) throws {
    for form in forms {
      guard isDefinitionForm(form, "define", in: environment),
        case .pair(let pair) = form else { break }
      let definition = try array(from: .pair(pair), context: "define")
      guard definition.count >= 3 else { throw SchemeError.syntax("define requires name and value") }
      let name: String
      if case .symbol = definition[1] {
        name = try identifier(definition[1], "define")
      } else {
        guard case .pair(let signature) = definition[1] else {
          throw SchemeError.syntax("invalid define")
        }
        name = try identifier(signature.car, "define")
      }
      guard !isDefinitionBoundaryKeyword(name) else {
        throw SchemeError.syntax("cannot define syntactic keyword \(name)")
      }
      if names.contains(name) {
        guard allowExistingNames.contains(name) else {
          throw SchemeError.syntax("duplicate internal definition \(name)")
        }
        continue
      }
      names.insert(name)
      environment.define(name, .undefined)
    }
  }

  private func one(_ values: [Value], _ context: String) throws -> Value {
    guard values.count == 1 else {
      throw SchemeError.arity("\(context) expected one value, got \(values.count)")
    }
    return values[0]
  }

  private func allowsDefinitions(in continuation: Continuation) -> Bool {
    switch continuation {
    case .halt: return true
    case .beginFrame(_, _, let allowed, _): return allowed
    default: return false
    }
  }

  private func run(_ initial: Control) throws -> [Value] {
    var control = initial
    var continuation: Continuation = .halt
    var winds: [Wind] = []

    func scheduleTransition(_ actions: [WindAction], _ target: Captured, _ delivered: [Value]) -> (
      Control, Continuation
    )? {
      guard let first = actions.first else { return (.values(delivered), target.continuation) }
      let rest = Array(actions.dropFirst())
      switch first {
      case .exit(let wind):
        if winds.last === wind { winds.removeLast() }
        return (.apply(wind.after, []), .transitionFrame(rest, target, delivered))
      case .enter(let wind):
        return (.apply(wind.before, []), .enteredFrame(wind, rest, target, delivered))
      }
    }

    while true {
      switch control {
      case .expression(let rawExpression, let environment):
        recordSymbols(rawExpression, in: environment)
        let expression = try expandMacros(rawExpression, in: environment)
        switch expression {
        case .symbol(let name): control = .values([try environment.get(name)])
        case .undefined: throw SchemeError.unbound("undefined value")
        case .pair:
          let form = try array(from: expression, context: "expression")
          guard !form.isEmpty else { throw SchemeError.syntax("empty application") }
          if let keyword = coreKeyword(form[0], in: environment) {
            switch keyword {
            case "quote":
              try require(form, 2, "quote")
              let literal = form[1]
              var seen = Set<ObjectIdentifier>()
              markLiteral(literal, &seen)
              control = .values([literal])
              continue
            case "if":
              guard form.count == 3 || form.count == 4 else {
                throw SchemeError.arity("if expects 2 or 3 arguments")
              }
              continuation = .ifFrame(
                form[2],
                form.count == 4 ? form[3] : .unspecified,
                environment,
                continuation
              )
              control = .expression(form[1], environment)
              continue
            case "begin":
              guard form.count > 1 else { throw SchemeError.syntax("begin requires an expression") }
              let allowDefinitions = allowsDefinitions(in: continuation)
              continuation = .beginFrame(
                Array(form.dropFirst(2)), environment, allowDefinitions, continuation
              )
              control = .expression(form[1], environment)
              continue
            case "lambda":
              guard form.count >= 3 else {
                throw SchemeError.syntax("lambda requires formals and body")
              }
              let formals = try parseFormals(form[1])
              let validation = SchemeEnvironment(parent: environment)
              for name in formals.fixed { validation.define(name, .undefined) }
              if let rest = formals.rest { validation.define(rest, .undefined) }
              let body = Array(form.dropFirst(2))
              try prepareInternalDefinitions(body, in: validation)
              try validateBody(body, context: "lambda", in: validation)
              control = .values([
                .procedure(
                  Procedure(
                    .closure(formals, body, environment)
                  )
                )
              ])
              continue
            case "define":
              guard form.count >= 3 else {
                throw SchemeError.syntax("define requires name and value")
              }
              guard allowsDefinitions(in: continuation) else {
                throw SchemeError.syntax("definition is not valid in expression context")
              }
              try environment.requireDefinitionAllowed()
              if case .symbol(let name) = form[1] {
                try require(form, 3, "define")
                guard !isDefinitionBoundaryKeyword(name) else {
                  throw SchemeError.syntax("cannot define syntactic keyword \(name)")
                }
                continuation = .defineFrame(name, environment, continuation)
                control = .expression(form[2], environment)
              } else {
                guard case .pair(let signature) = form[1] else {
                  throw SchemeError.syntax("invalid define")
                }
                let name = try identifier(signature.car, "define")
                guard !isDefinitionBoundaryKeyword(name) else {
                  throw SchemeError.syntax("cannot define syntactic keyword \(name)")
                }
                let formals = try parseFormals(signature.cdr)
                let validation = SchemeEnvironment(parent: environment)
                validation.define(name, .undefined)
                for formal in formals.fixed { validation.define(formal, .undefined) }
                if let rest = formals.rest { validation.define(rest, .undefined) }
                let body = Array(form.dropFirst(2))
                try prepareInternalDefinitions(body, in: validation)
                try validateBody(body, context: "define", in: validation)
                let procedure = Value.procedure(
                  Procedure(
                    .closure(formals, body, environment)
                  )
                )
                if !environment.fillPlaceholder(name, procedure) {
                  environment.define(name, procedure)
                }
                control = .values([.unspecified])
              }
              continue
            case "define-syntax":
              try require(form, 3, "define-syntax")
              guard allowsDefinitions(in: continuation) else {
                throw SchemeError.syntax("syntax definition is not valid in expression context")
              }
              try environment.requireDefinitionAllowed()
              let name = try identifier(form[1], "define-syntax")
              guard !isDefinitionBoundaryKeyword(name) else {
                throw SchemeError.syntax("cannot define syntactic keyword \(name)")
              }
              environment.macros[name] = try SyntaxRules(
                keyword: name,
                spec: form[2],
                definition: environment
              )
              control = .values([.unspecified])
              continue
            case "let-syntax", "letrec-syntax":
              guard form.count >= 3 else {
                throw SchemeError.syntax("\(keyword) requires bindings and body")
              }
              let definitions = try syntaxBindings(form[1], keyword)
              try ensureDistinct(definitions, "\(keyword) binding")
              let body = Array(form.dropFirst(2))
              let local = SchemeEnvironment(parent: environment)
              let definitionEnvironment = keyword == "letrec-syntax" ? local : environment
              for (name, spec) in definitions {
                local.macros[name] = try SyntaxRules(
                  keyword: name,
                  spec: spec,
                  definition: definitionEnvironment
                )
              }
              try prepareInternalDefinitions(body, in: local)
              try validateBody(body, context: keyword, in: local)
              continuation = .beginFrame(Array(body.dropFirst()), local, true, continuation)
              control = .expression(body[0], local)
              continue
            case "set!":
              try require(form, 3, "set!")
              continuation = .setFrame(try identifier(form[1], "set!"), environment, continuation)
              control = .expression(form[2], environment)
              continue
            case "let":
              control = .expression(try expandLet(form), environment)
              continue
            case "let*":
              control = .expression(try expandLetStar(form), environment)
              continue
            case "letrec":
              guard form.count >= 3 else {
                throw SchemeError.syntax("letrec requires bindings and body")
              }
              let entries = try bindings(form[1], "letrec")
              try ensureDistinct(entries, "letrec")
              let local = SchemeEnvironment(parent: environment)
              for (name, _) in entries { local.define(name, .undefined) }
              let bodyEnvironment = SchemeEnvironment(parent: local)
              let body = Array(form.dropFirst(2))
              try prepareInternalDefinitions(body, in: bodyEnvironment)
              try validateBody(body, context: "letrec", in: bodyEnvironment)
              if entries.isEmpty {
                continuation = .beginFrame(
                  Array(form.dropFirst(3)), bodyEnvironment, true, continuation
                )
                control = .expression(form[2], bodyEnvironment)
              } else {
                continuation = .letrecFrame(
                  entries,
                  0,
                  local,
                  Array(form.dropFirst(2)),
                  bodyEnvironment,
                  continuation
                )
                control = .expression(entries[0].1, local)
              }
              continue
            case "and":
              control = .expression(expandAnd(Array(form.dropFirst())), environment)
              continue
            case "or":
              control = .expression(expandOr(Array(form.dropFirst())), environment)
              continue
            case "cond":
              guard form.count >= 2 else { throw SchemeError.syntax("cond requires a clause") }
              control = .expression(
                try expandCond(Array(form.dropFirst()), environment),
                environment
              )
              continue
            case "case":
              control = .expression(try expandCase(form, environment), environment)
              continue
            case "do":
              control = .expression(try expandDo(form), environment)
              continue
            case "quasiquote":
              try require(form, 2, "quasiquote")
              control = .expression(
                try expandQuasiquote(form[1], depth: 1, environment),
                environment
              )
              continue
            case "unquote", "unquote-splicing":
              throw SchemeError.syntax("\(keyword) outside quasiquote")
            case "delay":
              try require(form, 2, "delay")
              control = .values([.promise(Promise(form[1], environment))])
              continue
            default: break
            }
          }
          continuation = .operatorFrame(Array(form.dropFirst()), environment, continuation)
          control = .expression(form[0], environment)
        default:
          let literal = expression
          var seen = Set<ObjectIdentifier>()
          markLiteral(literal, &seen)
          control = .values([literal])
        }

      case .values(let values):
        switch continuation {
        case .halt: return values
        case .ifFrame(let consequent, let alternate, let environment, let next):
          let test = try one(values, "if")
          continuation = .expressionContext(next)
          control = .expression(isFalse(test) ? alternate : consequent, environment)
        case .expressionContext(let next):
          continuation = next
          control = .values(values)
        case .beginFrame(let rest, let environment, let allowed, let next):
          if rest.isEmpty {
            continuation = next
            control = .values(values)
          } else {
            _ = try one(values, "sequence")
            continuation = .beginFrame(Array(rest.dropFirst()), environment, allowed, next)
            control = .expression(rest[0], environment)
          }
        case .discardFrame(let next):
          continuation = next
          control = .values([.unspecified])
        case .setFrame(let name, let environment, let next):
          let value = try one(values, "set!")
          try environment.set(name, value)
          continuation = next
          control = .values([.unspecified])
        case .defineFrame(let name, let environment, let next):
          let value = try one(values, "define")
          if !environment.fillPlaceholder(name, value) { environment.define(name, value) }
          continuation = next
          control = .values([.unspecified])
        case .operatorFrame(let operands, let environment, let next):
          let procedure = try one(values, "operator")
          if operands.isEmpty {
            continuation = next
            control = .apply(procedure, [])
          } else {
            continuation = .operandFrame(
              procedure,
              [],
              Array(operands.dropFirst()),
              environment,
              next
            )
            control = .expression(operands[0], environment)
          }
        case .operandFrame(let procedure, let done, let rest, let environment, let next):
          let argument = try one(values, "argument")
          let accumulated = done + [argument]
          if rest.isEmpty {
            continuation = next
            control = .apply(procedure, accumulated)
          } else {
            continuation = .operandFrame(
              procedure,
              accumulated,
              Array(rest.dropFirst()),
              environment,
              next
            )
            control = .expression(rest[0], environment)
          }
        case .letrecFrame(
          let entries, let index, let environment, let body, let bodyEnvironment, let next
        ):
          try environment.set(entries[index].0, try one(values, "letrec initializer"))
          let following = index + 1
          if following < entries.count {
            continuation = .letrecFrame(
              entries, following, environment, body, bodyEnvironment, next
            )
            control = .expression(entries[following].1, environment)
          } else {
            continuation = .beginFrame(Array(body.dropFirst()), bodyEnvironment, true, next)
            control = .expression(body[0], bodyEnvironment)
          }
        case .callValuesFrame(let consumer, let next):
          continuation = next
          control = .apply(consumer, values)
        case .promiseFrame(let promise, let next):
          continuation = next
          if case .done(let saved) = promise.state {
            control = .values(saved)
          } else {
            promise.state = .done(values)
            control = .values(values)
          }
        case .windBeforeFrame(let thunk, let after, let wind, let next):
          _ = try one(values, "dynamic-wind before thunk")
          winds.append(wind)
          continuation = .windBodyFrame(wind, after, next)
          control = .apply(thunk, [])
        case .windBodyFrame(let wind, let after, let next):
          let delivered = values
          if winds.last === wind { winds.removeLast() }
          continuation = .windAfterFrame(delivered, next)
          control = .apply(after, [])
        case .windAfterFrame(let delivered, let next):
          _ = try one(values, "dynamic-wind after thunk")
          continuation = next
          control = .values(delivered)
        case .transitionFrame(let actions, let target, let delivered):
          _ = try one(values, "dynamic-wind thunk")
          let scheduled = scheduleTransition(actions, target, delivered)!
          control = scheduled.0
          continuation = scheduled.1
        case .enteredFrame(let wind, let actions, let target, let delivered):
          _ = try one(values, "dynamic-wind before thunk")
          winds.append(wind)
          let scheduled = scheduleTransition(actions, target, delivered)!
          control = scheduled.0
          continuation = scheduled.1
        case .mapFrame(let procedure, let lists, let index, let results, let each, let next):
          let value = try one(values, each ? "for-each procedure" : "map procedure")
          let accumulated = each ? results : results + [value]
          let following = index + 1
          if following == lists[0].count {
            continuation = next
            control = .values([each ? .unspecified : makeList(accumulated)])
          } else {
            continuation = .mapFrame(procedure, lists, following, accumulated, each, next)
            control = .apply(procedure, lists.map { $0[following] })
          }
        case .closePortFrame(let port, let next):
          if !port.closed {
            port.closed = true
            do { try port.handle?.close() } catch {
              throw SchemeError.io(error.localizedDescription)
            }
          }
          continuation = next
          control = .values(values)
        case .restoreInputFrame(let previous, let opened, let next):
          currentInput = previous
          if !opened.closed {
            opened.closed = true
            do { try opened.handle?.close() } catch {
              throw SchemeError.io(error.localizedDescription)
            }
          }
          continuation = next
          control = .values(values)
        case .restoreOutputFrame(let previous, let opened, let next):
          currentOutput = previous
          if !opened.closed {
            opened.closed = true
            do { try opened.handle?.close() } catch {
              throw SchemeError.io(error.localizedDescription)
            }
          }
          continuation = next
          control = .values(values)
        case .outputStringFrame(let port, let next):
          _ = try one(values, "call-with-output-string procedure")
          continuation = next
          control = .values([.string(SchemeString(port.output))])
        }

      case .apply(let value, let arguments):
        guard case .procedure(let procedure) = value else {
          throw SchemeError.type("attempt to call non-procedure \(value.written)")
        }
        guard let implementation = procedure.implementation else {
          throw SchemeError.io("procedure was reclaimed")
        }
        switch implementation {
        case .primitive(_, let function): control = .values(try function(arguments))
        case .closure(let formals, let body, let captured):
          try checkArity(arguments, formals)
          let local = SchemeEnvironment(parent: captured)
          for (name, value) in zip(formals.fixed, arguments) { local.define(name, value) }
          if let rest = formals.rest {
            local.define(rest, makeList(arguments.dropFirst(formals.fixed.count)))
          }
          try prepareInternalDefinitions(body, in: local)
          try validateBody(body, context: "procedure body", in: local)
          guard let first = body.first else { throw SchemeError.syntax("empty procedure body") }
          continuation = .beginFrame(Array(body.dropFirst()), local, true, continuation)
          control = .expression(first, local)
        case .continuation(let target):
          let common = zip(winds, target.winds).prefix { $0 === $1 }.count
          let exits = winds.dropFirst(common).reversed().map(WindAction.exit)
          let enters = target.winds.dropFirst(common).map(WindAction.enter)
          let scheduled = scheduleTransition(exits + enters, target, arguments)!
          control = scheduled.0
          continuation = scheduled.1
        case .special(let special):
          switch special {
          case .apply:
            guard arguments.count >= 2 else {
              throw SchemeError.arity("apply expects at least 2 arguments")
            }
            control = .apply(
              arguments[0],
              Array(arguments.dropFirst().dropLast())
                + (try array(from: arguments.last!, context: "apply final argument"))
            )
          case .callCC:
            try require(arguments, 1, "call-with-current-continuation")
            let captured = Captured(continuation: continuation, winds: winds)
            control = .apply(arguments[0], [.procedure(Procedure(.continuation(captured)))])
          case .values: control = .values(arguments)
          case .callWithValues:
            try require(arguments, 2, "call-with-values")
            continuation = .callValuesFrame(arguments[1], continuation)
            control = .apply(arguments[0], [])
          case .dynamicWind:
            try require(arguments, 3, "dynamic-wind")
            windSerial += 1
            let wind = Wind(windSerial, arguments[0], arguments[2])
            continuation = .windBeforeFrame(arguments[1], arguments[2], wind, continuation)
            control = .apply(arguments[0], [])
          case .force:
            try require(arguments, 1, "force")
            guard case .promise(let promise) = arguments[0] else {
              throw SchemeError.type("force expects a promise")
            }
            switch promise.state {
            case .done(let values): control = .values(values)
            case .pending(let expression, let environment):
              promise.state = .forcing(expression, environment)
              continuation = .promiseFrame(promise, continuation)
              control = .expression(expression, environment)
            case .forcing(let expression, let environment):
              continuation = .promiseFrame(promise, continuation)
              control = .expression(expression, environment)
            }
          case .eval:
            try require(arguments, 2, "eval")
            guard case .environment(let environment) = arguments[1] else {
              throw SchemeError.type("eval expects an environment")
            }
            control = .expression(arguments[0], environment)
          case .map, .forEach:
            guard arguments.count >= 2 else {
              throw SchemeError.arity("map/for-each expects procedure and lists")
            }
            guard case .procedure = arguments[0] else {
              throw SchemeError.type("map/for-each expects a procedure")
            }
            let lists = try arguments.dropFirst().map {
              try array(from: $0, context: "map/for-each argument")
            }
            guard let count = lists.first?.count, lists.allSatisfy({ $0.count == count }) else {
              throw SchemeError.arity("map/for-each lists must have equal length")
            }
            let each = special == .forEach
            if count == 0 {
              control = .values([each ? .unspecified : .empty])
            } else {
              continuation = .mapFrame(arguments[0], lists, 0, [], each, continuation)
              control = .apply(arguments[0], lists.map { $0[0] })
            }
          case .load:
            try require(arguments, 1, "load")
            let path = try schemeString(arguments[0], "load").string
            let source: String
            do { source = try String(contentsOfFile: path, encoding: .utf8) } catch {
              throw SchemeError.io("cannot load \(path): \(error.localizedDescription)")
            }
            var reader = Reader(source)
            let forms = try reader.readAll()
            if forms.isEmpty {
              control = .values([.unspecified])
            } else {
              continuation = .discardFrame(continuation)
              continuation = .beginFrame(Array(forms.dropFirst()), global, true, continuation)
              control = .expression(forms[0], global)
            }
          case .callWithInputFile, .withInputFromFile:
            try require(
              arguments,
              2,
              special == .callWithInputFile ? "call-with-input-file" : "with-input-from-file"
            )
            let path = try schemeString(arguments[0], "input file").string
            if special == .callWithInputFile {
              let opened: SchemePort
              do {
                opened = SchemePort(
                  handle: try FileHandle(forReadingFrom: URL(fileURLWithPath: path)),
                  mode: .input
                )
              } catch { throw SchemeError.io(error.localizedDescription) }
              continuation = .closePortFrame(opened, continuation)
              control = .apply(arguments[1], [.port(opened)])
            } else {
              let state = DynamicFilePort(path, .input)
              let before = Value.procedure(
                Procedure(
                  .primitive("with-input-from-file before") { [unowned self] args in
                    try require(args, 0, "with-input-from-file before")
                    let opened: SchemePort
                    do {
                      opened = SchemePort(
                        handle: try FileHandle(forReadingFrom: URL(fileURLWithPath: state.path)),
                        mode: .input
                      )
                    } catch { throw SchemeError.io(error.localizedDescription) }
                    opened.position = state.position
                    state.previous = currentInput
                    state.opened = opened
                    currentInput = opened
                    return [.unspecified]
                  }
                )
              )
              let after = Value.procedure(
                Procedure(
                  .primitive("with-input-from-file after") { [unowned self] args in
                    try require(args, 0, "with-input-from-file after")
                    if let opened = state.opened {
                      state.position = opened.position
                      opened.closed = true
                      do { try opened.handle?.close() } catch {
                        throw SchemeError.io(error.localizedDescription)
                      }
                    }
                    if let previous = state.previous { currentInput = previous }
                    state.opened = nil
                    state.previous = nil
                    return [.unspecified]
                  }
                )
              )
              windSerial += 1
              let wind = Wind(windSerial, before, after)
              continuation = .windBeforeFrame(arguments[1], after, wind, continuation)
              control = .apply(before, [])
            }
          case .callWithInputString:
            try require(arguments, 2, "call-with-input-string")
            let port = SchemePort(
              input: try schemeString(arguments[0], "call-with-input-string").string
            )
            control = .apply(arguments[1], [.port(port)])
          case .callWithOutputString:
            try require(arguments, 1, "call-with-output-string")
            let port = SchemePort(output: true)
            continuation = .outputStringFrame(port, continuation)
            control = .apply(arguments[0], [.port(port)])
          case .callWithOutputFile, .withOutputToFile:
            try require(
              arguments,
              2,
              special == .callWithOutputFile ? "call-with-output-file" : "with-output-to-file"
            )
            let path = try schemeString(arguments[0], "output file").string
            guard FileManager.default.createFile(atPath: path, contents: nil) else {
              throw SchemeError.io("cannot create \(path)")
            }
            if special == .callWithOutputFile {
              let opened: SchemePort
              do {
                opened = SchemePort(
                  handle: try FileHandle(forWritingTo: URL(fileURLWithPath: path)),
                  mode: .output
                )
              } catch { throw SchemeError.io(error.localizedDescription) }
              continuation = .closePortFrame(opened, continuation)
              control = .apply(arguments[1], [.port(opened)])
            } else {
              let state = DynamicFilePort(path, .output)
              let before = Value.procedure(
                Procedure(
                  .primitive("with-output-to-file before") { [unowned self] args in
                    try require(args, 0, "with-output-to-file before")
                    let opened: SchemePort
                    do {
                      let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: state.path))
                      try handle.seek(toOffset: state.offset)
                      opened = SchemePort(handle: handle, mode: .output)
                    } catch { throw SchemeError.io(error.localizedDescription) }
                    state.previous = currentOutput
                    state.opened = opened
                    currentOutput = opened
                    return [.unspecified]
                  }
                )
              )
              let after = Value.procedure(
                Procedure(
                  .primitive("with-output-to-file after") { [unowned self] args in
                    try require(args, 0, "with-output-to-file after")
                    if let opened = state.opened {
                      state.offset = opened.handle?.offsetInFile ?? state.offset
                      opened.closed = true
                      do { try opened.handle?.close() } catch {
                        throw SchemeError.io(error.localizedDescription)
                      }
                    }
                    if let previous = state.previous { currentOutput = previous }
                    state.opened = nil
                    state.previous = nil
                    return [.unspecified]
                  }
                )
              )
              windSerial += 1
              let wind = Wind(windSerial, before, after)
              continuation = .windBeforeFrame(arguments[1], after, wind, continuation)
              control = .apply(before, [])
            }
          }
        }
      }
    }
  }

  private func parseFormals(_ value: Value) throws -> Formals {
    var fixed: [String] = []
    var rest: String?
    var cursor = value
    if case .symbol(let name) = cursor {
      rest = name
      cursor = .empty
    }
    var seen = Set<ObjectIdentifier>()
    while case .pair(let pair) = cursor {
      guard seen.insert(ObjectIdentifier(pair)).inserted else {
        throw SchemeError.syntax("cyclic formal list")
      }
      fixed.append(try identifier(pair.car, "lambda"))
      cursor = pair.cdr
    }
    if case .symbol(let name) = cursor {
      rest = name
    } else if case .empty = cursor {
    } else {
      throw SchemeError.syntax("invalid lambda formals")
    }
    let names = fixed + (rest.map { [$0] } ?? [])
    guard Set(names).count == names.count else {
      throw SchemeError.syntax("duplicate lambda parameter")
    }
    return Formals(fixed: fixed, rest: rest)
  }

  private func checkArity(_ arguments: [Value], _ formals: Formals) throws {
    if formals.rest == nil {
      guard arguments.count == formals.fixed.count else {
        throw SchemeError.arity("expected \(formals.fixed.count), got \(arguments.count)")
      }
    } else if arguments.count < formals.fixed.count {
      throw SchemeError.arity("expected at least \(formals.fixed.count), got \(arguments.count)")
    }
  }

  private func bindings(_ value: Value, _ context: String) throws -> [(String, Value)] {
    try array(from: value, context: "\(context) bindings").map {
      let item = try array(from: $0, context: "\(context) binding")
      guard item.count == 2 else {
        throw SchemeError.syntax("\(context) binding requires name and initializer")
      }
      return (try identifier(item[0], context), item[1])
    }
  }

  private func ensureDistinct(_ entries: [(String, Value)], _ context: String) throws {
    guard Set(entries.map(\.0)).count == entries.count else {
      throw SchemeError.syntax("duplicate \(context) binding")
    }
  }

  private func syntaxBindings(_ value: Value, _ context: String) throws -> [(String, Value)] {
    try array(from: value, context: "\(context) bindings").map {
      let item = try array(from: $0, context: "\(context) binding")
      guard item.count == 2 else { throw SchemeError.syntax("invalid \(context) binding") }
      return (try identifier(item[0], context), item[1])
    }
  }

  private func expandLet(_ form: [Value]) throws -> Value {
    guard form.count >= 3 else { throw SchemeError.syntax("let requires bindings and body") }
    if case .symbol(let rawName) = form[1] {
      guard form.count >= 4 else { throw SchemeError.syntax("named let requires body") }
      let name = rawName
      let entries = try bindings(form[2], "named let")
      try ensureDistinct(entries, "named let")
      let lambda = makeList(
        [internalSyntax("lambda"), makeList(entries.map { .symbol($0.0) })]
          + Array(form.dropFirst(3))
      )
      let binding = makeList([.symbol(name), lambda])
      return makeList([
        internalSyntax("letrec"), makeList([binding]), makeList([.symbol(name)] + entries.map(\.1))
      ])
    }
    let entries = try bindings(form[1], "let")
    try ensureDistinct(entries, "let")
    return makeList(
      [
        makeList(
          [internalSyntax("lambda"), makeList(entries.map { .symbol($0.0) })]
            + Array(form.dropFirst(2))
        )
      ] + entries.map(\.1)
    )
  }

  private func expandLetStar(_ form: [Value]) throws -> Value {
    guard form.count >= 3 else { throw SchemeError.syntax("let* requires bindings and body") }
    let entries = try bindings(form[1], "let*")
    if entries.isEmpty { return makeList([internalSyntax("let"), .empty] + Array(form.dropFirst(2))) }
    var result = makeList([internalSyntax("begin")] + Array(form.dropFirst(2)))
    for entry in entries.reversed() {
      result = makeList([
        internalSyntax("let"), makeList([makeList([.symbol(entry.0), entry.1])]), result
      ])
    }
    return result
  }

  private func expandAnd(_ expressions: [Value]) -> Value {
    guard let first = expressions.first else { return .boolean(true) }
    if expressions.count == 1 { return first }
    return makeList([
      internalSyntax("if"), first, expandAnd(Array(expressions.dropFirst())), .boolean(false)
    ])
  }

  private func expandOr(_ expressions: [Value]) -> Value {
    guard let first = expressions.first else { return .boolean(false) }
    if expressions.count == 1 { return first }
    macroSerial += 1
    let temp = internalTemporary("or#\(macroSerial)")
    return makeList([
      internalSyntax("let"), makeList([makeList([temp, first])]),
      makeList([
        internalSyntax("if"), temp, temp, expandOr(Array(expressions.dropFirst()))
      ])
    ])
  }

  private func expandCond(_ clauses: [Value], _ environment: SchemeEnvironment) throws -> Value {
    guard let first = clauses.first else { return .unspecified }
    let clause = try array(from: first, context: "cond clause")
    guard !clause.isEmpty else { throw SchemeError.syntax("empty cond clause") }
    let elseKeyword =
      environment.cell("else") == nil && environment.macro("else") == nil
      && isSymbol(clause[0], "else")
    if elseKeyword {
      guard clauses.count == 1 else { throw SchemeError.syntax("cond else must be last") }
      guard clause.count >= 2 else { throw SchemeError.syntax("cond else requires a body") }
      return makeList([internalSyntax("begin")] + Array(clause.dropFirst()))
    }
    let rest = try expandCond(Array(clauses.dropFirst()), environment)
    if clause.count == 1 {
      macroSerial += 1
      let temp = internalTemporary("cond#\(macroSerial)")
      return makeList([
        internalSyntax("let"), makeList([makeList([temp, clause[0]])]),
        makeList([internalSyntax("if"), temp, temp, rest])
      ])
    }
    let arrowKeyword =
      environment.cell("=>") == nil && environment.macro("=>") == nil && clause.count == 3
      && isSymbol(clause[1], "=>")
    if arrowKeyword {
      macroSerial += 1
      let temp = internalTemporary("cond#\(macroSerial)")
      return makeList([
        internalSyntax("let"), makeList([makeList([temp, clause[0]])]),
        makeList([internalSyntax("if"), temp, makeList([clause[2], temp]), rest])
      ])
    }
    return makeList([
      internalSyntax("if"), clause[0],
      makeList([internalSyntax("begin")] + Array(clause.dropFirst())), rest
    ])
  }

  private func expandCase(_ form: [Value], _ environment: SchemeEnvironment) throws -> Value {
    guard form.count >= 3 else { throw SchemeError.syntax("case requires key and clauses") }
    macroSerial += 1
    let key = internalTemporary("case#\(macroSerial)")
    var seenDatums: [Value] = []
    func clauses(_ remaining: ArraySlice<Value>) throws -> Value {
      guard let first = remaining.first else { return .unspecified }
      let clause = try array(from: first, context: "case clause")
      guard clause.count >= 2 else { throw SchemeError.syntax("invalid case clause") }
      if isSymbol(clause[0], "else") && environment.cell("else") == nil
        && environment.macro("else") == nil
      {
        guard remaining.count == 1 else { throw SchemeError.syntax("case else must be last") }
        guard clause.count >= 2 else { throw SchemeError.syntax("case else requires a body") }
        return makeList([internalSyntax("begin")] + Array(clause.dropFirst()))
      }
      let datums = try array(from: clause[0], context: "case datums")
      for datum in datums {
        guard !seenDatums.contains(where: { eqv($0, datum) }) else {
          throw SchemeError.syntax("duplicate case datum")
        }
        seenDatums.append(datum)
      }
      let tests = datums.map {
        coreCall("eqv?", [key, quoted($0)])
      }
      return makeList([
        internalSyntax("if"), expandOr(tests),
        makeList([internalSyntax("begin")] + Array(clause.dropFirst())),
        try clauses(remaining.dropFirst())
      ])
    }
    return makeList([
      internalSyntax("let"), makeList([makeList([key, form[1]])]),
      try clauses(form.dropFirst(2))
    ])
  }

  private func expandDo(_ form: [Value]) throws -> Value {
    guard form.count >= 3 else { throw SchemeError.syntax("do requires bindings and test") }
    let specs = try array(from: form[1], context: "do bindings").map {
      try array(from: $0, context: "do binding")
    }
    guard specs.allSatisfy({ $0.count == 2 || $0.count == 3 }) else {
      throw SchemeError.syntax("invalid do binding")
    }
    let test = try array(from: form[2], context: "do test")
    guard !test.isEmpty else { throw SchemeError.syntax("empty do test") }
    macroSerial += 1
    let loop = internalTemporary("do#\(macroSerial)")
    let names = try specs.map { try identifier($0[0], "do") }
    guard Set(names).count == names.count else { throw SchemeError.syntax("duplicate do variable") }
    let steps = zip(specs, names).map { $0.0.count == 3 ? $0.0[2] : .symbol($0.1) }
    let done =
      test.count == 1 ? .unspecified : makeList([internalSyntax("begin")] + Array(test.dropFirst()))
    let recur = makeList([loop] + steps)
    let body = makeList([
      internalSyntax("if"), test[0], done,
      makeList([internalSyntax("begin")] + Array(form.dropFirst(3)) + [recur])
    ])
    return makeList([
      internalSyntax("let"), loop,
      makeList(zip(names, specs).map { makeList([.symbol($0.0), $0.1[1]]) }), body
    ])
  }

  private func quoted(_ value: Value) -> Value { makeList([internalSyntax("quote"), value]) }

  private func expandQuasiquote(_ value: Value, depth: Int, _ environment: SchemeEnvironment) throws
    -> Value
  {
    if let form = try? array(from: value), form.count == 2, case .symbol(let name) = form[0] {
      let active = environment.cell(name) == nil && environment.macro(name) == nil
      if name == "unquote" && active {
        return depth == 1
          ? form[1]
          : coreCall("list", [
            quoted(.symbol(name)),
            try expandQuasiquote(form[1], depth: depth - 1, environment)
          ])
      }
      if name == "unquote-splicing" && active {
        guard depth > 1 else { throw SchemeError.syntax("unquote-splicing outside list context") }
        return coreCall("list", [quoted(.symbol(name)),
          try expandQuasiquote(form[1], depth: depth - 1, environment)])
      }
      if name == "quasiquote" && active {
        return coreCall("list", [quoted(.symbol(name)),
          try expandQuasiquote(form[1], depth: depth + 1, environment)])
      }
    }
    if case .vector(let vector) = value {
      return coreCall("list->vector", [
        try expandQuasiquote(makeList(vector.elements), depth: depth, environment)
      ])
    }
    guard case .pair(let pair) = value else { return quoted(value) }
    let head = pair.car
    if let form = try? array(from: head), form.count == 2,
      case .symbol("unquote-splicing") = form[0], depth == 1,
      environment.cell("unquote-splicing") == nil && environment.macro("unquote-splicing") == nil
    {
      return coreCall("append", [
        form[1], try expandQuasiquote(pair.cdr, depth: depth, environment)
      ])
    }
    return coreCall("cons", [
      try expandQuasiquote(head, depth: depth, environment),
      try expandQuasiquote(pair.cdr, depth: depth, environment)
    ])
  }

  private func primitive(
    _ name: String,
    in environment: SchemeEnvironment,
    _ body: @escaping ([Value]) throws -> Value
  ) { environment.define(name, .procedure(Procedure(.primitive(name) { [try body($0)] }))) }

  private func multiPrimitive(
    _ name: String,
    in environment: SchemeEnvironment,
    _ body: @escaping ([Value]) throws -> [Value]
  ) { environment.define(name, .procedure(Procedure(.primitive(name, body)))) }

  private func special(_ name: String, _ special: Special, in environment: SchemeEnvironment) {
    environment.define(name, .procedure(Procedure(.special(special))))
  }

  private func installPrimitives(in env: SchemeEnvironment) {
    primitive("+", in: env) { args in
      var result = SchemeNumber.zero
      for value in args { result = result + (try schemeNumber(value)) }
      return numberValue(result)
    }
    primitive("*", in: env) { args in
      var result = SchemeNumber.one
      for value in args { result = result * (try schemeNumber(value)) }
      return numberValue(result)
    }
    primitive("-", in: env) { args in
      guard let first = args.first else { throw SchemeError.arity("- expects at least 1 argument") }
      var result = try schemeNumber(first)
      if args.count == 1 { return numberValue(-result) }
      for value in args.dropFirst() { result = result - (try schemeNumber(value)) }
      return numberValue(result)
    }
    primitive("/", in: env) { args in
      guard let first = args.first else { throw SchemeError.arity("/ expects at least 1 argument") }
      var result = args.count == 1 ? SchemeNumber.one : try schemeNumber(first)
      for value in args.count == 1 ? args[...] : args.dropFirst() {
        do { result = try result / schemeNumber(value) } catch {
          throw SchemeError.numeric("division by zero")
        }
      }
      return numberValue(result)
    }
    for name in ["=", "<", ">", "<=", ">="] {
      primitive(name, in: env) { args in
        guard args.count >= 2 else {
          throw SchemeError.arity("\(name) expects at least 2 arguments")
        }
        let values = try args.map(schemeNumber)
        if name == "=" {
          return .boolean(zip(values, values.dropFirst()).allSatisfy(SchemeNumber.numericallyEqual))
        }
        let reals = try values.map { value -> RealComponent in
          guard value.isReal else { throw SchemeError.type("\(name) expects real numbers") }
          return value.parts.real
        }
        return .boolean(
          zip(reals, reals.dropFirst()).allSatisfy { a, b in
            guard let comparison = compareReal(a, b) else { return false }
            switch name {
            case "<": return comparison < 0
            case ">": return comparison > 0
            case "<=": return comparison <= 0
            default: return comparison >= 0
            }
          }
        )
      }
    }
    primitive("zero?", in: env) {
      try require($0, 1, "zero?")
      return .boolean(try schemeNumber($0[0]).isZero)
    }
    primitive("positive?", in: env) {
      try require($0, 1, "positive?")
      return .boolean(try realComponent($0[0], "positive?").signum > 0)
    }
    primitive("negative?", in: env) {
      try require($0, 1, "negative?")
      return .boolean(try realComponent($0[0], "negative?").signum < 0)
    }
    primitive("odd?", in: env) {
      try require($0, 1, "odd?")
      return .boolean(try integerComponent($0[0], "odd?").value.magnitudeModulo(2) == 1)
    }
    primitive("even?", in: env) {
      try require($0, 1, "even?")
      return .boolean(try integerComponent($0[0], "even?").value.magnitudeModulo(2) == 0)
    }
    primitive("abs", in: env) { args in
      try require(args, 1, "abs")
      let n = try schemeNumber(args[0])
      if n.isReal {
        let r = n.parts.real
        return numberValue(.real(r.signum < 0 ? -r : r))
      }
      return .real(n.magnitude)
    }
    for name in ["max", "min"] {
      primitive(name, in: env) { args in
        guard !args.isEmpty else { throw SchemeError.arity("\(name) expects arguments") }
        let values = try args.map { (try schemeNumber($0), try realComponent($0, name)) }
        var selected = values[0]
        for candidate in values.dropFirst() {
          guard let comparison = compareReal(selected.1, candidate.1) else {
            selected = candidate
            continue
          }
          if name == "max" ? comparison < 0 : comparison > 0 { selected = candidate }
        }
        let anyInexact = values.contains { !$0.1.isExact }
        return numberValue(anyInexact ? selected.0.inexact() : selected.0)
      }
    }
    for (name, operation) in [
      ("quotient", { try $0.quotient(dividingBy: $1) }),
      ("remainder", { try $0.remainder(dividingBy: $1) }), ("modulo", { try $0.modulo($1) })
    ] as [(String, (BigInt, BigInt) throws -> BigInt)] {
      primitive(name, in: env) { args in
        try require(args, 2, name)
        let a = try integerComponent(args[0], name)
        let b = try integerComponent(args[1], name)
        do {
          let result = try operation(a.value, b.value)
          return a.inexact || b.inexact ? .real(result.doubleValue) : .integer(result)
        } catch { throw SchemeError.numeric("division by zero") }
      }
    }
    primitive("gcd", in: env) { args in
      var result = BigInt.zero
      var inexact = false
      for value in args {
        let n = try integerComponent(value, "gcd")
        result = BigInt.gcd(result, n.value)
        inexact = inexact || n.inexact
      }
      return inexact ? .real(result.doubleValue) : .integer(result)
    }
    primitive("lcm", in: env) { args in
      var result = BigInt.one
      var inexact = false
      for value in args {
        let component = try integerComponent(value, "lcm")
        let n = component.value.absoluteValue
        inexact = inexact || component.inexact
        if result.isZero || n.isZero {
          result = .zero
        } else {
          result = try result.quotient(dividingBy: BigInt.gcd(result, n)) * n
        }
      }
      return inexact ? .real(result.doubleValue) : .integer(result)
    }
    for (name, rule) in [
      ("floor", Rational.Rounding.floor), ("ceiling", .ceiling), ("truncate", .truncate),
      ("round", .nearestEven)
    ] {
      primitive(name, in: env) { args in
        try require(args, 1, name)
        let component = try realComponent(args[0], name)
        switch component {
        case .exact(let r): return .integer(r.rounded(rule))
        case .inexact(let x):
          let y: Double =
            rule == .floor
            ? Foundation.floor(x)
            : rule == .ceiling
              ? Foundation.ceil(x)
              : rule == .truncate ? Foundation.trunc(x) : x.rounded(.toNearestOrEven)
          return .real(y)
        }
      }
    }
    primitive("numerator", in: env) { args in
      try require(args, 1, "numerator")
      let r = try rationalComponent(args[0], "numerator")
      return r.1 ? .real(r.0.numerator.doubleValue) : .integer(r.0.numerator)
    }
    primitive("denominator", in: env) { args in
      try require(args, 1, "denominator")
      let r = try rationalComponent(args[0], "denominator")
      return r.1 ? .real(r.0.denominator.doubleValue) : .integer(r.0.denominator)
    }
    primitive("make-rectangular", in: env) { args in
      try require(args, 2, "make-rectangular")
      return numberValue(
        .rectangular(
          try realComponent(args[0], "make-rectangular"),
          try realComponent(args[1], "make-rectangular")
        )
      )
    }
    primitive("make-polar", in: env) { args in
      try require(args, 2, "make-polar")
      return numberValue(
        .polar(
          magnitude: try realComponent(args[0], "make-polar"),
          angle: try realComponent(args[1], "make-polar")
        )
      )
    }
    primitive("real-part", in: env) { args in
      try require(args, 1, "real-part")
      return numberValue(.real(try schemeNumber(args[0]).parts.real))
    }
    primitive("imag-part", in: env) { args in
      try require(args, 1, "imag-part")
      return numberValue(.real(try schemeNumber(args[0]).parts.imaginary))
    }
    primitive("magnitude", in: env) { args in
      try require(args, 1, "magnitude")
      let number = try schemeNumber(args[0])
      return number.exactMagnitude.map { numberValue(SchemeNumber($0)) } ?? .real(number.magnitude)
    }
    primitive("angle", in: env) { args in
      try require(args, 1, "angle")
      return .real(try schemeNumber(args[0]).angle)
    }
    primitive("expt", in: env) { args in
      try require(args, 2, "expt")
      let base = try schemeNumber(args[0])
      let exponent = try schemeNumber(args[1])
      if base.isZero {
        let result = exponent.isZero ? SchemeNumber.one : SchemeNumber.zero
        return numberValue(base.isExact && exponent.isExact ? result : result.inexact())
      }
      if let e = exactIntegerExponent(exponent) {
        do { return numberValue(try base.exactPower(e)) } catch {
          throw SchemeError.numeric("division by zero")
        }
      }
      return numberValue(complexPower(base, exponent))
    }
    primitive("sqrt", in: env) { args in
      try require(args, 1, "sqrt")
      return numberValue(complexSqrt(try schemeNumber(args[0])))
    }
    for name in ["exp", "log", "sin", "cos", "tan", "asin", "acos"] {
      primitive(name, in: env) { args in
        try require(args, 1, name)
        return numberValue(complexTranscendental(name, try schemeNumber(args[0])))
      }
    }
    primitive("atan", in: env) { args in
      guard args.count == 1 || args.count == 2 else {
        throw SchemeError.arity("atan expects 1 or 2 arguments")
      }
      if args.count == 2 {
        return .real(
          Foundation.atan2(
            try realComponent(args[0], "atan").doubleValue,
            try realComponent(args[1], "atan").doubleValue
          )
        )
      }
      return numberValue(complexTranscendental("atan", try schemeNumber(args[0])))
    }
    primitive("rationalize", in: env) { args in
      try require(args, 2, "rationalize")
      guard (try realComponent(args[1], "rationalize")).signum >= 0 else {
        throw SchemeError.numeric("rationalize tolerance must be nonnegative")
      }
      return numberValue(try rationalized(args[0], args[1]))
    }
    primitive("number?", in: env) { try predicate($0, "number?", isNumber) }
    primitive("complex?", in: env) { try predicate($0, "complex?", isNumber) }
    primitive("real?", in: env) {
      try predicate($0, "real?") { (try? schemeNumber($0).isReal) == true }
    }
    primitive("rational?", in: env) {
      try predicate($0, "rational?") { (try? schemeNumber($0).isRational) == true }
    }
    primitive("integer?", in: env) {
      try predicate($0, "integer?") { (try? schemeNumber($0).isInteger) == true }
    }
    primitive("exact?", in: env) {
      try predicate($0, "exact?") { (try? schemeNumber($0).isExact) == true }
    }
    primitive("inexact?", in: env) {
      try predicate($0, "inexact?") {
        guard let n = try? schemeNumber($0) else { return false }
        return !n.isExact
      }
    }
    primitive("exact->inexact", in: env) { args in
      try require(args, 1, "exact->inexact")
      return numberValue(try schemeNumber(args[0]).inexact())
    }
    primitive("inexact->exact", in: env) { args in
      try require(args, 1, "inexact->exact")
      return numberValue(try exactNumber(schemeNumber(args[0])))
    }
    primitive("number->string", in: env) { args in
      guard args.count == 1 || args.count == 2 else {
        throw SchemeError.arity("number->string expects 1 or 2 arguments")
      }
      let radix = args.count == 2 ? try indexRadix(args[1], "number->string") : 10
      guard let text = try schemeNumber(args[0]).string(radix: radix) else {
        throw SchemeError.numeric("number cannot be represented in radix \(radix)")
      }
      return .string(SchemeString(text))
    }
    primitive("string->number", in: env) { args in
      guard args.count == 1 || args.count == 2 else {
        throw SchemeError.arity("string->number expects 1 or 2 arguments")
      }
      let radix = args.count == 2 ? try indexRadix(args[1], "string->number") : 10
      let text = try schemeString(args[0], "string->number").string
      var reader = Reader(
        text.hasPrefix("#") || radix == 10
          ? text : "#\(radix == 2 ? "b" : radix == 8 ? "o" : "x")\(text)"
      )
      guard let values = try? reader.readAll(), values.count == 1, let value = values.first,
        isNumber(value)
      else { return .boolean(false) }
      return value
    }

    primitive("cons", in: env) {
      try require($0, 2, "cons")
      return .pair(Pair($0[0], $0[1]))
    }
    primitive("car", in: env) {
      try require($0, 1, "car")
      return try pair($0[0], "car").car
    }
    primitive("cdr", in: env) {
      try require($0, 1, "cdr")
      return try pair($0[0], "cdr").cdr
    }
    primitive("set-car!", in: env) {
      try require($0, 2, "set-car!")
      let target = try pair($0[0], "set-car!")
      guard !target.isLiteral else { throw SchemeError.type("cannot mutate a literal pair") }
      target.car = $0[1]
      return .unspecified
    }
    primitive("set-cdr!", in: env) {
      try require($0, 2, "set-cdr!")
      let target = try pair($0[0], "set-cdr!")
      guard !target.isLiteral else { throw SchemeError.type("cannot mutate a literal pair") }
      target.cdr = $0[1]
      return .unspecified
    }
    primitive("list", in: env) { makeList($0) }
    primitive("length", in: env) {
      try require($0, 1, "length")
      return .integer(BigInt(try array(from: $0[0]).count))
    }
    primitive("append", in: env) { args in
      var result = args.last ?? .empty
      for list in args.dropLast().reversed() {
        result = makeList(try array(from: list, context: "append"), tail: result)
      }
      return result
    }
    primitive("reverse", in: env) {
      try require($0, 1, "reverse")
      return makeList(try array(from: $0[0]).reversed())
    }
    primitive("list-tail", in: env) { args in
      try require(args, 2, "list-tail")
      var value = args[0]
      for _ in 0..<(try index(args[1], "list-tail")) { value = try pair(value, "list-tail").cdr }
      return value
    }
    primitive("list-ref", in: env) { args in
      try require(args, 2, "list-ref")
      let values = try array(from: args[0])
      let index = try index(args[1], "list-ref")
      guard index < values.count else { throw SchemeError.numeric("index out of range") }
      return values[index]
    }
    for name in ["pair?", "null?", "list?"] {
      primitive(name, in: env) { args in
        try require(args, 1, name)
        if name == "pair?" { if case .pair = args[0] { return .boolean(true) } }
        if name == "null?" { if case .empty = args[0] { return .boolean(true) } }
        if name == "list?" { return .boolean((try? array(from: args[0])) != nil) }
        return .boolean(false)
      }
    }
    for depth in 2...4 {
      let count = 1 << depth
      for bits in 0..<count {
        var name = "c"
        var operations: [Character] = []
        for shift in (0..<depth).reversed() {
          let c: Character = ((bits >> shift) & 1) == 0 ? "a" : "d"
          name.append(c)
          operations.append(c)
        }
        name += "r"
        primitive(name, in: env) { args in
          try require(args, 1, name)
          var value = args[0]
          for operation in operations.reversed() {
            let p = try pair(value, name)
            value = operation == "a" ? p.car : p.cdr
          }
          return value
        }
      }
    }
    for name in ["memq", "memv", "member"] {
      primitive(name, in: env) { args in
        try require(args, 2, name)
        var cursor = args[1]
        while case .pair(let p) = cursor {
          let found =
            name == "memq"
            ? eq(args[0], p.car) : name == "memv" ? eqv(args[0], p.car) : equal(args[0], p.car)
          if found { return cursor }
          cursor = p.cdr
        }
        return .boolean(false)
      }
    }
    for name in ["assq", "assv", "assoc"] {
      primitive(name, in: env) { args in
        try require(args, 2, name)
        for item in try array(from: args[1], context: name) {
          let p = try pair(item, name)
          let found =
            name == "assq"
            ? eq(args[0], p.car) : name == "assv" ? eqv(args[0], p.car) : equal(args[0], p.car)
          if found { return item }
        }
        return .boolean(false)
      }
    }

    primitive("not", in: env) {
      try require($0, 1, "not")
      return .boolean(isFalse($0[0]))
    }
    primitive("boolean?", in: env) {
      try predicate($0, "boolean?") { if case .boolean = $0 { true } else { false } }
    }
    primitive("symbol?", in: env) {
      try predicate($0, "symbol?") { if case .symbol = $0 { true } else { false } }
    }
    primitive("char?", in: env) {
      try predicate($0, "char?") { if case .character = $0 { true } else { false } }
    }
    primitive("string?", in: env) {
      try predicate($0, "string?") { if case .string = $0 { true } else { false } }
    }
    primitive("vector?", in: env) {
      try predicate($0, "vector?") { if case .vector = $0 { true } else { false } }
    }
    primitive("port?", in: env) {
      try predicate($0, "port?") { if case .port = $0 { true } else { false } }
    }
    primitive("input-port?", in: env) {
      try predicate($0, "input-port?") {
        if case .port(let p) = $0 { return p.mode == .input }
        return false
      }
    }
    primitive("output-port?", in: env) {
      try predicate($0, "output-port?") {
        if case .port(let p) = $0 { return p.mode == .output }
        return false
      }
    }
    primitive("procedure?", in: env) {
      try predicate($0, "procedure?") { if case .procedure = $0 { true } else { false } }
    }
    primitive("eq?", in: env) {
      try require($0, 2, "eq?")
      return .boolean(eq($0[0], $0[1]))
    }
    primitive("eqv?", in: env) {
      try require($0, 2, "eqv?")
      return .boolean(eqv($0[0], $0[1]))
    }
    primitive("equal?", in: env) {
      try require($0, 2, "equal?")
      return .boolean(equal($0[0], $0[1]))
    }

    primitive("symbol->string", in: env) { args in
      try require(args, 1, "symbol->string")
      guard case .symbol(let s) = args[0] else { throw SchemeError.type("expected symbol") }
      let string = SchemeString(symbolSpelling(s))
      string.isLiteral = true
      return .string(string)
    }
    primitive("string->symbol", in: env) { args in
      try require(args, 1, "string->symbol")
      let spelling = try schemeString(args[0], "string->symbol").string
      return .symbol(symbolToken(spelling))
    }
    primitive("char->integer", in: env) {
      try require($0, 1, "char->integer")
      return .integer(BigInt(Int64(try scalar(character($0[0], "char->integer")))))
    }
    primitive("integer->char", in: env) {
      try require($0, 1, "integer->char")
      guard let codepoint = try exactInteger($0[0], "integer->char").exactInt,
        let scalar = UnicodeScalar(codepoint)
      else { throw SchemeError.numeric("invalid character") }
      return .character(Character(String(scalar)))
    }
    for name in [
      "char=?", "char<?", "char>?", "char<=?", "char>=?", "char-ci=?", "char-ci<?", "char-ci>?",
      "char-ci<=?", "char-ci>=?"
    ] {
      primitive(name, in: env) { args in
        guard args.count >= 2 else {
          throw SchemeError.arity("\(name) expects at least 2 arguments")
        }
        let characters = try args.map { try character($0, name) }
        let chars: [String] = name.contains("-ci")
          ? characters.map(scalarCaseKey)
          : characters.map(String.init)
        return .boolean(zip(chars, chars.dropFirst()).allSatisfy { compare($0, $1, name) })
      }
    }
    primitive("char-alphabetic?", in: env) {
      try charPredicate($0, "char-alphabetic?", isScalarCaseCharacter)
    }
    primitive("char-numeric?", in: env) { try charPredicate($0, "char-numeric?", { $0.isNumber }) }
    primitive("char-whitespace?", in: env) {
      try charPredicate($0, "char-whitespace?", { $0.isWhitespace })
    }
    primitive("char-upper-case?", in: env) {
      try charPredicate($0, "char-upper-case?", { isScalarCaseCharacter($0) && $0.isUppercase })
    }
    primitive("char-lower-case?", in: env) {
      try charPredicate($0, "char-lower-case?", { isScalarCaseCharacter($0) && $0.isLowercase })
    }
    primitive("char-upcase", in: env) {
      try require($0, 1, "char-upcase")
      return .character(scalarCaseMap(try character($0[0], "char-upcase"), upper: true))
    }
    primitive("char-downcase", in: env) {
      try require($0, 1, "char-downcase")
      return .character(scalarCaseMap(try character($0[0], "char-downcase"), upper: false))
    }

    primitive("string", in: env) {
      .string(SchemeString(String(try $0.map { try character($0, "string") })))
    }
    primitive("make-string", in: env) { args in
      guard args.count == 1 || args.count == 2 else {
        throw SchemeError.arity("make-string expects 1 or 2 arguments")
      }
      let result = SchemeString("")
      result.characters = Array(
        repeating: args.count == 2 ? try character(args[1], "make-string") : " ",
        count: try index(args[0], "make-string")
      )
      return .string(result)
    }
    primitive("string-length", in: env) {
      try require($0, 1, "string-length")
      return .integer(BigInt(try schemeString($0[0], "string-length").characters.count))
    }
    primitive("string-ref", in: env) { args in
      try require(args, 2, "string-ref")
      let string = try schemeString(args[0], "string-ref")
      let i = try index(args[1], "string-ref")
      guard i < string.characters.count else { throw SchemeError.numeric("index out of range") }
      return .character(string.characters[i])
    }
    primitive("string-set!", in: env) { args in
      try require(args, 3, "string-set!")
      let string = try schemeString(args[0], "string-set!")
      guard !string.isLiteral else { throw SchemeError.type("cannot mutate a literal string") }
      let i = try index(args[1], "string-set!")
      guard i < string.characters.count else { throw SchemeError.numeric("index out of range") }
      string.characters[i] = try character(args[2], "string-set!")
      return .unspecified
    }
    primitive("substring", in: env) { args in
      try require(args, 3, "substring")
      let chars = try schemeString(args[0], "substring").characters
      let a = try index(args[1], "substring")
      let b = try index(args[2], "substring")
      guard a <= b && b <= chars.count else { throw SchemeError.numeric("invalid substring range") }
      return .string(SchemeString(String(chars[a..<b])))
    }
    primitive("string-append", in: env) {
      .string(SchemeString(try $0.map { try schemeString($0, "string-append").string }.joined()))
    }
    primitive("string->list", in: env) {
      try require($0, 1, "string->list")
      return makeList(try schemeString($0[0], "string->list").characters.map(Value.character))
    }
    primitive("list->string", in: env) {
      try require($0, 1, "list->string")
      return .string(
        SchemeString(String(try array(from: $0[0]).map { try character($0, "list->string") }))
      )
    }
    primitive("string-copy", in: env) {
      try require($0, 1, "string-copy")
      return .string(SchemeString(try schemeString($0[0], "string-copy").string))
    }
    primitive("string-fill!", in: env) { args in
      try require(args, 2, "string-fill!")
      let string = try schemeString(args[0], "string-fill!")
      guard !string.isLiteral else { throw SchemeError.type("cannot mutate a literal string") }
      string.characters = Array(
        repeating: try character(args[1], "string-fill!"),
        count: string.characters.count
      )
      return .unspecified
    }
    for name in [
      "string=?", "string<?", "string>?", "string<=?", "string>=?", "string-ci=?", "string-ci<?",
      "string-ci>?", "string-ci<=?", "string-ci>=?"
    ] {
      primitive(name, in: env) { args in
        guard args.count >= 2 else {
          throw SchemeError.arity("\(name) expects at least 2 arguments")
        }
        var strings = try args.map { try schemeString($0, name).string }
        if name.contains("-ci") { strings = strings.map { $0.lowercased() } }
        return .boolean(zip(strings, strings.dropFirst()).allSatisfy { compare($0, $1, name) })
      }
    }

    primitive("vector", in: env) { .vector(SchemeVector($0)) }
    primitive("make-vector", in: env) { args in
      guard args.count == 1 || args.count == 2 else {
        throw SchemeError.arity("make-vector expects 1 or 2 arguments")
      }
      return .vector(
        SchemeVector(
          Array(
            repeating: args.count == 2 ? args[1] : .unspecified,
            count: try index(args[0], "make-vector")
          )
        )
      )
    }
    primitive("vector-length", in: env) {
      try require($0, 1, "vector-length")
      return .integer(BigInt(try vector($0[0], "vector-length").elements.count))
    }
    primitive("vector-ref", in: env) { args in
      try require(args, 2, "vector-ref")
      let vector = try vector(args[0], "vector-ref")
      let i = try index(args[1], "vector-ref")
      guard i < vector.elements.count else { throw SchemeError.numeric("index out of range") }
      return vector.elements[i]
    }
    primitive("vector-set!", in: env) { args in
      try require(args, 3, "vector-set!")
      let vector = try vector(args[0], "vector-set!")
      guard !vector.isLiteral else { throw SchemeError.type("cannot mutate a literal vector") }
      let i = try index(args[1], "vector-set!")
      guard i < vector.elements.count else { throw SchemeError.numeric("index out of range") }
      vector.elements[i] = args[2]
      return .unspecified
    }
    primitive("vector->list", in: env) {
      try require($0, 1, "vector->list")
      return makeList(try vector($0[0], "vector->list").elements)
    }
    primitive("list->vector", in: env) {
      try require($0, 1, "list->vector")
      return .vector(SchemeVector(try array(from: $0[0])))
    }
    primitive("vector-fill!", in: env) { args in
      try require(args, 2, "vector-fill!")
      let vector = try vector(args[0], "vector-fill!")
      guard !vector.isLiteral else { throw SchemeError.type("cannot mutate a literal vector") }
      vector.elements = Array(repeating: args[1], count: vector.elements.count)
      return .unspecified
    }

    special("apply", .apply, in: env)
    special("call-with-current-continuation", .callCC, in: env)
    if let procedure = env.cell("call-with-current-continuation")?.value {
      env.define("call/cc", procedure)
    }
    special("values", .values, in: env)
    special("call-with-values", .callWithValues, in: env)
    special("dynamic-wind", .dynamicWind, in: env)
    special("force", .force, in: env)
    special("eval", .eval, in: env)
    special("map", .map, in: env)
    special("for-each", .forEach, in: env)
    special("load", .load, in: env)
    special("call-with-input-file", .callWithInputFile, in: env)
    special("call-with-output-file", .callWithOutputFile, in: env)
    special("with-input-from-file", .withInputFromFile, in: env)
    special("with-output-to-file", .withOutputToFile, in: env)
    special("call-with-input-string", .callWithInputString, in: env)
    special("call-with-output-string", .callWithOutputString, in: env)

    primitive("scheme-report-environment", in: env) { args in
      try require(args, 1, "scheme-report-environment")
      guard try exactInteger(args[0], "scheme-report-environment") == 5 else {
        throw SchemeError.numeric("only report version 5 is supported")
      }
      let copy = SchemeEnvironment(definitionPolicy: .fixed)
      for name in r5rsReportProcedureNames {
        if let cell = env.values[name] { copy.define(name, cell.value) }
      }
      return .environment(copy)
    }
    primitive("null-environment", in: env) { args in
      try require(args, 1, "null-environment")
      guard try exactInteger(args[0], "null-environment") == 5 else {
        throw SchemeError.numeric("only report version 5 is supported")
      }
      return .environment(SchemeEnvironment(definitionPolicy: .fixed))
    }
    primitive("interaction-environment", in: env) { [unowned self] in
      try require($0, 0, "interaction-environment")
      return .environment(global)
    }

    primitive("current-input-port", in: env) { [unowned self] in
      try require($0, 0, "current-input-port")
      return .port(currentInput)
    }
    primitive("current-output-port", in: env) { [unowned self] in
      try require($0, 0, "current-output-port")
      return .port(currentOutput)
    }
    primitive("open-input-file", in: env) { args in
      try require(args, 1, "open-input-file")
      do {
        return .port(
          SchemePort(
            handle: try FileHandle(
              forReadingFrom: URL(
                fileURLWithPath: try schemeString(args[0], "open-input-file").string
              )
            ),
            mode: .input
          )
        )
      } catch { throw SchemeError.io(error.localizedDescription) }
    }
    primitive("open-output-file", in: env) { args in
      try require(args, 1, "open-output-file")
      let path = try schemeString(args[0], "open-output-file").string
      guard FileManager.default.createFile(atPath: path, contents: nil) else {
        throw SchemeError.io("cannot create \(path)")
      }
      do {
        return .port(
          SchemePort(
            handle: try FileHandle(forWritingTo: URL(fileURLWithPath: path)),
            mode: .output
          )
        )
      } catch { throw SchemeError.io(error.localizedDescription) }
    }
    primitive("close-input-port", in: env) { try closePort($0, .input, "close-input-port") }
    primitive("close-output-port", in: env) { try closePort($0, .output, "close-output-port") }
    primitive("read", in: env) { [unowned self] args in
      let port = try inputPort(args, currentInput, "read")
      var reader = Reader(port.input, start: port.position)
      let value = try reader.readOne()
      port.position = reader.index
      return value ?? .eof
    }
    primitive("read-char", in: env) { [unowned self] args in
      let port = try inputPort(args, currentInput, "read-char")
      guard port.position < port.input.count else { return .eof }
      defer { port.position += 1 }
      return .character(port.input[port.position])
    }
    primitive("peek-char", in: env) { [unowned self] args in
      let port = try inputPort(args, currentInput, "peek-char")
      return port.position < port.input.count ? .character(port.input[port.position]) : .eof
    }
    primitive("eof-object?", in: env) {
      try predicate($0, "eof-object?") { if case .eof = $0 { true } else { false } }
    }
    primitive("char-ready?", in: env) { [unowned self] args in
      _ = try inputPort(args, currentInput, "char-ready?")
      return .boolean(true)
    }
    primitive("write", in: env) { [unowned self] args in
      let (value, port) = try outputArguments(args, currentOutput, "write")
      try emit(value.written, to: port)
      return .unspecified
    }
    primitive("display", in: env) { [unowned self] args in
      let (value, port) = try outputArguments(args, currentOutput, "display")
      try emit(value.displayed, to: port)
      return .unspecified
    }
    primitive("newline", in: env) { [unowned self] args in
      let port = try outputPort(args, currentOutput, "newline")
      try emit("\n", to: port)
      return .unspecified
    }
    primitive("write-char", in: env) { [unowned self] args in
      guard args.count == 1 || args.count == 2 else {
        throw SchemeError.arity("write-char expects 1 or 2 arguments")
      }
      let destination = args.count == 2 ? try port(args[1], .output, "write-char") : currentOutput
      try emit(String(try character(args[0], "write-char")), to: destination)
      return .unspecified
    }
    primitive("open-input-string", in: env) { args in
      try require(args, 1, "open-input-string")
      return .port(SchemePort(input: try schemeString(args[0], "open-input-string").string))
    }
    primitive("open-output-string", in: env) { args in
      try require(args, 0, "open-output-string")
      return .port(SchemePort(output: true))
    }
    primitive("get-output-string", in: env) { args in
      try require(args, 1, "get-output-string")
      return .string(SchemeString(try port(args[0], .output, "get-output-string").output))
    }
    primitive("flush-output", in: env) { [unowned self] args in
      _ = try outputPort(args, currentOutput, "flush-output")
      return .unspecified
    }
    primitive("error", in: env) { args in
      throw SchemeError.io(args.map(\.displayed).joined(separator: " "))
    }
  }
}

private func require(_ values: [Value], _ count: Int, _ name: String) throws {
  guard values.count == count else { throw SchemeError.arity("\(name) expects \(count) arguments") }
}

private func schemeNumber(_ value: Value) throws -> SchemeNumber {
  switch value {
  case .integer(let n): return SchemeNumber(n)
  case .rational(let n): return SchemeNumber(n)
  case .real(let n): return SchemeNumber(n)
  case .complex(let real, let imaginary): return .complex(real: real, imaginary: imaginary)
  default: throw SchemeError.type("expected number, got \(value.written)")
  }
}

private func numberValue(_ number: SchemeNumber) -> Value {
  switch number {
  case .real(.exact(let rational)):
    return rational.isInteger ? .integer(rational.numerator) : .rational(rational)
  case .real(.inexact(let real)): return .real(real)
  case .complex(let real, let imaginary): return .complex(real: real, imaginary: imaginary)
  }
}

private func number(_ value: Value) throws -> Double {
  let number = try schemeNumber(value)
  guard number.isReal else { throw SchemeError.type("expected real number") }
  return number.parts.real.doubleValue
}

private func exactInteger(_ value: Value, _ context: String) throws -> BigInt {
  guard case .integer(let n) = value else {
    throw SchemeError.type("\(context) expects an exact integer")
  }
  return n
}

private func exactIntegerExponent(_ number: SchemeNumber) -> Int? {
  guard number.isExact, number.parts.imaginary.isZero,
    case .exact(let rational) = number.parts.real, rational.isInteger
  else { return nil }
  return rational.numerator.exactInt
}

private func integerComponent(_ value: Value, _ context: String) throws -> (
  value: BigInt, inexact: Bool
) {
  switch try realComponent(value, context) {
  case .exact(let rational):
    guard rational.isInteger else { throw SchemeError.type("\(context) expects an integer") }
    return (rational.numerator, false)
  case .inexact(let real):
    guard let rational = Rational.fromFiniteDouble(real), rational.isInteger else {
      throw SchemeError.type("\(context) expects an integer")
    }
    return (rational.numerator, true)
  }
}

private func realComponent(_ value: Value, _ context: String) throws -> RealComponent {
  let number = try schemeNumber(value)
  guard number.isReal else { throw SchemeError.type("\(context) expects a real number") }
  return number.parts.real
}

private func rationalComponent(_ value: Value, _ context: String) throws -> (Rational, Bool) {
  switch try realComponent(value, context) {
  case .exact(let rational): return (rational, false)
  case .inexact(let real):
    guard let rational = Rational.fromFiniteDouble(real) else {
      throw SchemeError.numeric("\(context) expects a finite rational")
    }
    return (rational, true)
  }
}

private func isNumber(_ value: Value) -> Bool { (try? schemeNumber(value)) != nil }

private func predicate(_ args: [Value], _ name: String, _ test: (Value) -> Bool) throws -> Value {
  try require(args, 1, name)
  return .boolean(test(args[0]))
}

private func compareReal(_ lhs: RealComponent, _ rhs: RealComponent) -> Int? {
  switch (lhs, rhs) {
  case (.exact(let a), .exact(let b)): return a == b ? 0 : (a < b ? -1 : 1)
  case (.inexact(let a), .inexact(let b)):
    guard !a.isNaN, !b.isNaN else { return nil }
    return a == b ? 0 : (a < b ? -1 : 1)
  case (.exact(let a), .inexact(let b)):
    guard !b.isNaN else { return nil }
    if b == .infinity { return -1 }
    if b == -.infinity { return 1 }
    let exactB = Rational.fromFiniteDouble(b)!
    return a == exactB ? 0 : (a < exactB ? -1 : 1)
  case (.inexact(let a), .exact(let b)):
    guard let comparison = compareReal(.exact(b), .inexact(a)) else { return nil }
    return -comparison
  }
}

private func indexRadix(_ value: Value, _ context: String) throws -> Int {
  guard let radix = try exactInteger(value, context).exactInt, [2, 8, 10, 16].contains(radix) else {
    throw SchemeError.numeric("\(context) requires radix 2, 8, 10, or 16")
  }
  return radix
}

private func exactNumber(_ number: SchemeNumber) throws -> SchemeNumber {
  let parts = number.parts
  func exact(_ component: RealComponent) throws -> RealComponent {
    switch component {
    case .exact: return component
    case .inexact(let value):
      guard let rational = Rational.fromFiniteDouble(value) else {
        throw SchemeError.numeric("cannot represent non-finite exact value")
      }
      return .exact(rational)
    }
  }
  return .rectangular(try exact(parts.real), try exact(parts.imaginary))
}

private struct InexactComplex {
  var real: Double
  var imaginary: Double
}
private func inexactComplex(_ number: SchemeNumber) -> InexactComplex {
  let p = number.parts
  return InexactComplex(real: p.real.doubleValue, imaginary: p.imaginary.doubleValue)
}
private func complexExp(_ z: InexactComplex) -> InexactComplex {
  let scale = Foundation.exp(z.real)
  return InexactComplex(
    real: scale * Foundation.cos(z.imaginary),
    imaginary: scale * Foundation.sin(z.imaginary)
  )
}
private func complexLog(_ z: InexactComplex) -> InexactComplex {
  InexactComplex(
    real: Foundation.log(Foundation.hypot(z.real, z.imaginary)),
    imaginary: Foundation.atan2(z.imaginary, z.real)
  )
}
private func complexMultiply(_ a: InexactComplex, _ b: InexactComplex) -> InexactComplex {
  InexactComplex(
    real: a.real * b.real - a.imaginary * b.imaginary,
    imaginary: a.real * b.imaginary + a.imaginary * b.real
  )
}
private func complexDivide(_ a: InexactComplex, _ b: InexactComplex) -> InexactComplex {
  let d = b.real * b.real + b.imaginary * b.imaginary
  return InexactComplex(
    real: (a.real * b.real + a.imaginary * b.imaginary) / d,
    imaginary: (a.imaginary * b.real - a.real * b.imaginary) / d
  )
}
private func fromComplex(_ z: InexactComplex) -> SchemeNumber {
  .rectangular(.inexact(z.real), .inexact(z.imaginary))
}
private func complexSqrt(_ number: SchemeNumber) -> SchemeNumber {
  let parts = number.parts
  if case .exact(let real) = parts.real, case .exact(let imaginary) = parts.imaginary {
    if imaginary.isZero {
      if let root = real.exactSquareRoot { return SchemeNumber(root) }
      if real.signum < 0, let root = (-real).exactSquareRoot {
        return .complex(real: .exact(.zero), imaginary: .exact(root))
      }
    } else if let magnitude = number.exactMagnitude,
      let rootReal = (try? (magnitude + real) / Rational(2))?.exactSquareRoot,
      let rootImaginary = (try? (magnitude - real) / Rational(2))?.exactSquareRoot
    {
      return .complex(
        real: .exact(rootReal),
        imaginary: .exact(imaginary.signum < 0 ? -rootImaginary : rootImaginary)
      )
    }
  }
  let z = inexactComplex(number)
  if z.imaginary == 0 && z.real >= 0 { return SchemeNumber(Foundation.sqrt(z.real)) }
  let magnitude = Foundation.hypot(z.real, z.imaginary)
  let real = Foundation.sqrt((magnitude + z.real) / 2)
  let imaginary =
    (z.imaginary.sign == .minus ? -1.0 : 1.0) * Foundation.sqrt((magnitude - z.real) / 2)
  return fromComplex(InexactComplex(real: real, imaginary: imaginary))
}
private func complexPower(_ base: SchemeNumber, _ exponent: SchemeNumber) -> SchemeNumber {
  fromComplex(
    complexExp(complexMultiply(inexactComplex(exponent), complexLog(inexactComplex(base))))
  )
}
private func complexTranscendental(_ name: String, _ number: SchemeNumber) -> SchemeNumber {
  let z = inexactComplex(number)
  let iZ = InexactComplex(real: -z.imaginary, imaginary: z.real)
  let minusIZ = InexactComplex(real: z.imaginary, imaginary: -z.real)
  switch name {
  case "exp": return fromComplex(complexExp(z))
  case "log": return fromComplex(complexLog(z))
  case "sin":
    let a = complexExp(iZ)
    let b = complexExp(minusIZ)
    return fromComplex(
      InexactComplex(real: (a.imaginary - b.imaginary) / 2, imaginary: (b.real - a.real) / 2)
    )
  case "cos":
    let a = complexExp(iZ)
    let b = complexExp(minusIZ)
    return fromComplex(
      InexactComplex(real: (a.real + b.real) / 2, imaginary: (a.imaginary + b.imaginary) / 2)
    )
  case "tan":
    let s = complexTranscendental("sin", number)
    let c = complexTranscendental("cos", number)
    return fromComplex(complexDivide(inexactComplex(s), inexactComplex(c)))
  case "asin":
    let root = inexactComplex(
      complexSqrt(
        fromComplex(
          InexactComplex(
            real: 1 - z.real * z.real + z.imaginary * z.imaginary,
            imaginary: -2 * z.real * z.imaginary
          )
        )
      )
    )
    let logged = complexLog(
      InexactComplex(real: root.real - z.imaginary, imaginary: root.imaginary + z.real)
    )
    return fromComplex(InexactComplex(real: logged.imaginary, imaginary: -logged.real))
  case "acos":
    let asin = inexactComplex(complexTranscendental("asin", number))
    return fromComplex(InexactComplex(real: Double.pi / 2 - asin.real, imaginary: -asin.imaginary))
  default:
    let oneMinus = fromComplex(InexactComplex(real: 1 + z.imaginary, imaginary: -z.real))
    let onePlus = fromComplex(InexactComplex(real: 1 - z.imaginary, imaginary: z.real))
    let quotient = complexDivide(inexactComplex(oneMinus), inexactComplex(onePlus))
    let logged = complexLog(quotient)
    return fromComplex(InexactComplex(real: -logged.imaginary / 2, imaginary: logged.real / 2))
  }
}

private func rationalized(_ value: Value, _ tolerance: Value) throws -> SchemeNumber {
  let x = try rationalComponent(value, "rationalize")
  let y = try rationalComponent(tolerance, "rationalize")
  let low = x.0 - y.0.absoluteValue
  let high = x.0 + y.0.absoluteValue
  func simplest(_ a: Rational, _ b: Rational) -> Rational {
    if a.signum < 0 && b.signum < 0 { return -simplest(-b, -a) }
    if a.signum <= 0 && b.signum >= 0 { return Rational(0) }
    let floorA = a.rounded(.floor)
    let floorB = b.rounded(.floor)
    if floorA < floorB { return Rational(floorA + .one)! }
    let fractionalA = a - Rational(floorA)!
    let fractionalB = b - Rational(floorB)!
    if fractionalA.isZero { return Rational(floorA)! }
    let reciprocal = simplest(try! (Rational.one / fractionalB), try! (Rational.one / fractionalA))
    return Rational(floorA)! + (try! (Rational.one / reciprocal))
  }
  let result = simplest(low, high)
  return x.1 || y.1 ? SchemeNumber(result).inexact() : SchemeNumber(result)
}

private func pair(_ value: Value, _ context: String) throws -> Pair {
  guard case .pair(let pair) = value else { throw SchemeError.type("\(context) expects a pair") }
  return pair
}
private func schemeString(_ value: Value, _ context: String) throws -> SchemeString {
  guard case .string(let string) = value else {
    throw SchemeError.type("\(context) expects a string")
  }
  return string
}
private func character(_ value: Value, _ context: String) throws -> Character {
  guard case .character(let character) = value else {
    throw SchemeError.type("\(context) expects a character")
  }
  return character
}
private func vector(_ value: Value, _ context: String) throws -> SchemeVector {
  guard case .vector(let vector) = value else {
    throw SchemeError.type("\(context) expects a vector")
  }
  return vector
}
private func index(_ value: Value, _ context: String) throws -> Int {
  let n = try exactInteger(value, context)
  guard n.signum >= 0, let result = n.exactInt else {
    throw SchemeError.numeric("\(context) requires nonnegative index")
  }
  return result
}
private func scalar(_ character: Character) throws -> UInt32 {
  guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
    throw SchemeError.type("character has multiple scalars")
  }
  return scalar.value
}
private func compare(_ lhs: String, _ rhs: String, _ name: String) -> Bool {
  if name.hasSuffix("<=?") { return lhs <= rhs }
  if name.hasSuffix(">=?") { return lhs >= rhs }
  if name.hasSuffix("=?") { return lhs == rhs }
  if name.hasSuffix("<?") { return lhs < rhs }
  return lhs > rhs
}

private func scalarCaseMapping(_ character: Character, upper: Bool) -> String {
  guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
    return String(character)
  }
  return upper ? scalar.properties.uppercaseMapping : scalar.properties.lowercaseMapping
}

private func hasScalarCaseMapping(_ character: Character, upper: Bool) -> Bool {
  scalarCaseMapping(character, upper: upper).unicodeScalars.count == 1
}

private func isScalarCaseCharacter(_ character: Character) -> Bool {
  character.isLetter && hasScalarCaseMapping(character, upper: true)
    && hasScalarCaseMapping(character, upper: false)
}

private func scalarCaseMap(_ character: Character, upper: Bool) -> Character {
  let mapped = scalarCaseMapping(character, upper: upper)
  guard mapped.unicodeScalars.count == 1, let scalar = mapped.unicodeScalars.first else {
    return character
  }
  return Character(String(scalar))
}

private func scalarCaseKey(_ character: Character) -> String {
  var pending = [character]
  var keys = Set<String>()
  while let current = pending.popLast() {
    let spelling = String(current)
    guard keys.insert(spelling).inserted else { continue }
    for upper in [true, false] {
      let mapped = scalarCaseMapping(current, upper: upper)
      guard mapped.unicodeScalars.count == 1, let scalar = mapped.unicodeScalars.first else {
        continue
      }
      pending.append(Character(String(scalar)))
    }
  }
  return keys.min() ?? String(character)
}

private func charPredicate(_ args: [Value], _ name: String, _ test: (Character) -> Bool) throws
  -> Value
{
  try require(args, 1, name)
  return .boolean(test(try character(args[0], name)))
}

private func port(_ value: Value, _ mode: SchemePort.Mode, _ context: String) throws -> SchemePort {
  guard case .port(let port) = value, port.mode == mode, !port.closed else {
    throw SchemeError.type("\(context) expects an open \(mode == .input ? "input" : "output") port")
  }
  return port
}
private func inputPort(_ args: [Value], _ fallback: SchemePort, _ name: String) throws -> SchemePort
{
  guard args.count <= 1 else { throw SchemeError.arity("\(name) expects 0 or 1 arguments") }
  return args.isEmpty ? fallback : try port(args[0], .input, name)
}
private func outputPort(_ args: [Value], _ fallback: SchemePort, _ name: String) throws
  -> SchemePort
{
  guard args.count <= 1 else { throw SchemeError.arity("\(name) expects 0 or 1 arguments") }
  return args.isEmpty ? fallback : try port(args[0], .output, name)
}
private func outputArguments(_ args: [Value], _ fallback: SchemePort, _ name: String) throws -> (
  Value, SchemePort
) {
  guard args.count == 1 || args.count == 2 else {
    throw SchemeError.arity("\(name) expects 1 or 2 arguments")
  }
  return (args[0], args.count == 2 ? try port(args[1], .output, name) : fallback)
}
private func emit(_ text: String, to port: SchemePort) throws {
  if let sink = port.sink { try sink(text) } else { port.output += text }
}
private func closePort(_ args: [Value], _ mode: SchemePort.Mode, _ name: String) throws -> Value {
  try require(args, 1, name)
  guard case .port(let p) = args[0], p.mode == mode else {
    throw SchemeError.type("\(name) expects an \(mode == .input ? "input" : "output") port")
  }
  if !p.closed {
    p.closed = true
    do { try p.handle?.close() } catch { throw SchemeError.io(error.localizedDescription) }
  }
  return .unspecified
}

private func eq(_ lhs: Value, _ rhs: Value) -> Bool {
  switch (lhs, rhs) {
  case (.boolean(let a), .boolean(let b)): a == b
  case (.character(let a), .character(let b)): a == b
  case (.symbol(let a), .symbol(let b)): a == b
  case (.empty, .empty), (.eof, .eof): true
  case (.pair(let a), .pair(let b)): a === b
  case (.string(let a), .string(let b)): a === b
  case (.vector(let a), .vector(let b)): a === b
  case (.procedure(let a), .procedure(let b)): a === b
  case (.promise(let a), .promise(let b)): a === b
  case (.port(let a), .port(let b)): a === b
  default: false
  }
}

private func eqv(_ lhs: Value, _ rhs: Value) -> Bool {
  if let a = try? schemeNumber(lhs), let b = try? schemeNumber(rhs) {
    return a.isExact == b.isExact && SchemeNumber.numericallyEqual(a, b)
  }
  return eq(lhs, rhs)
}

private struct IdentityPair: Hashable {
  let left: ObjectIdentifier
  let right: ObjectIdentifier
}

private func equal(_ lhs: Value, _ rhs: Value) -> Bool {
  var pending = [(lhs, rhs)]
  var seen = Set<IdentityPair>()
  while let (a, b) = pending.popLast() {
    switch (a, b) {
    case (.pair(let x), .pair(let y)):
      if x === y { continue }
      let id = IdentityPair(left: ObjectIdentifier(x), right: ObjectIdentifier(y))
      if seen.insert(id).inserted { pending += [(x.car, y.car), (x.cdr, y.cdr)] }
    case (.vector(let x), .vector(let y)):
      if x === y { continue }
      guard x.elements.count == y.elements.count else { return false }
      let id = IdentityPair(left: ObjectIdentifier(x), right: ObjectIdentifier(y))
      if seen.insert(id).inserted { pending += zip(x.elements, y.elements) }
    case (.string(let x), .string(let y)): if x.characters != y.characters { return false }
    default: if !eqv(a, b) { return false }
    }
  }
  return true
}
