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

package func exactIntegerExponent(_ number: SchemeNumber) -> Int? {
  guard number.isExact, number.parts.imaginary.isZero,
    case .exact(let rational) = number.parts.real, rational.isInteger
  else { return nil }
  return rational.numerator.exactInt
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
    let exactB = Rational.fromFiniteDouble(b)!
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
  let angle = Foundation.atan2(z.imaginary, z.real)
  return InexactComplex(
    real: Foundation.log(Foundation.hypot(z.real, z.imaginary)),
    imaginary: angle == -.pi ? .pi : angle
  )
}
package func complexMultiply(_ a: InexactComplex, _ b: InexactComplex) -> InexactComplex {
  InexactComplex(
    real: a.real * b.real - a.imaginary * b.imaginary,
    imaginary: a.real * b.imaginary + a.imaginary * b.real
  )
}
package func complexDivide(_ a: InexactComplex, _ b: InexactComplex) -> InexactComplex {
  let d = b.real * b.real + b.imaginary * b.imaginary
  return InexactComplex(
    real: (a.real * b.real + a.imaginary * b.imaginary) / d,
    imaginary: (a.imaginary * b.real - a.real * b.imaginary) / d
  )
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
  let magnitude = Foundation.hypot(z.real, z.imaginary)
  let real = Foundation.sqrt((magnitude + z.real) / 2)
  let imaginary =
    (z.imaginary.sign == .minus ? -1.0 : 1.0) * Foundation.sqrt((magnitude - z.real) / 2)
  return fromComplex(InexactComplex(real: real, imaginary: imaginary))
}
package func complexPower(_ base: SchemeNumber, _ exponent: SchemeNumber) -> SchemeNumber {
  fromComplex(
    complexExp(complexMultiply(inexactComplex(exponent), complexLog(inexactComplex(base))))
  )
}
package func complexTranscendental(_ name: String, _ number: SchemeNumber) -> SchemeNumber {
  let parts = number.parts
  if parts.imaginary.isZero, parts.real.doubleValue.isFinite {
    let real = parts.real.doubleValue
    switch name {
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
    let s = complexTranscendental("sin", number)
    let c = complexTranscendental("cos", number)
    return fromComplex(complexDivide(inexactComplex(s), inexactComplex(c)))
  case "asin":
    let root = inexactComplex(
      complexSqrt(
        fromComplex(
          InexactComplex(
            real: 1 - z.real * z.real + z.imaginary * z.imaginary,
            imaginary: -2 * z.real * z.imaginary
          )
        )
      )
    )
    let logged = complexLog(
      InexactComplex(real: root.real - z.imaginary, imaginary: root.imaginary + z.real)
    )
    return fromComplex(InexactComplex(real: logged.imaginary, imaginary: -logged.real))
  case "acos":
    let asin = inexactComplex(complexTranscendental("asin", number))
    return fromComplex(InexactComplex(real: Double.pi / 2 - asin.real, imaginary: -asin.imaginary))
  default:
    let oneMinus = fromComplex(InexactComplex(real: 1 + z.imaginary, imaginary: -z.real))
    let onePlus = fromComplex(InexactComplex(real: 1 - z.imaginary, imaginary: z.real))
    let quotient = complexDivide(inexactComplex(oneMinus), inexactComplex(onePlus))
    let logged = complexLog(quotient)
    return fromComplex(InexactComplex(real: -logged.imaginary / 2, imaginary: logged.real / 2))
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
    if floorA < floorB { return Rational(floorA + .one)! }
    let fractionalA = a - Rational(floorA)!
    let fractionalB = b - Rational(floorB)!
    if fractionalA.isZero { return Rational(floorA)! }
    let reciprocal = simplest(try! (Rational.one / fractionalB), try! (Rational.one / fractionalA))
    return Rational(floorA)! + (try! (Rational.one / reciprocal))
  }
  let result = simplest(low, high)
  return x.1 || y.1 ? SchemeNumber(result).inexact() : SchemeNumber(result)
}
