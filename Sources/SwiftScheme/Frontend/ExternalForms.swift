import Foundation
import SwiftSchemeNumeric
import SwiftSchemeRuntime

package struct Reader {
  private let input: [Character]
  package var spellings: [String: String] = [:]
  package var index: Int
  private var line = 1
  private var column = 1
  private var previousWasCarriageReturn = false

  package init(_ source: String, start: Int = 0) {
    self.init(scalarCharacters(source), start: start)
  }

  package init(_ characters: [Character], start: Int = 0) {
    input = scalarCharacters(characters)
    index = start
    let location = Self.location(in: input, before: start)
    line = location.line
    column = location.column
  }

  private static func location(in input: [Character], before index: Int) -> (line: Int, column: Int)
  {
    var line = 1
    var column = 1
    var previousWasCarriageReturn = false
    for character in input[..<min(index, input.count)] {
      if character == "\r" {
        line += 1
        column = 1
        previousWasCarriageReturn = true
      } else if character == "\n" {
        if !previousWasCarriageReturn { line += 1 }
        column = 1
        previousWasCarriageReturn = false
      } else {
        column += 1
        previousWasCarriageReturn = false
      }
    }
    return (line, column)
  }

  package mutating func readAll() throws -> [Value] {
    var result: [Value] = []
    while let value = try readOne() { result.append(value) }
    return result
  }

  package mutating func readOne() throws -> Value? {
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
    if character == "\r" {
      line += 1
      column = 1
      previousWasCarriageReturn = true
    } else if character == "\n" {
      if !previousWasCarriageReturn { line += 1 }
      column = 1
      previousWasCarriageReturn = false
    } else {
      column += 1
      previousWasCarriageReturn = false
    }
    return character
  }

  private mutating func skipSpace() {
    while let character = current {
      if character.isWhitespace {
        _ = advance()
      } else if character == ";" {
        while let next = current, next != "\n", next != "\r" { _ = advance() }
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
        if current == nil {
          throw SchemeError.lexical("unexpected end of input", line: line, column: column)
        }
        guard current != ")" else {
          throw SchemeError.lexical("missing dotted-list tail", line: line, column: column)
        }
        let tail = try datum()
        skipSpace()
        guard current != nil else {
          throw SchemeError.lexical("unexpected end of input", line: line, column: column)
        }
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
        case "n": result.append("\n")
        case "r": result.append("\r")
        case "t": result.append("\t")
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
    let tokenColumn = column - 1
    guard first.isLetter else { return .character(first) }
    var token = String(first)
    while let character = current, !isDelimiter(character) {
      guard let next = advance() else { break }
      token.append(next)
    }
    switch token.lowercased() {
    case "space": return .character(" ")
    case "newline": return .character("\n")
    default:
      guard token.unicodeScalars.count == 1 else {
        throw SchemeError.lexical(
          "invalid character literal #\\\(token)",
          line: line,
          column: tokenColumn
        )
      }
      return .character(first)
    }
  }

  private mutating func atom(starting first: Character) throws -> Value {
    let tokenColumn = column - 1
    var token = String(first)
    while let character = current, !isDelimiter(character) {
      guard let next = advance() else { break }
      token.append(next)
    }
    if token.contains(where: { "[]{}|".contains($0) }) {
      throw SchemeError.lexical(
        "reserved character in token \(token)",
        line: line,
        column: tokenColumn
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
        column: tokenColumn
      )
    }
    if folded.hasPrefix("#") {
      throw SchemeError.lexical(
        "unsupported or invalid token \(token)",
        line: line,
        column: tokenColumn
      )
    }
    if looksNumeric(token) {
      throw SchemeError.lexical("invalid numeric literal \(token)", line: line, column: tokenColumn)
    }
    guard isIdentifier(token) else {
      throw SchemeError.lexical("invalid identifier \(token)", line: line, column: tokenColumn)
    }
    if token != folded { spellings[folded] = token }
    return .symbol(folded)
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
    isIdentifierInitial(character) || (character.isASCII && character.isNumber)
      || "+-.@".contains(character)
  }

  private func peek(_ distance: Int) -> Character? {
    let position = index + distance
    return position < input.count ? input[position] : nil
  }

  private func isDelimiter(_ character: Character?) -> Bool {
    guard let character else { return true }
    return character.isWhitespace || ["(", ")", "\"", ";"].contains(character)
  }
}
