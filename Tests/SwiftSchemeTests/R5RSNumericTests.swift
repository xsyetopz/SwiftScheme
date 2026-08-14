import SwiftScheme
import Testing

@MainActor private func r5rsEvaluate(_ source: String) throws -> Value {
  try Interpreter(output: { _ in }).evaluate(source)
}

@MainActor private func r5rsExpectError(_ source: String, _ label: String) throws {
  do {
    _ = try r5rsEvaluate(source)
    #expect(Bool(false), "\(label): expected SchemeError")
  } catch is SchemeError {
    // The R5RS grammar classifies this input as invalid; the exact diagnostic is implementation-defined.
  }
}

@Suite("R5RS §7.1.1 numeric and external-form grammar") struct R5RSNumericTests {
  @Test("radix placeholders are accepted and remain inexact") @MainActor func radixPlaceholders()
    throws
  {
    let cases: [(literal: String, written: String)] = [
      ("#b1#", "2.0"), ("#i#b1#", "2.0"), ("#b#i1#", "2.0"), ("#o7#", "56.0"), ("#d12#", "120.0"),
      ("#xF#", "240.0"), ("#xF##", "3840.0"), ("1#", "10.0"), ("1##", "100.0"), (".1#", "0.1"),
      ("1.#", "1.0"), ("1#.", "10.0"), ("1#.#", "10.0"), ("1.2#", "1.2"), ("1#e2", "1000.0"),
      ("#b1#/1", "2.0"), ("#xF#/A#", "1.5"), ("1+2#i", "1+20.0i")
    ]
    for item in cases {
      let value = try r5rsEvaluate(item.literal)
      #expect(value.written == item.written, "\(item.literal): unexpected value \(value.written)")
      if case .real = value {
        // Every placeholder form must produce an inexact real, not an exact integer.
        #expect(try r5rsEvaluate("(inexact? \(item.literal))").written == "#t")
      } else if item.literal.contains("i") {
        #expect(try r5rsEvaluate("(inexact? \(item.literal))").written == "#t")
      } else {
        #expect(Bool(false), "\(item.literal): expected a real value")
      }
    }
  }

  @Test("decimal, rational, and complex placements follow the grammar") @MainActor
  func validNumericForms() throws {
    let exact: [(String, String)] = [
      ("0", "0"), ("+12", "12"), ("-12", "-12"), ("1/2", "1/2"), ("#e1.0", "1"), ("#e1e2", "100"),
      ("#e1e-2", "1/100"), ("1+2i", "1+2i"), ("1+i", "1+1i"), ("-1-i", "-1-1i"), ("+i", "0+1i"),
      ("-i", "0-1i"), ("#b1+1i", "1+1i"), ("#o7/7", "1"), ("#xF/A", "3/2")
    ]
    for (literal, written) in exact {
      let value = try r5rsEvaluate(literal)
      #expect(value.written == written, "\(literal): unexpected value \(value.written)")
      #expect(try r5rsEvaluate("(exact? \(literal))").written == "#t")
    }

    let inexact: [(String, String)] = [
      ("1.0", "1.0"), (".5", "0.5"), ("1.", "1.0"), ("1e2", "100.0"), ("1e-2", "0.01"),
      ("1.2e+2", "120.0"), ("#i1", "1.0"), ("#i1/2", "0.5"), ("#i+i", "0+1.0i"),
      ("#i1+i", "1.0+1.0i"), ("#i1-i", "1.0-1.0i"), ("1e+2+3i", "100.0+3i"), ("1+2.0i", "1+2.0i"),
      ("+1.0i", "0+1.0i")
    ]
    for (literal, written) in inexact {
      let value = try r5rsEvaluate(literal)
      #expect(value.written == written, "\(literal): unexpected value \(value.written)")
      #expect(try r5rsEvaluate("(inexact? \(literal))").written == "#t")
    }

    let polar = try r5rsEvaluate("1@2")
    if case .complex = polar {
      #expect(Bool(true))
    } else {
      #expect(Bool(false), "polar form must produce a complex number")
    }
  }

  @Test("invalid placeholder, exponent, and component placements are rejected") @MainActor
  func invalidNumericForms() throws {
    let invalid = [
      "1e#", "1e2#", "1e+2#", "#e1#", "#e1e#", "#e1e2#", "1#2", "1.#2", "1#.#2", ".#", "#.", "1##2",
      "1.0/2", "1/2.0", "1e2/3", "1/2e3", "1+2#3i", "1++2i", "1+-2i", "1@2@3", "1@2i", "i", "#b1.0",
      "#o7.0", "#xF.0", "#b1e2", "#b#b1", "#e#e1", "#i#i1", "#b#x1", "#e#b1#"
    ]
    for literal in invalid { try r5rsExpectError(literal, literal) }
    try r5rsExpectError("(rationalize 1 -1)", "negative rationalize tolerance")
  }

  @Test("reserved lexical characters are not identifiers") @MainActor func reservedCharacters()
    throws
  {
    for character in ["[", "]", "{", "}", "|"] {
      try r5rsExpectError(character, character)
      try r5rsExpectError("name\(character)", "name\(character)")
    }
  }

  @Test("malformed numeric-looking tokens fail without rejecting valid identifiers") @MainActor
  func invalidVersusSymbolDiagnostics() throws {
    for token in ["+foo", "-foo", ".foo", ".", "..", "...foo", "@", "foo#bar", "foo\\bar", "λ"] {
      try r5rsExpectError(token, token)
    }
    for token in ["+", "-", "...", "foo+bar", "foo-bar", "foo.bar", "foo@bar", "!", "_"] {
      let value = try r5rsEvaluate("'\(token)")
      if case .symbol = value {
        #expect(Bool(true))
      } else {
        #expect(Bool(false), "\(token): expected an identifier symbol")
      }
    }
  }

  @Test("string external forms use only R5RS escapes and preserve newlines") @MainActor
  func stringExternalForms() throws {
    for control in ["\n", "\r", "\t"] {
      let source = "\"line one\(control)line two\""
      let value = try r5rsEvaluate(source)
      #expect(value.written == source, "raw string control must round-trip: \(control.utf8)")
    }

    let escaped = "\"quote: \\\" and slash: \\\\\""
    let escapedValue = try r5rsEvaluate(escaped)
    #expect(escapedValue.written == escaped)

    for escape in ["n", "r", "t", "a"] {
      try r5rsExpectError("\"bad\\\(escape)escape\"", "\\\(escape) escape")
    }
  }
}
