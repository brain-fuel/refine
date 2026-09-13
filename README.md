# Refine

A GoPlus-authored compiler for Refined OpenAPI 3, Refined Avro, and Refined
JSON Schema, with Java 25 code generation and validated serde.

**Under development; not ready for release.** [SPEC.md](SPEC.md) is the agreed
product contract, not a claim that every capability exists. The implementation
and release evidence is tracked in [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md).

## Development

Use Go 1.26 or newer. GoPlus is pinned as a module tool at **v0.158.0**, verified
against the latest published module on 2026-09-12. Do not use an older globally
installed `goplus`. Semantic source lives in `.gp`; generated Go is committed so
ordinary Go consumers do not need the GoPlus compiler.
The generated `//goplus:v v0.28.0` marker is GoPlus's separate source-compatibility
vintage, not the compiler distribution version; `go tool goplus version` reports
the actual pinned release.

```sh
go mod download
go generate ./...
go tool goplus gen --check ./...
go test -race ./...
go vet ./...
```

The full race suite above is a once-per-stable-checkpoint integration gate,
not an edit/test loop. During development use the exact affected selections in
[docs/TESTING.md](docs/TESTING.md), preserve cached results, and do not run the
ordinary whole suite again before the race suite. Required Java/Maven dependency
settings and checkpoint evidence are recorded in
[docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md); missing-runtime skips are not
release evidence.

Implemented foundations (not the complete compiler): immutable exact numbers and
UTF-16 text; three-outcome validation results and deterministic budget meters;
lossless ordered JSON ingestion/editing; a Haskell-like parser, formatter, and
static type/pattern checker; and metered in-memory predicate execution and
typed payload validation. See [docs/RUNTIME.md](docs/RUNTIME.md) for the library
API, step accounting, and explicit limitations. Generated Java now includes
standalone validators, initial immutable domain models, exact timestamps,
canonical show/read, and deterministic dynamic regex predicates; see the
[Java runtime guide](docs/JAVA-RUNTIME.md). Checked native ingestion and bundles,
generic model families, bounded Jackson 3 serde, English algorithm export,
conservative logical analysis, release-planning libraries, schema-derived
JetCheck tests, Maven generation, validated Avro binary/JSON serde, and pure
OpenAPI request/response-context validation are available. Native projection
coverage, cross-format conversion, generator/example coverage, and the complete
specification/release audit remain in progress.

The development CLI exposes only the phases currently implemented:

```sh
go build -o bin/refine ./cmd/refine
bin/refine typecheck --json language/testdata/contracts.refine
bin/refine check-schema --json language/testdata/contracts.refine
bin/refine fmt language/testdata/contracts.refine
bin/refine inspect-json --json value/testdata/numbers.json
bin/refine explain examples/invoice.refine
bin/refine satisfiable --json examples/evolution/SNAPSHOT.refine Age
bin/refine project maven
```

`typecheck` is not payload/native schema validation. See
[docs/LANGUAGE.md](docs/LANGUAGE.md) for syntax, static checks, and remaining gaps.
`check-schema` additionally rejects proven-empty declarations while explicitly
reporting unknown satisfiability. Unknown permits compilation, not a claim of
proof; native schema validity and wire enforcement remain separate checks.
The [worked examples](examples/README.md), [native schema guide](docs/NATIVE.md),
[Jackson serde guide](docs/SERDE-JSON.md), [Maven workflow](docs/PROJECT.md), and
[release planning guide](docs/RELEASE.md) describe executable workflows and
their current limits.

The module is `goforge.dev/refine`, hosted at
[brain-fuel/refine](https://github.com/brain-fuel/refine). MIT licensed.
The Maven group ID remains undecided. Maven deployment is explicitly outside the
current implementation goal; preparing and testing Java artifacts is in scope.
