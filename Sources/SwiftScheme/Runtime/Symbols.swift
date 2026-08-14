import Foundation

package let nonstandardSymbolPrefix = "\u{1}"
package let internalSymbolPrefix = "\u{2}r5rs:"

package func symbolToken(_ spelling: String) -> String {
  let canonical = spelling.lowercased()
  return spelling == canonical && !spelling.hasPrefix(nonstandardSymbolPrefix)
    && !spelling.hasPrefix(internalSymbolPrefix) ? canonical : nonstandardSymbolPrefix + spelling
}

package func symbolSpelling(_ token: String) -> String {
  token.hasPrefix(nonstandardSymbolPrefix) ? String(token.dropFirst()) : token
}
