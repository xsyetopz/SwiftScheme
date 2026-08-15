import Foundation

/// A real or rectangular complex Scheme number.
public enum SchemeNumber: Hashable, Sendable, CustomStringConvertible {
  case real(RealComponent)
  case complex(real: RealComponent, imaginary: RealComponent)

  /// The numeric value or property represented by this instance.
  public static let zero = Self.real(.exact(Rational(0)))
  /// The numeric value or property represented by this instance.
  public static let one = Self.real(.exact(Rational(1)))

  /// Creates a numeric value.
  public init(_ integer: Int64) { self = .real(.exact(Rational(integer))) }
  /// Creates a numeric value.
  public init(_ integer: BigInt) { self = .real(.exact(Rational(integer) ?? .zero)) }
  /// Creates a numeric value.
  public init(_ rational: Rational) { self = .real(.exact(rational)) }
  /// Creates a numeric value.
  public init(_ inexact: Double) { self = .real(.inexact(inexact)) }

  /// Performs the corresponding numeric operation.
  public static func rectangular(_ real: RealComponent, _ imaginary: RealComponent) -> Self {
    guard imaginary.isZero else { return .complex(real: real, imaginary: imaginary) }
    return imaginary.isExact ? .real(real) : .complex(real: real, imaginary: imaginary)
  }

  /// The numeric value or property represented by this instance.
  public var parts: (real: RealComponent, imaginary: RealComponent) {
    switch self {
    case .real(let value): (value, RealComponent(0))
    case .complex(let real, let imaginary): (real, imaginary)
    }
  }

  /// The numeric value or property represented by this instance.
  public var isExact: Bool {
    let value = parts
    return value.real.isExact && value.imaginary.isExact
  }
  /// The numeric value or property represented by this instance.
  public var isReal: Bool { parts.imaginary.isZero }
  /// The numeric value or property represented by this instance.
  public var isRational: Bool {
    guard isReal else { return false }
    if case .exact = parts.real { return true }
    return parts.real.doubleValue.isFinite
  }
  /// The numeric value or property represented by this instance.
  public var isInteger: Bool {
    guard isReal else { return false }
    switch parts.real {
    case .exact(let value): return value.isInteger
    case .inexact(let value): return value.isFinite && value.rounded() == value
    }
  }
  /// The numeric value or property represented by this instance.
  public var isZero: Bool { parts.real.isZero && parts.imaginary.isZero }

  /// The numeric value or property represented by this instance.
  public var description: String {
    switch self {
    case .real(let value): return Self.describe(value)
    case .complex(let real, let imaginary):
      let imaginaryText = Self.describe(imaginary)
      let separator = imaginaryText.hasPrefix("-") || imaginaryText.hasPrefix("+") ? "" : "+"
      return Self.describe(real) + separator + imaginaryText + "i"
    }
  }

  /// Performs the corresponding numeric operation.
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
          let numerator = rational.numerator.string(radix: radix)
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
      // R5RS requires a decimal point for finite inexact radix-10 output
      // whenever a decimal representation can satisfy the round-trip rule.
      // Swift uses exponent notation for values such as 1e20; inserting .0
      // into the mantissa keeps its shortest-round-trip digits while meeting
      // the external-number grammar requirement.
      var text = String(number)
      if let exponent = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
        if !text[..<exponent].contains(".") { text.insert(contentsOf: ".0", at: exponent) }
      } else if !text.contains(".") {
        text += ".0"
      }
      return text
    }
  }

  /// Performs the corresponding numeric operation.
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

  /// Performs the corresponding numeric operation.
  public static prefix func - (value: Self) -> Self {
    if case .real(let real) = value { return .real(-real) }
    let value = value.parts
    return rectangular(-value.real, -value.imaginary)
  }

  /// Performs the corresponding numeric operation.
  public static func + (lhs: Self, rhs: Self) -> Self {
    if lhs.isReal, rhs.isReal { return .real(lhs.parts.real + rhs.parts.real) }
    let a = lhs.parts
    let b = rhs.parts
    return rectangular(a.real + b.real, a.imaginary + b.imaginary)
  }

  /// Performs the corresponding numeric operation.
  public static func - (lhs: Self, rhs: Self) -> Self { lhs + -rhs }

  /// Performs the corresponding numeric operation.
  public static func * (lhs: Self, rhs: Self) -> Self {
    if lhs.isReal, rhs.isReal { return .real(lhs.parts.real * rhs.parts.real) }
    if lhs.isReal {
      let a = lhs.parts.real
      let b = rhs.parts
      return rectangular(a * b.real, a * b.imaginary)
    }
    if rhs.isReal {
      let a = lhs.parts
      let b = rhs.parts.real
      return rectangular(a.real * b, a.imaginary * b)
    }
    let a = lhs.parts
    let b = rhs.parts
    if !a.real.isExact || !a.imaginary.isExact || !b.real.isExact || !b.imaginary.isExact {
      let result = Self.inexactComplexProduct(
        a.real.doubleValue,
        a.imaginary.doubleValue,
        b.real.doubleValue,
        b.imaginary.doubleValue
      )
      return rectangular(.inexact(result.0), .inexact(result.1))
    }
    return rectangular(
      a.real * b.real - a.imaginary * b.imaginary,
      a.real * b.imaginary + a.imaginary * b.real
    )
  }

  /// Performs the corresponding numeric operation.
  public static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
  /// Performs the corresponding numeric operation.
  public static func -= (lhs: inout Self, rhs: Self) { lhs = lhs - rhs }
  /// Performs the corresponding numeric operation.
  public static func *= (lhs: inout Self, rhs: Self) { lhs = lhs * rhs }

  /// Performs the corresponding numeric operation.
  public static func / (lhs: Self, rhs: Self) throws -> Self {
    if lhs.isReal, rhs.isReal { return .real(try lhs.parts.real / rhs.parts.real) }
    let a = lhs.parts
    let b = rhs.parts
    if !a.real.isExact || !a.imaginary.isExact || !b.real.isExact || !b.imaginary.isExact {
      let denominator = b.real.isZero && b.imaginary.isZero
      if denominator { throw BigIntError.divisionByZero }
      let result = Self.inexactComplexQuotient(
        a.real.doubleValue,
        a.imaginary.doubleValue,
        b.real.doubleValue,
        b.imaginary.doubleValue
      )
      return rectangular(.inexact(result.0), .inexact(result.1))
    }
    let denominator = b.real * b.real + b.imaginary * b.imaginary
    guard !denominator.isZero else { throw BigIntError.divisionByZero }
    return rectangular(
      try (a.real * b.real + a.imaginary * b.imaginary) / denominator,
      try (a.imaginary * b.real - a.real * b.imaginary) / denominator
    )
  }

}
