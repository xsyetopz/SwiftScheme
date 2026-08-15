set shell := ["bash", "-euo", "pipefail", "-c"]

developer_dir := env("DEVELOPER_DIR", shell("find /Applications -maxdepth 1 -type d -name 'Xcode-*.app' -print | sort | tail -1 | sed 's#$#/Contents/Developer#'"))
swift := env("SWIFT_BIN", "swift")
swift_env := if developer_dir == "" { "" } else { "DEVELOPER_DIR='" + developer_dir + "'" }
formatter := env("SWIFT_FORMAT_BIN", "swift-format")
swiftlint := env("SWIFTLINT_BIN", "swiftlint")

# Show the available project commands.
default:
    @just --list

# Build the debug package.
build:
    {{ swift_env }} {{ swift }} build

# Build the release executable and libraries.
release:
    {{ swift_env }} {{ swift }} build --configuration release

# Run all Swift Testing suites in parallel. Extra arguments are forwarded to SwiftPM.
test *args:
    {{ swift_env }} {{ swift }} test --parallel {{ args }}

# Run tests using release-optimized builds.
test-release:
    {{ swift_env }} {{ swift }} test --configuration release --parallel

# Run checked-in Scheme fixtures and compare captured stdout byte-for-byte.
fixtures:
    python3 Scripts/run-fixtures.py

# Run every R5RS-focused Swift Testing suite.
r5rs:
    {{ swift_env }} {{ swift }} test --parallel --filter R5RS

# Collect SwiftPM code-coverage data.
coverage:
    {{ swift_env }} {{ swift }} test --enable-code-coverage

# Run one test or suite, for example: just test-filter R5RSNumericTests
test-filter filter:
    {{ swift_env }} {{ swift }} test --parallel --filter "{{ filter }}"

# Format all Swift sources and tests in place.
format:
    {{ formatter }} format --configuration .swift-format --recursive --in-place Sources Tests

# Check Swift formatting and style diagnostics without changing files.
format-check:
    {{ formatter }} lint --configuration .swift-format --recursive --strict Sources Tests

# Run SwiftLint with the repository configuration.
lint:
    {{ swift_env }} {{ swiftlint }} lint --config .swiftlint.yml

# Apply SwiftLint's autocorrections.
lint-fix:
    {{ swift_env }} {{ swiftlint }} lint --config .swiftlint.yml --fix

# Detect substantial copy-paste duplication in production and test code.
duplication:
    npx --yes jscpd --reporters ai --min-tokens 100 Sources/SwiftScheme

# Apply source formatting and SwiftLint autocorrections.
fix: format lint-fix

# Run the complete local quality gate without mutating files.
check: build test lint format-check duplication fixtures

# Run the CLI with a small deterministic smoke program.
smoke: build
    printf '%s\n' '(display (+ 10 20))' '(newline)' | {{ swift_env }} {{ swift }} run swiftscheme

# Run the CLI against a Scheme source file: just run path/to/program.scm
run *args:
    {{ swift_env }} {{ swift }} run swiftscheme {{ args }}

# Remove SwiftPM build artifacts.
clean:
    {{ swift_env }} {{ swift }} package clean

# Print the resolved package graph and targets.
package:
    {{ swift_env }} {{ swift }} package dump-package
