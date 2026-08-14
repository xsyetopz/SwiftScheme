import Foundation
import SwiftSchemeNumeric

enum Writer {
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
      guard value.unicodeScalars.count == 1 else { return quoted(String(value)) }
      if value == " " { return "#\\space" }
      if value == "\n" { return "#\\newline" }
      return "#\\\(value)"
    case .symbol(let name): return symbolSpelling(name)
    case .string(let value): return quoted(value.string)
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

  private static func quoted(_ value: String) -> String {
    var result = "\""
    for scalar in value.unicodeScalars {
      switch scalar.value {
      case 0x22:
        result.append("\\")
        result.append("\"")
      case 0x5C:
        result.append("\\")
        result.append("\\")
      default: result.unicodeScalars.append(scalar)
      }
    }
    result.append("\"")
    return result
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
