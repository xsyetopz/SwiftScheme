import Foundation
import SwiftSchemeFrontend
import SwiftSchemeNumeric
import SwiftSchemePrimitives
import SwiftSchemeRuntime

extension Interpreter {
  func run(_ initial: Control) throws -> [Value] {
    var control = initial
    var continuation: Continuation = .halt
    var winds: [Wind] = []

    func scheduleTransition(_ actions: [WindAction], _ target: Captured, _ delivered: [Value]) -> (
      Control, Continuation
    )? {
      guard let first = actions.first else { return (.values(delivered), target.continuation) }
      let rest = Array(actions.dropFirst())
      switch first {
      case .exit(let wind):
        if winds.last === wind { winds.removeLast() }
        return (.apply(wind.after, []), .transitionFrame(rest, target, delivered))
      case .enter(let wind):
        return (.apply(wind.before, []), .enteredFrame(wind, rest, target, delivered))
      }
    }

    func tailContinuation(_ continuation: Continuation) -> Continuation {
      var current = continuation
      while true {
        switch current {
        case .expressionContext(let next): current = next
        case .beginFrame(let rest, _, _, let next) where rest.isEmpty: current = next
        default: return current
        }
      }
    }

    while true {
      switch control {
      case .expression(let rawExpression, let environment):
        recordSymbols(rawExpression, in: environment)
        let expression = try expandMacros(rawExpression, in: environment)
        switch expression {
        case .symbol(let name): control = .values([try environment.get(name)])
        case .undefined: throw SchemeError.unbound("undefined value")
        case .pair:
          let form = try array(from: expression, context: "expression")
          guard !form.isEmpty else { throw SchemeError.syntax("empty application") }
          if let keyword = coreKeyword(form[0], in: environment) {
            switch keyword {
            case "quote":
              try require(form, 2, "quote")
              let literal = form[1]
              var seen = Set<ObjectIdentifier>()
              markLiteral(literal, &seen)
              control = .values([literal])
              continue
            case "if":
              guard form.count == 3 || form.count == 4 else {
                throw SchemeError.arity("if expects 2 or 3 arguments")
              }
              continuation = .ifFrame(
                form[2],
                form.count == 4 ? form[3] : .unspecified,
                environment,
                continuation
              )
              control = .expression(form[1], environment)
              continue
            case "begin":
              guard form.count > 1 else { throw SchemeError.syntax("begin requires an expression") }
              let allowDefinitions = allowsDefinitions(in: continuation)
              continuation = .beginFrame(
                Array(form.dropFirst(2)),
                environment,
                allowDefinitions,
                continuation
              )
              control = .expression(form[1], environment)
              continue
            case "lambda":
              guard form.count >= 3 else {
                throw SchemeError.syntax("lambda requires formals and body")
              }
              let formals = try parseFormals(form[1])
              let validation = SchemeEnvironment(parent: environment)
              for name in formals.fixed { validation.define(name, .undefined) }
              if let rest = formals.rest { validation.define(rest, .undefined) }
              let body = Array(form.dropFirst(2))
              try prepareInternalDefinitions(body, in: validation)
              try validateBody(body, context: "lambda", in: validation)
              control = .values([.procedure(Procedure(.closure(formals, body, environment)))])
              continue
            case "define":
              guard form.count >= 3 else {
                throw SchemeError.syntax("define requires name and value")
              }
              guard allowsDefinitions(in: continuation) else {
                throw SchemeError.syntax("definition is not valid in expression context")
              }
              try environment.requireDefinitionAllowed()
              if case .symbol(let name) = form[1] {
                try require(form, 3, "define")
                guard !isDefinitionBoundaryKeyword(name) else {
                  throw SchemeError.syntax("cannot define syntactic keyword \(name)")
                }
                continuation = .defineFrame(name, environment, continuation)
                control = .expression(form[2], environment)
              } else {
                guard case .pair(let signature) = form[1] else {
                  throw SchemeError.syntax("invalid define")
                }
                let name = try identifier(signature.car, "define")
                guard !isDefinitionBoundaryKeyword(name) else {
                  throw SchemeError.syntax("cannot define syntactic keyword \(name)")
                }
                let formals = try parseFormals(signature.cdr)
                let validation = SchemeEnvironment(parent: environment)
                validation.define(name, .undefined)
                for formal in formals.fixed { validation.define(formal, .undefined) }
                if let rest = formals.rest { validation.define(rest, .undefined) }
                let body = Array(form.dropFirst(2))
                try prepareInternalDefinitions(body, in: validation)
                try validateBody(body, context: "define", in: validation)
                let procedure = Value.procedure(Procedure(.closure(formals, body, environment)))
                if !environment.fillPlaceholder(name, procedure) {
                  environment.define(name, procedure)
                }
                control = .values([.unspecified])
              }
              continue
            case "define-syntax":
              try require(form, 3, "define-syntax")
              guard allowsDefinitions(in: continuation) else {
                throw SchemeError.syntax("syntax definition is not valid in expression context")
              }
              try environment.requireDefinitionAllowed()
              let name = try identifier(form[1], "define-syntax")
              guard !isDefinitionBoundaryKeyword(name) else {
                throw SchemeError.syntax("cannot define syntactic keyword \(name)")
              }
              let transformer = try SyntaxRules(
                keyword: name,
                spec: form[2],
                definition: environment
              )
              // A syntax binding at this scope supersedes an existing value
              // binding; a later value definition can shadow it again.
              environment.values.removeValue(forKey: name)
              environment.macros[name] = transformer
              control = .values([.unspecified])
              continue
            case "let-syntax", "letrec-syntax":
              guard form.count >= 3 else {
                throw SchemeError.syntax("\(keyword) requires bindings and body")
              }
              let definitions = try syntaxBindings(form[1], keyword)
              try ensureDistinct(definitions, "\(keyword) binding")
              let body = Array(form.dropFirst(2))
              let local = SchemeEnvironment(parent: environment)
              let definitionEnvironment = keyword == "letrec-syntax" ? local : environment
              for (name, spec) in definitions {
                local.macros[name] = try SyntaxRules(
                  keyword: name,
                  spec: spec,
                  definition: definitionEnvironment
                )
              }
              try prepareInternalDefinitions(body, in: local)
              try validateBody(body, context: keyword, in: local)
              continuation = .beginFrame(Array(body.dropFirst()), local, true, continuation)
              control = .expression(body[0], local)
              continue
            case "set!":
              try require(form, 3, "set!")
              continuation = .setFrame(try identifier(form[1], "set!"), environment, continuation)
              control = .expression(form[2], environment)
              continue
            case "let":
              control = .expression(try expandLet(form), environment)
              continue
            case "let*":
              control = .expression(try expandLetStar(form), environment)
              continue
            case "letrec":
              guard form.count >= 3 else {
                throw SchemeError.syntax("letrec requires bindings and body")
              }
              let entries = try bindings(form[1], "letrec")
              try ensureDistinct(entries, "letrec")
              let local = SchemeEnvironment(parent: environment)
              for (name, _) in entries { local.define(name, .undefined) }
              let bodyEnvironment = SchemeEnvironment(parent: local)
              let body = Array(form.dropFirst(2))
              try prepareInternalDefinitions(body, in: bodyEnvironment)
              try validateBody(body, context: "letrec", in: bodyEnvironment)
              if entries.isEmpty {
                continuation = .beginFrame(
                  Array(form.dropFirst(3)),
                  bodyEnvironment,
                  true,
                  continuation
                )
                control = .expression(form[2], bodyEnvironment)
              } else {
                continuation = .letrecFrame(
                  entries,
                  0,
                  local,
                  Array(form.dropFirst(2)),
                  bodyEnvironment,
                  continuation
                )
                control = .expression(entries[0].1, local)
              }
              continue
            case "and":
              control = .expression(expandAnd(Array(form.dropFirst())), environment)
              continue
            case "or":
              control = .expression(expandOr(Array(form.dropFirst())), environment)
              continue
            case "cond":
              guard form.count >= 2 else { throw SchemeError.syntax("cond requires a clause") }
              control = .expression(
                try expandCond(Array(form.dropFirst()), environment),
                environment
              )
              continue
            case "case":
              control = .expression(try expandCase(form, environment), environment)
              continue
            case "do":
              control = .expression(try expandDo(form), environment)
              continue
            case "quasiquote":
              try require(form, 2, "quasiquote")
              control = .expression(
                try expandQuasiquote(form[1], depth: 1, environment),
                environment
              )
              continue
            case "unquote", "unquote-splicing":
              throw SchemeError.syntax("\(keyword) outside quasiquote")
            case "delay":
              try require(form, 2, "delay")
              control = .values([.promise(Promise(form[1], environment))])
              continue
            default: break
            }
          }
          continuation = .operatorFrame(Array(form.dropFirst()), environment, continuation)
          control = .expression(form[0], environment)
        case .empty, .vector: throw SchemeError.syntax("invalid expression")
        default:
          let literal = expression
          var seen = Set<ObjectIdentifier>()
          markLiteral(literal, &seen)
          control = .values([literal])
        }

      case .values(let values):
        switch continuation {
        case .halt: return values
        case .ifFrame(let consequent, let alternate, let environment, let next):
          let test = try one(values, "if")
          continuation = .expressionContext(next)
          control = .expression(isFalse(test) ? alternate : consequent, environment)
        case .expressionContext(let next):
          continuation = next
          control = .values(values)
        case .beginFrame(let rest, let environment, let allowed, let next):
          if rest.isEmpty {
            continuation = next
            control = .values(values)
          } else {
            _ = try one(values, "sequence")
            continuation = .beginFrame(Array(rest.dropFirst()), environment, allowed, next)
            control = .expression(rest[0], environment)
          }
        case .discardFrame(let next):
          continuation = next
          control = .values([.unspecified])
        case .setFrame(let name, let environment, let next):
          let value = try one(values, "set!")
          try environment.set(name, value)
          continuation = next
          control = .values([.unspecified])
        case .defineFrame(let name, let environment, let next):
          let value = try one(values, "define")
          if !environment.fillPlaceholder(name, value) { environment.define(name, value) }
          continuation = next
          control = .values([.unspecified])
        case .operatorFrame(let operands, let environment, let next):
          let procedure = try one(values, "operator")
          if operands.isEmpty {
            continuation = next
            control = .apply(procedure, [])
          } else {
            continuation = .operandFrame(
              procedure,
              [],
              Array(operands.dropFirst()),
              environment,
              next
            )
            control = .expression(operands[0], environment)
          }
        case .operandFrame(let procedure, let done, let rest, let environment, let next):
          let argument = try one(values, "argument")
          let accumulated = done + [argument]
          if rest.isEmpty {
            continuation = next
            control = .apply(procedure, accumulated)
          } else {
            continuation = .operandFrame(
              procedure,
              accumulated,
              Array(rest.dropFirst()),
              environment,
              next
            )
            control = .expression(rest[0], environment)
          }
        case .letrecFrame(
          let entries,
          let index,
          let environment,
          let body,
          let bodyEnvironment,
          let next
        ):
          try environment.set(entries[index].0, try one(values, "letrec initializer"))
          let following = index + 1
          if following < entries.count {
            continuation = .letrecFrame(
              entries,
              following,
              environment,
              body,
              bodyEnvironment,
              next
            )
            control = .expression(entries[following].1, environment)
          } else {
            continuation = .beginFrame(Array(body.dropFirst()), bodyEnvironment, true, next)
            control = .expression(body[0], bodyEnvironment)
          }
        case .callValuesFrame(let consumer, let next):
          continuation = next
          control = .apply(consumer, values)
        case .promiseFrame(let promise, let next):
          continuation = next
          if case .done(let saved) = promise.state {
            control = .values(saved)
          } else {
            promise.state = .done(values)
            control = .values(values)
          }
        case .windBeforeFrame(let thunk, let after, let wind, let next):
          // R5RS ignores every value produced by before.  It is not an
          // ordinary value context (and may legally produce zero or many).
          winds.append(wind)
          continuation = .windBodyFrame(wind, after, next)
          control = .apply(thunk, [])
        case .windBodyFrame(let wind, let after, let next):
          let delivered = values
          if winds.last === wind { winds.removeLast() }
          continuation = .windAfterFrame(delivered, next)
          control = .apply(after, [])
        case .windAfterFrame(let delivered, let next):
          // R5RS ignores every value produced by after as well.
          continuation = next
          control = .values(delivered)
        case .transitionFrame(let actions, let target, let delivered):
          // Dynamic-wind transition hooks are effect-only; discard all of
          // the values returned by each before/after procedure.
          let scheduled = scheduleTransition(actions, target, delivered)!
          control = scheduled.0
          continuation = scheduled.1
        case .enteredFrame(let wind, let actions, let target, let delivered):
          winds.append(wind)
          let scheduled = scheduleTransition(actions, target, delivered)!
          control = scheduled.0
          continuation = scheduled.1
        case .mapFrame(let procedure, let lists, let index, let results, let each, let next):
          // map requires one result per element, while for-each discards
          // every result from its effect-only procedure.
          let accumulated: [Value]
          if each {
            accumulated = results
          } else {
            accumulated = results + [try one(values, "map procedure")]
          }
          let following = index + 1
          if following == lists[0].count {
            continuation = next
            control = .values([each ? .unspecified : makeList(accumulated)])
          } else {
            continuation = .mapFrame(procedure, lists, following, accumulated, each, next)
            control = .apply(procedure, lists.map { $0[following] })
          }
        case .closePortFrame(let port, let next):
          try closePortHandle(port)
          continuation = next
          control = .values(values)
        case .restoreInputFrame(let previous, let opened, let next):
          currentInput = previous
          try closePortHandle(opened)
          continuation = next
          control = .values(values)
        case .restoreOutputFrame(let previous, let opened, let next):
          currentOutput = previous
          try closePortHandle(opened)
          continuation = next
          control = .values(values)
        case .outputStringFrame(let port, let next):
          _ = try one(values, "call-with-output-string procedure")
          continuation = next
          control = .values([.string(SchemeString(port.output))])
        }

      case .apply(let value, let arguments):
        guard case .procedure(let procedure) = value else {
          throw SchemeError.type("attempt to call non-procedure \(value.written)")
        }
        guard let implementation = procedure.implementation else {
          throw SchemeError.io("procedure was reclaimed")
        }
        switch implementation {
        case .primitive(_, let function): control = .values(try function(arguments))
        case .closure(let formals, let body, let captured):
          try checkArity(arguments, formals)
          let local = SchemeEnvironment(parent: captured)
          for (name, value) in zip(formals.fixed, arguments) { local.define(name, value) }
          if let rest = formals.rest {
            local.define(rest, makeList(arguments.dropFirst(formals.fixed.count)))
          }
          try prepareInternalDefinitions(body, in: local)
          try validateBody(body, context: "procedure body", in: local)
          guard let first = body.first else { throw SchemeError.syntax("empty procedure body") }
          continuation = .beginFrame(
            Array(body.dropFirst()),
            local,
            true,
            tailContinuation(continuation)
          )
          control = .expression(first, local)
        case .continuation(let target):
          let common = zip(winds, target.winds).prefix { $0 === $1 }.count
          let exits = winds.dropFirst(common).reversed().map(WindAction.exit)
          let enters = target.winds.dropFirst(common).map(WindAction.enter)
          let scheduled = scheduleTransition(exits + enters, target, arguments)!
          control = scheduled.0
          continuation = scheduled.1
        case .special(let special):
          try handleSpecial(
            special,
            arguments: arguments,
            control: &control,
            continuation: &continuation,
            winds: winds
          )
        }
      }
    }
  }
}
