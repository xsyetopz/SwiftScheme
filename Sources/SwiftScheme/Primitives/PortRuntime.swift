import Foundation
import SwiftSchemeNumeric
import SwiftSchemeRuntime

package func openPort(_ port: SchemePort, _ mode: SchemePort.Mode, _ context: String) throws
  -> SchemePort
{
  guard port.mode == mode, !port.closed else {
    throw SchemeError.type("\(context) expects an open \(mode == .input ? "input" : "output") port")
  }
  return port
}

package func port(_ value: Value, _ mode: SchemePort.Mode, _ context: String) throws -> SchemePort {
  guard case .port(let port) = value else {
    throw SchemeError.type("\(context) expects an open \(mode == .input ? "input" : "output") port")
  }
  return try openPort(port, mode, context)
}
package func inputPort(_ args: [Value], _ fallback: SchemePort, _ name: String) throws -> SchemePort
{
  guard args.count <= 1 else { throw SchemeError.arity("\(name) expects 0 or 1 arguments") }
  return args.isEmpty ? try openPort(fallback, .input, name) : try port(args[0], .input, name)
}
package func outputPort(_ args: [Value], _ fallback: SchemePort, _ name: String) throws
  -> SchemePort
{
  guard args.count <= 1 else { throw SchemeError.arity("\(name) expects 0 or 1 arguments") }
  return args.isEmpty ? try openPort(fallback, .output, name) : try port(args[0], .output, name)
}
package func outputArguments(_ args: [Value], _ fallback: SchemePort, _ name: String) throws -> (
  Value, SchemePort
) {
  guard args.count == 1 || args.count == 2 else {
    throw SchemeError.arity("\(name) expects 1 or 2 arguments")
  }
  return (
    args[0],
    args.count == 2 ? try port(args[1], .output, name) : try openPort(fallback, .output, name)
  )
}
package func emit(_ text: String, to port: SchemePort) throws {
  guard !port.closed else { throw SchemeError.io("cannot write to a closed port") }
  if let sink = port.sink { try sink(text) } else { port.output += text }
}
package func closePortHandle(_ port: SchemePort) throws {
  guard !port.closed else { return }
  port.closed = true
  do { try port.handle?.close() } catch { throw SchemeError.io(error.localizedDescription) }
}

package func closePort(_ args: [Value], _ mode: SchemePort.Mode, _ name: String) throws -> Value {
  try require(args, 1, name)
  guard case .port(let p) = args[0], p.mode == mode else {
    throw SchemeError.type("\(name) expects an \(mode == .input ? "input" : "output") port")
  }
  try closePortHandle(p)
  return .unspecified
}
