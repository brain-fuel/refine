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
- CI repeats generation, race, vet, and fuzz checks on Linux and macOS.
  The first pushed checkpoint `d463bb9` passed both platforms:
  [verified run](https://github.com/brain-fuel/refine/actions/runs/34638900164).
- Lossless JSON editing now supports validated JSON Pointer lookup and immutable
  replacement of an existing node. Tests verify that editing a `minimum` nested
  inside `allOf` leaves an unrelated `maximum` and all surrounding source bytes
  unchanged; identity and restoration properties are checked. This is the
  source-editing primitive, not yet canonical refinement translation.

## Language front-end checkpoint

- `language/*.gp` now defines a source-spanned Haskell/ML-style syntax tree,
  lexer/parser, deterministic formatter, static type checker, and nested pattern
  coverage checker. Records, nominal aliases/parents, Maybe/Nullable, tagged
  unions, ordinary polymorphic/higher-order named functions, repeated where
  clauses, custom messages/codes/budgets, and recursive definitions are parsed
  and checked. These are static checks, not predicate execution.
- `language/testdata/contracts.refine` is an executable syntax/type-check fixture
  based on the agreed examples. Positive/negative tables, format/parse properties,
  nested pattern tests, and a 3,000-case independent Boolean coverage property
  exercise the front end. Initial 15-second fuzz runs passed 1,147,304 compile
  cases and 482,013 parse/format cases; later changes receive reruns in CI.
- `cli/*.gp` and `cmd/refine/main.gp` expose `typecheck`, `fmt`, and `inspect-json`.
  Tests exercise exit status, file/stdin input, JSON diagnostic output, no default
  payload leakage, I/O errors, unchanged input files, and the real fixture.
- Local race tests, vet, generation verification, and an actual built CLI pass.
  Checkpoint `359ff42` passed Linux/macOS
  [CI](https://github.com/brain-fuel/refine/actions/runs/34641410771).
- Public consumption of `goforge.dev/refine@359ff42` from a separate Go module
  with `GOWORK=off`, no local replacements, and race tests passed. It resolved
  to development pseudo-version `v0.0.0-20260911195505-359ff42f6bbb`, not a product
  release. The Hugo vanity route is deployed and its go-import metadata verified.
- Required front-end work remains explicit in `docs/LANGUAGE.md`: imports,
  constraint-qualified polymorphism, full explicit conversion/numeric semantics,
  and integration with execution/native/Java backends. No full-language or release
  checkbox is marked complete based on this checkpoint.

## In-memory runtime checkpoint

- `value/data.gp` supplies deeply immutable structured payloads, explicit
  constructor alternatives, ordered record storage, order-independent record
  equality, metered iterative structural comparison, and multi-field candidate
  updates with no intermediate mutation or validation claim.
- `language/eval*.gp` implements budgeted eager/short-circuit expression execution,
  exact arithmetic, immutable lists/records/data, recursion, patterns,
  higher-order named functions, collection operations, and three-outcome
  combinators. The interpreter cannot obtain network/filesystem capabilities.
- `Program.ValidateData` connects named root declarations to structural checks,
  nested/inherited per-where validation, diagnostics, budgets, and custom-message
  fallback. This is in-memory language payload validation, not native serde.
- Tests include execution tables, all predicate outcome sequences up to length
  four, deterministic budget thresholds, 3,000 field/record equivalence cases,
  2,000 map/fold law cases, 3,000 immutable update law cases, privacy/concurrency,
  recursive/generic payloads, and fuzz properties. Initial 20-second fuzz runs
  passed 106,712 evaluator cases and 2,536,767 immutable-data cases; these counts
  prove only those runs, not complete runtime correctness.
- A follow-up 15-second evaluator fuzz run with corpus minimization disabled
  passed 2,812,113 cases. Local race tests, vet, generated-source checks, and
  the public-library example pass. Checkpoint `ea3a7d4` passed Linux/macOS
  [CI](https://github.com/brain-fuel/refine/actions/runs/34644247635), and a separate
  module fetched its public pseudo-version and passed race-tested validation and
  multi-field candidate-update checks without local replacements.
- Remaining runtime limitations and the initial operation-cost model are explicit
  in [RUNTIME.md](RUNTIME.md). Unsupported operations report indeterminate rather
  than silently succeed. No whole-language/Java/release gate is marked complete.

## Typed codec and function-contract checkpoint

- The checked module retains immutable inferred expression types and generic
  scopes. Typed `read` uses those types, including named generic and higher-order
  calls, and validates nominal/anonymous refinements before returning `Ok`.
- `ReadData` and `ShowDataWithoutValidation` expose the canonical in-memory codec.
  Literal decoding cannot execute input expressions. Invalid/unknown reads do
  not expose candidates. Explicit bypass display does not bypass validating read.
- Local annotations and curried function pre/postconditions now execute, including
  contracts on functions passed/returned as values. Named parent predicates are
  not rerun merely for substitution. Nested budget meters charge every enclosing
  scope without relaxing/resetting limits.
- A parser regression is fixed: identifiers named `text`, `number`, `newline`,
  or `eof` no longer impersonate token categories or truncate source parsing.
- Shared canonical-codec fixtures, 2,000 composite read/show property cases,
  literal-only decoding, invalid bypass rejection, generic/recursive codecs,
  higher-order contracts, and nested-meter tests cover this checkpoint. Initial
  20-second fuzz runs passed 1,311,801 typed read/show cases and 1,721,050 evaluator
  cases. Remaining gaps, including codec-capability inference through generic
  signatures, remain explicit in [RUNTIME.md](RUNTIME.md).

- Checkpoint `f85a023` passed Linux/macOS
  [CI](https://github.com/brain-fuel/refine/actions/runs/34646986712). A separate
  public consumer resolved `v0.0.0-20260911205816-f85a023ccedd` without local
  replacements and passed race-tested typed codecs, nominal refinement reads,
  and multi-field candidate updates.

## Regex and timestamp checkpoint

- `pattern/*.gp` connects Go/RE2 parsing/compilation to an iterative, metered
  regex matcher. `matches` and `search` now execute, including dynamic patterns,
  Unicode classes, surrogate identity, anchors, and explicit unsupported errors.
  Compilation/expansion and matching share the enclosing validation budget.
- `value/timestamp.gp` implements exact RFC 3339 parsing, offset metadata,
  instant ordering, original-payload preservation, and pinned leap knowledge.
  Typed payload/read boundaries parse timestamps for predicates without changing
  their raw text. Unknown future leap labels remain indeterminate; known sibling
  violations are still collected. Civil versus SI duration primitives are
  explicitly separate, not silent timestamp subtraction.
- Coverage includes shared timestamp JSON fixtures, 5,000 offset/instant
  property cases, regex differential properties, fixed work thresholds,
  unsupported-pattern privacy, timestamp read/show, sub-nanosecond booking
  comparisons, malformed/future leap labels, and concurrent program reuse.
- Local unit/property tests, race tests, vet, and deterministic GoPlus generation
  pass. `go list -m goforge.dev/goplus@latest` still resolves the pinned v0.158.0.
  A 20-second regex differential fuzz run passed 6,627,539 executions. A timestamp
  run hit a fuzz-harness deadline during shrinking; limiting each minimization
  attempt to 1,000 executions (not disabling shrinking) allowed a fresh 20-second
  run to pass 11,253,034 executions. CI uses this bounded shrink setting.
- This is not proof of native regex parity, complete timestamp/conversion
  vocabulary, a cross-runtime stable regex cost profile, or Java conformance.
  Those and the full unchecked release requirements remain outstanding.
- Checkpoint `035a1f8` passed Linux/macOS
  [CI](https://github.com/brain-fuel/refine/actions/runs/34649269559). An independent
  public consumer fetched `v0.0.0-20260911212451-035a1f8d8faa` with `GOWORK=off`
  and no replacements, then passed race-tested regex, exact leap-second ordering,
  immutable multi-field candidate updates and timestamp read/show checks.

## Native constraint provenance checkpoint

- `provenance/*.gp` discovers exact local numeric-bound correspondences at Draft
  2020-12 schema positions. It emits statically checked editable constraint units
  while retaining the entire native document and each unit's applicator context.
  It does not infer a numeric type merely from a bound, rewrite fractional
  integer bounds to rounded integers, or replace native string/regex semantics.
- Each native constraint has separate source-derived identity/fingerprint and
  canonical recovery. Editing a minimum breaks only its guarantee, not the
  maximum's. Adding arbitrary rules leaves existing guarantees intact. Layout
  changes are tolerated; arbitrary logical equivalence is not guessed.
- Exact `multipleOf` projection uses a new metered `isInteger :: Real -> Bool`
  primitive. Divisibility never uses floating-point tolerance. Shadowing that
  builtin breaks only the native correspondences that depend on its binding.
- Tests cover immutable/concurrent reuse, canonical forms, native metadata and
  schema-location traversal, added/edited/removed clauses, and exact native-token
  recovery. A pinned ecosystem Draft 2020-12 oracle independently checks 1,000
  generated numeric-bound predicates. A 20-second round-trip fuzz run passed
  9,344,642 executions with bounded, enabled shrinking. Local race tests, vet,
  and generated-source checks pass.
- After adding exact `multipleOf` and builtin-binding checks, a fresh 20-second
  fuzz run passed 9,324,262 executions; race and vet gates were rerun successfully.
- This is a reusable per-constraint foundation, not completed native schema
  validation/ingestion or a substitute for the full schema. Complete type
  projection, keyword adapters, refs, native/English exports, and OpenAPI/Avro
  integration remain required. See [NATIVE-PROVENANCE.md](NATIVE-PROVENANCE.md)
  and [dependency roles](DEPENDENCIES.md).

Next: finish conversions, capability inference, and recursive dispatch; connect
native constraint provenance and Java emission to the checked runtime. The full
checklist remains the release gate.
