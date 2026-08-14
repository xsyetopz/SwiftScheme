public enum BigIntError: Error, Equatable {
  case divisionByZero
  case negativeExponent
}

/// A signed arbitrary-precision integer stored as a normalized sign and
/// little-endian base-2^32 magnitude.
public struct BigInt: Hashable, Sendable, Comparable, CustomStringConvertible,
  ExpressibleByIntegerLiteral
{
  private var sign: Int8
  private var words: [UInt32]

  public static let zero = BigInt()
  public static let one = BigInt(1)

  public init() {
    sign = 0
    words = []
  }

  public init(_ value: Int) { self.init(Int64(value)) }

  public init(_ value: Int64) {
    let magnitude = value.magnitude
    var words = magnitude == 0 ? [] : [UInt32(truncatingIfNeeded: magnitude)]
    if magnitude > UInt32.max { words.append(UInt32(magnitude >> 32)) }
    self.init(sign: value < 0 ? -1 : 1, words: words)
  }

  public init(integerLiteral value: Int64) { self.init(value) }

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

  private init(sign: Int8, words: [UInt32]) {
    var normalized = words
    while normalized.last == 0 { normalized.removeLast() }
    self.words = normalized
    self.sign = normalized.isEmpty ? 0 : (sign < 0 ? -1 : 1)
  }

  public var isZero: Bool { sign == 0 }
  public var signum: Int { Int(sign) }
  public var absoluteValue: BigInt { BigInt(sign: 1, words: words) }
  public var description: String { string(radix: 10) }

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
    return String(decoding: digits.reversed(), as: UTF8.self)
  }

  public var exactInt64: Int64? {
    guard let magnitude = unsignedMagnitude else { return nil }
    if sign >= 0 { return magnitude <= UInt64(Int64.max) ? Int64(magnitude) : nil }
    let limit = UInt64(Int64.max) + 1
    guard magnitude <= limit else { return nil }
    return magnitude == limit ? Int64.min : -Int64(magnitude)
  }

  public var exactInt: Int? { exactInt64.flatMap(Int.init(exactly:)) }

  public var doubleValue: Double {
    var value = 0.0
    for word in words.reversed() { value = value * 4_294_967_296.0 + Double(word) }
    return sign < 0 ? -value : value
  }

  private var unsignedMagnitude: UInt64? {
    guard words.count <= 2 else { return nil }
    guard let first = words.first else { return 0 }
    return UInt64(first) | (words.count == 2 ? UInt64(words[1]) << 32 : 0)
  }

  public static prefix func - (value: BigInt) -> BigInt {
    BigInt(sign: -value.sign, words: value.words)
  }

  public static prefix func + (value: BigInt) -> BigInt { value }

  public static func < (lhs: BigInt, rhs: BigInt) -> Bool {
    if lhs.sign != rhs.sign { return lhs.sign < rhs.sign }
    switch lhs.sign {
    case -1: return compareMagnitude(lhs.words, rhs.words) > 0
    case 1: return compareMagnitude(lhs.words, rhs.words) < 0
    default: return false
    }
  }

  public static func + (lhs: BigInt, rhs: BigInt) -> BigInt {
    if lhs.sign == 0 { return rhs }
    if rhs.sign == 0 { return lhs }
    if lhs.sign == rhs.sign {
      return BigInt(sign: lhs.sign, words: addMagnitudes(lhs.words, rhs.words))
    }
    let comparison = compareMagnitude(lhs.words, rhs.words)
    if comparison == 0 { return .zero }
    if comparison > 0 {
      return BigInt(sign: lhs.sign, words: subtractMagnitudes(lhs.words, rhs.words))
    }
    return BigInt(sign: rhs.sign, words: subtractMagnitudes(rhs.words, lhs.words))
  }

  public static func - (lhs: BigInt, rhs: BigInt) -> BigInt { lhs + -rhs }

  public static func * (lhs: BigInt, rhs: BigInt) -> BigInt {
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
    return BigInt(sign: lhs.sign * rhs.sign, words: result)
  }

  /// Returns quotient and remainder using truncation toward zero. The
  /// remainder is zero or has the dividend's sign.
  public func quotientAndRemainder(dividingBy divisor: BigInt) throws -> (
    quotient: BigInt, remainder: BigInt
  ) {
    guard !divisor.isZero else { throw BigIntError.divisionByZero }
    guard !isZero else { return (.zero, .zero) }
    let division = Self.divideMagnitudes(words, by: divisor.words)
    return (
      BigInt(sign: sign * divisor.sign, words: division.quotient),
      BigInt(sign: sign, words: division.remainder)
    )
  }

  public func quotient(dividingBy divisor: BigInt) throws -> BigInt {
    try quotientAndRemainder(dividingBy: divisor).quotient
  }

  public func remainder(dividingBy divisor: BigInt) throws -> BigInt {
    try quotientAndRemainder(dividingBy: divisor).remainder
  }

  /// R5RS-style modulo: a nonzero result has the divisor's sign.
  public func modulo(_ divisor: BigInt) throws -> BigInt {
    let remainder = try remainder(dividingBy: divisor)
    return !remainder.isZero && remainder.sign != divisor.sign ? remainder + divisor : remainder
  }

  /// Fast unsigned helper used by parsing, printing, and divisibility checks.
  public func magnitudeModulo(_ divisor: UInt32) throws -> UInt32 {
    guard divisor != 0 else { throw BigIntError.divisionByZero }
    return Self.divideMagnitude(words, by: divisor).remainder
  }

  public static func gcd(_ lhs: BigInt, _ rhs: BigInt) -> BigInt {
    var a = lhs.absoluteValue
    var b = rhs.absoluteValue
    while !b.isZero {
      // b is known nonzero.
      let remainder = try! a.remainder(dividingBy: b)
      a = b
      b = remainder
    }
    return a
  }

  public func power(_ exponent: Int) throws -> BigInt {
    guard exponent >= 0 else { throw BigIntError.negativeExponent }
    var exponent = exponent
    var factor = self
    var result = BigInt.one
    while exponent != 0 {
      if exponent & 1 == 1 { result = result * factor }
      exponent >>= 1
      if exponent != 0 { factor = factor * factor }
    }
    return result
  }

  /// Returns floor(sqrt(self)) for nonnegative values.
  public func integerSquareRoot() -> BigInt? {
    guard sign >= 0 else { return nil }
    guard self > .one else { return self }
    var low = BigInt.one
    var high = self
    while low <= high {
      let middle = try! (low + high).quotient(dividingBy: BigInt(2))
      let square = middle * middle
      if square == self { return middle }
      if square < self { low = middle + .one } else { high = middle - .one }
    }
    return high
  }

  public var exactSquareRoot: BigInt? {
    guard let root = integerSquareRoot(), root * root == self else { return nil }
    return root
  }

  private static func compareMagnitude(_ lhs: [UInt32], _ rhs: [UInt32]) -> Int {
    if lhs.count != rhs.count { return lhs.count < rhs.count ? -1 : 1 }
    for index in lhs.indices.reversed() where lhs[index] != rhs[index] {
      return lhs[index] < rhs[index] ? -1 : 1
    }
    return 0
  }

  private static func addMagnitudes(_ lhs: [UInt32], _ rhs: [UInt32]) -> [UInt32] {
    var result: [UInt32] = []
    result.reserveCapacity(max(lhs.count, rhs.count) + 1)
    var carry: UInt64 = 0
    for index in 0..<max(lhs.count, rhs.count) {
      let sum =
        UInt64(index < lhs.count ? lhs[index] : 0) + UInt64(index < rhs.count ? rhs[index] : 0)
        + carry
      result.append(UInt32(truncatingIfNeeded: sum))
      carry = sum >> 32
    }
    if carry != 0 { result.append(UInt32(carry)) }
    return result
  }

  /// Subtracts rhs from lhs; lhs must be at least rhs.
  private static func subtractMagnitudes(_ lhs: [UInt32], _ rhs: [UInt32]) -> [UInt32] {
    var result = lhs
    var borrow: UInt64 = 0
    for index in lhs.indices {
      let subtrahend = UInt64(index < rhs.count ? rhs[index] : 0) + borrow
      let value = UInt64(lhs[index])
      result[index] = UInt32(truncatingIfNeeded: value &- subtrahend)
      borrow = value < subtrahend ? 1 : 0
    }
    while result.last == 0 { result.removeLast() }
    return result
  }

  private static func multiplyMagnitude(_ value: inout [UInt32], by multiplier: UInt32) {
    guard multiplier != 0, !value.isEmpty else {
      if multiplier == 0 { value.removeAll(keepingCapacity: true) }
      return
    }
    var carry: UInt64 = 0
    for index in value.indices {
      let product = UInt64(value[index]) * UInt64(multiplier) + carry
      value[index] = UInt32(truncatingIfNeeded: product)
      carry = product >> 32
    }
    if carry != 0 { value.append(UInt32(carry)) }
  }

  private static func addMagnitude(_ value: inout [UInt32], _ addend: UInt32) {
    var carry = UInt64(addend)
    var index = 0
    while carry != 0 && index < value.count {
      let sum = UInt64(value[index]) + carry
      value[index] = UInt32(truncatingIfNeeded: sum)
      carry = sum >> 32
      index += 1
    }
    if carry != 0 { value.append(UInt32(carry)) }
  }

  private static func divideMagnitude(_ dividend: [UInt32], by divisor: UInt32) -> (
    quotient: [UInt32], remainder: UInt32
  ) {
    precondition(divisor != 0)
    guard !dividend.isEmpty else { return ([], 0) }
    var quotient = Array(repeating: UInt32(0), count: dividend.count)
    var remainder: UInt64 = 0
    for index in dividend.indices.reversed() {
      let value = (remainder << 32) | UInt64(dividend[index])
      quotient[index] = UInt32(value / UInt64(divisor))
      remainder = value % UInt64(divisor)
    }
    while quotient.last == 0 { quotient.removeLast() }
    return (quotient, UInt32(remainder))
  }

  /// Knuth's normalized Algorithm D over base-2^32 words.
  private static func divideMagnitudes(_ dividend: [UInt32], by divisor: [UInt32]) -> (
    quotient: [UInt32], remainder: [UInt32]
  ) {
    precondition(!divisor.isEmpty)
    if compareMagnitude(dividend, divisor) < 0 { return ([], dividend) }
    if divisor.count == 1 {
      let division = divideMagnitude(dividend, by: divisor[0])
      return (division.quotient, division.remainder == 0 ? [] : [division.remainder])
    }

    let base = UInt64(1) << 32
    let shift = divisor.last!.leadingZeroBitCount
    let normalizedDivisor = shiftLeft(divisor, by: shift)
    var normalizedDividend = shiftLeft(dividend, by: shift)
    if normalizedDividend.count == dividend.count { normalizedDividend.append(0) }

    let n = normalizedDivisor.count
    let m = normalizedDividend.count - n - 1
    var quotient = Array(repeating: UInt32(0), count: m + 1)

    for j in stride(from: m, through: 0, by: -1) {
      let numerator =
        (UInt64(normalizedDividend[j + n]) << 32) | UInt64(normalizedDividend[j + n - 1])
      var estimate = numerator / UInt64(normalizedDivisor[n - 1])
      var remainder = numerator % UInt64(normalizedDivisor[n - 1])
      if estimate == base {
        estimate -= 1
        remainder += UInt64(normalizedDivisor[n - 1])
      }
      while remainder < base
        && estimate * UInt64(normalizedDivisor[n - 2]) > (remainder << 32)
          + UInt64(normalizedDividend[j + n - 2])
      {
        estimate -= 1
        remainder += UInt64(normalizedDivisor[n - 1])
      }

      var borrow: UInt64 = 0
      for i in 0..<n {
        let product = estimate * UInt64(normalizedDivisor[i]) + borrow
        let (word, underflow) = normalizedDividend[j + i].subtractingReportingOverflow(
          UInt32(truncatingIfNeeded: product)
        )
        normalizedDividend[j + i] = word
        borrow = (product >> 32) + (underflow ? 1 : 0)
      }
      let top = UInt64(normalizedDividend[j + n])
      let negative = top < borrow
      normalizedDividend[j + n] = UInt32(truncatingIfNeeded: top &- borrow)

      if negative {
        estimate -= 1
        var carry: UInt64 = 0
        for i in 0..<n {
          let sum = UInt64(normalizedDividend[j + i]) + UInt64(normalizedDivisor[i]) + carry
          normalizedDividend[j + i] = UInt32(truncatingIfNeeded: sum)
          carry = sum >> 32
        }
        normalizedDividend[j + n] &+= UInt32(carry)
      }
      quotient[j] = UInt32(estimate)
    }

    while quotient.last == 0 { quotient.removeLast() }
    var remainder = shiftRight(Array(normalizedDividend[0..<n]), by: shift)
    while remainder.last == 0 { remainder.removeLast() }
    return (quotient, remainder)
  }

  private static func shiftLeft(_ value: [UInt32], by shift: Int) -> [UInt32] {
    guard shift != 0 else { return value }
    var result: [UInt32] = []
    result.reserveCapacity(value.count + 1)
    var carry: UInt32 = 0
    for word in value {
      result.append((word << shift) | carry)
      carry = word >> (32 - shift)
    }
    if carry != 0 { result.append(carry) }
    return result
  }

  private static func shiftRight(_ value: [UInt32], by shift: Int) -> [UInt32] {
    guard shift != 0 else { return value }
    var result = value
    var carry: UInt32 = 0
    for index in value.indices.reversed() {
      result[index] = (value[index] >> shift) | carry
      carry = value[index] << (32 - shift)
    }
    return result
  }
}
