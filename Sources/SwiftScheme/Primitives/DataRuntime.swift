import Foundation
import SwiftSchemeNumeric
import SwiftSchemeRuntime

package func requireProcedure(_ value: Value, _ context: String) throws {
  guard case .procedure = value else { throw SchemeError.type("\(context) expects a procedure") }
}

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
  let ordering = scalarStringOrdering(lhs, rhs)
  if name.hasSuffix("<=?") { return ordering <= 0 }
  if name.hasSuffix(">=?") { return ordering >= 0 }
  if name.hasSuffix("=?") { return ordering == 0 }
  if name.hasSuffix("<?") { return ordering < 0 }
  return ordering > 0
}

package func compareCharacterKeys(_ lhs: [String], _ rhs: [String], _ name: String) -> Bool {
  for (left, right) in zip(lhs, rhs) {
    let ordering = scalarStringOrdering(left, right)
    if ordering != 0 {
      if name.hasSuffix("<=?") { return ordering < 0 }
      if name.hasSuffix(">=?") { return ordering > 0 }
      if name.hasSuffix("=?") { return false }
      if name.hasSuffix("<?") { return ordering < 0 }
      return ordering > 0
    }
  }
  if name.hasSuffix("<=?") { return lhs.count <= rhs.count }
  if name.hasSuffix(">=?") { return lhs.count >= rhs.count }
  if name.hasSuffix("=?") { return lhs.count == rhs.count }
  if name.hasSuffix("<?") { return lhs.count < rhs.count }
  return lhs.count > rhs.count
}

package func scalarStringOrdering(_ lhs: String, _ rhs: String) -> Int {
  let left = lhs.unicodeScalars.map(\.value)
  let right = rhs.unicodeScalars.map(\.value)
  for (a, b) in zip(left, right) where a != b { return a < b ? -1 : 1 }
  return left.count == right.count ? 0 : (left.count < right.count ? -1 : 1)
}

package func scalarCaseMapping(_ character: Character, upper: Bool) -> String {
  guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
    return String(character)
  }
  return upper ? scalar.properties.uppercaseMapping : scalar.properties.lowercaseMapping
}

package func scalarCaseMap(_ character: Character, upper: Bool) -> Character {
  let mapped = scalarCaseMapping(character, upper: upper)
  guard mapped.unicodeScalars.count == 1, let scalar = mapped.unicodeScalars.first else {
    return character
  }
  return Character(String(scalar))
}

package func scalarCaseKey(_ character: Character) -> String {
  let upper = scalarCaseMapping(character, upper: true)
  guard upper.unicodeScalars.count == 1, let upperScalar = upper.unicodeScalars.first else {
    let lower = scalarCaseMapping(character, upper: false)
    return lower.unicodeScalars.count == 1 ? lower : String(character)
  }
  let upperCharacter = Character(String(upperScalar))
  let lowerOfUpper = scalarCaseMapping(upperCharacter, upper: false)
  if lowerOfUpper.unicodeScalars.count == 1, let lowerScalar = lowerOfUpper.unicodeScalars.first {
    let lowerCharacter = Character(String(lowerScalar))
    // A one-way uppercase mapping such as ß -> SS needs the lowercase
    // representative shared with its titlecase counterpart ẞ.
    if scalarCaseMapping(lowerCharacter, upper: true).unicodeScalars.count != 1 {
      return lowerOfUpper
    }
  }
  return upper
}

package func isCaseStableAlphabetic(_ character: Character) -> Bool {
  guard character.isLetter else { return false }
  return scalarCaseMapping(character, upper: true).unicodeScalars.count == 1
    && scalarCaseMapping(character, upper: false).unicodeScalars.count == 1
}

package func hasRadixPrefix(_ text: String) -> Bool {
  let characters = Array(text.lowercased())
  var index = 0
  while index < characters.count {
    while index < characters.count, characters[index].isWhitespace { index += 1 }
    if index < characters.count, characters[index] == ";" {
      while index < characters.count, characters[index] != "\n" { index += 1 }
      continue
    }
    break
  }
  guard index + 1 < characters.count, characters[index] == "#" else { return false }
  var exactnessSeen = false
  var radixSeen = false
  while index + 1 < characters.count, characters[index] == "#" {
    switch characters[index + 1] {
    case "b", "o", "d", "x":
      guard !radixSeen else { return false }
      radixSeen = true
    case "e", "i":
      guard !exactnessSeen else { return false }
      exactnessSeen = true
    default: return false
    }
    index += 2
  }
  return radixSeen
}

package func addRadixPrefix(_ text: String, _ prefix: String) -> String {
  var characters = Array(text)
  var index = atmosphereEnd(characters)
  while index + 1 < characters.count, characters[index] == "#",
    characters[index + 1] == "e" || characters[index + 1] == "i"
  { index += 2 }
  characters.insert(contentsOf: prefix, at: index)
  return String(characters)
}

private func atmosphereEnd(_ characters: [Character]) -> Int {
  var index = 0
  while index < characters.count {
    while index < characters.count, characters[index].isWhitespace { index += 1 }
    if index < characters.count, characters[index] == ";" {
      while index < characters.count, characters[index] != "\n" { index += 1 }
      continue
    }
    return index
  }
  return index
}

package func charPredicate(_ args: [Value], _ name: String, _ test: (Character) -> Bool) throws
  -> Value
{
  try require(args, 1, name)
  return .boolean(test(try character(args[0], name)))
}
