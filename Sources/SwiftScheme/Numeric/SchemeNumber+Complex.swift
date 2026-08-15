import Foundation

extension SchemeNumber {
  package static func inexactComplexProduct(_ ar: Double, _ ai: Double, _ br: Double, _ bi: Double)
    -> (Double, Double)
  {
    let scaleA = max(abs(ar), abs(ai))
    let scaleB = max(abs(br), abs(bi))
    guard scaleA.isFinite, scaleB.isFinite, scaleA > 0, scaleB > 0 else {
      return (ar * br - ai * bi, ar * bi + ai * br)
    }
    let real = ar / scaleA * (br / scaleB) - ai / scaleA * (bi / scaleB)
    let imaginary = ar / scaleA * (bi / scaleB) + ai / scaleA * (br / scaleB)
    let scale = scaleA * scaleB
    if scale.isFinite, scale <= Double.greatestFiniteMagnitude / 2 {
      return (ar * br - ai * bi, ar * bi + ai * br)
    }
    if scale == 0 { return (ar * br - ai * bi, ar * bi + ai * br) }
    guard scale.isFinite else {
      return (
        real == 0 ? real : (real.sign == .minus ? -.infinity : .infinity),
        imaginary == 0 ? imaginary : (imaginary.sign == .minus ? -.infinity : .infinity)
      )
    }
    return (real * scale, imaginary * scale)
  }

  package static func inexactComplexQuotient(_ ar: Double, _ ai: Double, _ br: Double, _ bi: Double)
    -> (Double, Double)
  {
    let scaleA = max(abs(ar), abs(ai))
    let scaleB = max(abs(br), abs(bi))
    // A zero numerator is exactly zero for every nonzero, non-NaN
    // denominator.  The ordinary fallback below squares the denominator;
    // for tiny components that product underflows to zero and turns 0/denom
    // into NaN.  Keep the signed zero components while avoiding that loss.
    if scaleA == 0 {
      guard !br.isNaN, !bi.isNaN, scaleB > 0 else {
        let denominator = br * br + bi * bi
        return ((ar * br + ai * bi) / denominator, (ai * br - ar * bi) / denominator)
      }
      return (ar, ai)
    }
    guard scaleA.isFinite, scaleB.isFinite, scaleA > 0, scaleB > 0 else {
      let denominator = br * br + bi * bi
      return ((ar * br + ai * bi) / denominator, (ai * br - ar * bi) / denominator)
    }
    let nar = ar / scaleA
    let nai = ai / scaleA
    let nbr = br / scaleB
    let nbi = bi / scaleB
    let normalized: (Double, Double)
    if abs(nbr) >= abs(nbi) {
      guard nbr != 0 else { return (.nan, .nan) }
      let divisor = nbi / nbr
      let denominator = 1 + divisor * divisor
      normalized = (
        (nar + nai * divisor) / denominator / nbr, (nai - nar * divisor) / denominator / nbr
      )
    } else {
      guard nbi != 0 else { return (.nan, .nan) }
      let divisor = nbr / nbi
      let denominator = 1 + divisor * divisor
      normalized = (
        (nar * divisor + nai) / denominator / nbi, (nai * divisor - nar) / denominator / nbi
      )
    }
    let scale = scaleA / scaleB
    func scaled(_ value: Double) -> Double {
      guard value != 0 else { return value }
      guard scale.isFinite else { return value.sign == .minus ? -.infinity : .infinity }
      return value * scale
    }
    return (scaled(normalized.0), scaled(normalized.1))
  }

  /// Returns the exact magnitude when the rectangular components permit one.
  public var exactMagnitude: Rational? {
    let value = parts
    guard case .exact(let real) = value.real, case .exact(let imaginary) = value.imaginary else {
      return nil
    }
    if imaginary.isZero { return real.absoluteValue }
    return (real * real + imaginary * imaginary).exactSquareRoot
  }

  /// Returns the magnitude as a binary64 value.
  public var magnitude: Double {
    exactMagnitude?.doubleValue
      ?? Foundation.hypot(parts.real.doubleValue, parts.imaginary.doubleValue)
  }

  /// Returns the principal angle in the range `(-pi, pi]`.
  public var angle: Double {
    let value = parts
    let angle = Foundation.atan2(value.imaginary.doubleValue, value.real.doubleValue)
    return angle == -.pi ? .pi : angle
  }

  /// Raises the number to an exact integer power.
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

  /// Constructs a number from magnitude and angle components.
  public static func polar(magnitude: RealComponent, angle: RealComponent) -> Self {
    if angle.isZero {
      guard !angle.isExact else { return rectangular(magnitude, RealComponent(0)) }
      return rectangular(
        .inexact(magnitude.doubleValue),
        .inexact(magnitude.doubleValue * angle.doubleValue)
      )
    }
    let radius = magnitude.doubleValue
    let theta = angle.doubleValue
    return rectangular(
      .inexact(radius * Foundation.cos(theta)),
      .inexact(radius * Foundation.sin(theta))
    )
  }

  /// Converts every numeric component to an inexact representation.
  public func inexact() -> Self {
    switch self {
    case .real(let value): return .real(.inexact(value.doubleValue))
    case .complex:
      let value = parts
      return .complex(
        real: .inexact(value.real.doubleValue),
        imaginary: .inexact(value.imaginary.doubleValue)
      )
    }
  }
}
