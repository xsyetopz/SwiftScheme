import Foundation

public struct Rational: Hashable, Sendable, Comparable, CustomStringConvertible {
  public static let zero = Self(0)
  public static let one = Self(1)
  public let numerator: BigInt
  public let denominator: BigInt

  public init?(_ numerator: BigInt, _ denominator: BigInt = .one) {
    guard !denominator.isZero else { return nil }
    let divisor = BigInt.gcd(numerator, denominator)
    guard let reducedNumerator = try? numerator.quotient(dividingBy: divisor),
      let reducedDenominator = try? denominator.quotient(dividingBy: divisor)
    else { return nil }
    if reducedDenominator.signum < 0 {
      self.numerator = -reducedNumerator
      self.denominator = -reducedDenominator
    } else {
      self.numerator = reducedNumerator
      self.denominator = reducedDenominator
    }
  }

  public init(_ integer: Int64) {
    numerator = BigInt(integer)
    denominator = .one
  }

  private static func make(_ numerator: BigInt, _ denominator: BigInt) -> Self {
    guard let value = Self(numerator, denominator) else {
      preconditionFailure("Rational invariant violated")
    }
    return value
  }

  public var isInteger: Bool { denominator == .one }
  public var isZero: Bool { numerator.isZero }
  public var signum: Int { numerator.signum }
  public var absoluteValue: Self { Self.make(numerator.absoluteValue, denominator) }
  public var doubleValue: Double {
    guard !numerator.isZero else { return 0 }
    let numeratorApproximation = numerator.absoluteValue.binaryApproximation
    let denominatorApproximation = denominator.binaryApproximation
    var significand = numeratorApproximation.significand / denominatorApproximation.significand
    var exponent = numeratorApproximation.exponent - denominatorApproximation.exponent
    if significand >= 2 {
      significand /= 2
      exponent += 1
    } else if significand < 1 {
      significand *= 2
      exponent -= 1
    }
    let value = Foundation.scalbn(significand, Int32(clamping: exponent))
    return numerator.signum < 0 ? -value : value
  }
  public var description: String {
    isInteger ? numerator.description : "\(numerator)/\(denominator)"
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator
  }

  public static prefix func - (value: Self) -> Self {
    Self.make(-value.numerator, value.denominator)
  }

  public static func + (lhs: Self, rhs: Self) -> Self {
    Self.make(
      lhs.numerator * rhs.denominator + rhs.numerator * lhs.denominator,
      lhs.denominator * rhs.denominator
    )
  }

  public static func - (lhs: Self, rhs: Self) -> Self { lhs + -rhs }

  public static func * (lhs: Self, rhs: Self) -> Self {
    Self.make(lhs.numerator * rhs.numerator, lhs.denominator * rhs.denominator)
  }

  public static func / (lhs: Self, rhs: Self) throws -> Self {
    guard !rhs.isZero else { throw BigIntError.divisionByZero }
    return Self.make(lhs.numerator * rhs.denominator, lhs.denominator * rhs.numerator)
  }

  public func power(_ exponent: Int) throws -> Self {
    if exponent >= 0 {
      return Self.make(try numerator.power(exponent), try denominator.power(exponent))
    }
    guard !isZero else { throw BigIntError.divisionByZero }
    guard exponent != Int.min else { throw BigIntError.negativeExponent }
    return Self.make(try denominator.power(-exponent), try numerator.power(-exponent))
  }

  public var exactSquareRoot: Self? {
    guard signum >= 0, let numerator = numerator.exactSquareRoot,
      let denominator = denominator.exactSquareRoot
    else { return nil }
    return Self(numerator, denominator)
  }

  public enum Rounding { case floor, ceiling, truncate, nearestEven }

  public func rounded(_ rule: Rounding) -> BigInt {
    guard let division = try? numerator.quotientAndRemainder(dividingBy: denominator) else {
      preconditionFailure("Rational invariant violated")
    }
    let quotient = division.quotient
    let remainder = division.remainder
    guard !remainder.isZero else { return quotient }
    switch rule {
    case .truncate: return quotient
    case .floor: return numerator.signum < 0 ? quotient - .one : quotient
    case .ceiling: return numerator.signum > 0 ? quotient + .one : quotient
    case .nearestEven:
      let twice = remainder.absoluteValue * BigInt(2)
      if twice < denominator { return quotient }
      if twice > denominator { return numerator.signum < 0 ? quotient - .one : quotient + .one }
      let even = (try? quotient.absoluteValue.magnitudeModulo(2)) == 0
      return even ? quotient : (numerator.signum < 0 ? quotient - .one : quotient + .one)
    }
  }

  public static func exactDecimal(significand: BigInt, fractionalDigits: Int, exponent: Int)
    -> Self?
  {
    let scale = fractionalDigits - exponent
    if scale <= 0 {
      guard scale != Int.min, let power = try? BigInt(10).power(-scale) else { return nil }
      return Self(significand * power)
    }
    guard let power = try? BigInt(10).power(scale) else { return nil }
    return Self(significand, power)
  }

  public static func fromFiniteDouble(_ value: Double) -> Self? {
    guard value.isFinite else { return nil }
    if value == 0 { return Self(0) }
    let bits = value.bitPattern
    let negative = bits >> 63 != 0
    let exponentBits = Int((bits >> 52) & 0x7ff)
    let fraction = bits & ((UInt64(1) << 52) - 1)
    let significand: UInt64
    let exponent: Int
    if exponentBits == 0 {
      significand = fraction
      exponent = -1022 - 52
    } else {
      significand = fraction | (UInt64(1) << 52)
      exponent = exponentBits - 1023 - 52
    }
    guard var numerator = BigInt(String(significand)) else { return nil }
    var denominator = BigInt.one
    if exponent >= 0 {
      guard let power = try? BigInt(2).power(exponent) else { return nil }
      numerator *= power
    } else {
      guard let power = try? BigInt(2).power(-exponent) else { return nil }
      denominator = power
    }
    if negative { numerator = -numerator }
    return Self(numerator, denominator)
  }
}

public enum RealComponent: Hashable, Sendable {
  case exact(Rational)
  case inexact(Double)

  public init(_ integer: Int64) { self = .exact(Rational(integer)) }
  public var isExact: Bool { if case .exact = self { true } else { false } }
  public var doubleValue: Double {
    switch self {
    case .exact(let value): value.doubleValue
    case .inexact(let value): value
    }
  }
  public var isZero: Bool {
    switch self {
    case .exact(let value): value.isZero
    case .inexact(let value): value == 0
    }
  }
  public var signum: Int {
    switch self {
    case .exact(let value): value.signum
    case .inexact(let value): value == 0 ? 0 : (value < 0 ? -1 : 1)
    }
  }

  public static prefix func - (value: Self) -> Self {
    switch value {
    case .exact(let x): .exact(-x)
    case .inexact(let x): .inexact(-x)
    }
  }

  public static func + (lhs: Self, rhs: Self) -> Self {
    switch (lhs, rhs) {
    case (.exact(let a), .exact(let b)): .exact(a + b)
    default: .inexact(lhs.doubleValue + rhs.doubleValue)
    }
  }

  public static func - (lhs: Self, rhs: Self) -> Self { lhs + -rhs }

  public static func * (lhs: Self, rhs: Self) -> Self {
    switch (lhs, rhs) {
    case (.exact(let a), .exact(let b)): .exact(a * b)
    default: .inexact(lhs.doubleValue * rhs.doubleValue)
    }
  }

  public static func / (lhs: Self, rhs: Self) throws -> Self {
    guard !rhs.isZero else { throw BigIntError.divisionByZero }
    switch (lhs, rhs) {
    case (.exact(let a), .exact(let b)): return .exact(try a / b)
    default: return .inexact(lhs.doubleValue / rhs.doubleValue)
    }
  }
}

public enum SchemeNumber: Hashable, Sendable, CustomStringConvertible {
  case real(RealComponent)
  case complex(real: RealComponent, imaginary: RealComponent)

  public static let zero = Self.real(.exact(Rational(0)))
  public static let one = Self.real(.exact(Rational(1)))

  public init(_ integer: Int64) { self = .real(.exact(Rational(integer))) }
  public init(_ integer: BigInt) { self = .real(.exact(Rational(integer) ?? .zero)) }
  public init(_ rational: Rational) { self = .real(.exact(rational)) }
  public init(_ inexact: Double) { self = .real(.inexact(inexact)) }

  public static func rectangular(_ real: RealComponent, _ imaginary: RealComponent) -> Self {
    guard imaginary.isZero else { return .complex(real: real, imaginary: imaginary) }
    if imaginary.isExact { return .real(real) }
    return real.isExact ? .real(.inexact(real.doubleValue)) : .real(real)
  }

  public var parts: (real: RealComponent, imaginary: RealComponent) {
    switch self {
    case .real(let value): (value, RealComponent(0))
    case .complex(let real, let imaginary): (real, imaginary)
    }
  }

  public var isExact: Bool {
    let value = parts
    return value.real.isExact && value.imaginary.isExact
  }
  public var isReal: Bool { parts.imaginary.isZero }
  public var isRational: Bool {
    guard isReal else { return false }
    if case .exact = parts.real { return true }
    return parts.real.doubleValue.isFinite
  }
  public var isInteger: Bool {
    guard isReal else { return false }
    switch parts.real {
    case .exact(let value): return value.isInteger
    case .inexact(let value): return value.isFinite && value.rounded() == value
    }
  }
  public var isZero: Bool { parts.real.isZero && parts.imaginary.isZero }

  public var description: String {
    switch self {
    case .real(let value): return Self.describe(value)
    case .complex(let real, let imaginary):
      let imaginaryText = Self.describe(imaginary)
      let separator = imaginaryText.hasPrefix("-") || imaginaryText.hasPrefix("+") ? "" : "+"
      return Self.describe(real) + separator + imaginaryText + "i"
    }
  }

  public func string(radix: Int = 10) -> String? {
    guard [2, 8, 10, 16].contains(radix) else { return nil }
    func component(_ value: RealComponent) -> String? {
      switch value {
      case .exact(let rational):
        let numerator = rational.numerator.string(radix: radix)
        return rational.isInteger
          ? numerator : numerator + "/" + rational.denominator.string(radix: radix)
      case .inexact(let number):
        guard radix == 10 else {
          guard let rational = Rational.fromFiniteDouble(number) else { return nil }
          let numerator = (rational.numerator * BigInt(radix)).string(radix: radix)
          return numerator + "/" + rational.denominator.string(radix: radix) + "#"
        }
        return Self.describe(.inexact(number))
      }
    }
    switch self {
    case .real(let value): return component(value)
    case .complex(let real, let imaginary):
      guard let a = component(real), let b = component(imaginary) else { return nil }
      let separator = b.hasPrefix("-") || b.hasPrefix("+") ? "" : "+"
      return a + separator + b + "i"
    }
  }

  private static func describe(_ value: RealComponent) -> String {
    switch value {
    case .exact(let rational): return rational.description
    case .inexact(let number):
      if number.isNaN { return "+nan.0" }
      if number == .infinity { return "+inf.0" }
      if number == -.infinity { return "-inf.0" }
      var text = String(number)
      if !text.contains(".") && !text.lowercased().contains("e") { text += ".0" }
      return text
    }
  }

  public static func numericallyEqual(_ lhs: Self, _ rhs: Self) -> Bool {
    let a = lhs.parts
    let b = rhs.parts
    return componentEqual(a.real, b.real) && componentEqual(a.imaginary, b.imaginary)
  }

  private static func componentEqual(_ lhs: RealComponent, _ rhs: RealComponent) -> Bool {
    switch (lhs, rhs) {
    case (.exact(let a), .exact(let b)): return a == b
    case (.inexact(let a), .inexact(let b)): return a == b
    case (.exact(let a), .inexact(let b)), (.inexact(let b), .exact(let a)):
      guard let exactB = Rational.fromFiniteDouble(b) else { return false }
      return a == exactB
    }
  }

  public static prefix func - (value: Self) -> Self {
    let value = value.parts
    return rectangular(-value.real, -value.imaginary)
  }

  public static func + (lhs: Self, rhs: Self) -> Self {
    let a = lhs.parts
    let b = rhs.parts
    return rectangular(a.real + b.real, a.imaginary + b.imaginary)
  }

  public static func - (lhs: Self, rhs: Self) -> Self { lhs + -rhs }

  public static func * (lhs: Self, rhs: Self) -> Self {
    let a = lhs.parts
    let b = rhs.parts
    return rectangular(
      a.real * b.real - a.imaginary * b.imaginary,
      a.real * b.imaginary + a.imaginary * b.real
    )
  }

  public static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
  public static func -= (lhs: inout Self, rhs: Self) { lhs = lhs - rhs }
  public static func *= (lhs: inout Self, rhs: Self) { lhs = lhs * rhs }

  public static func / (lhs: Self, rhs: Self) throws -> Self {
    let a = lhs.parts
    let b = rhs.parts
    let denominator = b.real * b.real + b.imaginary * b.imaginary
    guard !denominator.isZero else { throw BigIntError.divisionByZero }
    return rectangular(
      try (a.real * b.real + a.imaginary * b.imaginary) / denominator,
      try (a.imaginary * b.real - a.real * b.imaginary) / denominator
    )
  }

  public var exactMagnitude: Rational? {
    let value = parts
    guard case .exact(let real) = value.real, case .exact(let imaginary) = value.imaginary else {
      return nil
    }
    if imaginary.isZero { return real.absoluteValue }
    return (real * real + imaginary * imaginary).exactSquareRoot
  }

  public var magnitude: Double {
    exactMagnitude?.doubleValue
      ?? Foundation.hypot(parts.real.doubleValue, parts.imaginary.doubleValue)
  }

  public var angle: Double {
    let value = parts
    let angle = Foundation.atan2(value.imaginary.doubleValue, value.real.doubleValue)
    return angle == -.pi ? .pi : angle
  }

  public func exactPower(_ exponent: Int) throws -> Self {
    if exponent == 0 { return .one }
    if exponent < 0 {
      guard exponent != Int.min else { throw BigIntError.negativeExponent }
      return try .one / exactPower(-exponent)
    }
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

  public static func polar(magnitude: RealComponent, angle: RealComponent) -> Self {
    if angle.isZero { return rectangular(magnitude, RealComponent(0)) }
    let radius = magnitude.doubleValue
    let theta = angle.doubleValue
    return rectangular(
      .inexact(radius * Foundation.cos(theta)),
      .inexact(radius * Foundation.sin(theta))
    )
  }

  public func inexact() -> Self {
    let value = parts
    return Self.rectangular(.inexact(value.real.doubleValue), .inexact(value.imaginary.doubleValue))
  }
}
