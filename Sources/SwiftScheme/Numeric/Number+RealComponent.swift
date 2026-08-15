import Foundation

/// A real component with exact or binary floating-point precision.
public enum RealComponent: Hashable, Sendable {
  case exact(Rational)
  case inexact(Double)

  /// Creates a numeric value.
  public init(_ integer: Int64) { self = .exact(Rational(integer)) }
  /// The numeric value or property represented by this instance.
  public var isExact: Bool { if case .exact = self { true } else { false } }
  /// The numeric value or property represented by this instance.
  public var doubleValue: Double {
    switch self {
    case .exact(let value): value.doubleValue
    case .inexact(let value): value
    }
  }
  /// The numeric value or property represented by this instance.
  public var isZero: Bool {
    switch self {
    case .exact(let value): value.isZero
    case .inexact(let value): value == 0
    }
  }
  /// The numeric value or property represented by this instance.
  public var signum: Int {
    switch self {
    case .exact(let value): value.signum
    case .inexact(let value): value.isNaN ? 0 : (value == 0 ? 0 : (value < 0 ? -1 : 1))
    }
  }

  /// Performs the corresponding numeric operation.
  public static prefix func - (value: Self) -> Self {
    switch value {
    case .exact(let x): .exact(-x)
    case .inexact(let x): .inexact(-x)
    }
  }

  /// Performs the corresponding numeric operation.
  public static func + (lhs: Self, rhs: Self) -> Self {
    switch (lhs, rhs) {
    case (.exact(let a), .exact(let b)): .exact(a + b)
    default: .inexact(lhs.doubleValue + rhs.doubleValue)
    }
  }

  /// Performs the corresponding numeric operation.
  public static func - (lhs: Self, rhs: Self) -> Self { lhs + -rhs }

  /// Performs the corresponding numeric operation.
  public static func * (lhs: Self, rhs: Self) -> Self {
    switch (lhs, rhs) {
    case (.exact(let a), .exact(let b)): .exact(a * b)
    default: .inexact(lhs.doubleValue * rhs.doubleValue)
    }
  }

  /// Performs the corresponding numeric operation.
  public static func / (lhs: Self, rhs: Self) throws -> Self {
    guard !rhs.isZero else { throw BigIntError.divisionByZero }
    switch (lhs, rhs) {
    case (.exact(let a), .exact(let b)): return .exact(try a / b)
    default: return .inexact(lhs.doubleValue / rhs.doubleValue)
    }
  }
}
