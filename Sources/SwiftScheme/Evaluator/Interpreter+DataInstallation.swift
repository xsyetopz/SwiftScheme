import Foundation
import SwiftSchemeFrontend
import SwiftSchemeNumeric
import SwiftSchemePrimitives
import SwiftSchemeRuntime

extension Interpreter {
  func installDataPrimitives(in env: SchemeEnvironment) {
    primitive("cons", in: env) {
      try require($0, 2, "cons")
      return .pair(Pair($0[0], $0[1]))
    }
    primitive("car", in: env) {
      try require($0, 1, "car")
      return try pair($0[0], "car").car
    }
    primitive("cdr", in: env) {
      try require($0, 1, "cdr")
      return try pair($0[0], "cdr").cdr
    }
    primitive("set-car!", in: env) {
      try require($0, 2, "set-car!")
      let target = try pair($0[0], "set-car!")
      guard !target.isLiteral else { throw SchemeError.type("cannot mutate a literal pair") }
      target.car = $0[1]
      return .unspecified
    }
    primitive("set-cdr!", in: env) {
      try require($0, 2, "set-cdr!")
      let target = try pair($0[0], "set-cdr!")
      guard !target.isLiteral else { throw SchemeError.type("cannot mutate a literal pair") }
      target.cdr = $0[1]
      return .unspecified
    }
    primitive("list", in: env) { makeList($0) }
    primitive("length", in: env) {
      try require($0, 1, "length")
      return .integer(BigInt(try array(from: $0[0]).count))
    }
    primitive("append", in: env) { args in
      var result = args.last ?? .empty
      for list in args.dropLast().reversed() {
        result = makeList(try array(from: list, context: "append"), tail: result)
      }
      return result
    }
    primitive("reverse", in: env) {
      try require($0, 1, "reverse")
      return makeList(try array(from: $0[0]).reversed())
    }
    primitive("list-tail", in: env) { args in
      try require(args, 2, "list-tail")
      let count = try array(from: args[0], context: "list-tail").count
      let offset = try index(args[1], "list-tail")
      guard offset <= count else { throw SchemeError.numeric("index out of range") }
      var value = args[0]
      for _ in 0..<offset { value = try pair(value, "list-tail").cdr }
      return value
    }
    primitive("list-ref", in: env) { args in
      try require(args, 2, "list-ref")
      let values = try array(from: args[0])
      let index = try index(args[1], "list-ref")
      guard index < values.count else { throw SchemeError.numeric("index out of range") }
      return values[index]
    }
    for name in ["pair?", "null?", "list?"] {
      primitive(name, in: env) { args in
        try require(args, 1, name)
        if name == "pair?" { if case .pair = args[0] { return .boolean(true) } }
        if name == "null?" { if case .empty = args[0] { return .boolean(true) } }
        if name == "list?" { return .boolean((try? array(from: args[0])) != nil) }
        return .boolean(false)
      }
    }
    for depth in 2...4 {
      let count = 1 << depth
      for bits in 0..<count {
        var name = "c"
        var operations: [Character] = []
        for shift in (0..<depth).reversed() {
          let c: Character = ((bits >> shift) & 1) == 0 ? "a" : "d"
          name.append(c)
          operations.append(c)
        }
        name += "r"
        primitive(name, in: env) { args in
          try require(args, 1, name)
          var value = args[0]
          for operation in operations.reversed() {
            let p = try pair(value, name)
            value = operation == "a" ? p.car : p.cdr
          }
          return value
        }
      }
    }
    for name in ["memq", "memv", "member"] {
      primitive(name, in: env) { args in
        try require(args, 2, name)
        let values = try array(from: args[1], context: name)
        var cursor = args[1]
        for value in values {
          let p = try pair(cursor, name)
          let found =
            name == "memq"
            ? eq(args[0], value) : name == "memv" ? eqv(args[0], value) : equal(args[0], value)
          if found { return cursor }
          cursor = p.cdr
        }
        return .boolean(false)
      }
    }
    for name in ["assq", "assv", "assoc"] {
      primitive(name, in: env) { args in
        try require(args, 2, name)
        for item in try array(from: args[1], context: name) {
          let p = try pair(item, name)
          let found =
            name == "assq"
            ? eq(args[0], p.car) : name == "assv" ? eqv(args[0], p.car) : equal(args[0], p.car)
          if found { return item }
        }
        return .boolean(false)
      }
    }

    primitive("not", in: env) {
      try require($0, 1, "not")
      return .boolean(isFalse($0[0]))
    }
    primitive("boolean?", in: env) {
      try predicate($0, "boolean?") { if case .boolean = $0 { true } else { false } }
    }
    primitive("symbol?", in: env) {
      try predicate($0, "symbol?") { if case .symbol = $0 { true } else { false } }
    }
    primitive("char?", in: env) {
      try predicate($0, "char?") {
        guard case .character(let character) = $0 else { return false }
        return character.unicodeScalars.count == 1
      }
    }
    primitive("string?", in: env) {
      try predicate($0, "string?") { if case .string = $0 { true } else { false } }
    }
    primitive("vector?", in: env) {
      try predicate($0, "vector?") { if case .vector = $0 { true } else { false } }
    }
    primitive("port?", in: env) {
      try predicate($0, "port?") { if case .port = $0 { true } else { false } }
    }
    primitive("input-port?", in: env) {
      try predicate($0, "input-port?") {
        if case .port(let p) = $0 { return p.mode == .input }
        return false
      }
    }
    primitive("output-port?", in: env) {
      try predicate($0, "output-port?") {
        if case .port(let p) = $0 { return p.mode == .output }
        return false
      }
    }
    primitive("procedure?", in: env) {
      try predicate($0, "procedure?") { if case .procedure = $0 { true } else { false } }
    }
    primitive("eq?", in: env) {
      try require($0, 2, "eq?")
      return .boolean(eq($0[0], $0[1]))
    }
    primitive("eqv?", in: env) {
      try require($0, 2, "eqv?")
      return .boolean(eqv($0[0], $0[1]))
    }
    primitive("equal?", in: env) {
      try require($0, 2, "equal?")
      return .boolean(equal($0[0], $0[1]))
    }

    primitive("symbol->string", in: env) { args in
      try require(args, 1, "symbol->string")
      guard case .symbol(let s) = args[0] else { throw SchemeError.type("expected symbol") }
      let string = SchemeString(symbolSpelling(s))
      string.isLiteral = true
      return .string(string)
    }
    primitive("string->symbol", in: env) { args in
      try require(args, 1, "string->symbol")
      let spelling = try schemeString(args[0], "string->symbol").string
      return .symbol(symbolToken(spelling))
    }
    primitive("char->integer", in: env) {
      try require($0, 1, "char->integer")
      return .integer(BigInt(Int64(try scalar(character($0[0], "char->integer")))))
    }
    primitive("integer->char", in: env) {
      try require($0, 1, "integer->char")
      guard let codepoint = try exactInteger($0[0], "integer->char").exactInt,
        let scalar = UnicodeScalar(codepoint)
      else { throw SchemeError.numeric("invalid character") }
      return .character(Character(String(scalar)))
    }
    for name in [
      "char=?", "char<?", "char>?", "char<=?", "char>=?", "char-ci=?", "char-ci<?", "char-ci>?",
      "char-ci<=?", "char-ci>=?",
    ] {
      primitive(name, in: env) { args in
        guard args.count >= 2 else {
          throw SchemeError.arity("\(name) expects at least 2 arguments")
        }
        let characters = try args.map { try character($0, name) }
        let chars: [String] =
          name.contains("-ci") ? characters.map(scalarCaseKey) : characters.map(String.init)
        return .boolean(zip(chars, chars.dropFirst()).allSatisfy { compare($0, $1, name) })
      }
    }
    primitive("char-alphabetic?", in: env) {
      try charPredicate($0, "char-alphabetic?", isScalarCaseCharacter)
    }
    primitive("char-numeric?", in: env) { try charPredicate($0, "char-numeric?") { $0.isNumber } }
    primitive("char-whitespace?", in: env) {
      try charPredicate($0, "char-whitespace?") { $0.isWhitespace }
    }
    primitive("char-upper-case?", in: env) {
      try charPredicate($0, "char-upper-case?") { isScalarCaseCharacter($0) && $0.isUppercase }
    }
    primitive("char-lower-case?", in: env) {
      try charPredicate($0, "char-lower-case?") { isScalarCaseCharacter($0) && $0.isLowercase }
    }
    primitive("char-upcase", in: env) {
      try require($0, 1, "char-upcase")
      return .character(scalarCaseMap(try character($0[0], "char-upcase"), upper: true))
    }
    primitive("char-downcase", in: env) {
      try require($0, 1, "char-downcase")
      return .character(scalarCaseMap(try character($0[0], "char-downcase"), upper: false))
    }

    primitive("string", in: env) {
      .string(SchemeString(characters: try $0.map { try character($0, "string") }))
    }
    primitive("make-string", in: env) { args in
      guard args.count == 1 || args.count == 2 else {
        throw SchemeError.arity("make-string expects 1 or 2 arguments")
      }
      let result = SchemeString("")
      result.characters = Array(
        repeating: args.count == 2 ? try character(args[1], "make-string") : " ",
        count: try index(args[0], "make-string")
      )
      return .string(result)
    }
    primitive("string-length", in: env) {
      try require($0, 1, "string-length")
      return .integer(BigInt(try schemeString($0[0], "string-length").characters.count))
    }
    primitive("string-ref", in: env) { args in
      try require(args, 2, "string-ref")
      let string = try schemeString(args[0], "string-ref")
      let i = try index(args[1], "string-ref")
      guard i < string.characters.count else { throw SchemeError.numeric("index out of range") }
      return .character(string.characters[i])
    }
    primitive("string-set!", in: env) { args in
      try require(args, 3, "string-set!")
      let string = try schemeString(args[0], "string-set!")
      guard !string.isLiteral else { throw SchemeError.type("cannot mutate a literal string") }
      let i = try index(args[1], "string-set!")
      guard i < string.characters.count else { throw SchemeError.numeric("index out of range") }
      string.characters[i] = try character(args[2], "string-set!")
      return .unspecified
    }
    primitive("substring", in: env) { args in
      try require(args, 3, "substring")
      let chars = try schemeString(args[0], "substring").characters
      let a = try index(args[1], "substring")
      let b = try index(args[2], "substring")
      guard a <= b && b <= chars.count else { throw SchemeError.numeric("invalid substring range") }
      return .string(SchemeString(characters: Array(chars[a..<b])))
    }
    primitive("string-append", in: env) {
      .string(
        SchemeString(
          characters: try $0.flatMap { try schemeString($0, "string-append").characters }
        )
      )
    }
    primitive("string->list", in: env) {
      try require($0, 1, "string->list")
      return makeList(try schemeString($0[0], "string->list").characters.map(Value.character))
    }
    primitive("list->string", in: env) {
      try require($0, 1, "list->string")
      return .string(
        SchemeString(characters: try array(from: $0[0]).map { try character($0, "list->string") })
      )
    }
    primitive("string-copy", in: env) {
      try require($0, 1, "string-copy")
      return .string(SchemeString(characters: try schemeString($0[0], "string-copy").characters))
    }
    primitive("string-fill!", in: env) { args in
      try require(args, 2, "string-fill!")
      let string = try schemeString(args[0], "string-fill!")
      guard !string.isLiteral else { throw SchemeError.type("cannot mutate a literal string") }
      string.characters = Array(
        repeating: try character(args[1], "string-fill!"),
        count: string.characters.count
      )
      return .unspecified
    }
    for name in [
      "string=?", "string<?", "string>?", "string<=?", "string>=?", "string-ci=?", "string-ci<?",
      "string-ci>?", "string-ci<=?", "string-ci>=?",
    ] {
      primitive(name, in: env) { args in
        guard args.count >= 2 else {
          throw SchemeError.arity("\(name) expects at least 2 arguments")
        }
        let values = try args.map { try schemeString($0, name) }
        let keys = values.map { value in
          value.characters.map(name.contains("-ci") ? scalarCaseKey : String.init)
        }
        return .boolean(
          zip(keys, keys.dropFirst()).allSatisfy { compareCharacterKeys($0, $1, name) }
        )
      }
    }

    primitive("vector", in: env) { .vector(SchemeVector($0)) }
    primitive("make-vector", in: env) { args in
      guard args.count == 1 || args.count == 2 else {
        throw SchemeError.arity("make-vector expects 1 or 2 arguments")
      }
      return .vector(
        SchemeVector(
          Array(
            repeating: args.count == 2 ? args[1] : .unspecified,
            count: try index(args[0], "make-vector")
          )
        )
      )
    }
    primitive("vector-length", in: env) {
      try require($0, 1, "vector-length")
      return .integer(BigInt(try vector($0[0], "vector-length").elements.count))
    }
    primitive("vector-ref", in: env) { args in
      try require(args, 2, "vector-ref")
      let vector = try vector(args[0], "vector-ref")
      let i = try index(args[1], "vector-ref")
      guard i < vector.elements.count else { throw SchemeError.numeric("index out of range") }
      return vector.elements[i]
    }
    primitive("vector-set!", in: env) { args in
      try require(args, 3, "vector-set!")
      let vector = try vector(args[0], "vector-set!")
      guard !vector.isLiteral else { throw SchemeError.type("cannot mutate a literal vector") }
      let i = try index(args[1], "vector-set!")
      guard i < vector.elements.count else { throw SchemeError.numeric("index out of range") }
      vector.elements[i] = args[2]
      return .unspecified
    }
    primitive("vector->list", in: env) {
      try require($0, 1, "vector->list")
      return makeList(try vector($0[0], "vector->list").elements)
    }
    primitive("list->vector", in: env) {
      try require($0, 1, "list->vector")
      return .vector(SchemeVector(try array(from: $0[0])))
    }
    primitive("vector-fill!", in: env) { args in
      try require(args, 2, "vector-fill!")
      let vector = try vector(args[0], "vector-fill!")
      guard !vector.isLiteral else { throw SchemeError.type("cannot mutate a literal vector") }
      vector.elements = Array(repeating: args[1], count: vector.elements.count)
      return .unspecified
    }

  }
}
