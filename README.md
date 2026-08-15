# SwiftScheme

A compact Swift 6.3.3 Scheme implementation targeting the R5RS core.

## Build and test

```sh
swift build
swift test
python3 Scripts/run-fixtures.py
python3 Scripts/run-chibi-r5rs.py
```

The pinned Chibi-Scheme corpus currently passes 189/189 tests. The local Swift test suite passes 160/160 tests.

## Run

```sh
swift run swiftscheme path/to/program.scm
```

See `Reference/r5rs.pdf` for the normative language specification, `CONTRIBUTING.md` for contribution requirements, and `CHANGELOG.md` for project history.
