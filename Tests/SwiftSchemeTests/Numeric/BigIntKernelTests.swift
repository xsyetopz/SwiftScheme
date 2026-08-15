import SwiftScheme
import Testing

func runBigIntKernelChecks() throws {
  func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    #expect(condition(), "BigInt: \(label)")
  }

  let samples: [Int64] = Array(-96...96)
  for a in samples {
    let x = BigInt(a)
    expect(x.exactInt64 == a, "Int64 round trip \(a)")
    for b in samples {
      let y = BigInt(b)
      expect((x + y).exactInt64 == a + b, "addition \(a), \(b)")
      expect((x - y).exactInt64 == a - b, "subtraction \(a), \(b)")
      expect((x * y).exactInt64 == a * b, "multiplication \(a), \(b)")
      expect((x < y) == (a < b), "comparison \(a), \(b)")
      if b != 0 {
        let division = try x.quotientAndRemainder(dividingBy: y)
        expect(division.quotient.exactInt64 == a / b, "quotient \(a), \(b)")
        expect(division.remainder.exactInt64 == a % b, "remainder \(a), \(b)")
        let schemeModulo = a.isMultiple(of: b) || (a < 0) == (b < 0) ? a % b : a % b + b
        let modulo = try x.modulo(y)
        expect(modulo.exactInt64 == schemeModulo, "modulo \(a), \(b)")
      }
    }
  }

  var state: UInt64 = 0x243f_6a88_85a3_08d3
  func nextInt64() -> Int64 {
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Int64(bitPattern: state)
  }
  for _ in 0..<2_000 {
    let a = nextInt64()
    var b = nextInt64()
    if b == 0 || (a == .min && b == -1) { b = 1 }
    let division = try BigInt(a).quotientAndRemainder(dividingBy: BigInt(b))
    expect(division.quotient.exactInt64 == a / b, "full-width quotient")
    expect(division.remainder.exactInt64 == a % b, "full-width remainder")
    expect(
      division.quotient * BigInt(b) + division.remainder == BigInt(a),
      "full-width division reconstruction"
    )
  }

  let limits: [Int64] = [.min, .min + 1, -1, 0, 1, .max]
  for value in limits {
    let integer = BigInt(value)
    expect(integer.exactInt64 == value, "Int64 boundary \(value)")
    for radix in [2, 8, 10, 16] {
      let text = integer.string(radix: radix)
      expect(BigInt(text, radix: radix) == integer, "radix \(radix) boundary round trip")
    }
  }
  expect(BigInt("9223372036854775808")?.exactInt64 == nil, "positive Int64 overflow")
  expect(BigInt("-9223372036854775809")?.exactInt64 == nil, "negative Int64 overflow")
  expect(BigInt("+ff", radix: 16) == BigInt(255), "signed hexadecimal parse")
  expect(BigInt("102", radix: 2) == nil, "invalid radix digit")
  expect(BigInt("-0") == .zero && BigInt("-0")?.signum == 0, "normalized zero")

  let a = try #require(BigInt("12345678901234567890123456789012345678901234567890"))
  let b = try #require(BigInt("987654321098765432109876543210987654321"))
  let expectedSum = try #require(BigInt("12345678902222222211222222221122222222112222222211"))
  expect(a + b == expectedSum, "known huge sum")
  let expectedProduct = try #require(
    BigInt(
      "12193263113702179522618503273386678859449931412844871208653362292333223746380111126352690"
    )
  )
  expect(a * b == expectedProduct, "known huge product")
  let product = a * b
  let productDivision = try product.quotientAndRemainder(dividingBy: a)
  expect(
    productDivision.quotient == b && productDivision.remainder.isZero,
    "huge product division identity"
  )

  let constructed = product + a - BigInt(17)
  let division = try constructed.quotientAndRemainder(dividingBy: b)
  expect(
    division.quotient * b + division.remainder == constructed,
    "huge quotient/remainder reconstruction"
  )
  expect(division.remainder.absoluteValue < b.absoluteValue, "huge remainder bound")
  for signedDividend in [constructed, -constructed] {
    for signedDivisor in [b, -b] {
      let signedDivision = try signedDividend.quotientAndRemainder(dividingBy: signedDivisor)
      expect(
        signedDivision.quotient * signedDivisor + signedDivision.remainder == signedDividend,
        "signed huge division reconstruction"
      )
      expect(
        signedDivision.remainder.isZero || signedDivision.remainder.signum == signedDividend.signum,
        "signed huge remainder sign"
      )
    }
  }
  for iteration in 0..<128 {
    let leftA = try #require(BigInt(String(nextInt64().magnitude)))
    let leftB = try #require(BigInt(String(nextInt64().magnitude)))
    let leftC = try #require(BigInt(String(nextInt64().magnitude)))
    let left = leftA * leftB + leftC
    let rightA = try #require(BigInt(String(nextInt64().magnitude | 1)))
    let rightB = try #require(BigInt(String(nextInt64().magnitude | 1)))
    let right = rightA * rightB
    let signedLeft = iteration & 1 == 0 ? left : -left
    let signedRight = iteration & 2 == 0 ? right : -right
    let qr = try signedLeft.quotientAndRemainder(dividingBy: signedRight)
    expect(
      qr.quotient * signedRight + qr.remainder == signedLeft,
      "deterministic huge division reconstruction \(iteration)"
    )
    expect(
      qr.remainder.isZero || qr.remainder.signum == signedLeft.signum,
      "deterministic huge remainder sign \(iteration)"
    )
    expect(
      qr.remainder.absoluteValue < signedRight.absoluteValue,
      "deterministic huge remainder bound \(iteration)"
    )
  }

  let power = try BigInt(2).power(521)
  expect(
    power.string(radix: 2) == "1" + String(repeating: "0", count: 521),
    "binary exponentiation"
  )
  let magnitudeModulo = try power.magnitudeModulo(31)
  expect(magnitudeModulo == 2, "magnitude modulo helper")
  expect(BigInt.gcd(product, a) == a, "huge gcd")
  expect(BigInt.gcd(BigInt(-84), BigInt(30)) == BigInt(6), "signed gcd")
  expect(
    BigInt(9).absoluteValue == BigInt(9) && BigInt(-9).absoluteValue == BigInt(9),
    "absolute value"
  )
  expect((-BigInt(-9)) == BigInt(9), "unary sign")
  expect(BigInt(1).doubleValue == 1.0 && BigInt(-1).doubleValue == -1.0, "Double conversion")
  expect(BigInt(Int64.max).exactInt == Int(exactly: Int64.max), "exact Int conversion")

  do {
    _ = try a.quotient(dividingBy: .zero)
    #expect(Bool(false), "BigInt: division by zero accepted")
  } catch BigIntError.divisionByZero {}
  do {
    _ = try BigInt(2).power(-1)
    #expect(Bool(false), "BigInt: negative exponent accepted")
  } catch BigIntError.negativeExponent {}
}
