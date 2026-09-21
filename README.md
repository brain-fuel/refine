# Refine

A GoPlus-authored compiler for Refined OpenAPI 3, Refined Avro, and Refined
JSON Schema, with Java 25 code generation and validated serde.

**v0.1.0 scope; release tags are issued only after the required CI passes on the
exact candidate commit.**
[SPEC.md](SPEC.md) is the agreed product contract. The implementation and release
evidence is tracked in [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md). The
finite release gates and documented fail-closed support boundaries are
summarized in
[docs/RELEASE-READINESS.md](docs/RELEASE-READINESS.md).
The pinned [GitHub Actions workflow](.github/workflows/ci.yml) is the source of
truth for the final cross-platform generation, race, Java, Maven, vet, CLI and
selected-fuzz gate; focused development checks do not substitute for that run.

## Development

Use Go 1.26 or newer. GoPlus is pinned as a module tool at **v0.158.0**, verified
against the latest published module on 2026-09-19. Do not use an older globally
installed `goplus`. Semantic source lives in `.gp`; generated Go is committed so
ordinary Go consumers do not need the GoPlus compiler.
The generated `//goplus:v v0.28.0` marker is GoPlus's separate source-compatibility
vintage, not the compiler distribution version; `go tool goplus version` reports
the actual pinned release.

```sh
go mod download
go generate ./...
go tool goplus gen --check ./...
go test -race -timeout=20m ./...
go vet ./...
```

The full race suite above is a once-per-stable-checkpoint integration gate,
not an edit/test loop. During development use the exact affected selections in
[docs/TESTING.md](docs/TESTING.md), preserve cached results, and do not run the
ordinary whole suite again before the race suite. Required Java/Maven dependency
settings and checkpoint evidence are recorded in
[docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md); missing-runtime skips are not
release evidence.

The implemented surface includes immutable exact values, three-outcome
validation and deterministic budgets; the checked Haskell-like language;
lossless native ingestion and editable supported constraint units; ordinary and
Refined exports with complete documented-loss explanations; immutable Java 25
models, validators, Jackson 3 and Avro binary/JSON serde; native-aware OpenAPI
request/response context; schema-derived JetCheck tests and embedded examples;
release planning/promotion; and reproducible unsigned Maven assembly. See
[docs/RUNTIME.md](docs/RUNTIME.md), [docs/NATIVE.md](docs/NATIVE.md), and the
[Java runtime guide](docs/JAVA-RUNTIME.md) for exact APIs and limits. Unsupported
native correspondences, wire encodings and ambiguous automatic projections fail
closed; the release does not claim unrestricted conversion among all schemas.

The CLI exposes the implemented phases:

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
[docs/LANGUAGE.md](docs/LANGUAGE.md) for syntax, static checks, and supported
boundaries.
`check-schema` additionally rejects proven-empty declarations while explicitly
reporting unknown satisfiability. Unknown permits compilation, not a claim of
proof; native schema validity and wire enforcement remain separate checks.
The [worked examples](examples/README.md), [native schema guide](docs/NATIVE.md),
[Jackson serde guide](docs/SERDE-JSON.md), [Maven workflow](docs/PROJECT.md), and
[release planning guide](docs/RELEASE.md) describe executable workflows and
their current limits.

The module is `goforge.dev/refine`, hosted at
[brain-fuel/refine](https://github.com/brain-fuel/refine). MIT licensed.
The Java runtime and Maven plugin are configured for publication as `dev.goforge:refine` and
`dev.goforge:refine-maven-plugin`; see [Maven Central publication](docs/MAVEN-PUBLISHING.md)
for the signed release procedure. Generated schema artifacts remain owned by
the consuming Maven or Gradle project.

The Maven 0.4.0 distribution runs generation on the JVM and formats generated
production and test Java with Google Java Format by default. Consumers need Java
25 and Maven; `-Drefine.javaFormat=none` disables formatting. See the
[Spring integration roadmap](docs/SPRING-ROADMAP.md) for the prioritized work
toward automatic imports, refinements, HTTP bindings, and Kafka integration.
