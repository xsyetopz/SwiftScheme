# External conformance evidence ledger

This ledger separates **reproducible native evidence** from local upstream
checkouts used only for audit context. A fixture result is evidence only when
the source, expected output, runner, and relevant tool/version inputs are
available in the candidate. No upstream result is inferred from a registration
count or from a checkout merely being present on disk.

## Reproducible native fixtures

The four checked-in programs in [`../Fixtures/`](../Fixtures/) are deterministic
smoke/program fixtures, not a complete R5RS suite. Their complete stdout is
checked in beside each source as `.out` files. The checked-in
[`manifest.json`](../Fixtures/manifest.json) pins every source and expected
output by SHA-256 and byte length; the runner rejects missing, changed, or
unlisted fixture files before building or running anything. Run them with:

```sh
python3 Scripts/run-fixtures.py
# or: just fixtures
```

For release evidence, run the same manifest against a release build and retain
the command output with the build artifact:

```sh
python3 Scripts/run-fixtures.py --configuration release
```

The runner builds the local `swiftscheme` executable when needed, executes only
these manifest-listed fixtures, rejects unexpected stderr/non-zero exits, and
compares stdout as raw bytes. An explicitly supplied relative executable path
is resolved against the caller's working directory, so release evidence can be
rerun from outside the repository. The repository-declared Swift toolchain version
is recorded in [`.swift-version`](../../.swift-version); the runner does not claim
to verify a host toolchain beyond the build succeeding. This gives a repeatable sanity check
without presenting program fixtures as language-wide conformance proof; fixture
results remain native evidence, not an upstream R5RS score.

| Source | Captured output | Scope claim |
| --- | --- | --- |
| `Tests/Fixtures/control-data.scm` | `Tests/Fixtures/control-data.out` | derived control, multiple values, dynamic-wind, and data conversions |
| `Tests/Fixtures/numeric-programs.scm` | `Tests/Fixtures/numeric-programs.out` | representative exact/complex arithmetic and numeric conversion |
| `Tests/Fixtures/portable-programs.scm` | `Tests/Fixtures/portable-programs.out` | representative recursion, sorting, macro, and values behavior |
| `Tests/Fixtures/smoke.scm` | `Tests/Fixtures/smoke.out` | CLI/file-runner smoke path |

## Upstream revisions observed as audit context

The following rows record revisions observed in temporary local checkouts during
the audit. Those trees are not release inputs, are not run by
`Scripts/run-fixtures.py`, and are not vendored dependencies of the package; the
rows do not support a SwiftScheme conformance score. A future upstream campaign
must provide a separately reviewed, licensed source snapshot and adapter.

| Tree | Upstream remote and observed revision | License marker | Reproducible adapted result |
| --- | --- | --- | --- |
| Chibi-Scheme audit tree | `https://github.com/ashinn/chibi-scheme.git` @ `e5be6cbbcc29ce1fcd2b306644c4fcf3e02707d3` (`VERSION` 0.12.0) | `COPYING` | **No**: no checked-in adapter, exact command, expected output, or clean source snapshot |
| Larceny audit tree | `https://github.com/larcenists/larceny.git` @ `fef550c7d3923deb7a5a1ccd5a628e54cf231c75` | `COPYRIGHT` | **No**: no checked-in R5RS adapter, command, or captured result |
| Racket R5RS audit tree | `https://github.com/racket/r5rs.git` @ `b2672d845419893d69e96453fe4d6d3d587ae22f` | `LICENSE.txt` | **No**: no checked-in R5RS adapter, command, or captured result |

A prior audit note referred to an adapted 184-case Chibi fixture and a
`symbol->string 'Martin` expected-value normalization. The exact adapted source,
revision/pin, license decision, invocation, and captured output are not present
in this candidate. Therefore **no 184/184 result is reported**. To promote that
campaign, check in a separately reviewed adapter and fixture manifest, record
the upstream pin and license, and capture the complete output with a deterministic
runner.

The local PDF remains the normative source for the native audit:
`Reference/r5rs.pdf` SHA-256
`09b71fe4373610d763e86a728ec80146e391a1cd9c00341364200ce3b2e2bc97`.
