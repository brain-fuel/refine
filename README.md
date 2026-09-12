# Refine

A GoPlus-authored compiler for Refined OpenAPI 3, Refined Avro, and Refined
JSON Schema, with Java 25 code generation and validated serde.

**Under development; not ready for release.** [SPEC.md](SPEC.md) is the agreed
product contract, not a claim that every capability exists. The implementation
and release evidence is tracked in [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md).

## Development

Use Go 1.26 or newer. GoPlus is pinned as a module tool at **v0.158.0**, verified
against the latest published module on 2026-09-11. Do not use an older globally
installed `goplus`. Semantic source lives in `.gp`; generated Go is committed so
ordinary Go consumers do not need the GoPlus compiler.
The generated `//goplus:v v0.28.0` marker is GoPlus's separate source-compatibility
vintage, not the compiler distribution version; `go tool goplus version` reports
the actual pinned release.

```sh
go mod download
go generate ./...
go tool goplus gen --check ./...
go test ./...
go test -race ./...
go vet ./...
```

Implemented foundations (not the complete compiler): immutable exact numbers and
UTF-16 text; three-outcome validation results and deterministic budget meters;
lossless ordered JSON ingestion/editing; a Haskell-like parser, formatter, and
static type/pattern checker; and metered in-memory predicate execution and
typed payload validation. See [docs/RUNTIME.md](docs/RUNTIME.md) for the library
API, step accounting, and explicit limitations. Generated Java now includes
standalone validators, initial immutable domain models, exact timestamps,
canonical show/read, and deterministic dynamic regex predicates; see the
[Java runtime guide](docs/JAVA-RUNTIME.md). Native schema/wire validation,
complete model shapes and serde, remaining language features, and release
orchestration remain in progress.

The development CLI exposes only the phases currently implemented:

```sh
go build -o bin/refine ./cmd/refine
bin/refine typecheck --json language/testdata/contracts.refine
bin/refine fmt language/testdata/contracts.refine
bin/refine inspect-json --json value/testdata/numbers.json
```

`typecheck` is not payload/native schema validation. See
[docs/LANGUAGE.md](docs/LANGUAGE.md) for syntax, static checks, and remaining gaps.

The module is `goforge.dev/refine`, hosted at
[brain-fuel/refine](https://github.com/brain-fuel/refine). MIT licensed.
The Maven group ID remains undecided. Maven deployment is explicitly outside the
current implementation goal; preparing and testing Java artifacts is in scope.
