import Foundation
import SwiftScheme

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count <= 1 else {
  FileHandle.standardError.write(Data("usage: swiftscheme [file]\n".utf8))
  exit(64)
}

func emit(_ text: String, to handle: FileHandle = .standardOutput) { handle.write(Data(text.utf8)) }

let interpreter: Interpreter
if arguments.count == 1 && isatty(STDIN_FILENO) == 0 {
  let data = FileHandle.standardInput.readDataToEndOfFile()
  guard let input = String(data: data, encoding: .utf8) else {
    emit("I/O error: standard input is not valid UTF-8\n", to: .standardError)
    exit(1)
  }
  interpreter = Interpreter(output: { emit($0) }, input: input)
} else {
  interpreter = Interpreter { emit($0) }
}

do {
  if let path = arguments.first {
    let source: String
    do { source = try String(contentsOfFile: path, encoding: .utf8) } catch {
      throw SchemeError.io("cannot read \(path): \(error.localizedDescription)")
    }
    _ = try interpreter.evaluate(source)
  } else if isatty(STDIN_FILENO) != 0 {
    var source = ""
    while true {
      emit(source.isEmpty ? "> " : "| ")
      guard let line = readLine() else {
        if !source.isEmpty { emit("lexical error: unexpected end of input\n", to: .standardError) }
        break
      }
      source += line + "\n"
      guard interpreter.isComplete(source) else { continue }
      do {
        let value = try interpreter.evaluate(source)
        if case .unspecified = value {} else { emit(value.written + "\n") }
      } catch { emit("\(error)\n", to: .standardError) }
      source = ""
    }
  } else {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let source = String(data: data, encoding: .utf8) else {
      throw SchemeError.io("standard input is not valid UTF-8")
    }
    _ = try interpreter.evaluate(source)
  }
} catch {
  emit("\(error)\n", to: .standardError)
  exit(1)
}
