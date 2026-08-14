import SwiftScheme
import Testing

@Suite("R5RS §6 required procedure inventory") @MainActor struct R5RSProcedureInventoryTests {
  @Test("every required procedure name is bound as a procedure") func requiredProcedureBindings()
    throws
  {
    let names = [
      "eq?", "eqv?", "equal?", "number?", "complex?", "real?", "rational?", "integer?", "exact?",
      "inexact?", "=", "<", ">", "<=", ">=", "zero?", "positive?", "negative?", "odd?", "even?",
      "max", "min", "+", "*", "-", "/", "abs", "quotient", "remainder", "modulo", "gcd", "lcm",
      "numerator", "denominator", "floor", "ceiling", "truncate", "round", "rationalize", "exp",
      "log", "sin", "cos", "tan", "asin", "acos", "atan", "sqrt", "expt", "make-rectangular",
      "make-polar", "real-part", "imag-part", "magnitude", "angle", "exact->inexact",
      "inexact->exact", "number->string", "string->number", "not", "boolean?", "pair?", "cons",
      "car", "cdr", "set-car!", "set-cdr!", "caar", "cadr", "cdar", "cddr", "caaar", "caadr",
      "cadar", "caddr", "cdaar", "cdadr", "cddar", "caaaar", "caaadr", "caadar", "caaddr", "cadaar",
      "cadadr", "caddar", "cadddr", "cdaaar", "cdaadr", "cdadar", "cdaddr", "cddaar", "cddadr",
      "cdddar", "cddddr", "null?", "list?", "list", "length", "append", "reverse", "list-tail",
      "list-ref", "memq", "memv", "member", "assq", "assv", "assoc", "symbol?", "symbol->string",
      "string->symbol", "char?", "char=?", "char<?", "char>?", "char<=?", "char>=?", "char-ci=?",
      "char-ci<?", "char-ci>?", "char-ci<=?", "char-ci>=?", "char-alphabetic?", "char-numeric?",
      "char-whitespace?", "char-upper-case?", "char-lower-case?", "char-upcase", "char-downcase",
      "char->integer", "integer->char", "string?", "make-string", "string", "string-length",
      "string-ref", "string-set!", "substring", "string-append", "string->list", "list->string",
      "string-copy", "string-fill!", "string=?", "string<?", "string>?", "string<=?", "string>=?",
      "string-ci=?", "string-ci<?", "string-ci>?", "string-ci<=?", "string-ci>=?", "vector?",
      "make-vector", "vector", "vector-length", "vector-ref", "vector-set!", "vector->list",
      "list->vector", "vector-fill!", "procedure?", "port?", "call-with-current-continuation",
      "apply", "map", "for-each", "values", "force", "eval", "call-with-values", "dynamic-wind",
      "scheme-report-environment", "null-environment", "input-port?", "output-port?",
      "call-with-input-file", "call-with-output-file", "open-input-file", "open-output-file",
      "close-input-port", "close-output-port", "current-input-port", "current-output-port", "read",
      "read-char", "peek-char", "eof-object?", "char-ready?", "write", "display", "newline",
      "write-char"
    ]
    let interpreter = Interpreter(output: { _ in })
    for name in Set(names) {
      #expect(
        try interpreter.evaluate("(procedure? \(name))").written == "#t",
        "missing required procedure binding: \(name)"
      )
    }
  }

  @Test("supported optional procedure names are bound separately")
  func supportedOptionalProcedureBindings() throws {
    let names = ["interaction-environment", "with-input-from-file", "with-output-to-file", "load"]
    let interpreter = Interpreter(output: { _ in })
    for name in names {
      #expect(
        try interpreter.evaluate("(procedure? \(name))").written == "#t",
        "missing supported optional procedure binding: \(name)"
      )
    }
  }
}
