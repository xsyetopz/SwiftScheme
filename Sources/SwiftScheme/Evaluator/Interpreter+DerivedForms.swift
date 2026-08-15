import Foundation
import SwiftSchemeFrontend
import SwiftSchemeNumeric
import SwiftSchemePrimitives
import SwiftSchemeRuntime

extension Interpreter {
  func expandMacros(_ rawExpression: Value, in environment: SchemeEnvironment) throws -> Value {
    var expression = rawExpression
    while case .pair(let pair) = expression, case .symbol(let head) = pair.car,
      let transformer = environment.macro(head)
    { expression = try transformer.expand(expression, in: environment, serial: &macroSerial) }
    return expression
  }

  func isCoreForm(_ value: Value, _ name: String, in environment: SchemeEnvironment) -> Bool {
    guard case .pair(let pair) = value else { return false }
    if internalSyntaxName(pair.car) == name { return true }
    guard isSymbol(pair.car, name) else { return false }
    return environment.cell(name) == nil && environment.macro(name) == nil
  }

  func isDefinitionForm(_ value: Value, _ name: String, in environment: SchemeEnvironment) -> Bool {
    isCoreForm(value, name, in: environment)
  }

  func leadingBodyForms(_ body: [Value], in environment: SchemeEnvironment) throws -> [Value] {
    var pending = body
    var result: [Value] = []
    var leading = true
    while !pending.isEmpty {
      let form = pending.removeFirst()
      if leading, isCoreForm(form, "begin", in: environment) {
        let elements = try array(from: form, context: "begin")
        pending.insert(contentsOf: elements.dropFirst(), at: 0)
        continue
      }
      result.append(form)
      if !isDefinitionForm(form, "define", in: environment),
        !isDefinitionForm(form, "define-syntax", in: environment)
      {
        leading = false
      }
    }
    return result
  }

  func expandedBody(_ body: [Value], in environment: SchemeEnvironment) throws -> [Value] {
    var pending = body
    var expanded: [Value] = []
    while !pending.isEmpty {
      let form = try expandMacros(pending.removeFirst(), in: environment)
      if isCoreForm(form, "begin", in: environment) {
        let elements = try array(from: form, context: "begin")
        pending.insert(contentsOf: elements.dropFirst(), at: 0)
      } else {
        expanded.append(form)
      }
    }
    return expanded
  }

  func validateBody(_ body: [Value], context: String, in environment: SchemeEnvironment) throws {
    let expanded = try expandedBody(body, in: environment)
    var sawExpression = false
    for form in expanded {
      if isDefinitionForm(form, "define", in: environment)
        || isDefinitionForm(form, "define-syntax", in: environment)
      {
        if sawExpression { throw SchemeError.syntax("definition after expression in \(context)") }
        if isDefinitionForm(form, "define-syntax", in: environment) {
          throw SchemeError.syntax("define-syntax is only valid at top level")
        }
      } else {
        sawExpression = true
      }
    }
    guard sawExpression else { throw SchemeError.syntax("\(context) requires an expression") }
  }

  func prepareInternalDefinitions(_ body: [Value], in environment: SchemeEnvironment) throws {
    var names = Set<String>()
    let raw = try leadingBodyForms(body, in: environment)
    try prebindDefinitions(raw, in: environment, names: &names)
    let rawNames = names

    _ = try expandedBodyWithPrebinding(body, in: environment, names: &names, rawNames: rawNames)
  }

  func expandedBodyWithPrebinding(
    _ body: [Value],
    in environment: SchemeEnvironment,
    names: inout Set<String>,
    rawNames: Set<String>
  ) throws -> [Value] {
    var pending = body.map { ($0, true) }
    var expanded: [Value] = []
    var leading = true
    while !pending.isEmpty {
      let (rawForm, isRaw) = pending.removeFirst()
      let rawWasDefinition = isDefinitionForm(rawForm, "define", in: environment)
      let form = try expandMacros(rawForm, in: environment)
      if isCoreForm(form, "begin", in: environment) {
        let elements = try array(from: form, context: "begin")
        let literalRawBegin = isRaw && isCoreForm(rawForm, "begin", in: environment)
        pending.insert(contentsOf: elements.dropFirst().map { ($0, literalRawBegin) }, at: 0)
        continue
      }
      expanded.append(form)
      if leading, isDefinitionForm(form, "define", in: environment) {
        try prebindDefinitions(
          [form],
          in: environment,
          names: &names,
          allowExistingNames: isRaw && rawWasDefinition ? rawNames : []
        )
      } else if !isDefinitionForm(form, "define-syntax", in: environment) {
        leading = false
      }
    }
    return expanded
  }

  func prebindDefinitions(
    _ forms: [Value],
    in environment: SchemeEnvironment,
    names: inout Set<String>,
    allowExistingNames: Set<String> = []
  ) throws {
    for form in forms {
      guard isDefinitionForm(form, "define", in: environment), case .pair(let pair) = form else {
        break
      }
      let definition = try array(from: .pair(pair), context: "define")
      guard definition.count >= 3 else {
        throw SchemeError.syntax("define requires name and value")
      }
      let name: String
      if case .symbol = definition[1] {
        name = try identifier(definition[1], "define")
      } else {
        guard case .pair(let signature) = definition[1] else {
          throw SchemeError.syntax("invalid define")
        }
        name = try identifier(signature.car, "define")
      }
      guard !isDefinitionBoundaryKeyword(name) else {
        throw SchemeError.syntax("cannot define syntactic keyword \(name)")
      }
      if names.contains(name) {
        guard allowExistingNames.contains(name) else {
          throw SchemeError.syntax("duplicate internal definition \(name)")
        }
        continue
      }
      names.insert(name)
      environment.define(name, .undefined)
    }
  }

  func one(_ values: [Value], _ context: String) throws -> Value {
    guard values.count == 1 else {
      throw SchemeError.arity("\(context) expected one value, got \(values.count)")
    }
    return values[0]
  }

  func allowsDefinitions(in continuation: Continuation) -> Bool {
    switch continuation {
    case .halt: return true
    case .beginFrame(_, _, let allowed, _): return allowed
    default: return false
    }
  }

  func parseFormals(_ value: Value) throws -> Formals {
    var fixed: [String] = []
    var rest: String?
    var cursor = value
    if case .symbol(let name) = cursor {
      rest = name
      cursor = .empty
    }
    var seen = Set<ObjectIdentifier>()
    while case .pair(let pair) = cursor {
      guard seen.insert(ObjectIdentifier(pair)).inserted else {
        throw SchemeError.syntax("cyclic formal list")
      }
      fixed.append(try identifier(pair.car, "lambda"))
      cursor = pair.cdr
    }
    if case .symbol(let name) = cursor {
      rest = name
    } else if case .empty = cursor {
    } else {
      throw SchemeError.syntax("invalid lambda formals")
    }
    let names = fixed + (rest.map { [$0] } ?? [])
    guard Set(names).count == names.count else {
      throw SchemeError.syntax("duplicate lambda parameter")
    }
    return Formals(fixed: fixed, rest: rest)
  }

  func checkArity(_ arguments: [Value], _ formals: Formals) throws {
    if formals.rest == nil {
      guard arguments.count == formals.fixed.count else {
        throw SchemeError.arity("expected \(formals.fixed.count), got \(arguments.count)")
      }
    } else if arguments.count < formals.fixed.count {
      throw SchemeError.arity("expected at least \(formals.fixed.count), got \(arguments.count)")
    }
  }

  func bindings(_ value: Value, _ context: String) throws -> [(String, Value)] {
    try array(from: value, context: "\(context) bindings").map {
      let item = try array(from: $0, context: "\(context) binding")
      guard item.count == 2 else {
        throw SchemeError.syntax("\(context) binding requires name and initializer")
      }
      return (try identifier(item[0], context), item[1])
    }
  }

  func ensureDistinct(_ entries: [(String, Value)], _ context: String) throws {
    guard Set(entries.map(\.0)).count == entries.count else {
      throw SchemeError.syntax("duplicate \(context) binding")
    }
  }

  func syntaxBindings(_ value: Value, _ context: String) throws -> [(String, Value)] {
    try array(from: value, context: "\(context) bindings").map {
      let item = try array(from: $0, context: "\(context) binding")
      guard item.count == 2 else { throw SchemeError.syntax("invalid \(context) binding") }
      return (try identifier(item[0], context), item[1])
    }
  }

  func expandLet(_ form: [Value]) throws -> Value {
    guard form.count >= 3 else { throw SchemeError.syntax("let requires bindings and body") }
    if case .symbol(let rawName) = form[1] {
      guard form.count >= 4 else { throw SchemeError.syntax("named let requires body") }
      let name = rawName
      let entries = try bindings(form[2], "named let")
      try ensureDistinct(entries, "named let")
      let lambda = makeList(
        [internalSyntax("lambda"), makeList(entries.map { .symbol($0.0) })]
          + Array(form.dropFirst(3))
      )
      let binding = makeList([.symbol(name), lambda])
      return makeList([
        internalSyntax("letrec"), makeList([binding]), makeList([.symbol(name)] + entries.map(\.1))
      ])
    }
    let entries = try bindings(form[1], "let")
    try ensureDistinct(entries, "let")
    return makeList(
      [
        makeList(
          [internalSyntax("lambda"), makeList(entries.map { .symbol($0.0) })]
            + Array(form.dropFirst(2))
        ),
      ] + entries.map(\.1)
    )
  }

  func expandLetStar(_ form: [Value]) throws -> Value {
    guard form.count >= 3 else { throw SchemeError.syntax("let* requires bindings and body") }
    let entries = try bindings(form[1], "let*")
    if entries.isEmpty {
      return makeList([internalSyntax("let"), .empty] + Array(form.dropFirst(2)))
    }
    var result = makeList([internalSyntax("begin")] + Array(form.dropFirst(2)))
    for entry in entries.reversed() {
      result = makeList([
        internalSyntax("let"), makeList([makeList([.symbol(entry.0), entry.1])]), result
      ])
    }
    return result
  }

  func expandAnd(_ expressions: [Value]) -> Value {
    guard let first = expressions.first else { return .boolean(true) }
    if expressions.count == 1 { return first }
    return makeList([
      internalSyntax("if"), first, expandAnd(Array(expressions.dropFirst())), .boolean(false)
    ])
  }

  func expandOr(_ expressions: [Value]) -> Value {
    guard let first = expressions.first else { return .boolean(false) }
    if expressions.count == 1 { return first }
    macroSerial += 1
    let temp = internalTemporary("or#\(macroSerial)")
    return makeList([
      internalSyntax("let"), makeList([makeList([temp, first])]),
      makeList([internalSyntax("if"), temp, temp, expandOr(Array(expressions.dropFirst()))]),
    ])
  }

  func expandCond(_ clauses: [Value], _ environment: SchemeEnvironment) throws -> Value {
    guard let first = clauses.first else { return .unspecified }
    let clause = try array(from: first, context: "cond clause")
    guard !clause.isEmpty else { throw SchemeError.syntax("empty cond clause") }
    let elseKeyword =
      environment.cell("else") == nil && environment.macro("else") == nil
      && isSymbol(clause[0], "else")
    if elseKeyword {
      guard clauses.count == 1 else { throw SchemeError.syntax("cond else must be last") }
      guard clause.count >= 2 else { throw SchemeError.syntax("cond else requires a body") }
      return makeList([internalSyntax("begin")] + Array(clause.dropFirst()))
    }
    let rest = try expandCond(Array(clauses.dropFirst()), environment)
    if clause.count == 1 {
      macroSerial += 1
      let temp = internalTemporary("cond#\(macroSerial)")
      return makeList([
        internalSyntax("let"), makeList([makeList([temp, clause[0]])]),
        makeList([internalSyntax("if"), temp, temp, rest]),
      ])
    }
    let arrowKeyword =
      environment.cell("=>") == nil && environment.macro("=>") == nil && clause.count == 3
      && isSymbol(clause[1], "=>")
    if arrowKeyword {
      macroSerial += 1
      let temp = internalTemporary("cond#\(macroSerial)")
      return makeList([
        internalSyntax("let"), makeList([makeList([temp, clause[0]])]),
        makeList([internalSyntax("if"), temp, makeList([clause[2], temp]), rest]),
      ])
    }
    return makeList([
      internalSyntax("if"), clause[0],
      makeList([internalSyntax("begin")] + Array(clause.dropFirst())), rest,
    ])
  }

  func expandCase(_ form: [Value], _ environment: SchemeEnvironment) throws -> Value {
    guard form.count >= 2 else { throw SchemeError.syntax("case requires a key") }
    macroSerial += 1
    let key = internalTemporary("case#\(macroSerial)")
    var seenDatums: [Value] = []
    func clauses(_ remaining: ArraySlice<Value>) throws -> Value {
      guard let first = remaining.first else { return .unspecified }
      let clause = try array(from: first, context: "case clause")
      guard clause.count >= 2 else { throw SchemeError.syntax("invalid case clause") }
      if isSymbol(clause[0], "else") && environment.cell("else") == nil
        && environment.macro("else") == nil
      {
        guard remaining.count == 1 else { throw SchemeError.syntax("case else must be last") }
        guard clause.count >= 2 else { throw SchemeError.syntax("case else requires a body") }
        return makeList([internalSyntax("begin")] + Array(clause.dropFirst()))
      }
      let datums = try array(from: clause[0], context: "case datums")
      for datum in datums {
        guard !seenDatums.contains(where: { eqv($0, datum) }) else {
          throw SchemeError.syntax("duplicate case datum")
        }
        seenDatums.append(datum)
      }
      let tests = datums.map { coreCall("eqv?", [key, quoted($0)]) }
      return makeList([
        internalSyntax("if"), expandOr(tests),
        makeList([internalSyntax("begin")] + Array(clause.dropFirst())),
        try clauses(remaining.dropFirst()),
      ])
    }
    return makeList([
      internalSyntax("let"), makeList([makeList([key, form[1]])]), try clauses(form.dropFirst(2))
    ])
  }

  func expandDo(_ form: [Value]) throws -> Value {
    guard form.count >= 3 else { throw SchemeError.syntax("do requires bindings and test") }
    let specs = try array(from: form[1], context: "do bindings").map {
      try array(from: $0, context: "do binding")
    }
    guard specs.allSatisfy({ $0.count == 2 || $0.count == 3 }) else {
      throw SchemeError.syntax("invalid do binding")
    }
    let test = try array(from: form[2], context: "do test")
    guard !test.isEmpty else { throw SchemeError.syntax("empty do test") }
    macroSerial += 1
    let loop = internalTemporary("do#\(macroSerial)")
    let names = try specs.map { try identifier($0[0], "do") }
    guard Set(names).count == names.count else { throw SchemeError.syntax("duplicate do variable") }
    let steps = zip(specs, names).map { $0.0.count == 3 ? $0.0[2] : .symbol($0.1) }
    let done =
      test.count == 1 ? .unspecified : makeList([internalSyntax("begin")] + Array(test.dropFirst()))
    let recur = makeList([loop] + steps)
    let body = makeList([
      internalSyntax("if"), test[0], done,
      makeList([internalSyntax("begin")] + Array(form.dropFirst(3)) + [recur]),
    ])
    return makeList([
      internalSyntax("let"), loop,
      makeList(zip(names, specs).map { makeList([.symbol($0.0), $0.1[1]]) }), body,
    ])
  }

  func quoted(_ value: Value) -> Value { makeList([internalSyntax("quote"), value]) }

  func expandQuasiquote(_ value: Value, depth: Int, _ environment: SchemeEnvironment) throws
    -> Value
  {
    if let form = try? array(from: value), form.count == 2, case .symbol(let name) = form[0] {
      let active = environment.cell(name) == nil && environment.macro(name) == nil
      if name == "unquote" && active {
        return depth == 1
          ? form[1]
          : coreCall(
            "list",
            [quoted(.symbol(name)), try expandQuasiquote(form[1], depth: depth - 1, environment)]
          )
      }
      if name == "unquote-splicing" && active {
        guard depth > 1 else { throw SchemeError.syntax("unquote-splicing outside list context") }
        return coreCall(
          "list",
          [quoted(.symbol(name)), try expandQuasiquote(form[1], depth: depth - 1, environment)]
        )
      }
      if name == "quasiquote" && active {
        return coreCall(
          "list",
          [quoted(.symbol(name)), try expandQuasiquote(form[1], depth: depth + 1, environment)]
        )
      }
    }
    if case .vector(let vector) = value {
      return coreCall(
        "list->vector",
        [try expandQuasiquote(makeList(vector.elements), depth: depth, environment)]
      )
    }
    guard case .pair(let pair) = value else { return quoted(value) }
    let head = pair.car
    if let form = try? array(from: head), form.count == 2,
      case .symbol("unquote-splicing") = form[0], depth == 1,
      environment.cell("unquote-splicing") == nil && environment.macro("unquote-splicing") == nil
    {
      return coreCall(
        "append",
        [form[1], try expandQuasiquote(pair.cdr, depth: depth, environment)]
      )
    }
    return coreCall(
      "cons",
      [
        try expandQuasiquote(head, depth: depth, environment),
        try expandQuasiquote(pair.cdr, depth: depth, environment),
      ]
    )
  }

}
