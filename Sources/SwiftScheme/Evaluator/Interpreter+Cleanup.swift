import SwiftSchemePrimitives
import SwiftSchemeRuntime

extension Interpreter {
  func cleanupContinuation(_ continuation: Continuation) {
    switch continuation {
    case .halt: break
    case .ifFrame(_, _, _, let next), .beginFrame(_, _, _, let next), .loadFrame(_, _, _, let next),
      .expressionContext(let next), .discardFrame(let next), .setFrame(_, _, let next),
      .defineFrame(_, _, let next), .operatorFrame(_, _, let next),
      .operandFrame(_, _, _, _, let next), .letrecFrame(_, _, _, _, _, let next),
      .callValuesFrame(_, let next), .promiseFrame(_, let next), .mapFrame(_, _, _, _, _, let next),
      .outputStringFrame(_, let next):
      cleanupContinuation(next)
    case .windBeforeFrame(_, _, let wind, let next), .windBodyFrame(let wind, _, let next):
      wind.unwind()
      cleanupContinuation(next)
    case .windAfterFrame(_, let next): cleanupContinuation(next)
    case .transitionFrame(let actions, let captured, _),
      .enteredFrame(_, let actions, let captured, _):
      for action in actions {
        switch action {
        case .exit(let wind), .enter(let wind): wind.unwind()
        }
      }
      for wind in captured.winds { wind.unwind() }
      cleanupContinuation(captured.continuation)
    case .closePortFrame(let port, let next):
      try? closePortHandle(port)
      cleanupContinuation(next)
    case .restoreInputFrame(let previous, let opened, let next):
      currentInput = previous
      try? closePortHandle(opened)
      cleanupContinuation(next)
    case .restoreOutputFrame(let previous, let opened, let next):
      currentOutput = previous
      try? closePortHandle(opened)
      cleanupContinuation(next)
    }
  }
}
