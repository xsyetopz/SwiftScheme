import Foundation
import SwiftScheme
import Testing

@MainActor
private func evaluateIO(_ source: String) throws -> Value {
  try Interpreter(output: { _ in }).evaluate(source)
}

@MainActor
private func expectIOError(_ source: String, _ label: String) {
  do {
    _ = try evaluateIO(source)
    #expect(Bool(false), "\(label): expected an error")
  } catch is SchemeError {
    // R5RS specifies the error condition, not the host diagnostic wording.
  } catch {
    #expect(Bool(false), "\(label): expected SchemeError, got \(error)")
  }
}

@Suite("R5RS §6.3.4–6.3.6 and §6.6 I/O/data contracts")
@MainActor
struct R5RSIODataTests {
  @Test("source literals reject mutation")
  func immutableLiterals() {
    expectIOError("(set-car! '(1 2) 3)", "literal pair")
    expectIOError("(set-cdr! '(1 2) '())", "literal pair cdr")
    expectIOError("(string-set! \"abc\" 0 #\\z)", "literal string")
    expectIOError("(string-fill! \"abc\" #\\z)", "literal string fill")
    expectIOError("(vector-set! '#(1 2) 0 3)", "literal vector")
    expectIOError("(vector-fill! '#(1 2) 3)", "literal vector fill")
    expectIOError(
      "(let ((name (symbol->string 'immutable))) (string-set! name 0 #\\x))",
      "symbol->string result"
    )
  }

  @Test("symbols preserve standard case and string-created spelling")
  func symbolConversion() throws {
    let result = try evaluateIO(
      "(list (symbol->string 'Martin) (symbol->string (string->symbol \"bitBlt\")) "
        + "(eq? 'bitBlt (string->symbol \"bitBlt\")) "
        + "(eq? (string->symbol \"bitBlt\") (string->symbol \"bitBlt\")))"
    )
    #expect(result.written == "(\"martin\" \"bitBlt\" #f #t)")
  }

  @Test("string-created symbols preserve control-character spellings")
  func symbolConversionEscapesInternalTag() throws {
    let result = try evaluateIO(
      "(let ((s (string-append (string (integer->char 1)) \"abc\"))) "
        + "(string=? s (symbol->string (string->symbol s))))"
    )
    #expect(result.written == "#t")
  }

  @Test("character case conversion preserves R5RS character invariants")
  func characterCaseConversion() throws {
    let result = try evaluateIO(
      """
      (let ((check (lambda (c)
                     (if (char-alphabetic? c)
                         (let ((up (char-upcase c)) (down (char-downcase c)))
                           (and (char-ci=? c up) (char-ci=? c down)
                                (char-upper-case? up) (char-lower-case? down)
                                (char=? up (integer->char (char->integer up)))
                                (char=? down (integer->char (char->integer down)))))
                         #t))))
        (and (check #\\A) (check #\\a)
             (char-ci=? #\\ß (char-upcase #\\ß))
             (char-ci=? #\\İ (char-downcase #\\İ))
             (char-alphabetic? #\\ſ)
             (char=? #\\S (char-upcase #\\ſ))
             (char-ci=? #\\ſ #\\S)
             (char=? #\\İ (integer->char (char->integer (char-downcase #\\İ))))))
      """
    )
    #expect(result.written == "#t")
  }

  @Test("read-created pairs, strings, and vectors remain mutable")
  func readValuesAreMutable() throws {
    #expect(
      try evaluateIO(
        "(call-with-input-string \"(1 2)\" (lambda (p) (let ((x (read p))) (set-car! x 9) x)))"
      ).written == "(9 2)"
    )
    #expect(
      try evaluateIO(
        "(call-with-input-string \"\\\"abc\\\"\" (lambda (p) (let ((s (read p))) (string-set! s 1 #\\z) s)))"
      ).written == "\"azc\""
    )
    #expect(
      try evaluateIO(
        "(call-with-input-string \"#(1 2)\" (lambda (p) (let ((v (read p))) (vector-set! v 0 9) v)))"
      ).written == "#(9 2)"
    )
  }

  @Test("input ports obey read, peek, EOF, readiness, and close contracts")
  func inputPortMatrix() throws {
    let result = try evaluateIO(
      """
      (call-with-input-string " 1 (a . b)"
        (lambda (p)
          (let ((first (read p))
                (second (read p))
                (peeked (peek-char p))
                (next (read-char p))
                (eof (read p)))
            (list first second peeked next (eof-object? eof) (char-ready? p)))))
      """
    )
    #expect(result.written == "(1 (a . b) #<eof> #<eof> #t #t)")
    expectIOError(
      "(call-with-input-string \"x\" (lambda (p) (close-input-port p) (read-char p)))",
      "read from closed input port"
    )
  }

  @Test("output ports distinguish write, display, and character output")
  func outputPortMatrix() throws {
    let source = """
    (call-with-output-string
      (lambda (p)
        (write "a\n" p)
        (display "b\n" p)
        (write-char #\\! p)
        (newline p)))
    """
    let result = try evaluateIO(source)
    #expect(result.written == "\"\\\"a\n\\\"b\n!\n\"")
  }

  @Test("vectors preserve mutation and list conversion contracts")
  func vectorMatrix() throws {
    let result = try evaluateIO(
      "(let ((v (make-vector 3 0))) (vector-fill! v 7) (list (vector-length v) (vector-ref v 1) (vector->list v) (list->vector '(a b))))"
    )
    #expect(result.written == "(3 7 (7 7 7) #(a b))")
    expectIOError("(vector-ref '#(1) 1)", "vector index")
    expectIOError("(make-vector -1)", "negative vector length")
  }

  @Test("load evaluates source in the interaction environment")
  func loadAndFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "swiftscheme-r5rs-\(UUID().uuidString)", isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("loaded.scm").path
    try "(define loaded-value 41) (+ loaded-value 1)".write(
      toFile: path, atomically: true, encoding: .utf8
    )
    let quotedPath = "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
      of: "\"", with: "\\\""
    ) + "\""
    let interpreter = Interpreter(output: { _ in })
    _ = try interpreter.evaluate("(load \(quotedPath))")
    #expect(try interpreter.evaluate("loaded-value").written == "41")
    #expect(try interpreter.evaluate("(load \(quotedPath))").written == "#<unspecified>")
  }
}
