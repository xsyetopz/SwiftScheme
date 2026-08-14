// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "SwiftScheme",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "SwiftScheme", targets: ["SwiftScheme"]),
    .executable(name: "swiftscheme", targets: ["SwiftSchemeCLI"])
  ],
  targets: [
    .target(name: "SwiftScheme", path: "Sources/swiftscheme"),
    .executableTarget(
      name: "SwiftSchemeCLI",
      dependencies: ["SwiftScheme"],
      path: "Sources/SwiftSchemeCLI"
    ),
    .testTarget(
      name: "SwiftSchemeTests",
      dependencies: ["SwiftScheme"],
      path: "Tests/SwiftSchemeTests"
    )
  ],
  swiftLanguageModes: [.v6]
)
