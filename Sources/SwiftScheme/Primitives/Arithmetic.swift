import Foundation
import SwiftSchemeNumeric
import SwiftSchemeRuntime

package func require(_ values: [Value], _ count: Int, _ name: String) throws {
  guard values.count == count else { throw SchemeError.arity("\(name) expects \(count) arguments") }
}

package func schemeNumber(_ value: Value) throws -> SchemeNumber {
  guard let number = schemeNumberValue(value) else {
    throw SchemeError.type("expected number, got \(value.written)")
  }
  return number
}

package func numberValue(_ number: SchemeNumber) -> Value {
  switch number {
  case .real(.exact(let rational)):
    return rational.isInteger ? .integer(rational.numerator) : .rational(rational)
  case .real(.inexact(let real)): return .real(real)
  case .complex(let real, let imaginary): return .complex(real: real, imaginary: imaginary)
  }
}

package func number(_ value: Value) throws -> Double {
  let number = try schemeNumber(value)
  guard number.isReal else { throw SchemeError.type("expected real number") }
  return number.parts.real.doubleValue
}

package func exactInteger(_ value: Value, _ context: String) throws -> BigInt {
  guard let number = try? schemeNumber(value), number.isExact, number.parts.imaginary.isZero,
    case .exact(let rational) = number.parts.real, rational.isInteger
  else { throw SchemeError.type("\(context) expects an exact integer") }
  return rational.numerator
}

package func exactIntegerExponent(_ number: SchemeNumber) -> BigInt? {
  guard number.isExact, number.parts.imaginary.isZero,
    case .exact(let rational) = number.parts.real, rational.isInteger
  else { return nil }
  return rational.numerator
}

package func integerComponent(_ value: Value, _ context: String) throws -> (
  value: BigInt, inexact: Bool
) {
  switch try realComponent(value, context) {
  case .exact(let rational):
    guard rational.isInteger else { throw SchemeError.type("\(context) expects an integer") }
    return (rational.numerator, false)
  case .inexact(let real):
    guard let rational = Rational.fromFiniteDouble(real), rational.isInteger else {
      throw SchemeError.type("\(context) expects an integer")
    }
    return (rational.numerator, true)
  }
}

package func realComponent(_ value: Value, _ context: String) throws -> RealComponent {
  let number = try schemeNumber(value)
  guard number.isReal else { throw SchemeError.type("\(context) expects a real number") }
  return number.parts.real
}

package func rationalComponent(_ value: Value, _ context: String) throws -> (Rational, Bool) {
  switch try realComponent(value, context) {
  case .exact(let rational): return (rational, false)
  case .inexact(let real):
    guard let rational = Rational.fromFiniteDouble(real) else {
      throw SchemeError.numeric("\(context) expects a finite rational")
    }
    return (rational, true)
  }
}

package func isNumber(_ value: Value) -> Bool { (try? schemeNumber(value)) != nil }

package func predicate(_ args: [Value], _ name: String, _ test: (Value) -> Bool) throws -> Value {
  try require(args, 1, name)
  return .boolean(test(args[0]))
}

package func requiredRational(_ numerator: BigInt, _ denominator: BigInt = .one) -> Rational {
  guard let value = Rational(numerator, denominator) else {
    preconditionFailure("Rational invariant violated")
  }
  return value
}

package func requiredRationalDivision(_ lhs: Rational, _ rhs: Rational) -> Rational {
  guard let value = try? lhs / rhs else { preconditionFailure("Rational invariant violated") }
  return value
}

package func compareReal(_ lhs: RealComponent, _ rhs: RealComponent) -> Int? {
  switch (lhs, rhs) {
  case (.exact(let a), .exact(let b)): return a == b ? 0 : (a < b ? -1 : 1)
  case (.inexact(let a), .inexact(let b)):
    guard !a.isNaN, !b.isNaN else { return nil }
    return a == b ? 0 : (a < b ? -1 : 1)
  case (.exact(let a), .inexact(let b)):
    guard !b.isNaN else { return nil }
    if b == .infinity { return -1 }
    if b == -.infinity { return 1 }
    guard let exactB = Rational.fromFiniteDouble(b) else { return nil }
    return a == exactB ? 0 : (a < exactB ? -1 : 1)
  case (.inexact(let a), .exact(let b)):
    guard let comparison = compareReal(.exact(b), .inexact(a)) else { return nil }
    return -comparison
  }
}

package func indexRadix(_ value: Value, _ context: String) throws -> Int {
  guard let radix = try exactInteger(value, context).exactInt, [2, 8, 10, 16].contains(radix) else {
    throw SchemeError.numeric("\(context) requires radix 2, 8, 10, or 16")
  }
  return radix
}

package func exactNumber(_ number: SchemeNumber) throws -> SchemeNumber {
  let parts = number.parts
  func exact(_ component: RealComponent) throws -> RealComponent {
    switch component {
    case .exact: return component
    case .inexact(let value):
      guard let rational = Rational.fromFiniteDouble(value) else {
        throw SchemeError.numeric("cannot represent non-finite exact value")
      }
      return .exact(rational)
    }
  }
  return .rectangular(try exact(parts.real), try exact(parts.imaginary))
}

package struct InexactComplex {
  var real: Double
  var imaginary: Double
}
package func inexactComplex(_ number: SchemeNumber) -> InexactComplex {
  let p = number.parts
  return InexactComplex(real: p.real.doubleValue, imaginary: p.imaginary.doubleValue)
}
package func complexExp(_ z: InexactComplex) -> InexactComplex {
  let scale = Foundation.exp(z.real)
  let sine = Foundation.sin(z.imaginary)
  return InexactComplex(
    real: scale * Foundation.cos(z.imaginary),
    imaginary: sine == 0 ? sine : scale * sine
  )
}
package func complexLog(_ z: InexactComplex) -> InexactComplex {
  let real: Double
  if z.real.isInfinite || z.imaginary.isInfinite {
    real = .infinity
  } else {
    let scale = max(abs(z.real), abs(z.imaginary))
    real =
      scale == 0
      ? -.infinity
      : Foundation.log(scale)
        + Foundation.log(Foundation.hypot(z.real / scale, z.imaginary / scale))
  }
  let angle = Foundation.atan2(z.imaginary, z.real)
  return InexactComplex(real: real, imaginary: angle == -.pi ? .pi : angle)
}
package func complexMultiply(_ a: InexactComplex, _ b: InexactComplex) -> InexactComplex {
  let result = SchemeNumber.inexactComplexProduct(a.real, a.imaginary, b.real, b.imaginary)
  return InexactComplex(real: result.0, imaginary: result.1)
}
package func complexDivide(_ a: InexactComplex, _ b: InexactComplex) -> InexactComplex {
  let result = SchemeNumber.inexactComplexQuotient(a.real, a.imaginary, b.real, b.imaginary)
  return InexactComplex(real: result.0, imaginary: result.1)
}
package func fromComplex(_ z: InexactComplex) -> SchemeNumber {
  .rectangular(.inexact(z.real), .inexact(z.imaginary))
}
package func complexSqrt(_ number: SchemeNumber) -> SchemeNumber {
  let parts = number.parts
  if case .exact(let real) = parts.real, case .exact(let imaginary) = parts.imaginary {
    if imaginary.isZero {
      if let root = real.exactSquareRoot { return SchemeNumber(root) }
      if real.signum < 0, let root = (-real).exactSquareRoot {
        return .complex(real: .exact(.zero), imaginary: .exact(root))
      }
    } else if let magnitude = number.exactMagnitude,
      let rootReal = (try? (magnitude + real) / Rational(2))?.exactSquareRoot,
      let rootImaginary = (try? (magnitude - real) / Rational(2))?.exactSquareRoot
    {
      return .complex(
        real: .exact(rootReal),
        imaginary: .exact(imaginary.signum < 0 ? -rootImaginary : rootImaginary)
      )
    }
  }
  let z = inexactComplex(number)
  if z.imaginary == 0 && z.real >= 0 { return SchemeNumber(Foundation.sqrt(z.real)) }
  if z.imaginary == 0 && z.real == -.infinity {
    return fromComplex(InexactComplex(real: 0, imaginary: .infinity))
  }
  if z.real == .infinity {
    if z.imaginary.isFinite {
      return fromComplex(
        InexactComplex(real: .infinity, imaginary: z.imaginary.sign == .minus ? -0.0 : 0.0)
      )
    }
    return fromComplex(
      InexactComplex(
        real: .infinity,
        imaginary: z.imaginary.sign == .minus ? -.infinity : .infinity
      )
    )
  }
  if z.real == -.infinity {
    if z.imaginary.isFinite {
      return fromComplex(
        InexactComplex(real: 0, imaginary: z.imaginary.sign == .minus ? -.infinity : .infinity)
      )
    }
    return fromComplex(
      InexactComplex(
        real: .infinity,
        imaginary: z.imaginary.sign == .minus ? -.infinity : .infinity
      )
    )
  }
  if z.imaginary == .infinity {
    return fromComplex(InexactComplex(real: .infinity, imaginary: .infinity))
  }
  if z.imaginary == -.infinity {
    return fromComplex(InexactComplex(real: .infinity, imaginary: -.infinity))
  }
  if z.imaginary == 0 && z.real < 0 {
    return fromComplex(InexactComplex(real: 0, imaginary: Foundation.sqrt(-z.real)))
  }

  let scale = max(abs(z.real), abs(z.imaginary))
  guard scale > 0, scale.isFinite else {
    return fromComplex(InexactComplex(real: .nan, imaginary: .nan))
  }
  let normalizedReal = z.real / scale
  let normalizedImaginary = z.imaginary / scale
  let radius = Foundation.hypot(normalizedReal, normalizedImaginary)
  let rootReal: Double
  let rootImaginary: Double
  if normalizedReal >= 0 {
    rootReal = Foundation.sqrt(0.5 * (radius + normalizedReal))
    rootImaginary = normalizedImaginary / (2 * rootReal)
  } else {
    rootImaginary =
      (normalizedImaginary.sign == .minus ? -1.0 : 1.0)
      * Foundation.sqrt(0.5 * (radius - normalizedReal))
    rootReal = abs(normalizedImaginary) / (2 * abs(rootImaginary))
  }
  let rootScale = Foundation.sqrt(scale)
  return fromComplex(
    InexactComplex(real: rootScale * rootReal, imaginary: rootScale * rootImaginary)
  )
}

package func exactNegativeUnitHalfPower(_ base: SchemeNumber, _ exponent: SchemeNumber)
  -> SchemeNumber?
{
  guard base.isExact, base.isReal, case .exact(let baseReal) = base.parts.real, baseReal.isInteger,
    baseReal.numerator == -BigInt.one, exponent.isExact, exponent.parts.imaginary.isZero,
    case .exact(let power) = exponent.parts.real, power.denominator == BigInt(2),
    let magnitudeRemainder = try? power.numerator.magnitudeModulo(4)
  else { return nil }
  let remainder = power.numerator.signum < 0 ? (4 - magnitudeRemainder) % 4 : magnitudeRemainder
  switch remainder {
  case 0: return SchemeNumber.one
  case 1: return .rectangular(.exact(.zero), .exact(.one))
  case 2: return SchemeNumber(Int64(-1))
  default: return .rectangular(.exact(.zero), .exact(Rational(-1)))
  }
}

package func exactRationalPower(_ base: SchemeNumber, _ exponent: SchemeNumber) -> SchemeNumber? {
  guard base.isExact, exponent.isExact, exponent.parts.imaginary.isZero,
    case .exact(let power) = exponent.parts.real, let numerator = power.numerator.exactInt,
    let denominator = power.denominator.exactInt, denominator > 1
  else { return nil }
  if denominator == 2 {
    let root = complexSqrt(base)
    guard root.isExact else { return nil }
    return try? root.exactPower(numerator)
  }
  guard case .exact(let real) = base.parts.real, base.parts.imaginary.isZero,
    !(denominator % 2 == 1 && real.signum < 0),
    let rootNumerator = real.numerator.exactNthRoot(denominator),
    let rootDenominator = real.denominator.exactNthRoot(denominator),
    let root = Rational(rootNumerator, rootDenominator)
  else { return nil }
  return try? SchemeNumber(root).exactPower(numerator)
}

package func complexPower(_ base: SchemeNumber, _ exponent: SchemeNumber) -> SchemeNumber {
  if base.isReal, exponent.isReal {
    let baseReal = base.parts.real.doubleValue
    let exponentReal = exponent.parts.real.doubleValue
    if baseReal == .infinity { return .real(.inexact(exponentReal > 0 ? .infinity : 0)) }
    if baseReal == -.infinity, exponentReal.isFinite, exponentReal != 0 {
      let magnitude: Double = exponentReal > 0 ? .infinity : 0
      let doubled = exponentReal * 2
      if doubled.isFinite, doubled.rounded() == doubled, doubled >= Double(Int.min),
        doubled <= Double(Int.max)
      {
        let half = Int(doubled)
        switch ((half % 4) + 4) % 4 {
        case 0: return fromComplex(InexactComplex(real: magnitude, imaginary: 0))
        case 1: return fromComplex(InexactComplex(real: 0, imaginary: magnitude))
        case 2: return fromComplex(InexactComplex(real: -magnitude, imaginary: 0))
        default: return fromComplex(InexactComplex(real: 0, imaginary: -magnitude))
        }
      }
      let phase = Double.pi * exponentReal
      return fromComplex(
        InexactComplex(
          real: magnitude * Foundation.cos(phase),
          imaginary: magnitude * Foundation.sin(phase)
        )
      )
    }
    if baseReal > 0 { return .real(.inexact(Foundation.pow(baseReal, exponentReal))) }
  }
  return fromComplex(
    complexExp(complexMultiply(inexactComplex(exponent), complexLog(inexactComplex(base))))
  )
}
package func complexTranscendental(_ name: String, _ number: SchemeNumber) -> SchemeNumber {
  let parts = number.parts
  if number.isReal {
    let real = parts.real.doubleValue
    switch name {
    case "exp": return .real(.inexact(Foundation.exp(real)))
    case "log" where real >= 0: return .real(.inexact(Foundation.log(real)))
    case "sin": return .real(.inexact(Foundation.sin(real)))
    case "cos": return .real(.inexact(Foundation.cos(real)))
    case "tan": return .real(.inexact(Foundation.tan(real)))
    case "asin" where abs(real) <= 1: return .real(.inexact(Foundation.asin(real)))
    case "acos" where abs(real) <= 1: return .real(.inexact(Foundation.acos(real)))
    default: break
    }
  }
  let z = inexactComplex(number)
  let iZ = InexactComplex(real: -z.imaginary, imaginary: z.real)
  let minusIZ = InexactComplex(real: z.imaginary, imaginary: -z.real)
  switch name {
  case "exp": return fromComplex(complexExp(z))
  case "log": return fromComplex(complexLog(z))
  case "sin":
    let a = complexExp(iZ)
    let b = complexExp(minusIZ)
    return fromComplex(
      InexactComplex(real: (a.imaginary - b.imaginary) / 2, imaginary: (b.real - a.real) / 2)
    )
  case "cos":
    let a = complexExp(iZ)
    let b = complexExp(minusIZ)
    return fromComplex(
      InexactComplex(real: (a.real + b.real) / 2, imaginary: (a.imaginary + b.imaginary) / 2)
    )
  case "tan":
    let doubledReal = 2 * Foundation.remainder(z.real, Double.pi)
    let doubledImaginary = 2 * z.imaginary
    let decay = Foundation.exp(-abs(doubledImaginary))
    if decay == 0 {
      return fromComplex(
        InexactComplex(real: 0, imaginary: doubledImaginary.sign == .minus ? -1.0 : 1.0)
      )
    }
    let cosine = Foundation.cos(doubledReal)
    let denominator = 1 + 2 * decay * cosine + decay * decay
    return fromComplex(
      InexactComplex(
        real: 2 * decay * Foundation.sin(doubledReal) / denominator,
        imaginary: (doubledImaginary.sign == .minus ? -1.0 : 1.0) * (1 - decay * decay)
          / denominator
      )
    )
  case "asin":
    if z.imaginary == 0, z.real > 1 {
      return fromComplex(InexactComplex(real: .pi / 2, imaginary: -Foundation.acosh(z.real)))
    }
    if z.imaginary == 0, z.real < -1 {
      return fromComplex(InexactComplex(real: -.pi / 2, imaginary: Foundation.acosh(-z.real)))
    }
    let scale = max(abs(z.real), abs(z.imaginary))
    let directLog: () -> InexactComplex = {
      let square = complexMultiply(z, z)
      let root = inexactComplex(
        complexSqrt(
          fromComplex(InexactComplex(real: 1 - square.real, imaginary: -square.imaginary))
        )
      )
      return complexLog(
        InexactComplex(real: root.real - z.imaginary, imaginary: root.imaginary + z.real)
      )
    }
    let logged: InexactComplex
    if scale > 1, scale <= 1e6 {
      logged = directLog()
    } else if scale > 1, scale.isFinite {
      let normalizedReal = z.real / scale
      let normalizedImaginary = z.imaginary / scale
      let inverseScaleSquared =
        scale <= Foundation.sqrt(Double.greatestFiniteMagnitude) ? 1 / (scale * scale) : 0
      let square = InexactComplex(
        real: normalizedReal * normalizedReal - normalizedImaginary * normalizedImaginary,
        imaginary: 2 * normalizedReal * normalizedImaginary
      )
      let root = inexactComplex(
        complexSqrt(
          fromComplex(
            InexactComplex(real: inverseScaleSquared - square.real, imaginary: -square.imaginary)
          )
        )
      )
      let argument = InexactComplex(
        real: root.real - normalizedImaginary,
        imaginary: root.imaginary + normalizedReal
      )
      if Foundation.hypot(argument.real, argument.imaginary) < 1e-14 {
        let rootMagnitudeSquared = root.real * root.real + root.imaginary * root.imaginary
        let correctionScale = 1 / scale / (2 * rootMagnitudeSquared)
        logged = complexLog(
          InexactComplex(
            real: correctionScale * root.real,
            imaginary: -correctionScale * root.imaginary
          )
        )
      } else {
        let normalizedLog = complexLog(argument)
        logged = InexactComplex(
          real: Foundation.log(scale) + normalizedLog.real,
          imaginary: normalizedLog.imaginary
        )
      }
    } else {
      logged = directLog()
    }
    return fromComplex(InexactComplex(real: logged.imaginary, imaginary: -logged.real))
  case "acos":
    let asin = inexactComplex(complexTranscendental("asin", number))
    return fromComplex(InexactComplex(real: Double.pi / 2 - asin.real, imaginary: -asin.imaginary))
  default:
    let oneMinus = complexLog(InexactComplex(real: 1 + z.imaginary, imaginary: -z.real))
    let onePlus = complexLog(InexactComplex(real: 1 - z.imaginary, imaginary: z.real))
    return fromComplex(
      InexactComplex(
        real: (onePlus.imaginary - oneMinus.imaginary) / 2,
        imaginary: (oneMinus.real - onePlus.real) / 2
      )
    )
  }
}

package func rationalized(_ value: Value, _ tolerance: Value) throws -> SchemeNumber {
  let x = try rationalComponent(value, "rationalize")
  let y = try rationalComponent(tolerance, "rationalize")
  let low = x.0 - y.0.absoluteValue
  let high = x.0 + y.0.absoluteValue
  func simplest(_ a: Rational, _ b: Rational) -> Rational {
    if a.signum < 0 && b.signum < 0 { return -simplest(-b, -a) }
    if a.signum <= 0 && b.signum >= 0 { return Rational(0) }
    let floorA = a.rounded(.floor)
    let floorB = b.rounded(.floor)
    if floorA < floorB { return requiredRational(floorA + .one) }
    let fractionalA = a - requiredRational(floorA)
    let fractionalB = b - requiredRational(floorB)
    if fractionalA.isZero { return requiredRational(floorA) }
    let reciprocal = simplest(
      requiredRationalDivision(.one, fractionalB),
      requiredRationalDivision(.one, fractionalA)
    )
    return requiredRational(floorA) + requiredRationalDivision(.one, reciprocal)
  }
  let result = simplest(low, high)
  return x.1 || y.1 ? SchemeNumber(result).inexact() : SchemeNumber(result)
}
