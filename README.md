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
lossless ordered JSON syntax ingestion with duplicate-key rejection. Native schema
validation, language compilation, Java generation, and release orchestration remain
in progress. No installable CLI or release is advertised yet.

The module is `goforge.dev/refine`, hosted at
[brain-fuel/refine](https://github.com/brain-fuel/refine). MIT licensed.
The Maven group ID remains undecided. Maven deployment is explicitly outside the
current implementation goal; preparing and testing Java artifacts is in scope.
