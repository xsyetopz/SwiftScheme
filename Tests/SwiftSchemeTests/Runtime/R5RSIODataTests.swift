import Foundation
import SwiftScheme
import Testing

@MainActor private func evaluateIO(_ source: String) throws -> Value {
  try Interpreter { _ in }.evaluate(source)
}

@MainActor private func expectIOError(_ source: String, _ label: String) {
  do {
    _ = try evaluateIO(source)
    #expect(Bool(false), "\(label): expected an error")
  } catch is SchemeError {} catch {
    #expect(Bool(false), "\(label): expected SchemeError, got \(error)")
  }
}

@Suite("R5RS §6.3.4–6.3.6 and §6.6 I/O/data contracts") @MainActor struct R5RSIODataTests {
  @Test("source literals reject mutation") func immutableLiterals() {
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

  @Test("symbols preserve standard case and string-created spelling") func symbolConversion() throws
  {
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
             (char-alphabetic? #\\ẞ)
             (char=? #\\ß (char-downcase #\\ẞ))
             (char-ci=? #\\ẞ #\\ß)
             (char=? #\\İ (integer->char (char->integer (char-downcase #\\İ))))))
      """
    )
    #expect(result.written == "#t")
  }

  @Test("R5RS §6.3.5 string-ci extends §6.3.4 char-ci character classes")
  func stringCaseOrderingUsesCharacterKeys() throws {
    let result = try evaluateIO(
      "(list (char-ci=? #\\ſ #\\S) (string-ci=? \"ſ\" \"S\") "
        + "(char-ci=? #\\ẞ #\\ß) (string-ci=? \"ẞ\" \"ß\") "
        + "(string-ci<? \"ſa\" \"Sa\") (string-ci>=? \"ẞ\" \"ß\"))"
    )
    #expect(result.written == "(#t #t #t #t #f #t)")
  }

  @Test("R5RS §6.3.5 string-ci preserves stored character boundaries")
  func stringCaseOrderingPreservesCharacterBoundaries() throws {
    let equality = try evaluateIO(
      "(let ((a (make-string 2 #\\a)) (b (make-string 2 #\\a)) " + "(mark (integer->char 768))) "
        + "" + "(string-set! b 0 #\\A) (string-set! a 1 mark) " + "(string-set! b 1 mark) "
        + "(list (string-length a) (string-length b) "
        + "(char-ci=? (string-ref a 0) (string-ref b 0)) "
        + "(char-ci=? (string-ref a 1) (string-ref b 1)) " + "(string-ci=? a b)))"
    )
    #expect(equality.written == "(2 2 #t #t #t)")

    let ordering = try evaluateIO(
      "(let ((a (make-string 2 #\\a)) (b (make-string 2 #\\a)) "
        + "(grave (integer->char 768)) (overline (integer->char 773))) "
        + "(string-set! a 1 grave) (string-set! b 1 overline) "
        + "(list (char-ci<? grave overline) (string-ci<? a b) "
        + "(char-ci>? grave overline) (string-ci>? a b)))"
    )
    #expect(ordering.written == "(#t #t #f #f)")
  }

  @Test("R5RS §6.3.5 string constructors preserve stored character boundaries")
  func stringConstructorsPreserveCharacterBoundaries() throws {
    let result = try evaluateIO(
      """
      (let ((source (make-string 2 #\\a)) (mark (integer->char 768)))
        (string-set! source 1 mark)
        (let ((constructed (string (string-ref source 0) (string-ref source 1)))
              (sliced (substring source 0 2))
              (joined (string-append source ""))
              (roundTrip (list->string (string->list source)))
              (copied (string-copy source)))
          (list (string-length constructed) (string-length sliced)
                (string-length joined) (string-length roundTrip) (string-length copied)
                (char=? (string-ref constructed 1) mark)
                (char=? (string-ref sliced 1) mark)
                (char=? (string-ref joined 1) mark)
                (char=? (string-ref roundTrip 1) mark)
                (char=? (string-ref copied 1) mark)
                (equal? source constructed) (equal? source sliced)
                (equal? source joined) (equal? source roundTrip)
                (equal? source copied))))
      """
    )
    #expect(result.written == "(2 2 2 2 2 #t #t #t #t #t #t #t #t #t #t)")
  }

  @Test("R5RS §6.3.4 rejects multi-scalar character literals") func scalarCharacterLiteralDomain()
    throws
  {
    do {
      _ = try evaluateIO("#\\e\u{301}")
      #expect(Bool(false), "multi-scalar character literal should fail")
    } catch let SchemeError.lexical(message, line, column) {
      #expect(message == "invalid character literal #\\e\u{301}")
      #expect(line == 1)
      #expect(column == 3)
    } catch { #expect(Bool(false), "expected lexical error, got \(error)") }

    do {
      _ = try evaluateIO("e\u{301}")
      #expect(Bool(false), "invalid scalar identifier should fail")
    } catch let SchemeError.lexical(message, line, column) {
      #expect(message == "invalid identifier e\u{301}")
      #expect(line == 1)
      #expect(column == 1)
    } catch { #expect(Bool(false), "expected lexical error, got \(error)") }
  }

  @Test("R5RS §6.3.4 strings and ports expose scalar character boundaries")
  func scalarCharacterBoundariesAndIntegerRoundTrips() throws {
    let stringResult = try evaluateIO(
      """
      (let ((s "e\u{301}") (mark (integer->char 769)))
        (let ((first (string-ref s 0)) (second (string-ref s 1)))
          (list (string-length s) (char? first) (char? second)
                (char->integer first) (char->integer second)
                (char=? second mark)
                (char=? (integer->char (char->integer first)) #\\e)
                (char=? (integer->char (char->integer second)) mark))))
      """
    )
    #expect(stringResult.written == "(2 #t #t 101 769 #t #t #t)")

    let portResult = try evaluateIO(
      """
      (call-with-input-string "e\u{301}"
        (lambda (p)
          (let ((first (read-char p)) (second (read-char p)))
            (list (char? first) (char? second)
                  (char->integer first) (char->integer second)))))
      """
    )
    #expect(portResult.written == "(#t #t 101 769)")
  }

  @Test("public string and character values preserve a safe scalar write/read boundary")
  func publicScalarValueBoundary() throws {
    let cluster = Character("e\u{301}")
    let string = SchemeString("x")
    string.characters = [cluster]
    #expect(string.characters.count == 2)
    #expect(string.characters.allSatisfy { $0.unicodeScalars.count == 1 })

    let interpreter = Interpreter { _ in }
    let stringRead = try interpreter.read(Value.string(string).written)
    #expect(stringRead.count == 1)
    if case .string(let roundTrip) = stringRead.first {
      #expect(roundTrip.characters.count == 2)
      #expect(roundTrip.characters.allSatisfy { $0.unicodeScalars.count == 1 })
    } else {
      #expect(Bool(false), "normalized string should read as a string")
    }

    let characterWritten = Value.character(cluster).written
    #expect(characterWritten == "\"e\u{301}\"")
    let characterRead = try interpreter.read(characterWritten)
    #expect(characterRead.count == 1)
    if case .string(let roundTrip) = characterRead.first {
      #expect(roundTrip.characters.count == 2)
    } else {
      #expect(Bool(false), "invalid host character should write as a string datum")
    }

    func expectScalarString(_ values: [Value], _ label: String) {
      #expect(values.count == 1, "\(label)")
      guard values.count == 1, case .string(let value) = values[0] else {
        #expect(Bool(false), "\(label)")
        return
      }
      #expect(value.characters.count == 2, "\(label)")
      #expect(value.characters.allSatisfy { $0.unicodeScalars.count == 1 }, "\(label)")
    }

    for cluster in [Character("\"\u{301}"), Character("\\\u{301}")] {
      expectScalarString(
        try interpreter.read(Value.character(cluster).written),
        "host character quote/backslash fallback"
      )
    }
    for base in ["\"", "\\"] {
      let source = SchemeString("")
      source.characters = [Character(base), Character("\u{301}")]
      expectScalarString(
        try interpreter.read(Value.string(source).written),
        "normalized string quote/backslash boundary"
      )
    }
  }

  @Test("R5RS §6.3.2 list consumers reject non-list and improper arguments")
  func listArgumentDomains() {
    expectIOError("(list-tail 1 0)", "list-tail scalar domain")
    expectIOError("(list-tail '(a . b) 0)", "list-tail improper domain")
    expectIOError("(list-tail '(a) 2)", "list-tail bounds")
    expectIOError("(memq 'a 1)", "memq scalar domain")
    expectIOError("(memq 'z '(a . b))", "memq improper domain")
    expectIOError("(let ((x (cons 'a '()))) (set-cdr! x x) (memq 'z x))", "memq cyclic domain")
    expectIOError("(memv 'a 1)", "memv scalar domain")
    expectIOError("(memv 'z '(a . b))", "memv improper domain")
    expectIOError("(member 'a 1)", "member scalar domain")
    expectIOError("(member 'z '(a . b))", "member improper domain")
  }

  @Test("list-tail and membership preserve valid list results") func validListConsumers() throws {
    let result = try evaluateIO(
      "(list (list-tail '(a b c) 0) (list-tail '(a b c) 2) "
        + "(memq 'b '(a b c)) (memv 2 '(1 2 3)) (member '(b) '((a) (b))))"
    )
    #expect(result.written == "((a b c) (c) (b c) (2 3) ((b)))")
  }

  @Test("read-created pairs, strings, and vectors remain mutable") func readValuesAreMutable()
    throws
  {
    #expect(
      try evaluateIO(
        "(call-with-input-string \"(1 2)\" (lambda (p) (let ((x (read p))) (set-car! x 9) x)))"
      ).written == "(9 2)"
    )
    #expect(
      try evaluateIO(
        "(call-with-input-string \"\\\"abc\\\"\" (lambda (p) (let ((s (read p))) (string-set! s "
          + "1 #\\z) s)))"
      ).written == "\"azc\""
    )
    #expect(
      try evaluateIO(
        "(call-with-input-string \"#(1 2)\" (lambda (p) (let ((v (read p))) (vector-set! v 0 9) "
          + "v)))"
      ).written == "#(9 2)"
    )
  }

  @Test("input ports obey read, peek, EOF, readiness, and close contracts") func inputPortMatrix()
    throws
  {
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

  @Test("omitted input ports reject a closed current input port") func closedCurrentInputDefaults()
  {
    for operation in ["read", "read-char", "peek-char", "char-ready?"] {
      expectIOError(
        "(let ((p (current-input-port))) (close-input-port p) (\(operation)))",
        "closed current input for \(operation)"
      )
    }
  }

  @Test("output ports distinguish write, display, and character output") func outputPortMatrix()
    throws
  {
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

  @Test("omitted output ports reject a closed current output port")
  func closedCurrentOutputDefaults() {
    let operations = [
      ("(write 'still-writes)", "write"), ("(display 'still-displays)", "display"),
      ("(newline)", "newline"), ("(write-char #\\!)", "write-char"),
    ]
    for (operation, name) in operations {
      expectIOError(
        "(let ((p (current-output-port))) (close-output-port p) \(operation))",
        "closed current output for \(name)"
      )
    }
  }

  @Test("closed explicit ports retain mode predicates and remain invalid for I/O")
  func closedExplicitPortContracts() throws {
    let result = try evaluateIO(
      """
      (let ((input (open-input-string "x")) (output (open-output-string)))
        (close-input-port input)
        (close-input-port input)
        (close-output-port output)
        (close-output-port output)
        (list (port? input) (input-port? input) (output-port? input)
              (port? output) (input-port? output) (output-port? output)))
      """
    )
    #expect(result.written == "(#t #t #f #t #f #t)")
    expectIOError(
      "(let ((p (open-input-string \"x\"))) (close-input-port p) (read-char p))",
      "explicit closed input port"
    )
    expectIOError(
      "(let ((p (open-output-string))) (close-output-port p) (write 'x p))",
      "explicit closed output port"
    )
  }

  @Test("vectors preserve mutation and list conversion contracts") func vectorMatrix() throws {
    let result = try evaluateIO(
      "(let ((v (make-vector 3 0))) (vector-fill! v 7) (list (vector-length v) (vector-ref v 1) "
        + "(vector->list v) (list->vector '(a b))))"
    )
    #expect(result.written == "(3 7 (7 7 7) #(a b))")
    expectIOError("(vector-ref '#(1) 1)", "vector index")
    expectIOError("(make-vector -1)", "negative vector length")
  }

  @Test("load evaluates source in the interaction environment") func loadAndFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "swiftscheme-r5rs-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("loaded.scm").path
    try "(define loaded-value 41) (+ loaded-value 1)".write(
      toFile: path,
      atomically: true,
      encoding: .utf8
    )
    let quotedPath =
      "\""
      + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
        of: "\"",
        with: "\\\""
      ) + "\""
    let interpreter = Interpreter { _ in }
    _ = try interpreter.evaluate("(load \(quotedPath))")
    #expect(try interpreter.evaluate("loaded-value").written == "41")
    #expect(try interpreter.evaluate("(load \(quotedPath))").written == "#<unspecified>")
  }
}
