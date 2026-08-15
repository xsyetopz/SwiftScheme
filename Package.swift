// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "SwiftScheme",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "SwiftScheme", targets: ["SwiftScheme"]),
    .executable(name: "swiftscheme", targets: ["SwiftSchemeCLI"]),
  ],
  targets: [
    .target(name: "SwiftSchemeNumeric", path: "Sources/SwiftScheme/Numeric"),
    .target(
      name: "SwiftSchemeRuntime",
      dependencies: ["SwiftSchemeNumeric"],
      path: "Sources/SwiftScheme/Runtime"
    ),
    .target(
      name: "SwiftSchemeFrontend",
      dependencies: ["SwiftSchemeNumeric", "SwiftSchemeRuntime"],
      path: "Sources/SwiftScheme/Frontend"
    ),
    .target(
      name: "SwiftSchemePrimitives",
      dependencies: ["SwiftSchemeNumeric", "SwiftSchemeRuntime"],
      path: "Sources/SwiftScheme/Primitives"
    ),
    .target(
      name: "SwiftSchemeEvaluator",
      dependencies: [
        "SwiftSchemeFrontend", "SwiftSchemeNumeric", "SwiftSchemePrimitives", "SwiftSchemeRuntime"
      ],
      path: "Sources/SwiftScheme/Evaluator"
    ),
    .target(
      name: "SwiftScheme",
      dependencies: ["SwiftSchemeEvaluator", "SwiftSchemeNumeric", "SwiftSchemeRuntime"],
      path: "Sources/SwiftScheme/API"
    ),
    .executableTarget(
      name: "SwiftSchemeCLI",
      dependencies: ["SwiftScheme"],
      path: "Sources/SwiftSchemeCLI"
    ),
    .testTarget(
      name: "SwiftSchemeTests",
      dependencies: ["SwiftScheme"],
      path: "Tests/SwiftSchemeTests"
    ),
  ],
  swiftLanguageModes: [.v6]
)
