import SwiftScheme
import Testing

@MainActor @Suite("R5RS reader and external-form boundaries") struct R5RSReaderBoundaryTests {
  private func interpreter() -> Interpreter { Interpreter { _ in } }

  @Test("malformed complete external forms report SchemeError") func malformedExternalForms() {
    let sources = [
      ")", "(a .)", "(a . b c)", "#\\", "#\\not-a-character", "#(a", "\"unterminated", "1e#",
      "1/2.0", "1+2#3i", "[]", "a|b", "#q",
    ]
    for source in sources {
      do {
        _ = try interpreter().read(source)
        #expect(Bool(false), "expected malformed form to fail: \(source)")
      } catch is SchemeError {
        // Expected.
      } catch { #expect(Bool(false), "unexpected error for \(source): \(error)") }
    }
  }

  @Test("interactive completeness distinguishes incomplete input from complete errors")
  func interactiveCompleteness() {
    let reader = interpreter()
    for source in ["(", "'", "\"", "#\\", "#(", "(a"] {
      #expect(!reader.isComplete(source), "expected incomplete input: \(source)")
    }
    for source in [")", "(a .)", "(a . b c)", "1e#", "a|b"] {
      #expect(reader.isComplete(source), "expected complete diagnostic input: \(source)")
    }
    #expect(!reader.isComplete("(a . b"), "a dotted tail ending at EOF is incomplete")
  }

  @Test("one-character literals terminate without a delimiter") func characterLiteralTermination()
    throws
  {
    let reader = interpreter()
    for (source, first, second) in [
      ("#\\(a", "#\\(", "a"), ("#\\1foo", "#\\1", "foo"), ("#\\;foo", "#\\;", "foo"),
    ] {
      let values = try reader.read(source)
      #expect(values.count == 2, "source: \(source)")
      #expect(values[0].written == first, "source: \(source)")
      #expect(values[1].written == second, "source: \(source)")
    }
  }

  @Test("comments terminate on LF, CR, and CRLF source lines") func commentLineEndings() throws {
    for source in ["; comment\r1", "; comment\r\n1", "; comment\n1"] {
      #expect(
        try interpreter().read(source).first?.written == "1",
        "source: \(source.debugDescription)"
      )
    }
  }

  @Test("CR-only comment boundaries preserve diagnostic line numbers")
  func carriageReturnDiagnosticLocation() {
    for source in ["; comment\r)", "; comment\r\n)"] {
      do {
        _ = try interpreter().read(source)
        #expect(Bool(false), "expected malformed form: \(source.debugDescription)")
      } catch let error as SchemeError {
        guard case .lexical(_, let line, _) = error else {
          #expect(Bool(false), "expected lexical error, got \(error)")
          continue
        }
        #expect(line == 2, "source: \(source.debugDescription)")
      } catch { #expect(Bool(false), "unexpected error: \(error)") }
    }
  }

  @Test("supported external forms round-trip through read and write") func externalRoundTrips()
    throws
  {
    let forms = [
      "'a", "(a 1 #t \"x\\\\y\" . b)", "#(a #\\space 1/2)", "#\\newline", "#e3/2", "1+2i", "#xFF",
      "`(a ,b)",
    ]
    let reader = interpreter()
    for source in forms {
      let values = try reader.read(source)
      #expect(values.count == 1, "expected one datum: \(source)")
      guard let value = values.first else { continue }
      let printed = reader.write(value)
      let reread = try reader.read(printed)
      #expect(reread.count == 1, "written form did not reread: \(printed)")
      guard let rereadValue = reread.first else { continue }
      #expect(rereadValue.written == printed, "round-trip changed \(source) to \(printed)")
    }
  }
}
