import Foundation

package final class Wind: SchemeHeapNode {
  package let id: Int
  package var before: Value
  package var after: Value
  package init(_ id: Int, _ before: Value, _ after: Value) {
    self.id = id
    self.before = before
    self.after = after
    registerSchemeNode(self)
  }
  package func traceSchemeChildren(_ visit: (any SchemeHeapNode) -> Void) {
    traceValue(before, visit)
    traceValue(after, visit)
  }
  package func breakSchemeCycles() {
    before = .undefined
    after = .undefined
  }
}

package struct Captured {
  package let continuation: Continuation
  package let winds: [Wind]
  package init(continuation: Continuation, winds: [Wind]) {
    self.continuation = continuation
    self.winds = winds
  }
}

package enum WindAction {
  case exit(Wind)
  case enter(Wind)
}

package indirect enum Continuation {
  case halt
  case ifFrame(Value, Value, SchemeEnvironment, Self)
  case beginFrame([Value], SchemeEnvironment, Bool, Self)
  case expressionContext(Self)
  case discardFrame(Self)
  case setFrame(String, SchemeEnvironment, Self)
  case defineFrame(String, SchemeEnvironment, Self)
  case operatorFrame([Value], SchemeEnvironment, Self)
  case operandFrame(Value, [Value], [Value], SchemeEnvironment, Self)
  case letrecFrame([(String, Value)], Int, SchemeEnvironment, [Value], SchemeEnvironment, Self)
  case callValuesFrame(Value, Self)
  case promiseFrame(Promise, Self)
  case windBeforeFrame(Value, Value, Wind, Self)
  case windBodyFrame(Wind, Value, Self)
  case windAfterFrame([Value], Self)
  case transitionFrame([WindAction], Captured, [Value])
  case enteredFrame(Wind, [WindAction], Captured, [Value])
  case mapFrame(Value, [[Value]], Int, [Value], Bool, Self)
  case closePortFrame(SchemePort, Self)
  case restoreInputFrame(SchemePort, SchemePort, Self)
  case restoreOutputFrame(SchemePort, SchemePort, Self)
  case outputStringFrame(SchemePort, Self)
}

package enum Control {
  case expression(Value, SchemeEnvironment)
  case values([Value])
  case apply(Value, [Value])
}

package func traceValue(_ value: Value, _ visit: (any SchemeHeapNode) -> Void) {
  switch value {
  case .pair(let node): visit(node)
  case .vector(let node): visit(node)
  case .procedure(let node): visit(node)
  case .promise(let node): visit(node)
  case .environment(let node): visit(node)
  default: break
  }
}

package func containsSchemeNode(_ value: Value) -> Bool {
  switch value {
  case .pair, .vector, .procedure, .promise, .environment: true
  default: false
  }
}

package func traceValues(_ values: [Value], _ visit: (any SchemeHeapNode) -> Void) {
  values.forEach { traceValue($0, visit) }
}

package func traceContinuation(_ continuation: Continuation, _ visit: (any SchemeHeapNode) -> Void)
{
  switch continuation {
  case .halt: break
  case .ifFrame(let a, let b, let environment, let next):
    traceValue(a, visit)
    traceValue(b, visit)
    visit(environment)
    traceContinuation(next, visit)
  case .beginFrame(let values, let environment, _, let next):
    traceValues(values, visit)
    visit(environment)
    traceContinuation(next, visit)
  case .expressionContext(let next): traceContinuation(next, visit)
  case .discardFrame(let next): traceContinuation(next, visit)
  case .setFrame(_, let environment, let next), .defineFrame(_, let environment, let next):
    visit(environment)
    traceContinuation(next, visit)
  case .operatorFrame(let values, let environment, let next):
    traceValues(values, visit)
    visit(environment)
    traceContinuation(next, visit)
  case .operandFrame(let value, let a, let b, let environment, let next):
    traceValue(value, visit)
    traceValues(a, visit)
    traceValues(b, visit)
    visit(environment)
    traceContinuation(next, visit)
  case .letrecFrame(let bindings, _, let environment, let values, let bodyEnvironment, let next):
    bindings.forEach { traceValue($0.1, visit) }
    visit(environment)
    traceValues(values, visit)
    visit(bodyEnvironment)
    traceContinuation(next, visit)
  case .callValuesFrame(let value, let next):
    traceValue(value, visit)
    traceContinuation(next, visit)
  case .promiseFrame(let promise, let next):
    visit(promise)
    traceContinuation(next, visit)
  case .windBeforeFrame(let a, let b, let wind, let next):
    traceValue(a, visit)
    traceValue(b, visit)
    visit(wind)
    traceContinuation(next, visit)
  case .windBodyFrame(let wind, let value, let next):
    visit(wind)
    traceValue(value, visit)
    traceContinuation(next, visit)
  case .windAfterFrame(let values, let next):
    traceValues(values, visit)
    traceContinuation(next, visit)
  case .transitionFrame(let actions, let captured, let values),
    .enteredFrame(_, let actions, let captured, let values):
    actions.forEach { action in
      switch action {
      case .exit(let wind), .enter(let wind): visit(wind)
      }
    }
    traceContinuation(captured.continuation, visit)
    captured.winds.forEach(visit)
    traceValues(values, visit)
  case .mapFrame(let value, let lists, _, let values, _, let next):
    traceValue(value, visit)
    lists.forEach { traceValues($0, visit) }
    traceValues(values, visit)
    traceContinuation(next, visit)
  case .closePortFrame(_, let next), .restoreInputFrame(_, _, let next),
    .restoreOutputFrame(_, _, let next), .outputStringFrame(_, let next):
    traceContinuation(next, visit)
  }
}
