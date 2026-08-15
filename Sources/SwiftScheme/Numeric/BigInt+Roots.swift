import Foundation

extension BigInt {
  package func exactNthRoot(_ degree: Int) -> Self? {
    guard degree > 0 else { return nil }
    if degree == 1 { return self }
    let negative = signum < 0
    guard !negative || degree % 2 == 1 else { return nil }
    let target = absoluteValue
    var low = Self.zero
    var high = target
    while low <= high {
      guard let middle = try? (low + high).quotient(dividingBy: Self(2)) else { return nil }
      guard let power = try? middle.power(degree) else { return nil }
      if power == target { return negative ? -middle : middle }
      if power < target { low = middle + .one } else { high = middle - .one }
    }
    return nil
  }
}
