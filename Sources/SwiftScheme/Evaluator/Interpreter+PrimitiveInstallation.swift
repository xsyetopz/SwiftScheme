import Foundation
import SwiftSchemeFrontend
import SwiftSchemeNumeric
import SwiftSchemePrimitives
import SwiftSchemeRuntime

let r5rsReportProcedureNames: Set<String> = [
  "eq?", "eqv?", "equal?", "number?", "complex?", "real?", "rational?", "integer?", "exact?",
  "inexact?", "=", "<", ">", "<=", ">=", "zero?", "positive?", "negative?", "odd?", "even?", "max",
  "min", "+", "*", "-", "/", "abs", "quotient", "remainder", "modulo", "gcd", "lcm", "numerator",
  "denominator", "floor", "ceiling", "truncate", "round", "rationalize", "exp", "log", "sin", "cos",
  "tan", "asin", "acos", "atan", "sqrt", "expt", "make-rectangular", "make-polar", "real-part",
  "imag-part", "magnitude", "angle", "exact->inexact", "inexact->exact", "number->string",
  "string->number", "not", "boolean?", "pair?", "cons", "car", "cdr", "set-car!", "set-cdr!",
  "caar", "cadr", "cdar", "cddr", "caaar", "caadr", "cadar", "caddr", "cdaar", "cdadr", "cddar",
  "caaaar", "caaadr", "caadar", "caaddr", "cadaar", "cadadr", "caddar", "cadddr", "cdaaar",
  "cdaadr", "cdadar", "cdaddr", "cddaar", "cddadr", "cdddar", "cddddr", "null?", "list?", "list",
  "length", "append", "reverse", "list-tail", "list-ref", "memq", "memv", "member", "assq", "assv",
  "assoc", "symbol?", "symbol->string", "string->symbol", "char?", "char=?", "char<?", "char>?",
  "char<=?", "char>=?", "char-ci=?", "char-ci<?", "char-ci>?", "char-ci<=?", "char-ci>=?",
  "char-alphabetic?", "char-numeric?", "char-whitespace?", "char-upper-case?", "char-lower-case?",
  "char-upcase", "char-downcase", "char->integer", "integer->char", "string?", "make-string",
  "string", "string-length", "string-ref", "string-set!", "substring", "string-append",
  "string->list", "list->string", "string-copy", "string-fill!", "string=?", "string<?", "string>?",
  "string<=?", "string>=?", "string-ci=?", "string-ci<?", "string-ci>?", "string-ci<=?",
  "string-ci>=?", "vector?", "make-vector", "vector", "vector-length", "vector-ref", "vector-set!",
  "vector->list", "list->vector", "vector-fill!", "procedure?", "port?", "apply",
  "call-with-current-continuation", "map", "for-each", "values", "call-with-values", "dynamic-wind",
  "force", "eval", "scheme-report-environment", "null-environment", "input-port?", "output-port?",
  "current-input-port", "current-output-port", "call-with-input-file", "call-with-output-file",
  "open-input-file", "open-output-file", "close-input-port", "close-output-port", "read",
  "read-char", "peek-char", "eof-object?", "char-ready?", "write", "display", "newline",
  "write-char", "interaction-environment", "with-input-from-file", "with-output-to-file", "load"
]

extension Interpreter {
  func primitive(
    _ name: String,
    in environment: SchemeEnvironment,
    _ body: @escaping ([Value]) throws -> Value
  ) { environment.define(name, .procedure(Procedure(.primitive(name) { [try body($0)] }))) }

  func multiPrimitive(
    _ name: String,
    in environment: SchemeEnvironment,
    _ body: @escaping ([Value]) throws -> [Value]
  ) { environment.define(name, .procedure(Procedure(.primitive(name, body)))) }

  func special(_ name: String, _ special: Special, in environment: SchemeEnvironment) {
    environment.define(name, .procedure(Procedure(.special(special))))
  }

  func installPrimitives(in env: SchemeEnvironment) {
    installNumericPrimitives(in: env)
    installDataPrimitives(in: env)
    installControlAndIOPrimitives(in: env)
  }
}
