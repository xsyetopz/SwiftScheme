Create **SwiftScheme**, a compact Scheme implementation in Swift 6.3.3 guided by the bundled R5RS PDF.

Deliver a runnable SwiftPM executable named `swiftscheme` and focused tests. Aim for the broadest coherent R5RS core that fits in one focused implementation session: reader/parser, lexical environments, evaluation, closures, proper tail-oriented evaluation where practical, pairs/lists, symbols, numbers, booleans, strings, quote/quasiquote essentials, `define`, `set!`, `lambda`, `if`, `begin`, the `let` family, core arithmetic/comparison/list/string predicates and procedures, and a REPL/file runner. Identify any remaining unsupported R5RS surface in the final report; do not claim completeness.

Constraints:

- Use the local `Reference/r5rs.pdf` as the normative source.
- Swift 6.3.3, no third-party dependencies.
- Compact code is preferred, but it must compile and include meaningful behavioral tests.
- Agents, AgentSwarm, subagents, and background agents are allowed when useful.
- Work autonomously through implementation, `swift test`, and a CLI smoke test.
- Do not stop at a plan; implement and validate the code.
