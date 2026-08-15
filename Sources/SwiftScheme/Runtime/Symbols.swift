import Foundation

package let nonstandardSymbolPrefix = "\u{1}"
package let internalSymbolPrefix = "\u{2}r5rs:"
private let encodedSymbolPrefix = nonstandardSymbolPrefix + "u:"

package func symbolToken(_ spelling: String) -> String {
  guard spelling == spelling.lowercased(), isStandardIdentifier(spelling) else {
    return encodeSymbolSpelling(spelling)
  }
  return spelling
}

package func symbolSpelling(_ token: String) -> String {
  guard token.hasPrefix(nonstandardSymbolPrefix) else { return token }
  let payload = String(token.dropFirst())
  guard payload.hasPrefix("u:") else { return payload }
  let encoded = String(payload.dropFirst(2))
  guard encoded.count.isMultiple(of: 2) else { return payload }
  var bytes: [UInt8] = []
  bytes.reserveCapacity(encoded.count / 2)
  var index = encoded.startIndex
  while index < encoded.endIndex {
    let next = encoded.index(index, offsetBy: 2)
    guard let byte = UInt8(encoded[index..<next], radix: 16) else { return payload }
    bytes.append(byte)
    index = next
  }
  return String(bytes: bytes, encoding: .utf8) ?? payload
}

package func symbolCanonical(_ token: String) -> String {
  token.hasPrefix(nonstandardSymbolPrefix) || token.hasPrefix(internalSymbolPrefix)
    ? token : token.lowercased()
}

private func encodeSymbolSpelling(_ spelling: String) -> String {
  let bytes = spelling.utf8
  let payload = bytes.map { byte in
    let text = String(byte, radix: 16)
    return text.count == 1 ? "0" + text : text
  }.joined()
  return encodedSymbolPrefix + payload
}

private func isStandardIdentifier(_ spelling: String) -> Bool {
  if spelling == "+" || spelling == "-" || spelling == "..." { return true }
  let characters = Array(spelling)
  guard let first = characters.first, isIdentifierInitial(first) else { return false }
  return characters.dropFirst().allSatisfy(isIdentifierSubsequent)
}

private func isIdentifierInitial(_ character: Character) -> Bool {
  guard character.isASCII else { return false }
  switch character {
  case "a"..."z", "A"..."Z": return true
  default: return "!$%&*/:<=>?^_~".contains(character)
  }
}

private func isIdentifierSubsequent(_ character: Character) -> Bool {
  isIdentifierInitial(character) || (character.isASCII && character.isNumber)
    || "+-.@".contains(character)
}
