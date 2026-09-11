# Implementation and release evidence

The release objective is the entire [agreed specification](../SPEC.md), tested,
versioned, and pushed, stopping before Maven deployment. Passing a subset of
tests does not satisfy that objective. No release is ready yet.

## Architecture

1. Lossless native document ingestion preserves native schema nodes and attaches
   per-constraint provenance to canonical refinement expressions. It never
   confuses additional refinements with loss of an existing native constraint.
2. A Haskell/ML-style front end produces a typed common contract representation:
   nominal declarations, recursive structural types, functions and patterns,
   predicates, native annotations, HTTP context, and publication metadata.
3. A pure evaluator supplies exact arithmetic, explicit errors, deterministic
   step budgets, immutable values, and three-outcome validation. The Java runtime
   must implement the same specified operations and pass shared conformance data.
4. Native backends lower the contract into ordinary and Refined Avro, OpenAPI 3,
   and JSON Schema. English explanations come from the executable expressions,
   not a separately maintained description of the contract.
5. Java generation produces semantic domain types and validates construction,
   atomic updates, Jackson 3 serde, and Avro binary/JSON serde. Generated Java
   is an output of the GoPlus tool, not an assumption that the GoPlus compiler's
   Java backend supports arbitrary Go libraries used by the tool itself.
6. Conservative schema/proof analysis and the release engine handle unknown
   results, comparison-specific overrides, justified fixes, immutable versions,
   dependency pins, atomic promotions, and the agreed Maven removal policy.
7. Project integration orchestrates generated sources/resources/tests and Maven
   packaging. Publication remains a separate step requiring completed gates.

## Required gates and status

All entries below are required, not a menu of optional milestones. Evidence must
be expanded as concrete tests and commands land. Unchecked items are incomplete.

- [ ] GoPlus module-tool pin, deterministic checked-in Go generation, clean
      consumer without local replacements, CI, race and vet gates.
- [ ] Pure immutable values: exact rational/default integer arithmetic,
      fixed-width overflow/rounding policies, UTF-16 length, exact Unicode
      equality, RFC 3339, regex semantics, canonical typed show/read.
- [ ] Full language: records, nominal parents, recursion, tagged unions,
      Maybe/Nullable, exhaustive patterns, polymorphic/higher-order named
      functions, static inference, safe absence handling, no predicate I/O.
- [ ] Validation: each-where diagnostics, budgets, exceptions/nonthrowing
      outcomes, custom messages with fallback, no default payload leakage,
      combinator truth tables, context-dependent checks, explicit bypasses.
- [ ] Native ingestion: all three formats, strict duplicate-key handling,
      exact native semantics, canonical editable source and per-constraint
      bijection, unknown native metadata preservation, bundling and baselines.
- [ ] Native generation: refined/ordinary outputs for all formats, recursive
      lowering, native oneOf, lossless wire policies and complete English output.
- [ ] Schema validity/type checks, satisfiability, both compatibility directions,
      sound unknown results and fingerprinted version-controlled overrides.
- [ ] Java 25: nominal models, parent substitutability, immutable collections,
      atomic updates, raw access, optional/null/extra-field semantics,
      Jackson 3 and Avro validated read/write, reader resolution/defaults.
- [ ] Semver: all prior in-major baselines, pre-1.0 boundaries, justified fixes,
      immutable release files, multi-family atomic promotion and dependency pins.
- [ ] Maven: one artifact by default, all versions/no-codegen, package layout
      detection/overrides, generated tests/resources, custom removal rules,
      reproducible unsigned artifacts ready for later deployment.
- [ ] Automatic valid/invalid generators, shrinking/replay via JetBrains
      jetCheck, generation-exhaustion failures, embedded executable examples,
      parameterized/data-driven tests and cross-runtime property conformance.
- [ ] Worked examples: booking, invoice, batch import, deployment graph, payment,
      recursive expression tree, polygon, and schema evolution.
- [ ] CLI human/JSON diagnostics and end-to-end execution of real workflows.
- [ ] Release audit against SPEC.md, tested version tags, pushed repository,
      deployed vanity discovery and clean public module resolution.

## Publication inputs

- Existing upstream: `git@github.com:brain-fuel/refine.git`, branch `main`.
- Module: `goforge.dev/refine`; license: upstream MIT.
- Maven group ID: undecided; do not fabricate final publication coordinates.
- Hugo vanity page is prepared in `../goforge/dev.goforge`; deployment is not
  proven by a successful local Hugo build.

## Current evidence (2026-09-11 foundation checkpoint)

- Latest published GoPlus `v0.158.0` verified through `go list -m ...@latest`
  and upstream Git tags, pinned in go.mod. The generated `v0.28.0` header is
  the upstream source-compatibility vintage, intentionally independent of the
  compiler distribution version.
- `value/*.gp`: immutable exact numbers and UTF-16 sequences, rational
  arithmetic, explicit checked/wrapping integer boundaries, exact finite-decimal
  encoding, string read/show. Table, property, external fixture, and fuzz tests.
- `validation/*.gp`: exhaustive GoPlus result/combinator variants, immutable
  diagnostics, JSON reports, schema/caller/per-clause deterministic budget caps.
  Truth-table, state-permutation, immutability, overflow, and budget properties.
- `schemajson/*.gp`: source-preserving, ordered immutable JSON syntax tree;
  duplicate decoded-key rejection, exact escaped UTF-16 keys, bounded ingestion.
  Native-shaped fixtures, mutation-isolation tests, properties and fuzzing.
  This is NOT yet validation against Avro/OpenAPI/JSON Schema meta-schemata.
- Local `go test -race ./...`, `go vet ./...`, and
  `go tool goplus gen --check ./...` passed for these foundations.
- Initial 10-second fuzz runs: 746,799 JSON cases and 5,557,063 text cases passed.
  Counts are evidence of those runs only, not exhaustive correctness or a
  replacement for the missing language/native/Java/end-to-end test suites.
- CI is configured to repeat generation, race, vet, and fuzz checks on Linux and
  macOS. Remote CI success still requires observation of the pushed run.

Next: typed language AST/parser and evaluator, then connect native constraint
provenance and Java emission to that shared representation. The full checklist
above remains the release gate.
