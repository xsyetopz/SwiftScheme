import Foundation
import SwiftSchemeNumeric

private func sameScalarSpelling(_ lhs: String, _ rhs: String) -> Bool {
  lhs.unicodeScalars.elementsEqual(rhs.unicodeScalars)
}

package func eq(_ lhs: Value, _ rhs: Value) -> Bool {
  switch (lhs, rhs) {
  case (.boolean(let a), .boolean(let b)): a == b
  case (.character(let a), .character(let b)): sameScalarSpelling(String(a), String(b))
  case (.symbol(let a), .symbol(let b)): sameScalarSpelling(a, b)
  case (.empty, .empty), (.eof, .eof): true
  case (.pair(let a), .pair(let b)): a === b
  case (.string(let a), .string(let b)): a === b
  case (.vector(let a), .vector(let b)): a === b
  case (.procedure(let a), .procedure(let b)): a === b
  case (.promise(let a), .promise(let b)): a === b
  case (.port(let a), .port(let b)): a === b
  default: false
  }
}

package func eqv(_ lhs: Value, _ rhs: Value) -> Bool {
  if let a = schemeNumberValue(lhs), let b = schemeNumberValue(rhs) {
    return a.isExact == b.isExact && SchemeNumber.numericallyEqual(a, b)
  }
  return eq(lhs, rhs)
}

struct IdentityPair: Hashable {
  let left: ObjectIdentifier
  let right: ObjectIdentifier
}

package func equal(_ lhs: Value, _ rhs: Value) -> Bool {
  var pending = [(lhs, rhs)]
  var seen = Set<IdentityPair>()
  while let (a, b) = pending.popLast() {
    switch (a, b) {
    case (.pair(let x), .pair(let y)):
      if x === y { continue }
      let id = IdentityPair(left: ObjectIdentifier(x), right: ObjectIdentifier(y))
      if seen.insert(id).inserted { pending += [(x.car, y.car), (x.cdr, y.cdr)] }
    case (.vector(let x), .vector(let y)):
      if x === y { continue }
      guard x.elements.count == y.elements.count else { return false }
      let id = IdentityPair(left: ObjectIdentifier(x), right: ObjectIdentifier(y))
      if seen.insert(id).inserted { pending += zip(x.elements, y.elements) }
    case (.string(let x), .string(let y)):
      guard x.characters.count == y.characters.count,
        zip(x.characters, y.characters).allSatisfy({ sameScalarSpelling(String($0), String($1)) })
      else { return false }
    default: if !eqv(a, b) { return false }
    }
  }
  return true
}
