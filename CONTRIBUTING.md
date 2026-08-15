# Contributing

## Requirements

- Swift 6.3.3 and Swift Package Manager
- macOS 14 or newer

## Validation

Run from the repository root:

```sh
swift build
swift test
python3 Scripts/run-fixtures.py
python3 Scripts/run-chibi-r5rs.py
```

All commands must pass before submitting a change. Keep R5RS behavior grounded in `Reference/r5rs.pdf`; external corpus changes require pinned provenance and license review.

## Scope

Keep changes compact, add focused tests for semantic changes, and do not claim conformance beyond the recorded evidence.
