import Foundation

package protocol SchemeMacro: SchemeHeapNode {
  func expand(_ use: Value, in useEnvironment: SchemeEnvironment, serial: inout Int) throws -> Value
}

/// A forward binding used while constructing mutually recursive `letrec-syntax`.
///
/// The binding identity is stable during transformer capture;
/// its target is filled once the corresponding `syntax-rules` object exists.
///
package final class ForwardMacro: SchemeMacro {
  package var target: (any SchemeMacro)?

  package init() { registerSchemeNode(self) }

  package func expand(_ use: Value, in useEnvironment: SchemeEnvironment, serial: inout Int) throws
    -> Value
  {
    guard let target else { throw SchemeError.syntax("uninitialized letrec-syntax transformer") }
    return try target.expand(use, in: useEnvironment, serial: &serial)
  }

  package func traceSchemeChildren(_ visit: (any SchemeHeapNode) -> Void) {
    if let target { visit(target) }
  }

  package func breakSchemeCycles() { target = nil }
}
