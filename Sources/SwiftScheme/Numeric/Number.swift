import Foundation

/// A normalized exact rational number.
public struct Rational: Hashable, Sendable, Comparable, CustomStringConvertible {
  /// The numeric value or property represented by this instance.
  public static let zero = Self(0)
  /// The numeric value or property represented by this instance.
  public static let one = Self(1)
  /// The numeric value or property represented by this instance.
  public let numerator: BigInt
  /// The numeric value or property represented by this instance.
  public let denominator: BigInt

  /// Creates a numeric value.
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

  /// Creates a numeric value.
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

  /// The numeric value or property represented by this instance.
  public var isInteger: Bool { denominator == .one }
  /// The numeric value or property represented by this instance.
  public var isZero: Bool { numerator.isZero }
  /// The numeric value or property represented by this instance.
  public var signum: Int { numerator.signum }
  /// The numeric value or property represented by this instance.
  public var absoluteValue: Self { Self.make(numerator.absoluteValue, denominator) }
  /// The numeric value or property represented by this instance.
  public var doubleValue: Double {
    guard !numerator.isZero else { return 0 }

    // Round the exact ratio to binary64, rather than dividing separately
    // rounded approximations of the numerator and denominator. The latter
    // can be one ulp wrong near a tie.
    let numerator = self.numerator.absoluteValue
    let denominator = self.denominator
    func compareWithPowerOfTwo(_ exponent: Int) -> Int {
      if exponent >= 0 {
        let scaledDenominator = denominator.shiftedLeft(exponent)
        return numerator < scaledDenominator ? -1 : (numerator == scaledDenominator ? 0 : 1)
      }
      let scaledNumerator = numerator.shiftedLeft(-exponent)
      return scaledNumerator < denominator ? -1 : (scaledNumerator == denominator ? 0 : 1)
    }

    // The bit-width difference is within one of floor(log2(numerator /
    // denominator)); correct that estimate with exact comparisons.
    var exponent = numerator.bitWidth - denominator.bitWidth
    while compareWithPowerOfTwo(exponent) < 0 { exponent -= 1 }
    while compareWithPowerOfTwo(exponent + 1) >= 0 { exponent += 1 }

    func roundedQuotient(_ dividend: BigInt, _ divisor: BigInt) -> BigInt {
      guard let division = try? dividend.quotientAndRemainder(dividingBy: divisor) else {
        preconditionFailure("Rational invariant violated")
      }
      var quotient = division.quotient
      let twiceRemainder = division.remainder * BigInt(2)
      if twiceRemainder > divisor
        || (twiceRemainder == divisor && (try? quotient.magnitudeModulo(2)) == 1)
      {
        quotient += .one
      }
      return quotient
    }

    let significand: BigInt
    if exponent < -1022 {
      // Subnormal values are integral multiples of 2^-1074.
      significand = roundedQuotient(numerator.shiftedLeft(1074), denominator)
      if significand.isZero { return self.numerator.signum < 0 ? -0.0 : 0.0 }
      let value = Foundation.scalbn(significand.doubleValue, -1074)
      return self.numerator.signum < 0 ? -value : value
    }

    let shift = 52 - exponent
    let dividend = shift >= 0 ? numerator.shiftedLeft(shift) : numerator
    let divisor = shift >= 0 ? denominator : denominator.shiftedLeft(-shift)
    var rounded = roundedQuotient(dividend, divisor)
    if rounded == BigInt(1).shiftedLeft(53) {
      rounded = BigInt(1).shiftedLeft(52)
      exponent += 1
    }
    let value = Foundation.scalbn(rounded.doubleValue, Int32(clamping: exponent - 52))
    return self.numerator.signum < 0 ? -value : value
  }
  /// The numeric value or property represented by this instance.
  public var description: String {
    isInteger ? numerator.description : "\(numerator)/\(denominator)"
  }

  /// Performs the corresponding numeric operation.
  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator
  }

  /// Performs the corresponding numeric operation.
  public static prefix func - (value: Self) -> Self {
    Self.make(-value.numerator, value.denominator)
  }

  /// Performs the corresponding numeric operation.
  public static func + (lhs: Self, rhs: Self) -> Self {
    Self.make(
      lhs.numerator * rhs.denominator + rhs.numerator * lhs.denominator,
      lhs.denominator * rhs.denominator
    )
  }

  /// Performs the corresponding numeric operation.
  public static func - (lhs: Self, rhs: Self) -> Self { lhs + -rhs }

  /// Performs the corresponding numeric operation.
  public static func * (lhs: Self, rhs: Self) -> Self {
    Self.make(lhs.numerator * rhs.numerator, lhs.denominator * rhs.denominator)
  }

  /// Performs the corresponding numeric operation.
  public static func / (lhs: Self, rhs: Self) throws -> Self {
    guard !rhs.isZero else { throw BigIntError.divisionByZero }
    return Self.make(lhs.numerator * rhs.denominator, lhs.denominator * rhs.numerator)
  }

  /// Performs the corresponding numeric operation.
  public func power(_ exponent: Int) throws -> Self {
    if exponent >= 0 {
      return Self.make(try numerator.power(exponent), try denominator.power(exponent))
    }
    guard !isZero else { throw BigIntError.divisionByZero }
    guard exponent != Int.min else { throw BigIntError.negativeExponent }
    return Self.make(try denominator.power(-exponent), try numerator.power(-exponent))
  }

  /// The numeric value or property represented by this instance.
  public var exactSquareRoot: Self? {
    guard signum >= 0, let numerator = numerator.exactSquareRoot,
      let denominator = denominator.exactSquareRoot
    else { return nil }
    return Self(numerator, denominator)
  }

  /// A numeric rounding or classification choice.
  public enum Rounding { case floor, ceiling, truncate, nearestEven }

  /// Performs the corresponding numeric operation.
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

  /// Performs the corresponding numeric operation.
  public static func exactDecimal(significand: BigInt, fractionalDigits: Int, exponent: Int)
    -> Self?
  {
    guard fractionalDigits >= 0 else { return nil }
    let (scale, overflow) = fractionalDigits.subtractingReportingOverflow(exponent)
    guard !overflow else { return nil }
    if scale <= 0 {
      guard scale != Int.min, let power = try? BigInt(10).power(-scale) else { return nil }
      return Self(significand * power)
    }
    guard let power = try? BigInt(10).power(scale) else { return nil }
    return Self(significand, power)
  }

  /// Performs the corresponding numeric operation.
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
