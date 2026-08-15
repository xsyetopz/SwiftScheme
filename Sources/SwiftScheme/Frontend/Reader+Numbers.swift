import Foundation
import SwiftSchemeNumeric
import SwiftSchemeRuntime

extension Reader {
  enum NumericExactness {
    case unspecified
    case exact
    case inexact
  }

  struct ParsedInteger {
    let value: BigInt
    let hasPlaceholder: Bool
  }

  func parseNumber(_ raw: String) -> Value? {
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
    if !radixSeen, exactness != .exact {
      switch token {
      case "+inf.0": return .real(Double.infinity)
      case "-inf.0": return .real(-Double.infinity)
      case "+nan.0", "-nan.0": return .real(Double.nan)
      default: break
      }
    }
    guard let parsed = parseComplex(token, radix: radix, exactness: exactness) else { return nil }
    return value(from: parsed)
  }

  func parseComplex(_ token: String, radix: Int, exactness: NumericExactness) -> SchemeNumber? {
    if let at = token.firstIndex(of: "@") {
      guard !token[token.index(after: at)...].contains("@"),
        let magnitude = parseReal(String(token[..<at]), radix: radix, exactness: exactness),
        let angle = parseReal(
          String(token[token.index(after: at)...]),
          radix: radix,
          exactness: exactness
        )
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
      guard let sign = body.first else { return nil }
      return .complex(
        real: .exact(Rational(0)),
        imaginary: implicitImaginaryUnit(sign, exactness: exactness)
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
      guard let imaginary = parseUnsignedReal(magnitude, radix: radix, exactness: exactness) else {
        return nil
      }
      return .complex(real: .exact(Rational(0)), imaginary: sign == "+" ? imaginary : -imaginary)
    }
    return nil
  }

  func implicitImaginaryUnit(_ sign: Character, exactness: NumericExactness) -> RealComponent {
    let value = sign == "+" ? 1.0 : -1.0
    return exactness == .inexact ? .inexact(value) : .exact(Rational(Int64(value)))
  }

  func parseReal(_ text: String, radix: Int, exactness: NumericExactness) -> RealComponent? {
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

  func parseUnsignedReal(_ text: String, radix: Int, exactness: NumericExactness) -> RealComponent?
  {
    guard !text.isEmpty else { return nil }
    if radix == 10, exactness != .exact {
      switch text {
      case "inf.0": return .inexact(Double.infinity)
      case "nan.0": return .inexact(Double.nan)
      default: break
      }
    }
    // `number->string` marks non-decimal inexact rationals with a trailing
    // `#`.  Here it is an inexactness marker, not an unspecified digit:
    // preserving the exact ratio is required for binary64 round-trips.
    let generatedCandidate = text.hasSuffix("#") ? String(text.dropLast()) : text
    let generatedInexact = text.hasSuffix("#") && generatedCandidate.contains("/")
      && !generatedCandidate.split(separator: "/").contains { $0.contains("#") }
    let numericText = generatedInexact ? generatedCandidate : text
    let slashParts = numericText.split(separator: "/", omittingEmptySubsequences: false)
    if numericText.contains("/") {
      guard slashParts.count == 2,
        let numerator = parseUnsignedInteger(String(slashParts[0]), radix: radix),
        let denominator = parseUnsignedInteger(String(slashParts[1]), radix: radix),
        let rational = Rational(numerator.value, denominator.value)
      else { return nil }
      guard exactness != .exact || (!numerator.hasPlaceholder && !denominator.hasPlaceholder) else {
        return nil
      }
      let inexact = generatedInexact || exactness == .inexact || numerator.hasPlaceholder || denominator.hasPlaceholder
      return inexact ? .inexact(rational.doubleValue) : .exact(rational)
    }

    if radix != 10 {
      guard let integer = parseUnsignedInteger(text, radix: radix) else { return nil }
      guard exactness != .exact || !integer.hasPlaceholder else { return nil }
      return exactness == .inexact || integer.hasPlaceholder
        ? .inexact(integer.value.doubleValue) : .exact(Rational(integer.value) ?? .zero)
    }

    return parseDecimalReal(text, exactness: exactness)
  }

  func parseUnsignedInteger(_ text: String, radix: Int) -> ParsedInteger? {
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

  func parseDecimalReal(_ text: String, exactness: NumericExactness) -> RealComponent? {
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
      guard let exponentText, validExponent(exponentText) else { return nil }
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
    let normalized =
      normalizedMantissa + (exponentMarker.map { String($0) } ?? "") + (exponentText ?? "")
    if exactness == .exact {
      guard let rational = exactDecimal(normalized) else { return nil }
      return .exact(rational)
    }
    if !inexactSyntax, let integer = BigInt(normalized, radix: 10) {
      return exactness == .inexact
        ? .inexact(integer.doubleValue) : .exact(Rational(integer) ?? .zero)
    }
    let doubleText = normalized.replacingOccurrences(of: "s", with: "e").replacingOccurrences(
      of: "f",
      with: "e"
    ).replacingOccurrences(of: "d", with: "e").replacingOccurrences(of: "l", with: "e")
    guard let real = Double(doubleText) else { return nil }
    return .inexact(real)
  }

  struct DecimalMantissa {
    let normalized: String
    let hasPlaceholder: Bool
    let hasDot: Bool
  }

  func parseDecimalMantissa(_ text: String) -> DecimalMantissa? {
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

  struct DecimalDigitHashRun {
    let normalized: String
    let digitCount: Int
    let hasPlaceholder: Bool
  }

  func decimalDigitHashRun(_ text: String, requireDigit: Bool) -> DecimalDigitHashRun? {
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

  func validExponent(_ text: String) -> Bool {
    let characters = Array(text)
    guard !characters.isEmpty else { return false }
    let start = characters.first == "+" || characters.first == "-" ? 1 : 0
    guard start < characters.count else { return false }
    return characters[start...].allSatisfy { $0.isASCII && $0.isNumber }
  }

  func isDigit(_ character: Character, radix: Int) -> Bool {
    guard character.isASCII else { return false }
    switch character {
    case "0"..."9":
      guard let value = Int(String(character)) else { return false }
      return value < radix
    case "a"..."f": return radix == 16
    default: return false
    }
  }

  func exactDecimal(_ text: String) -> Rational? {
    let exponentIndex = text.firstIndex { "esfdl".contains($0) }
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

  func value(from number: SchemeNumber) -> Value {
    switch number {
    case .real(.exact(let rational)):
      return rational.isInteger ? .integer(rational.numerator) : .rational(rational)
    case .real(.inexact(let real)): return .real(real)
    case .complex(let real, let imaginary): return .complex(real: real, imaginary: imaginary)
    }
  }

}
