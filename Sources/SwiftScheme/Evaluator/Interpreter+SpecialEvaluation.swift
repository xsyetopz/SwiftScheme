import Foundation
import SwiftSchemeFrontend
import SwiftSchemeNumeric
import SwiftSchemePrimitives
import SwiftSchemeRuntime

extension Interpreter {
  func isEvalExpression(_ value: Value) -> Bool {
    switch value {
    case .integer, .rational, .real, .complex, .boolean, .character, .string, .symbol, .pair:
      return true
    default: return false
    }
  }

  func handleSpecial(
    _ special: Special,
    arguments: [Value],
    control: inout Control,
    continuation: inout Continuation,
    winds: [Wind]
  ) throws {
    switch special {
    case .apply:
      guard arguments.count >= 2 else {
        throw SchemeError.arity("apply expects at least 2 arguments")
      }
      guard let finalArgument = arguments.last else {
        throw SchemeError.arity("apply expects a final list")
      }
      control = .apply(
        arguments[0],
        Array(arguments.dropFirst().dropLast())
          + (try array(from: finalArgument, context: "apply final argument"))
      )
    case .callCC:
      try require(arguments, 1, "call-with-current-continuation")
      try requireProcedure(arguments[0], "call-with-current-continuation")
      let captured = Captured(continuation: continuation, winds: winds)
      control = .apply(arguments[0], [.procedure(Procedure(.continuation(captured)))])
    case .values: control = .values(arguments)
    case .callWithValues:
      try require(arguments, 2, "call-with-values")
      try requireProcedure(arguments[0], "call-with-values producer")
      try requireProcedure(arguments[1], "call-with-values consumer")
      continuation = .callValuesFrame(arguments[1], continuation)
      control = .apply(arguments[0], [])
    case .dynamicWind:
      try require(arguments, 3, "dynamic-wind")
      try requireProcedure(arguments[0], "dynamic-wind before")
      try requireProcedure(arguments[1], "dynamic-wind thunk")
      try requireProcedure(arguments[2], "dynamic-wind after")
      windSerial += 1
      let wind = Wind(windSerial, arguments[0], arguments[2])
      continuation = .windBeforeFrame(arguments[1], arguments[2], wind, continuation)
      control = .apply(arguments[0], [])
    case .force:
      try require(arguments, 1, "force")
      guard case .promise(let promise) = arguments[0] else {
        throw SchemeError.type("force expects a promise")
      }
      switch promise.state {
      case .done(let values): control = .values(values)
      case .pending(let expression, let environment):
        promise.state = .forcing(expression, environment)
        continuation = .promiseFrame(promise, continuation)
        control = .expression(expression, environment)
      case .forcing(let expression, let environment):
        continuation = .promiseFrame(promise, continuation)
        control = .expression(expression, environment)
      }
    case .eval:
      try require(arguments, 2, "eval")
      guard case .environment(let environment) = arguments[1] else {
        throw SchemeError.type("eval expects an environment")
      }
      guard isEvalExpression(arguments[0]) else {
        throw SchemeError.syntax("eval expects an expression")
      }
      let expanded = try expandedBody([arguments[0]], in: environment)
      if expanded.contains(where: {
        isDefinitionForm($0, "define", in: environment)
          || isDefinitionForm($0, "define-syntax", in: environment)
      }) {
        try environment.requireDefinitionAllowed()
        throw SchemeError.syntax("eval expects an expression")
      }
      control = .expression(arguments[0], environment)
    case .map, .forEach:
      guard arguments.count >= 2 else {
        throw SchemeError.arity("map/for-each expects procedure and lists")
      }
      guard case .procedure = arguments[0] else {
        throw SchemeError.type("map/for-each expects a procedure")
      }
      let lists = try arguments.dropFirst().map {
        try array(from: $0, context: "map/for-each argument")
      }
      guard let count = lists.first?.count, lists.allSatisfy({ $0.count == count }) else {
        throw SchemeError.arity("map/for-each lists must have equal length")
      }
      let each = special == .forEach
      if count == 0 {
        control = .values([each ? .unspecified : .empty])
      } else {
        continuation = .mapFrame(arguments[0], lists, 0, [], each, continuation)
        control = .apply(arguments[0], lists.map { $0[0] })
      }
    case .load:
      try require(arguments, 1, "load")
      let path = try schemeString(arguments[0], "load").string
      let source: String
      do { source = try String(contentsOfFile: path, encoding: .utf8) } catch {
        throw SchemeError.io("cannot load \(path): \(error.localizedDescription)")
      }
      var reader = Reader(source)
      guard let form = try reader.readOne() else {
        control = .values([.unspecified])
        break
      }
      noteReaderSpellings(reader)
      continuation = .loadFrame(source, reader.index, global, continuation)
      control = .expression(form, global)
    case .callWithInputFile, .withInputFromFile:
      try require(
        arguments,
        2,
        special == .callWithInputFile ? "call-with-input-file" : "with-input-from-file"
      )
      let path = try schemeString(arguments[0], "input file").string
      try requireProcedure(
        arguments[1],
        special == .callWithInputFile ? "call-with-input-file" : "with-input-from-file"
      )
      if special == .callWithInputFile {
        let opened: SchemePort
        do {
          opened = try SchemePort(
            handle: try FileHandle(forReadingFrom: URL(fileURLWithPath: path)),
            mode: .input
          )
        } catch let error as SchemeError { throw error } catch {
          throw SchemeError.io(error.localizedDescription)
        }
        continuation = .closePortFrame(opened, continuation)
        control = .apply(arguments[1], [.port(opened)])
      } else {
        let state = DynamicFilePort(path, .input)
        let before = Value.procedure(
          Procedure(
            .primitive("with-input-from-file before") { [weak self] args in
              guard let self else { throw SchemeError.io("interpreter was reclaimed") }
              try require(args, 0, "with-input-from-file before")
              let opened: SchemePort
              do {
                opened = try SchemePort(
                  handle: try FileHandle(forReadingFrom: URL(fileURLWithPath: state.path)),
                  mode: .input
                )
              } catch let error as SchemeError { throw error } catch {
                throw SchemeError.io(error.localizedDescription)
              }
              opened.position = state.position
              state.previous = currentInput
              state.opened = opened
              currentInput = opened
              return [.unspecified]
            }
          )
        )
        let after = Value.procedure(
          Procedure(
            .primitive("with-input-from-file after") { [weak self] args in
              guard let self else { throw SchemeError.io("interpreter was reclaimed") }
              try require(args, 0, "with-input-from-file after")
              return try finishDynamicFile(
                state,
                updatePosition: { state.position = $0.position },
                restore: { currentInput = $0 }
              )
            }
          )
        )
        windSerial += 1
        let wind = Wind(windSerial, before, after)
        wind.cleanup = { [weak self] in
          guard let self else { return }
          if let opened = state.opened {
            try? closePortHandle(opened)
            state.opened = nil
          }
          if let previous = state.previous {
            self.currentInput = previous
            state.previous = nil
          }
        }
        continuation = .windBeforeFrame(arguments[1], after, wind, continuation)
        control = .apply(before, [])
      }
    case .callWithInputString:
      try require(arguments, 2, "call-with-input-string")
      try requireProcedure(arguments[1], "call-with-input-string")
      let port = SchemePort(input: try schemeString(arguments[0], "call-with-input-string").string, defaultReady: true)
      control = .apply(arguments[1], [.port(port)])
    case .callWithOutputString:
      try require(arguments, 1, "call-with-output-string")
      try requireProcedure(arguments[0], "call-with-output-string")
      let port = SchemePort(output: true)
      continuation = .outputStringFrame(port, continuation)
      control = .apply(arguments[0], [.port(port)])
    case .callWithOutputFile, .withOutputToFile:
      try require(
        arguments,
        2,
        special == .callWithOutputFile ? "call-with-output-file" : "with-output-to-file"
      )
      let path = try schemeString(arguments[0], "output file").string
      try requireProcedure(
        arguments[1],
        special == .callWithOutputFile ? "call-with-output-file" : "with-output-to-file"
      )
      guard FileManager.default.createFile(atPath: path, contents: nil) else {
        throw SchemeError.io("cannot create \(path)")
      }
      if special == .callWithOutputFile {
        let opened: SchemePort
        do {
          opened = try SchemePort(
            handle: try FileHandle(forWritingTo: URL(fileURLWithPath: path)),
            mode: .output
          )
        } catch let error as SchemeError { throw error } catch {
          throw SchemeError.io(error.localizedDescription)
        }
        continuation = .closePortFrame(opened, continuation)
        control = .apply(arguments[1], [.port(opened)])
      } else {
        let state = DynamicFilePort(path, .output)
        let before = Value.procedure(
          Procedure(
            .primitive("with-output-to-file before") { [weak self] args in
              guard let self else { throw SchemeError.io("interpreter was reclaimed") }
              try require(args, 0, "with-output-to-file before")
              let opened: SchemePort
              do {
                let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: state.path))
                try handle.seek(toOffset: state.offset)
                opened = try SchemePort(handle: handle, mode: .output)
              } catch let error as SchemeError { throw error } catch {
                throw SchemeError.io(error.localizedDescription)
              }
              state.previous = currentOutput
              state.opened = opened
              currentOutput = opened
              return [.unspecified]
            }
          )
        )
        let after = Value.procedure(
          Procedure(
            .primitive("with-output-to-file after") { [weak self] args in
              guard let self else { throw SchemeError.io("interpreter was reclaimed") }
              try require(args, 0, "with-output-to-file after")
              return try finishDynamicFile(
                state,
                updatePosition: { state.offset = $0.handle?.offsetInFile ?? state.offset },
                restore: { currentOutput = $0 }
              )
            }
          )
        )
        windSerial += 1
        let wind = Wind(windSerial, before, after)
        wind.cleanup = { [weak self] in
          guard let self else { return }
          if let opened = state.opened {
            try? closePortHandle(opened)
            state.opened = nil
          }
          if let previous = state.previous {
            self.currentOutput = previous
            state.previous = nil
          }
        }
        continuation = .windBeforeFrame(arguments[1], after, wind, continuation)
        control = .apply(before, [])
      }
    }
  }
}
