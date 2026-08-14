import Foundation
import SwiftSchemeNumeric
import SwiftSchemeRuntime

package func pair(_ value: Value, _ context: String) throws -> Pair {
  guard case .pair(let pair) = value else { throw SchemeError.type("\(context) expects a pair") }
  return pair
}
package func schemeString(_ value: Value, _ context: String) throws -> SchemeString {
  guard case .string(let string) = value else {
    throw SchemeError.type("\(context) expects a string")
  }
  return string
}
package func character(_ value: Value, _ context: String) throws -> Character {
  guard case .character(let character) = value else {
    throw SchemeError.type("\(context) expects a character")
  }
  guard character.unicodeScalars.count == 1 else {
    throw SchemeError.type("character has multiple scalars")
  }
  return character
}
package func vector(_ value: Value, _ context: String) throws -> SchemeVector {
  guard case .vector(let vector) = value else {
    throw SchemeError.type("\(context) expects a vector")
  }
  return vector
}
package func index(_ value: Value, _ context: String) throws -> Int {
  let n = try exactInteger(value, context)
  guard n.signum >= 0, let result = n.exactInt else {
    throw SchemeError.numeric("\(context) requires nonnegative index")
  }
  return result
}
package func scalar(_ character: Character) throws -> UInt32 {
  guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
    throw SchemeError.type("character has multiple scalars")
  }
  return scalar.value
}
package func compare(_ lhs: String, _ rhs: String, _ name: String) -> Bool {
  if name.hasSuffix("<=?") { return lhs <= rhs }
  if name.hasSuffix(">=?") { return lhs >= rhs }
  if name.hasSuffix("=?") { return lhs == rhs }
  if name.hasSuffix("<?") { return lhs < rhs }
  return lhs > rhs
}

package func compareCharacterKeys(_ lhs: [String], _ rhs: [String], _ name: String) -> Bool {
  for (left, right) in zip(lhs, rhs) where left != right { return compare(left, right, name) }
  if name.hasSuffix("<=?") { return lhs.count <= rhs.count }
  if name.hasSuffix(">=?") { return lhs.count >= rhs.count }
  if name.hasSuffix("=?") { return lhs.count == rhs.count }
  if name.hasSuffix("<?") { return lhs.count < rhs.count }
  return lhs.count > rhs.count
}

package func scalarCaseMapping(_ character: Character, upper: Bool) -> String {
  guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
    return String(character)
  }
  return upper ? scalar.properties.uppercaseMapping : scalar.properties.lowercaseMapping
}

package func hasScalarCaseMapping(_ character: Character, upper: Bool) -> Bool {
  scalarCaseMapping(character, upper: upper).unicodeScalars.count == 1
}

package func isScalarCaseCharacter(_ character: Character) -> Bool {
  character.isLetter && hasScalarCaseMapping(character, upper: true)
    && hasScalarCaseMapping(character, upper: false)
}

package func scalarCaseMap(_ character: Character, upper: Bool) -> Character {
  let mapped = scalarCaseMapping(character, upper: upper)
  guard mapped.unicodeScalars.count == 1, let scalar = mapped.unicodeScalars.first else {
    return character
  }
  return Character(String(scalar))
}

package func scalarCaseKey(_ character: Character) -> String {
  var pending = [character]
  var keys = Set<String>()
  while let current = pending.popLast() {
    let spelling = String(current)
    guard keys.insert(spelling).inserted else { continue }
    for upper in [true, false] {
      let mapped = scalarCaseMapping(current, upper: upper)
      guard mapped.unicodeScalars.count == 1, let scalar = mapped.unicodeScalars.first else {
        continue
      }
      pending.append(Character(String(scalar)))
    }
  }
  return keys.min() ?? String(character)
}

package func hasRadixPrefix(_ text: String) -> Bool {
  let characters = Array(text.lowercased())
  var index = 0
  while index + 1 < characters.count, characters[index] == "#" {
    switch characters[index + 1] {
    case "b", "o", "d", "x": return true
    case "e", "i": index += 2
    default: return false
    }
  }
  return false
}

package func charPredicate(_ args: [Value], _ name: String, _ test: (Character) -> Bool) throws
  -> Value
{
  try require(args, 1, name)
  return .boolean(test(try character(args[0], name)))
}
