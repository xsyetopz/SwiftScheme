import Foundation

/// Errors raised by arbitrary-precision arithmetic.
public enum BigIntError: Error, Equatable {
  case divisionByZero
  case negativeExponent
}

/// An arbitrary-precision signed integer.
public struct BigInt: Hashable, Sendable, Comparable, CustomStringConvertible,
  ExpressibleByIntegerLiteral
{
  package var sign: Int8
  package var words: [UInt32]

  /// The numeric value or property represented by this instance.
  public static let zero = Self()
  /// The numeric value or property represented by this instance.
  public static let one = Self(1)

  /// Creates a numeric value.
  public init() {
    sign = 0
    words = []
  }

  /// Creates a numeric value.
  public init(_ value: Int) { self.init(Int64(value)) }

  /// Creates a numeric value.
  public init(_ value: Int64) {
    let magnitude = value.magnitude
    var words = magnitude == 0 ? [] : [UInt32(truncatingIfNeeded: magnitude)]
    if magnitude > UInt32.max { words.append(UInt32(magnitude >> 32)) }
    self.init(sign: value < 0 ? -1 : 1, words: words)
  }

  /// Creates a numeric value.
  public init(integerLiteral value: Int64) { self.init(value) }

  /// Creates a numeric value.
  public init?(_ text: String, radix: Int = 10) {
    guard [2, 8, 10, 16].contains(radix) else { return nil }
    let bytes = Array(text.utf8)
    guard !bytes.isEmpty else { return nil }

    var index = 0
    var parsedSign: Int8 = 1
    if bytes[index] == 45 {
      parsedSign = -1
      index += 1
    } else if bytes[index] == 43 {
      index += 1
    }
    guard index < bytes.count else { return nil }

    var magnitude: [UInt32] = []
    while index < bytes.count {
      let byte = bytes[index]
      let digit: UInt32
      switch byte {
      case 48...57: digit = UInt32(byte - 48)
      case 65...70: digit = UInt32(byte - 65 + 10)
      case 97...102: digit = UInt32(byte - 97 + 10)
      default: return nil
      }
      guard digit < radix else { return nil }
      Self.multiplyMagnitude(&magnitude, by: UInt32(radix))
      Self.addMagnitude(&magnitude, digit)
      index += 1
    }
    self.init(sign: parsedSign, words: magnitude)
  }

  package init(sign: Int8, words: [UInt32]) {
    var normalized = words
    while normalized.last == 0 { normalized.removeLast() }
    self.words = normalized
    self.sign = normalized.isEmpty ? 0 : (sign < 0 ? -1 : 1)
  }

  /// The numeric value or property represented by this instance.
  public var isZero: Bool { sign == 0 }
  /// The numeric value or property represented by this instance.
  public var signum: Int { Int(sign) }
  /// The numeric value or property represented by this instance.
  public var absoluteValue: Self { Self(sign: 1, words: words) }
  /// The numeric value or property represented by this instance.
  public var description: String { string(radix: 10) }

  /// Performs the corresponding numeric operation.
  public func string(radix: Int = 10) -> String {
    precondition([2, 8, 10, 16].contains(radix), "unsupported radix")
    guard !isZero else { return "0" }

    let alphabet = Array("0123456789abcdef".utf8)
    var value = words
    var digits: [UInt8] = []
    while !value.isEmpty {
      let division = Self.divideMagnitude(value, by: UInt32(radix))
      value = division.quotient
      digits.append(alphabet[Int(division.remainder)])
    }
    if sign < 0 { digits.append(45) }
    return String(bytes: digits.reversed(), encoding: .utf8) ?? ""
  }

  package var bitWidth: Int {
    guard let mostSignificant = words.last, mostSignificant != 0 else { return 0 }
    return (words.count - 1) * 32 + (32 - mostSignificant.leadingZeroBitCount)
  }

  package func shiftedLeft(_ shift: Int) -> Self {
    guard shift > 0, !isZero else { return self }
    let wordShift = shift / 32
    let bitShift = shift % 32
    var result = Array(repeating: UInt32(0), count: words.count + wordShift + 1)
    var carry: UInt32 = 0
    for (index, word) in words.enumerated() {
      let destination = index + wordShift
      result[destination] = (word << UInt32(bitShift)) | carry
      carry = bitShift == 0 ? 0 : word >> UInt32(32 - bitShift)
    }
    if carry != 0 { result[words.count + wordShift] = carry }
    return Self(sign: sign, words: result)
  }

  /// The numeric value or property represented by this instance.
  public var exactInt64: Int64? {
    guard let magnitude = unsignedMagnitude else { return nil }
    if sign >= 0 { return magnitude <= UInt64(Int64.max) ? Int64(magnitude) : nil }
    let limit = UInt64(Int64.max) + 1
    guard magnitude <= limit else { return nil }
    return magnitude == limit ? Int64.min : -Int64(magnitude)
  }

  /// Creates a numeric value.
  public var exactInt: Int? { exactInt64.flatMap(Int.init(exactly:)) }

  /// The numeric value or property represented by this instance.
  public var doubleValue: Double {
    var value = 0.0
    for word in words.reversed() { value = value * 4_294_967_296.0 + Double(word) }
    return sign < 0 ? -value : value
  }

  var binaryApproximation: (significand: Double, exponent: Int) {
    guard !isZero, let topWord = words.last else { return (0, 0) }
    let topWordBits = 32 - topWord.leadingZeroBitCount
    let bitWidth = (words.count - 1) * 32 + topWordBits
    let requestedBits = min(bitWidth, 53)
    var remaining = requestedBits
    var wordIndex = words.count - 1
    var availableBits = topWordBits
    var leading: UInt64 = 0

    while remaining > 0 {
      let taken = min(remaining, availableBits)
      let shift = availableBits - taken
      let mask = taken == 64 ? UInt64.max : (UInt64(1) << UInt64(taken)) - 1
      let chunk = (UInt64(words[wordIndex]) >> UInt64(shift)) & mask
      leading = (leading << UInt64(taken)) | chunk
      remaining -= taken
      if remaining > 0 {
        wordIndex -= 1
        availableBits = 32
      }
    }

    var exponent = bitWidth - 1
    let discardedBits = bitWidth - requestedBits
    if discardedBits > 0 {
      let guardIndex = discardedBits - 1
      let guardWord = guardIndex / 32
      let guardBit = (words[guardWord] & (UInt32(1) << UInt32(guardIndex % 32))) != 0
      var sticky = false
      if guardIndex > 0 {
        let fullWords = guardIndex / 32
        if words[..<fullWords].contains(where: { $0 != 0 }) { sticky = true }
        let remainder = guardIndex % 32
        if !sticky && remainder > 0 {
          let mask = (UInt32(1) << UInt32(remainder)) - 1
          sticky = (words[fullWords] & mask) != 0
        }
      }
      if guardBit && (sticky || (leading & 1) != 0) { leading += 1 }
      if leading == UInt64(1) << UInt64(requestedBits) {
        leading >>= 1
        exponent += 1
      }
    }

    let scale = Foundation.scalbn(1.0, Int32(requestedBits - 1))
    let signed = Double(leading) / scale
    return (sign < 0 ? -signed : signed, exponent)
  }

  private var unsignedMagnitude: UInt64? {
    guard words.count <= 2 else { return nil }
    guard let first = words.first else { return 0 }
    return UInt64(first) | (words.count == 2 ? UInt64(words[1]) << 32 : 0)
  }

  /// Performs the corresponding numeric operation.
  public static prefix func - (value: Self) -> Self { Self(sign: -value.sign, words: value.words) }

  /// Performs the corresponding numeric operation.
  public static prefix func + (value: Self) -> Self { value }

  /// Performs the corresponding numeric operation.
  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.sign != rhs.sign { return lhs.sign < rhs.sign }
    switch lhs.sign {
    case -1: return compareMagnitude(lhs.words, rhs.words) > 0
    case 1: return compareMagnitude(lhs.words, rhs.words) < 0
    default: return false
    }
  }

  /// Performs the corresponding numeric operation.
  public static func + (lhs: Self, rhs: Self) -> Self {
    if lhs.sign == 0 { return rhs }
    if rhs.sign == 0 { return lhs }
    if lhs.sign == rhs.sign {
      return Self(sign: lhs.sign, words: addMagnitudes(lhs.words, rhs.words))
    }
    let comparison = compareMagnitude(lhs.words, rhs.words)
    if comparison == 0 { return .zero }
    if comparison > 0 {
      return Self(sign: lhs.sign, words: subtractMagnitudes(lhs.words, rhs.words))
    }
    return Self(sign: rhs.sign, words: subtractMagnitudes(rhs.words, lhs.words))
  }

  /// Performs the corresponding numeric operation.
  public static func - (lhs: Self, rhs: Self) -> Self { lhs + -rhs }

  /// Performs the corresponding numeric operation.
  public static func * (lhs: Self, rhs: Self) -> Self {
    guard !lhs.isZero, !rhs.isZero else { return .zero }
    var result = Array(repeating: UInt32(0), count: lhs.words.count + rhs.words.count)
    for i in lhs.words.indices {
      var carry: UInt64 = 0
      for j in rhs.words.indices {
        let index = i + j
        let product = UInt64(lhs.words[i]) * UInt64(rhs.words[j]) + UInt64(result[index]) + carry
        result[index] = UInt32(truncatingIfNeeded: product)
        carry = product >> 32
      }
      var index = i + rhs.words.count
      while carry != 0 {
        let sum = UInt64(result[index]) + carry
        result[index] = UInt32(truncatingIfNeeded: sum)
        carry = sum >> 32
        index += 1
      }
    }
    return Self(sign: lhs.sign * rhs.sign, words: result)
  }

  /// Performs the corresponding numeric operation.
  public static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }

  /// Performs the corresponding numeric operation.
  public static func *= (lhs: inout Self, rhs: Self) { lhs = lhs * rhs }

  /// Performs the corresponding numeric operation.
  public func quotientAndRemainder(dividingBy divisor: Self) throws -> (
    quotient: Self, remainder: Self
  ) {
    guard !divisor.isZero else { throw BigIntError.divisionByZero }
    guard !isZero else { return (.zero, .zero) }
    let division = Self.divideMagnitudes(words, by: divisor.words)
    return (
      Self(sign: sign * divisor.sign, words: division.quotient),
      Self(sign: sign, words: division.remainder)
    )
  }

  /// Performs the corresponding numeric operation.
  public func quotient(dividingBy divisor: Self) throws -> Self {
    try quotientAndRemainder(dividingBy: divisor).quotient
  }

  /// Performs the corresponding numeric operation.
  public func remainder(dividingBy divisor: Self) throws -> Self {
    try quotientAndRemainder(dividingBy: divisor).remainder
  }

  /// Performs the corresponding numeric operation.
  public func modulo(_ divisor: Self) throws -> Self {
    let remainder = try remainder(dividingBy: divisor)
    return !remainder.isZero && remainder.sign != divisor.sign ? remainder + divisor : remainder
  }

  /// Performs the corresponding numeric operation.
  public func magnitudeModulo(_ divisor: UInt32) throws -> UInt32 {
    guard divisor != 0 else { throw BigIntError.divisionByZero }
    return Self.divideMagnitude(words, by: divisor).remainder
  }

  /// Performs the corresponding numeric operation.
  public static func gcd(_ lhs: Self, _ rhs: Self) -> Self {
    var a = lhs.absoluteValue
    var b = rhs.absoluteValue
    while !b.isZero {
      guard let remainder = try? a.remainder(dividingBy: b) else {
        preconditionFailure("BigInt invariant violated")
      }
      a = b
      b = remainder
    }
    return a
  }

  /// Performs the corresponding numeric operation.
  public func power(_ exponent: Int) throws -> Self {
    guard exponent >= 0 else { throw BigIntError.negativeExponent }
    var exponent = exponent
    var factor = self
    var result = Self.one
    while exponent != 0 {
      if exponent & 1 == 1 { result *= factor }
      exponent >>= 1
      if exponent != 0 { factor *= factor }
    }
    return result
  }

  /// Performs the corresponding numeric operation.
  public func integerSquareRoot() -> Self? {
    guard sign >= 0 else { return nil }
    guard self > .one else { return self }
    var low = Self.one
    var high = self
    while low <= high {
      guard let middle = try? (low + high).quotient(dividingBy: Self(2)) else {
        preconditionFailure("BigInt invariant violated")
      }
      let square = middle * middle
      if square == self { return middle }
      if square < self { low = middle + .one } else { high = middle - .one }
    }
    return high
  }

  /// The numeric value or property represented by this instance.
  public var exactSquareRoot: Self? {
    guard let root = integerSquareRoot(), root * root == self else { return nil }
    return root
  }

}
