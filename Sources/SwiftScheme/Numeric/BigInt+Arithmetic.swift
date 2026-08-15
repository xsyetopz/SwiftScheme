import Foundation

extension BigInt {
  package static func compareMagnitude(_ lhs: [UInt32], _ rhs: [UInt32]) -> Int {
    if lhs.count != rhs.count { return lhs.count < rhs.count ? -1 : 1 }
    for index in lhs.indices.reversed() where lhs[index] != rhs[index] {
      return lhs[index] < rhs[index] ? -1 : 1
    }
    return 0
  }

  package static func addMagnitudes(_ lhs: [UInt32], _ rhs: [UInt32]) -> [UInt32] {
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

  package static func subtractMagnitudes(_ lhs: [UInt32], _ rhs: [UInt32]) -> [UInt32] {
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

  package static func multiplyMagnitude(_ value: inout [UInt32], by multiplier: UInt32) {
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

  package static func addMagnitude(_ value: inout [UInt32], _ addend: UInt32) {
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

  package static func divideMagnitude(_ dividend: [UInt32], by divisor: UInt32) -> (
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

  package static func divideMagnitudes(_ dividend: [UInt32], by divisor: [UInt32]) -> (
    quotient: [UInt32], remainder: [UInt32]
  ) {
    precondition(!divisor.isEmpty)
    if compareMagnitude(dividend, divisor) < 0 { return ([], dividend) }
    if divisor.count == 1 {
      let division = divideMagnitude(dividend, by: divisor[0])
      return (division.quotient, division.remainder == 0 ? [] : [division.remainder])
    }

    let base = UInt64(1) << 32
    guard let mostSignificant = divisor.last else { return ([], dividend) }
    let shift = mostSignificant.leadingZeroBitCount
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
