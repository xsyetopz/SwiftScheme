import Foundation
import SwiftSchemeRuntime
import SwiftSchemeFrontend
import SwiftSchemePrimitives
import SwiftSchemeNumeric

extension Interpreter {
  func installControlAndIOPrimitives(in env: SchemeEnvironment) {
    special("apply", .apply, in: env)
    special("call-with-current-continuation", .callCC, in: env)
    if let procedure = env.cell("call-with-current-continuation")?.value {
      env.define("call/cc", procedure)
    }
    special("values", .values, in: env)
    special("call-with-values", .callWithValues, in: env)
    special("dynamic-wind", .dynamicWind, in: env)
    special("force", .force, in: env)
    special("eval", .eval, in: env)
    special("map", .map, in: env)
    special("for-each", .forEach, in: env)
    special("load", .load, in: env)
    special("call-with-input-file", .callWithInputFile, in: env)
    special("call-with-output-file", .callWithOutputFile, in: env)
    special("with-input-from-file", .withInputFromFile, in: env)
    special("with-output-to-file", .withOutputToFile, in: env)
    special("call-with-input-string", .callWithInputString, in: env)
    special("call-with-output-string", .callWithOutputString, in: env)

    primitive("scheme-report-environment", in: env) { args in
      try require(args, 1, "scheme-report-environment")
      guard try exactInteger(args[0], "scheme-report-environment") == 5 else {
        throw SchemeError.numeric("only report version 5 is supported")
      }
      let copy = SchemeEnvironment(definitionPolicy: .fixed)
      for name in r5rsReportProcedureNames {
        if let cell = env.values[name] { copy.define(name, cell.value) }
      }
      return .environment(copy)
    }
    primitive("null-environment", in: env) { args in
      try require(args, 1, "null-environment")
      guard try exactInteger(args[0], "null-environment") == 5 else {
        throw SchemeError.numeric("only report version 5 is supported")
      }
      return .environment(SchemeEnvironment(definitionPolicy: .fixed))
    }
    primitive("interaction-environment", in: env) { [unowned self] in
      try require($0, 0, "interaction-environment")
      return .environment(global)
    }

    primitive("current-input-port", in: env) { [unowned self] in
      try require($0, 0, "current-input-port")
      return .port(currentInput)
    }
    primitive("current-output-port", in: env) { [unowned self] in
      try require($0, 0, "current-output-port")
      return .port(currentOutput)
    }
    primitive("open-input-file", in: env) { args in
      try require(args, 1, "open-input-file")
      do {
        return .port(
          SchemePort(
            handle: try FileHandle(
              forReadingFrom: URL(
                fileURLWithPath: try schemeString(args[0], "open-input-file").string
              )
            ),
            mode: .input
          )
        )
      } catch { throw SchemeError.io(error.localizedDescription) }
    }
    primitive("open-output-file", in: env) { args in
      try require(args, 1, "open-output-file")
      let path = try schemeString(args[0], "open-output-file").string
      guard FileManager.default.createFile(atPath: path, contents: nil) else {
        throw SchemeError.io("cannot create \(path)")
      }
      do {
        return .port(
          SchemePort(
            handle: try FileHandle(forWritingTo: URL(fileURLWithPath: path)),
            mode: .output
          )
        )
      } catch { throw SchemeError.io(error.localizedDescription) }
    }
    primitive("close-input-port", in: env) { try closePort($0, .input, "close-input-port") }
    primitive("close-output-port", in: env) { try closePort($0, .output, "close-output-port") }
    primitive("read", in: env) { [unowned self] args in
      let port = try inputPort(args, currentInput, "read")
      var reader = Reader(port.input, start: port.position)
      let value = try reader.readOne()
      port.position = reader.index
      return value ?? .eof
    }
    primitive("read-char", in: env) { [unowned self] args in
      let port = try inputPort(args, currentInput, "read-char")
      guard port.position < port.input.count else { return .eof }
      defer { port.position += 1 }
      return .character(port.input[port.position])
    }
    primitive("peek-char", in: env) { [unowned self] args in
      let port = try inputPort(args, currentInput, "peek-char")
      return port.position < port.input.count ? .character(port.input[port.position]) : .eof
    }
    primitive("eof-object?", in: env) {
      try predicate($0, "eof-object?") { if case .eof = $0 { true } else { false } }
    }
    primitive("char-ready?", in: env) { [unowned self] args in
      _ = try inputPort(args, currentInput, "char-ready?")
      return .boolean(true)
    }
    primitive("write", in: env) { [unowned self] args in
      let (value, port) = try outputArguments(args, currentOutput, "write")
      try emit(value.written, to: port)
      return .unspecified
    }
    primitive("display", in: env) { [unowned self] args in
      let (value, port) = try outputArguments(args, currentOutput, "display")
      try emit(value.displayed, to: port)
      return .unspecified
    }
    primitive("newline", in: env) { [unowned self] args in
      let port = try outputPort(args, currentOutput, "newline")
      try emit("\n", to: port)
      return .unspecified
    }
    primitive("write-char", in: env) { [unowned self] args in
      guard args.count == 1 || args.count == 2 else {
        throw SchemeError.arity("write-char expects 1 or 2 arguments")
      }
      let destination =
        args.count == 2
        ? try port(args[1], .output, "write-char")
        : try openPort(currentOutput, .output, "write-char")
      try emit(String(try character(args[0], "write-char")), to: destination)
      return .unspecified
    }
    primitive("open-input-string", in: env) { args in
      try require(args, 1, "open-input-string")
      return .port(SchemePort(input: try schemeString(args[0], "open-input-string").string))
    }
    primitive("open-output-string", in: env) { args in
      try require(args, 0, "open-output-string")
      return .port(SchemePort(output: true))
    }
    primitive("get-output-string", in: env) { args in
      try require(args, 1, "get-output-string")
      return .string(SchemeString(try port(args[0], .output, "get-output-string").output))
    }
    primitive("flush-output", in: env) { [unowned self] args in
      _ = try outputPort(args, currentOutput, "flush-output")
      return .unspecified
    }
    primitive("error", in: env) { args in
      throw SchemeError.io(args.map(\.displayed).joined(separator: " "))
    }
  }
}
