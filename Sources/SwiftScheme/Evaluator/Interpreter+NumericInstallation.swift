import Foundation
import SwiftSchemeFrontend
import SwiftSchemeNumeric
import SwiftSchemePrimitives
import SwiftSchemeRuntime

extension Interpreter {
  func installNumericPrimitives(in env: SchemeEnvironment) {
    primitive("+", in: env) { args in
      var result = SchemeNumber.zero
      for value in args { result = result + (try schemeNumber(value)) }
      return numberValue(result)
    }
    primitive("*", in: env) { args in
      var result = SchemeNumber.one
      for value in args { result = result * (try schemeNumber(value)) }
      return numberValue(result)
    }
    primitive("-", in: env) { args in
      guard let first = args.first else { throw SchemeError.arity("- expects at least 1 argument") }
      var result = try schemeNumber(first)
      if args.count == 1 { return numberValue(-result) }
      for value in args.dropFirst() { result = result - (try schemeNumber(value)) }
      return numberValue(result)
    }
    primitive("/", in: env) { args in
      guard let first = args.first else { throw SchemeError.arity("/ expects at least 1 argument") }
      var result = args.count == 1 ? SchemeNumber.one : try schemeNumber(first)
      for value in args.count == 1 ? args[...] : args.dropFirst() {
        do { result = try result / schemeNumber(value) } catch {
          throw SchemeError.numeric("division by zero")
        }
      }
      return numberValue(result)
    }
    for name in ["=", "<", ">", "<=", ">="] {
      primitive(name, in: env) { args in
        guard args.count >= 2 else {
          throw SchemeError.arity("\(name) expects at least 2 arguments")
        }
        let values = try args.map(schemeNumber)
        if name == "=" {
          return .boolean(zip(values, values.dropFirst()).allSatisfy(SchemeNumber.numericallyEqual))
        }
        let reals = try values.map { value -> RealComponent in
          guard value.isReal else { throw SchemeError.type("\(name) expects real numbers") }
          return value.parts.real
        }
        return .boolean(
          zip(reals, reals.dropFirst()).allSatisfy { a, b in
            guard let comparison = compareReal(a, b) else { return false }
            switch name {
            case "<": return comparison < 0
            case ">": return comparison > 0
            case "<=": return comparison <= 0
            default: return comparison >= 0
            }
          }
        )
      }
    }
    primitive("zero?", in: env) {
      try require($0, 1, "zero?")
      return .boolean(try schemeNumber($0[0]).isZero)
    }
    primitive("positive?", in: env) {
      try require($0, 1, "positive?")
      return .boolean(try realComponent($0[0], "positive?").signum > 0)
    }
    primitive("negative?", in: env) {
      try require($0, 1, "negative?")
      return .boolean(try realComponent($0[0], "negative?").signum < 0)
    }
    primitive("odd?", in: env) {
      try require($0, 1, "odd?")
      return .boolean(try integerComponent($0[0], "odd?").value.magnitudeModulo(2) == 1)
    }
    primitive("even?", in: env) {
      try require($0, 1, "even?")
      return .boolean(try integerComponent($0[0], "even?").value.magnitudeModulo(2) == 0)
    }
    primitive("abs", in: env) { args in
      try require(args, 1, "abs")
      let n = try schemeNumber(args[0])
      if n.isReal {
        let r = n.parts.real
        return numberValue(.real(r.signum < 0 ? -r : r))
      }
      return .real(n.magnitude)
    }
    for name in ["max", "min"] {
      primitive(name, in: env) { args in
        guard !args.isEmpty else { throw SchemeError.arity("\(name) expects arguments") }
        let values = try args.map { (try schemeNumber($0), try realComponent($0, name)) }
        var selected = values[0]
        for candidate in values.dropFirst() {
          guard let comparison = compareReal(selected.1, candidate.1) else {
            selected = candidate
            continue
          }
          if name == "max" ? comparison < 0 : comparison > 0 { selected = candidate }
        }
        let anyInexact = values.contains { !$0.1.isExact }
        return numberValue(anyInexact ? selected.0.inexact() : selected.0)
      }
    }
    for (name, operation) in [
      ("quotient", { try $0.quotient(dividingBy: $1) }),
      ("remainder", { try $0.remainder(dividingBy: $1) }), ("modulo", { try $0.modulo($1) })
    ] as [(String, (BigInt, BigInt) throws -> BigInt)] {
      primitive(name, in: env) { args in
        try require(args, 2, name)
        let a = try integerComponent(args[0], name)
        let b = try integerComponent(args[1], name)
        do {
          let result = try operation(a.value, b.value)
          return a.inexact || b.inexact ? .real(result.doubleValue) : .integer(result)
        } catch { throw SchemeError.numeric("division by zero") }
      }
    }
    primitive("gcd", in: env) { args in
      var result = BigInt.zero
      var inexact = false
      for value in args {
        let n = try integerComponent(value, "gcd")
        result = BigInt.gcd(result, n.value)
        inexact = inexact || n.inexact
      }
      return inexact ? .real(result.doubleValue) : .integer(result)
    }
    primitive("lcm", in: env) { args in
      var result = BigInt.one
      var inexact = false
      for value in args {
        let component = try integerComponent(value, "lcm")
        let n = component.value.absoluteValue
        inexact = inexact || component.inexact
        if result.isZero || n.isZero {
          result = .zero
        } else {
          result = try result.quotient(dividingBy: BigInt.gcd(result, n)) * n
        }
      }
      return inexact ? .real(result.doubleValue) : .integer(result)
    }
    for (name, rule) in [
      ("floor", Rational.Rounding.floor), ("ceiling", .ceiling), ("truncate", .truncate),
      ("round", .nearestEven)
    ] {
      primitive(name, in: env) { args in
        try require(args, 1, name)
        let component = try realComponent(args[0], name)
        switch component {
        case .exact(let r): return .integer(r.rounded(rule))
        case .inexact(let x):
          let y: Double =
            rule == .floor
            ? Foundation.floor(x)
            : rule == .ceiling
              ? Foundation.ceil(x)
              : rule == .truncate ? Foundation.trunc(x) : x.rounded(.toNearestOrEven)
          return .real(y)
        }
      }
    }
    primitive("numerator", in: env) { args in
      try require(args, 1, "numerator")
      let r = try rationalComponent(args[0], "numerator")
      return r.1 ? .real(r.0.numerator.doubleValue) : .integer(r.0.numerator)
    }
    primitive("denominator", in: env) { args in
      try require(args, 1, "denominator")
      let r = try rationalComponent(args[0], "denominator")
      return r.1 ? .real(r.0.denominator.doubleValue) : .integer(r.0.denominator)
    }
    primitive("make-rectangular", in: env) { args in
      try require(args, 2, "make-rectangular")
      return numberValue(
        .rectangular(
          try realComponent(args[0], "make-rectangular"),
          try realComponent(args[1], "make-rectangular")
        )
      )
    }
    primitive("make-polar", in: env) { args in
      try require(args, 2, "make-polar")
      return numberValue(
        .polar(
          magnitude: try realComponent(args[0], "make-polar"),
          angle: try realComponent(args[1], "make-polar")
        )
      )
    }
    primitive("real-part", in: env) { args in
      try require(args, 1, "real-part")
      return numberValue(.real(try schemeNumber(args[0]).parts.real))
    }
    primitive("imag-part", in: env) { args in
      try require(args, 1, "imag-part")
      return numberValue(.real(try schemeNumber(args[0]).parts.imaginary))
    }
    primitive("magnitude", in: env) { args in
      try require(args, 1, "magnitude")
      let number = try schemeNumber(args[0])
      return number.exactMagnitude.map { numberValue(SchemeNumber($0)) } ?? .real(number.magnitude)
    }
    primitive("angle", in: env) { args in
      try require(args, 1, "angle")
      return .real(try schemeNumber(args[0]).angle)
    }
    primitive("expt", in: env) { args in
      try require(args, 2, "expt")
      let base = try schemeNumber(args[0])
      let exponent = try schemeNumber(args[1])
      if base.isZero {
        let result = exponent.isZero ? SchemeNumber.one : SchemeNumber.zero
        return numberValue(base.isExact && exponent.isExact ? result : result.inexact())
      }
      if let e = exactIntegerExponent(exponent) {
        do { return numberValue(try base.exactPower(e)) } catch {
          throw SchemeError.numeric("division by zero")
        }
      }
      return numberValue(complexPower(base, exponent))
    }
    primitive("sqrt", in: env) { args in
      try require(args, 1, "sqrt")
      return numberValue(complexSqrt(try schemeNumber(args[0])))
    }
    for name in ["exp", "log", "sin", "cos", "tan", "asin", "acos"] {
      primitive(name, in: env) { args in
        try require(args, 1, name)
        return numberValue(complexTranscendental(name, try schemeNumber(args[0])))
      }
    }
    primitive("atan", in: env) { args in
      guard args.count == 1 || args.count == 2 else {
        throw SchemeError.arity("atan expects 1 or 2 arguments")
      }
      if args.count == 2 {
        let angle = Foundation.atan2(
          try realComponent(args[0], "atan").doubleValue,
          try realComponent(args[1], "atan").doubleValue
        )
        return .real(angle == -.pi ? .pi : angle)
      }
      return numberValue(complexTranscendental("atan", try schemeNumber(args[0])))
    }
    primitive("rationalize", in: env) { args in
      try require(args, 2, "rationalize")
      guard (try realComponent(args[1], "rationalize")).signum >= 0 else {
        throw SchemeError.numeric("rationalize tolerance must be nonnegative")
      }
      return numberValue(try rationalized(args[0], args[1]))
    }
    primitive("number?", in: env) { try predicate($0, "number?", isNumber) }
    primitive("complex?", in: env) { try predicate($0, "complex?", isNumber) }
    primitive("real?", in: env) {
      try predicate($0, "real?") { (try? schemeNumber($0).isReal) == true }
    }
    primitive("rational?", in: env) {
      try predicate($0, "rational?") { (try? schemeNumber($0).isRational) == true }
    }
    primitive("integer?", in: env) {
      try predicate($0, "integer?") { (try? schemeNumber($0).isInteger) == true }
    }
    primitive("exact?", in: env) {
      try predicate($0, "exact?") { (try? schemeNumber($0).isExact) == true }
    }
    primitive("inexact?", in: env) {
      try predicate($0, "inexact?") {
        guard let n = try? schemeNumber($0) else { return false }
        return !n.isExact
      }
    }
    primitive("exact->inexact", in: env) { args in
      try require(args, 1, "exact->inexact")
      return numberValue(try schemeNumber(args[0]).inexact())
    }
    primitive("inexact->exact", in: env) { args in
      try require(args, 1, "inexact->exact")
      return numberValue(try exactNumber(schemeNumber(args[0])))
    }
    primitive("number->string", in: env) { args in
      guard args.count == 1 || args.count == 2 else {
        throw SchemeError.arity("number->string expects 1 or 2 arguments")
      }
      let radix = args.count == 2 ? try indexRadix(args[1], "number->string") : 10
      guard let text = try schemeNumber(args[0]).string(radix: radix) else {
        throw SchemeError.numeric("number cannot be represented in radix \(radix)")
      }
      return .string(SchemeString(text))
    }
    primitive("string->number", in: env) { args in
      guard args.count == 1 || args.count == 2 else {
        throw SchemeError.arity("string->number expects 1 or 2 arguments")
      }
      let radix = args.count == 2 ? try indexRadix(args[1], "string->number") : 10
      let text = try schemeString(args[0], "string->number").string
      var reader = Reader(
        hasRadixPrefix(text) || radix == 10
          ? text : "#\(radix == 2 ? "b" : radix == 8 ? "o" : "x")\(text)"
      )
      guard let values = try? reader.readAll(), values.count == 1, let value = values.first,
        isNumber(value)
      else { return .boolean(false) }
      return value
    }

  }
}
