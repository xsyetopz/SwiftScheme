import Foundation
import SwiftScheme
import Testing

@MainActor private func expectIOEdgeError(_ source: String, _ label: String) {
  do {
    _ = try Interpreter { _ in }.evaluate(source)
    #expect(Bool(false), "\(label): expected an error")
  } catch is SchemeError {} catch {
    #expect(Bool(false), "\(label): expected SchemeError, got \(error)")
  }
}

@Suite("R5RS cyclic data I/O edges") @MainActor struct R5RSIODataEdgeTests {
  @Test("eval rejects cyclic data without recursive descent") func evalCyclicData() {
    expectIOEdgeError(
      "(let ((p (cons 'p '()))) (set-car! p p) " + "(eval p (interaction-environment)))",
      "cyclic pair expression"
    )
    expectIOEdgeError(
      "(let ((v (vector #f))) (vector-set! v 0 v) " + "(eval v (interaction-environment)))",
      "cyclic vector expression"
    )
  }
  @Test("R5RS predicates distinguish the principal value domains") func predicateDomainMatrix()
    throws
  {
    let result = try Interpreter { _ in }.evaluate(
      "(list (boolean? #t) (symbol? 'a) (char? #\\a) (vector? '#()) "
        + "(pair? '(a)) (number? 1) (string? \"\") "
        + "(port? (current-input-port)) (input-port? (current-input-port)) "
        + "(output-port? (current-output-port)) (procedure? +) (eof-object? (read)))"
    )
    #expect(result.written == "(#t #t #t #t #t #t #t #t #t #t #t #t)")
  }

  @Test("cyclic lists are rejected by finite-list consumers") func cyclicListDomains() {
    for source in [
      "(let ((p (cons 1 '()))) (set-cdr! p p) (list? p))",
      "(let ((p (cons 1 '()))) (set-cdr! p p) (length p))",
      "(let ((p (cons 1 '()))) (set-cdr! p p) (reverse p))",
    ] {
      do {
        let value = try Interpreter { _ in }.evaluate(source)
        if source.contains("(list? p)") {
          #expect(value.written == "#f")
        } else {
          #expect(Bool(false), "expected cyclic list error: \(source)")
        }
      } catch is SchemeError {
        // Finite-list consumers must reject cyclic structure rather than recurse forever.
        #expect(!source.contains("(list? p)"), "list? should return #f")
      } catch { #expect(Bool(false), "unexpected error: \(error)") }
    }
  }

  @Test("char-ready? tracks string port exhaustion") func charReadyTracksExhaustion() throws {
    let value = try Interpreter { _ in }.evaluate(
      "(let ((p (open-input-string \"a\"))) " +
      "(list (char-ready? p) (read-char p) (char-ready? p) (eof-object? (read-char p))))"
    )
    #expect(value.written == "(#t #\\a #f #t)")
  }

  @Test("file open failures report Scheme I/O errors") func fileOpenFailures() {
    let directory = FileManager.default.temporaryDirectory
    let missing = directory.appendingPathComponent("swiftscheme-missing-\(UUID().uuidString)")
    let nested = missing.appendingPathComponent("child/output.scm")
    let missingText = String(reflecting: missing.path)
    let nestedText = String(reflecting: nested.path)
    expectIOEdgeError("(open-input-file \(missingText))", "missing input file")
    expectIOEdgeError("(open-output-file \(nestedText))", "uncreatable output file")
  }

}
