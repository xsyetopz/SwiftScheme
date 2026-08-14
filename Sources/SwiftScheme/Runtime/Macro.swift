import Foundation

package protocol SchemeMacro: SchemeHeapNode {
  func expand(_ use: Value, in useEnvironment: SchemeEnvironment, serial: inout Int) throws -> Value
}
