# Implementation and release evidence

The release objective is the entire [agreed specification](../SPEC.md), tested,
versioned, and pushed, stopping before Maven deployment. Passing a subset of
tests does not satisfy that objective. No release is ready yet.

## Architecture

Development test selection and rerun policy are recorded in
[TESTING.md](TESTING.md). Exact focused checks are reused on unchanged inputs;
whole-repository race/vet/generation runs belong to integration checkpoints.

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

## Native/Maven integration checkpoint (2026-09-12)

- Native JSON Schema and selected OpenAPI 3.0/3.1/3.2 payloads have offline,
  exact-number native validation composed with checked Refine decoding. Native
  Avro binary validation has bounded preflight and an independent ecosystem
  oracle. The Go Avro-to-Refine bridge was unfinished at this earlier checkpoint;
  binary and strict JSON writer boundaries are recorded in the later evidence
  below.
- Java generation now includes validated Jackson 3 and Apache Avro 1.12 binary
  and JSON adapters, named scalar metadata, anonymous typed nested records,
  closed generic native lowering, bounded finite float conversion, and generated
  JetCheck wire properties. Native JSON and Avro candidate filters reject only
  proven invalid/unrepresentable samples; resource/indeterminate failures are
  not converted into ordinary sampling misses.
- Canonical JSON native constraint units are versioned and audited at their
  original scope. Supported edits affect the effective native validator while
  immutable original bytes remain available. Same-format project exports retain
  external URI/resource manifests, native-unit authority, checked wire metadata,
  and ordinary/refined explanations. Unsupported cross-format opaque conversion
  fails closed. This is not a claim of complete native schema projection.
- Project/CLI generation accepts self-contained `.refined.json` catalog entries;
  release planning binds approvals to the complete bundle and publication policy.
  Promotion preserves native bundle bytes, rechecks inputs under the shared
  generation/promotion lock, and retains the snapshot. Recovery rejects reserved,
  duplicate and symlinked destinations before mutation.
- Qualified polymorphic capabilities, named-call continuations, finite Float32/
  Float64 semantics and scoped resource checks have focused Go/Java conformance
  evidence. The full integration run found two obsolete fixtures (untyped
  `show []`, formerly unsupported nested records) and a typed-read structural
  depth mismatch. The fixtures were corrected without weakening checking;
  Java typed reads now inherit structural depth independently of expression-call
  depth, retaining the shared guard for nested validating reads.
- One frozen-source `go test -race ./... -skip
  '^TestMavenRegenerationAndReproducibleArtifact$'` run passed every non-Java
  package and all but those three Java tests (Java package duration 160.057s).
  After the scoped fixes, the exact anchored race reruns passed:
  `TestGeneratedTypedRead` (8.213s), `TestGeneratedCanonicalShow` (11.737s), and
  `TestModelGenerationBoundaries` (1.702s). The full suite was not repeated.
- The real Maven lifecycle test passed in 14.667s with both ordinary generated
  JSON/Avro contracts and an imported native JSON bundle. Its four builds verify
  initial compilation/property execution, byte-identical reproducibility,
  snapshot regeneration and expected generation-exhaustion failure. This
  lifecycle evidence is reused locally; CI supplies independent platform runs.
- Environment: Go 1.26.5, GoPlus v0.158.0, Java 25, pinned Maven 3.9.16,
  JetCheck 0.3.0, Apache Avro 1.12.0, Jackson 3.2.0 standalone and 3.2.1 with
  networknt 3.0.7. Java harnesses verify dependency digests and compile with
  warnings-as-errors. Deterministic development selections are in
  [TESTING.md](TESTING.md).
- Still required: complete native projection and cross-format conversion,
  OpenAPI request/response context, broader Java JSON codec allocation/stack
  hardening, bounded ECMA native regex execution, complete generators/examples,
  full specification audit and eventual versioned release. No product release
  tag or Maven deployment is implied by this integration checkpoint.
- Source checkpoint `d504826` was pushed with authored GoPlus and generated Go
  together. A fresh external module fetched public pseudo-version
  `v0.0.0-20260912173240-d504826cffaf` with `GOWORK=off` and no replacements.
  Its anchored race test passed in 2.814s, checking native/refined Go outcomes,
  project output generation, Java 25 warnings-as-errors compilation, and Jackson
  read/write validation with no emitted bytes on invalid writes at `-Xss256k`.
  The harness selected the seven exact native JSON dependency filenames; an
  initial fixture-only dependency-directory count assumption was corrected
  before the passing run. No production correction was needed for this consumer.

## Post-checkpoint focused work (2026-09-12)

The scopes below extend `d504826`; they do not mark the full release gates done.

- `Program.ReadDataWithoutRefinements` and the closed `PayloadType` equivalent
  provide the structural-only canonical-text reader needed by invalid examples.
  They skip `where` execution while preserving literal-only parsing, structural
  and fixed-width/finite-float/timestamp validation, budgets and failure-value
  isolation. They do not mutate the program or weaken subsequent validating
  reads. The nine-test reader selection passed except a new fixture whose UInt8
  predicate used an unconverted Int literal; correcting that fixture to `False`
  required only its exact test rerun (0.334s). The new seeded property covers
  1,000 integer round trips. No extra parser fuzz campaign is needed for this
  dispatch-only change; the integration suite replays its existing seeds.
- Generated native JSON regexes use conditional, pinned GraalJS 25.0.1 with
  isolated contexts, tighten-only limits and cancellation. The warmed adversarial
  backreference/concurrent-cancellation gate passed in 1.423s; the no-Graal
  non-pattern compile/run passed in 0.857s. The composed Jackson regex-limit
  read/write gate passed in 2.448s, including zero output on rejected writes.
- The JSON codec limit selection in TESTING.md passed under race in 10.127s.
  Generated property tests now use the bounded `strictMapper()`; their two
  affected anchored tests passed under race in 2.753s. Imported native JSON and
  OpenAPI numbers select exact decimal wire encoding without extra configuration;
  one Java invocation covered scalar/nested values, large decimals, preserved
  native minima, and rejection of nonterminating rational writes (2.449s).
  Standalone language-only generation still requires an explicit Real policy.
- `TestMavenInfersOnlyRequiredNativeRegexDependency` and
  `TestMavenSnippetAndNoCodegenPlan` passed in 0.222s. The updated real Maven
  four-build campaign passed in 82.692s with automatic Polyglot compile-time API
  and GraalJS runtime selection from a native regex schema. The same campaign
  covers plain JSON/Avro contracts and an exact native numeric bundle. Reuse this
  result on unchanged fixture/generator/dependency inputs instead of rebuilding
  Maven for unrelated changes.
- OpenAPI operation-context Go/Java focused race gates passed: immutable checked
  bindings, exact/class/default response selection, preserved invalid plus
  incomplete outcomes when request context is absent, and shared cross-context
  rules. The Java conformance/rejection selection took 2.881s. Native bundle and
  project integration is subsequent work, not evidence supplied by these tests.
- Subsequent native metadata/project integration passed its focused Go/Java
  gates, retaining immutable operation bindings, native-bundle authority, release
  identity and merged Java facade/runtime sources. Native ordinary export now
  removes recognized Refine schema annotations without changing literal payload
  keys, and validates the native resource closure without trying to re-type-check
  declarations intentionally absent from ordinary output. Numeric/recursive
  OpenAPI export regression selection passed in 0.256s after fixing generated
  definition references to use collision-free OpenAPI components.
  This is metadata retention plus pure Refine context validation, not native
  operation reconciliation: imported path/parameter/header/body/response schema
  locations are not yet composed into that facade. The full-document native
  operation boundary remains a required implementation gap.
- Native Avro validation now includes a full bounded binary-to-Refine bridge and
  compilation checks for refined field defaults. Original raw defaults remain
  authoritative: fractional/overflowing integer defaults are rejected and Avro
  1.12 first-matching union defaults work even when the matching branch is not
  first. The private hamba structural input omits field defaults without reordering
  unions; scoped tests cover exact original bytes, named/dependency references,
  nested omissions, cycles, and no synthesis of absent writer bytes.
- `analysis.CheckSchema` checks closed declarations as independent entrypoints;
  `CheckSchemaRoots` instead limits rejection to explicitly selected roots while
  retaining evidence for every declaration. Native and generated projects select
  the payload plus bound OpenAPI request/response/context types. An impossible
  unused declaration or optional child is not itself proof that a selected root
  is empty. Unknown/generic results remain explicit, returned root/findings
  slices are defensively copied, and bundle reload recomputes the report.
  `check-schema` exposes the all-declaration phase in human/JSON form without
  changing the narrower `typecheck` command. Project generation rejects a proven
  selected-root contradiction before returning any files, including no-codegen
  cases, and emits scoped `schema-analysis.json`. Focused proof,
  native, CLI and project tests passed. One new project numeric fixture expected
  the wrong root-resource filename; only that fixture's assertion was fixed,
  and its exact anchored rerun passed in 0.252s.
- Subsequent Java regex hardening replaces the shared scheduled cancellation
  worker with request-owned Java 25 virtual watchdogs. They inherit neither
  thread-local values nor a context classloader, cancel independently, and stop
  on request cleanup. Cleanup failures are sanitized enforcement outcomes;
  malformed number tokens are invalid, not numeric-resource exhaustion. The
  actual Java 25 regex/native-validator selection passed in 2.046s with pinned
  dependencies. Shared engine initialization failures remain fatal deployment
  configuration errors, not payload outcomes.
- Checkpoint CI `34708563276` passed generation, full race tests (including Maven),
  vet and CLI smoke on Linux and macOS, then the macOS typed-read fuzz target hit
  a context deadline; the fail-fast policy cancelled Linux fuzzing. A scoped
  local 10-second `FuzzTypedReadShow` campaign with bounded 1000-execution
  minimization passed 4,747,217 executions. CI now bounds that minimization and
  keeps platform jobs independent. This is not a green CI claim for the dirty
  worktree, nor proof of the original timeout's cause.

## Bounded validation integration checkpoint (2026-09-12)

- Source checkpoint `dc71871` was committed and pushed with authored GoPlus and
  generated Go together. The separate Linux/macOS verification is
  [CI run 34712953922](https://github.com/brain-fuel/refine/actions/runs/34712953922).
  Both jobs failed: one generated-facade test assumed a Homebrew Java path, and
  the Maven regex fixture exhausted the payload deadline during cold engine
  startup (macOS also exposed this in the standalone regex harness). Generation
  passed; later vet/smoke/fuzz stages were not reached. These jobs have not been
  rerun unchanged. The following local evidence does not supersede those failures.
- Frozen authored/generated sources passed `go tool goplus gen --check ./...`
  and `go vet ./...`. One `go test -race ./...` invocation required Java and
  Maven, with the pinned environment listed above and the NetworkNT/GraalJS
  dependency directories enabled. Every package passed except two integration
  fixtures in CLI and Java; the Java package took 178.889s, native 34.688s,
  language 7.261s, and project 28.458s. The passing project package includes the
  real four-build Maven lifecycle, not a skipped or mocked Maven check.
- The CLI fixture expected `where False` to compile. It now uses the inhabitable
  `where it < 3`, retaining rejection of its payload `3`, the custom message,
  native-only scope, privacy and original-byte assertions. Its exact race rerun
  `go test -race ./cli -run '^TestNativeArtifactWorkflow$'` passed in 1.476s.
- The native-regex fixture deliberately tests `patternProperties`, now rejected
  by automatic typed-map projection instead of silently becoming an empty
  record. Its native-only intent is made explicit with a checked root annotation;
  all original regex/map assertions remain. JSON ingestion now honors that
  selected annotation before automatic projection, just as OpenAPI ingestion
  does. Native schema validation still runs first. Bad source/root/proof checks
  remain atomic, and unannotated maps still fail. The four new native annotation/
  projection regressions passed in 0.249s. The exact Java race rerun
  `TestGeneratedNativeRegexECMA262AndBudgets` passed in 2.754s.
- Seven affected existing native annotation/provenance/bundle/export regressions
  passed under race in 1.451s; exact selections are in TESTING.md. Scoped
  generation consistency and vet passed after the corrections. The whole race
  suite was not repeated. At that checkpoint Maven evidence remained applicable: its unchanged
  ordinary native fixtures take the same projection path, and its generated
  refined resources already had projectable shapes and identical annotated
  source. No Maven generator, dependency, or lifecycle fixture changed after
  that successful campaign.
- This checkpoint also includes the public 514-alias Avro default traversal
  regression: a reachable depth limit now emits `native.limit` rather than an
  empty check list. Rational-record component defaults reject conclusive bad
  encodings/refinements; encoding-valid contextual defaults stay explicitly
  unknown. These are bounded checks, not a claim that arbitrary predicates can
  be proved or that the full specification is complete.

## Follow-up integration checkpoint (2026-09-12)

Committed and pushed as `a0bc5eb`; separate platform verification is tracked in
[CI run 34715151520](https://github.com/brain-fuel/refine/actions/runs/34715151520).
The local result below is not a claim that this CI run has completed.

The coherent source batch below passed one full local integration gate, with
Java and Maven required and all pinned dependency directories enabled:

```sh
go tool goplus gen -check ./...
go vet ./...
REFINE_REQUIRE_JAVA=1 REFINE_JAVA_HOME=/opt/homebrew/opt/openjdk@25 \
REFINE_JETCHECK_DIR=/tmp/refine-jetcheck-sfZEQ7 \
REFINE_JACKSON_DIR=/tmp/refine-jackson-dCP3wX \
REFINE_AVRO_DIR=/tmp/refine-avro-1.12.0 \
REFINE_NETWORKNT_DIR=/tmp/refine-networknt-jars \
REFINE_GRAALJS_DIR=/tmp/refine-regex-maven/jars \
REFINE_REQUIRE_MAVEN=1 \
REFINE_MAVEN_HOME=/tmp/refine-maven-SoxP0H/apache-maven-3.9.16 \
go test -race ./...
```

All packages passed: Java 208.084s, native 36.108s, project 29.989s,
CLI 5.673s, release 2.635s, OpenAPI 1.672s, and examples 1.614s. Unchanged
foundation packages reused Go's test cache. The project result includes the
actual initial, reproducible, changed-schema regeneration, and expected-failure
Maven builds. No standalone Maven campaign or repeat full suite was run.
`git diff --check` also passed. Documentation-only evidence updates do not
invalidate this source-state result. CI still provides separate platform
verification; the release gaps at the end of this document remain unresolved.

- Regex initialization now has a separate fixed trusted warmup phase; schema
  patterns and payloads enter only after the aggregate caller deadline begins.
  No payload limit was raised. The three anchored regex tests listed in
  TESTING.md passed in 3.913s with Java 25, NetworkNT and GraalJS provisioned.
  This production template change invalidated the previous Maven evidence;
  the next lifecycle run was held until the shared generator batch was stable
  and passed in the integration gate above.
- The new explicit raw JSON reader/writer skips only Refine predicates. Native
  schema gates, exact wire representations, duplicate-key checks, parser bounds,
  structure and caller budgets remain enforced. The initial two-test selection
  passed the existing Jackson regression but exposed a fixture that had removed
  its canonical native constraint. After preserving that constraint, only
  `TestGeneratedJSONRawBypassKeepsNativeAndStructuralValidation` was rerun; it
  passed in 2.058s. Generated Go was refreshed before each source-state check.
- Worked examples and separated valid/invalid property seed pools passed their
  three-test Java/JetCheck selection in 5.821s. This covers all eight worked
  families through generated models and canonical codecs, not native wire
  coverage for every family. Existing example checks passed in 0.210s.
- Embedded examples passed native (0.289s), project (1.487s) and CLI (0.675s)
  focused selections. Java discovery additionally passed the CI-shaped run with
  `REFINE_JAVA_HOME` unset and only `JAVA_HOME` configured (1.274s). These are the
  exact named selections in TESTING.md, not whole-package gates.
- Go native Avro JSON validation and refined decoding passed four tests plus
  fixed fuzz seeds in 0.340s. A single Apache Avro Java oracle JVM passed nine
  exact decoded-data comparisons in 0.702s; the explicit CLI encoding flag and
  four affected existing CLI regressions passed in 0.292s. JSON and binary
  writer boundaries are connected; reader resolution remains a generated Java
  capability rather than an implicit Go decoder feature.
- Promotion's published-version catalog now rejects duplicate identities and
  attempts to republish an existing `(family, version)` before staging or writes.
  Four focused release tests passed in 0.262s. A final assertion-only edit reran
  just the new atomicity test (0.188s), followed by generation consistency.
  Three exact affected CLI promotion callers passed in 2.306s and the project
  shared-lock caller passed in 0.233s before the integration gate.
- Composed native OpenAPI Java validation passed its focused Java regression
  in 2.214s and project generation regression in 0.260s. A single generated
  wrapper shares native node/regex budgets across operation parts. Each input
  part is separately checked for one-value framing before assembly; constructor
  caps precede copying. Request tokens bind the instance, project and operation.
- Native Avro big-decimal validation passed its two pure-Go tests in 0.241s
  and the pinned Apache Java oracle in 0.996s. This validates the nested native
  encoding and preserves physical bytes; it does not invent a fixed-scale
  `Real` mapping. The full gate also covers the added valid/invalid Avro JSON
  big-decimal composition table rows.

## Historical evidence (2026-09-11 foundation checkpoint)

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
- At this checkpoint, imports, qualified polymorphism, conversion/numeric
  semantics and backend integration remained. Later evidence below supersedes
  that historical gap list; see `docs/LANGUAGE.md` and `docs/CAPABILITIES.md` for
  the current boundary. No release checkbox is inferred from this checkpoint.

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

- Checkpoint `d8dcf32` passed Linux/macOS
  [CI](https://github.com/brain-fuel/refine/actions/runs/34650847660). A separate
  public consumer fetched `v0.0.0-20260911214438-d8dcf323e0c3` without local
  replacements and passed race-tested exact divisibility, per-constraint edits,
  native-token/metadata preservation and builtin-shadowing checks.

## Java runtime generation checkpoint

- `java/*.gp` emits five Java 25 runtime sources: canonical exact rationals,
  UTF-16 text codecs, sealed validation outcomes, a try/catch-compatible
  exception, and nested unsigned-64-bit budget meters. Generation is pure and
  package-relative; the sources can live in the user's single Maven artifact.
- Emitted sources compile with all javac warnings treated as errors. Tests
  compare 5,670 Java/Go cases and compile five package-layout variants, including
  Unicode and unnamed packages.
- JetBrains jetCheck runs four fresh-seeded 2,000-iteration law suites and an
  explicit shrink/serialized-replay regression. Three consecutive local runs
  passed. Both test jars are checksum-pinned and checked before execution;
  neither tests nor generated code fetch dependencies. CI requires Java 25 and
  the property-test dependency directory on Linux and macOS.
- Full local race tests, vet and deterministic generation checks pass. A
  20-second package-name fuzz run passed 12,478,996 executions. The local
  source-generation benchmark measured 3,000 ns/op, 21,120 B/op and 23 allocs/op
  on Darwin/arm64 (Apple M5 Max); this measures source generation only, not
  payload-validation performance. Latest GoPlus still resolves to v0.158.0.
- This is not schema model generation, a Java evaluator, or serde. The full
  required artifact, validator, native-format, compatibility, versioning,
  Maven and example gates remain unchecked. See [JAVA-RUNTIME.md](JAVA-RUNTIME.md)
  for implemented APIs and resource-policy limitations.

- Checkpoint `2654b57` passed Linux/macOS
  [CI](https://github.com/brain-fuel/refine/actions/runs/34655231371). An independent
  consumer fetched `v0.0.0-20260911224324-2654b57ed0bf` without local replacements,
  emitted/compiled Java and passed exact arithmetic, UTF-16, validation exception
  and nested-budget checks under Go's race detector.

## Generated Java contract validators

- `GenerateValidator` connects checked language declarations to standalone Java
  execution. It emits immutable language payloads, an immutable contract graph,
  structure/refinement validation and an ordinary throwing boundary that returns
  the original payload unchanged. No Go runtime or dynamic schema loading is
  needed by emitted Java.
- Records, aliases, lists, recursive/generic tagged unions and optional/null/
  result forms execute. Expression-only field and whole-structure refinements
  preserve ordered diagnostics, exact arithmetic, overflow, UTF-16, error-message
  fallback, invalid/unknown aggregation, and Go's logical-step accounting.
- 13,250 full-report comparisons include tiny total/per-clause budgets and
  explicit over-depth trees. Generated contracts also pass 5,000 jetCheck cases
  for scalar, relational record and recursive generic validation. Initial
  unbounded random trees exceeded evaluator limits and caused lengthy shrinking;
  the all-leaves law now bounds generated trees to fit the resource policy while
  dedicated over-limit cases require matching indeterminate reports.
- Unsupported expression/function/timestamp forms reject generation explicitly,
  as do unsafe class names and oversized initializers. These are outstanding
  implementation obligations, not relaxed release requirements. Model classes,
  serde, native formats, complete language execution and project integration
  still remain required; see [JAVA-RUNTIME.md](JAVA-RUNTIME.md).
- Local full-repository race tests, vet and deterministic generation pass. A
  20-second emitter fuzz run passed 10,689,334 executions; the source-generation
  benchmark measured 121,626 ns/op, 418,878 B/op and 3,939 allocs/op on Darwin/arm64
  (Apple M5 Max), including a fresh detached syntax parse. Tests also exercise
  concurrent Java validation, copied payload collections and forged numeric
  metadata. GoPlus latest still resolves to the pinned v0.158.0.

- Checkpoint `035ab1b` passed Linux/macOS
  [CI](https://github.com/brain-fuel/refine/actions/runs/34656772216). A fresh
  consumer fetched `v0.0.0-20260911230628-035ab1b85506` without replacements and
  passed race-tested source generation, Java compilation, whole-record checks,
  validation exceptions, indeterminate evaluation and budget exhaustion.

## Semantic Java model checkpoint

- `GenerateModels` emits nominal scalar/record/list models and refinement
  hierarchies backed by the generated validator. Public fields remain semantically
  typed; primitive access is explicit. Constructors validate by default, throwing
  the ordinary validation exception. Parent substitution performs no validation.
- Named bypass factories skip predicates only. A matching Go
  `ValidateDataWithoutRefinements` API and Java structural mode retain type,
  numeric representability and resource checks. Cross-runtime report comparisons
  now cover 26,500 normal/bypass cases.
- Record drafts stage changes without checking intermediate states, freeze only
  explicitly set fields, and validate the completed candidate once. Escaped
  drafts/collections cannot mutate old or returned objects. Optional absence,
  untouched extras and raw-object identity survive no-op updates. Refined record
  subclasses retain their dynamic type/invariants through parent references.
- Tests cover nominal inheritance/evidence isolation, unrelated-type compile
  rejection, immutable nested collections, recursive optional records, distinct
  optional/null/result states, bypass representability, callback failure,
  code-name collisions and unnamed/Unicode packages. A Go-derived tight budget
  checks single-pass update validation. Two fresh-seeded jetCheck suites add
  4,000 model construction/update cases.
- Local race tests, vet and deterministic generation pass. A 20-second model
  emitter fuzz run passed 9,799,010 executions. A local Darwin/arm64 (Apple M5 Max)
  source-generation benchmark measured 235,865 ns/op, 709,645 B/op and 5,855
  allocs/op; it does not measure payload throughput. GoPlus latest remains the
  pinned v0.158.0.
- Generic domain declarations, tagged alternatives, anonymous nested record
  models, full predicate/function execution, native codecs/schema adapters,
  generated tests, versioning and project integration remain required. Current
  unsupported model forms reject generation instead of weakening field types.
  [JAVA-MODELS.md](JAVA-MODELS.md) describes the exact API and remaining scope.

Next: complete model shapes and generated function/codec execution, then connect
native formats and project workflows. The full checklist remains the release gate.

## Java stack-safety correction

- Checkpoint `67fa270` passed the local model tests and an independent public
  consumer, but [CI failed](https://github.com/brain-fuel/refine/actions/runs/34659362646):
  Ubuntu's JVM exhausted its host stack during deep structural validation before
  reaching the intended logical depth guard. The macOS matrix job was cancelled.
  This is a runtime defect, not a reason to increase the JVM stack or relax tests.
- Data transfer, structural validation, optional-type expansion, expression
  execution, and deep equality now use iterative work/continuation frames. The
  existing 512-level logical guard, charging order, short circuits, traversal
  order, diagnostic paths, and normal/explicit-bypass semantics are unchanged.
- The original 26,500 full-report comparisons now run with `-Xss256k`. Separate
  stress tests add 528 deep-equality comparisons and 18,006 long-expression
  comparisons, including mismatches at the deepest field, per-clause/overall
  budget boundaries, and structural bypass. Within-policy cases must remain
  conclusively valid or invalid; matching unknowns are not accepted as success
  for those cases. All tests compare complete reports with the Go evaluator.
- Full local race tests, vet and deterministic generation passed after the
  traversal correction. GoPlus latest resolves to the pinned v0.158.0.
  A 10-second validator-emitter fuzz run passed 4,723,184 executions.
- Correction `ffd0519` passed the complete Linux and macOS
  [CI run](https://github.com/brain-fuel/refine/actions/runs/34660566145), including
  race tests, vet, generation, CLI checks and all fuzz gates. A fresh module
  fetched `v0.0.0-20260912000740-ffd0519ebb37` with `GOWORK=off` and no replacements,
  then generated/compiled Java models and passed race-tested consumer checks:
  120-level recursive records, deep equality/mismatches, atomic updates and
  bypasses, 160-term expressions, and over-limit indeterminate results, all with
  a 256 KiB JVM stack. The same consumer fails with `StackOverflowError` on
  `67fa270` and passes again after restoring `ffd0519`.

## Bounded Java contract initialization

- The single contract initializer and 48,000-byte source rejection are replaced
  by dependency-ordered, typed initializer nodes. Groups of 32 nodes and bounded
  loader classes avoid method/constant-pool growth in a single class. Sequential
  loading avoids recursive class initialization. Large lists are grouped without
  reordering, and long strings are joined from UTF-8-boundary-safe pieces rather
  than folded into oversized JVM constants.
- This preserves the eight-file validator source set and public APIs. Helper
  classes are package-private within the contract source; Java consumers need
  no Go toolchain or extra Maven artifact. Separate model-source/shape limits and
  unsupported execution forms remain obligations, not silent approximations.
- A 4,836,146-byte generated contract compiles with Java 25 warnings-as-errors
  and runs with `-Xss256k`: 1,100 named refinements, 1,100 record fields, 1,100
  alternatives, a 1,100-element expression literal, 70 ordered rules, a
  70,000-character message, a 70,000-character inactive expression constant, and
  a long supplementary-Unicode diagnostic code. Complete reports match Go.
  Property tests cover splitting at supplementary characters, NUL and escapes.
- Full local race, vet and deterministic-generation checks pass, including the
  existing 45,034 report comparisons and model/jetCheck suites. A 10-second
  validator-emitter fuzz run passed 4,933,626 executions. Source generation for
  the regular validator fixture measured 258,076 ns/op, 959,183 B/op and 7,669
  allocations/op on Darwin/arm64 (Apple M5 Max); this measures generation, not
  payload throughput.
- A fresh consumer fetched `v0.0.0-20260912002054-17e9fb761d91` without workspace
  replacements, generated 401 semantic models plus their large contract, compiled
  with Java 25 warnings-as-errors, and passed a race-tested harness at `-Xss256k`.
  It verifies normal/rejected constructors and the exact 70,000-character custom
  message. The independent deep-model/equality/atomic-update consumer also passes
  after fetching this checkpoint. Checkpoint `17e9fb7` passed the full Linux/macOS
  [CI run](https://github.com/brain-fuel/refine/actions/runs/34661325983), including
  all fuzz gates. This verifies bounded initialization, not the unfinished full
  compiler/model/serde/release requirements above.

## Java named-function and pattern execution

- `Program.CheckedSyntax()` supplies a detached, checked syntax/inference/scope
  snapshot for backends. Mutation tests cover expression/type nodes and generic
  scope maps without changing the original program or independent snapshots.
  Java emission now retains type instantiation and generic declaration/function
  bindings instead of dropping the checker's metadata.
- Generated Java executes named functions, ordinary and polymorphic recursion,
  partial application, higher-order arguments/results, nullary definitions,
  constructors, ordered equations and nested case/list/cons/literal patterns.
  Ordinary local type annotations are supported. Functions inhabit a private
  value hierarchy, not the public payload `Data` variants.
- Collection operators and all four `satisfies*` spellings preserve the Go
  evaluator's logical-step/depth accounting and three-outcome semantics. Queued
  exception boundaries let nested quantifiers recover from unknowns without
  recursively re-entering the host JVM stack or retaining failed continuations.
- The function suite compares 82,048 complete Go/Java reports, including all
  no/yes/unknown sequences through length four, tiny total/clause budgets,
  ignored eager arguments, generic optional arguments, record signatures,
  fixed-width overflow, builtin shadowing, polymorphic recursion and recovery
  after depth failure. Another 3,000 fresh jetCheck cases exercise recursive sum
  and higher-order/unknown composition. Model constructors and bypasses now
  exercise function-backed predicates too. Existing runtime/model/stack/large
  initializer suites remain in force.
- Java builtin `show`/`read`, regex, timestamps and anonymous inline assertions
  (including refined function signatures) still reject emission explicitly.
  They remain required alongside the outstanding model, native-format, serde,
  English, analysis, versioning, generated-test and Maven/CLI work.
- A 10-second validator-emitter fuzz run passed 5,028,211 executions. The regular
  validator generation benchmark measured 455,620 ns/op, 1,103,522 B/op and 9,530
  allocations/op on Darwin/arm64 (Apple M5 Max), now including a detached full
  type check. Full local race tests, vet and deterministic generation pass.
  GoPlus latest remains pinned at v0.158.0.
- A fresh external module fetched `v0.0.0-20260912005118-a1844066b133` with
  `GOWORK=off` and no replacements. Its race-tested harness generated and compiled
  function-backed invoice models with Java 25 warnings-as-errors, then verified
  recursive line totals, quantifier checks, invalid construction, atomic updates,
  bypass revalidation, tiny-budget unknowns and recovery from a looping predicate,
  all with `-Xss256k`. Mutating a checked snapshot did not affect generation.
  Checkpoint `a184406` passed the complete Linux/macOS
  [CI run](https://github.com/brain-fuel/refine/actions/runs/34662998323), including
  generation, race, vet, CLI and all fuzz gates. The remaining execution forms
  and the full release checklist above are still required.

## Java inline refinement contracts

- Generated Java now enforces anonymous refinements on local bindings and
  function arguments/results. Immutable guards survive currying, higher-order
  arguments, returned functions, and function values nested inside local
  records/lists. Named parent predicates are not re-run for substitution.
- Nested contract predicates use child meters on the same continuation queue;
  recursion observes Go's logical depth guard without recursive JVM calls.
  All clauses are collected with invalid-over-unknown precedence; failed custom
  messages still consume budget but do not erase a conclusive false predicate.
  Inline assertion failures remain evaluation errors, making the enclosing
  payload clause indeterminate rather than falsely reporting a Boolean result.
- Deferred expression/signature references form a finite metadata table, even
  when a signature predicate recursively invokes its own function. Bounded
  initializer chunks remain in use. Immutable definition maps retain source
  order for exact metered generic-declaration lookup.
- Function conformance now compares 166,054 complete Go/Java reports, including
  84,006 inline-contract cases across total/clause budgets and bypasses. Coverage
  includes optional/result/recursive generic types, record-field ordering,
  declaration-rule erasure, partial-call preconditions, nullary postconditions,
  recursive guards, recovery after unknowns, and message failures. The 3,000-case
  jetCheck suite now independently asserts inline boundary behavior and rule
  aggregation as well as the earlier function laws. Semantic models exercise
  validated construction, ordinary exceptions, and bypass revalidation of
  inline function contracts.
- Full local race tests, vet and deterministic generation pass with Java 25;
  function conformance runs with `-Xss256k`. A 10-second emitter fuzz run passed
  4,966,112 executions, including new recursive-signature and local-guard seeds.
  The regular validator generation benchmark measured 332,858 ns/op,
  1,121,633 B/op and 9,632 allocations/op on Darwin/arm64 (Apple M5 Max).
  GoPlus latest remains v0.158.0, reverified through the module registry.
- This closes the inline-assertion limitation of the preceding checkpoint, not
  the release checklist. Java builtin show/read, regex/timestamps, complete
  models, native formats, validated serde, English output, analysis, versioning,
  schema-derived tests, Maven wiring and full CLI workflows remain required.
- A fresh external module fetched `v0.0.0-20260912011209-7e2def006ae6` with
  `GOWORK=off` and no replacements. Its race-tested harness generated semantic
  models and compiled them with Java 25 warnings-as-errors, then verified local
  function guards, whole-record function preconditions, atomic updates,
  exceptions, bypass revalidation, tiny-budget unknowns, and recovery from a
  recursively guarded function at `-Xss256k`.
  Checkpoint `7e2def0` passed the complete Linux/macOS
  [CI run](https://github.com/brain-fuel/refine/actions/runs/34664106288), including
  generation, race, vet, CLI and all fuzz gates. No product tag or Maven
  deployment was made; the full release checklist remains open.

## Java canonical display

- Java's `show` builtin now handles exact numbers, UTF-16 text, Booleans,
  records, lists and tagged constructors. First-class use works through named
  higher-order functions, local aliases and inline guards. Display preserves
  mathematical values, quotes signed/fractional constructor arguments, and sorts
  record identifiers by Unicode scalar order rather than UTF-16 order.
- Generated `Contract.showWithoutValidation` accepts raw payloads and optional
  caller limits without asserting refinements, matching Go's explicit raw-display
  API. Invalid bypass-created models remain displayable via `rawData()`. Failure
  throws a normal validation exception with diagnostics, never partial output.
  Traversal uses continuations and preserves Go's logical depth/step accounting.
- Generated contract support embeds Go's Unicode 15.0.0 letter/digit/uppercase
  tables instead of relying on the JDK's independently versioned classifiers.
  Go's full BSD-style notice accompanies the tables; the final binary artifact
  attribution audit remains a release obligation.
- The display suite passes 71,400 full-report/raw-boundary Go/Java comparisons,
  including every small total/clause budget for representative values, invalid
  grammar names, deep values at the logical depth boundary, and explicit bypasses.
  It exhaustively compares Unicode classifications for all 1,114,112 code points.
  Another 4,000 fresh-seeded jetCheck cases exercise arbitrary UTF-16 text,
  rational display, record ordering, higher-order equivalence and unchanged raw
  payloads. Semantic model tests also show a bypass-created invalid value.
- Full local race tests, vet and deterministic GoPlus generation pass. A
  10-second validator-emitter fuzz run passed 4,646,098 executions. The regular
  validator generation benchmark measured 528,692 ns/op, 1,469,316 B/op and
  11,386 allocations/op on Darwin/arm64 (Apple M5 Max), including Unicode table
  emission. These are generation measurements, not payload throughput claims.
- Java typed `read` remains explicitly rejected until its data-only parser and
  nested validating path are complete. Regex/timestamps, complete model shapes,
  native formats, validated serde, English output, analysis, versioning,
  schema-derived tests, Maven wiring and full CLI workflows remain required.
- A fresh public consumer fetched `v0.0.0-20260912012910-0ce812855fe2` with
  `GOWORK=off` and no replacements. Its race-tested harness generated semantic
  models, compiled with Java 25 warnings-as-errors, then verified exact display,
  UTF-16 preservation, Unicode scalar record ordering, computed error messages,
  explicit invalid-model bypass display, budget exceptions, and depth-510 raw
  traversal at `-Xss256k`.
  Checkpoint `0ce8128` passed the complete Linux/macOS
  [CI run](https://github.com/brain-fuel/refine/actions/runs/34664959672), including
  generation, race, vet, CLI and all fuzz gates. GoPlus latest remains pinned at
  v0.158.0. No product tag or Maven deployment was made; the full release
  checklist remains open.

## Java typed canonical reading

- The `read` builtin now resolves inferred targets through generic functions,
  higher-order calls, local bindings and declaration scopes. It parses the same
  expression/type/pattern grammar as Go, then interprets only literal data and
  constructor forms. Text cannot execute arbitrary functions or expressions.
  Parser and decoder traversal are iterative, retaining Go's depth, token,
  UTF-8 byte and logical-step limits.
- Target validation shares enclosing meters and the expression continuation
  queue. `Ok` is produced only after successful validation; malformed input and
  conclusive target violations produce `Err`; unknown target validation remains
  an evaluation failure. Recursively reading a refined target cannot reset its
  caller's budget or recurse on the JVM stack. Failed custom messages preserve
  a conclusive target violation.
- `Contract.read` returns full reports and exposes a candidate only for a valid
  read. `orThrow()` integrates with ordinary exception handling. Generated model
  `read` factories use the validated nominal evidence directly; instance
  `showWithoutValidation` supports canonical display of bypass-created values,
  which are checked again on subsequent reads. Field naming avoids collisions
  with the new codec methods.
- Tests compare 34,575 complete Go/Java read reports/values and 11,717 parser
  differential/resource cases. Structural hashes compare expression/type/pattern
  trees, not just parser acceptance. Cases cover generic scopes, anonymous and
  named refinements, optional/recursive data, failed messages, recursive reads,
  unknown recovery, small budgets, 512-level boundaries, 16 MiB UTF-8 limits and
  the million-token limit, all with a 256 KiB JVM stack. Four fresh-seeded
  jetCheck suites add 8,000 cases for primitive/structured round trips,
  refinement enforcement and arbitrary-input determinism. Generated model tests
  exercise typed factories, parent evidence, collisions and bypass revalidation.
- Full local race tests, vet and deterministic GoPlus generation pass. A
  10-second validator-emitter fuzz run passed 3,679,216 executions. The regular
  validator generation benchmark measured 571,867 ns/op, 1,535,548 B/op and
  11,386 allocations/op on Darwin/arm64 (Apple M5 Max). These measurements cover
  generation, not payload throughput. The latest GoPlus remains v0.158.0.
- A fresh public consumer fetched `v0.0.0-20260912020304-fe8449ba6193` with
  `GOWORK=off` and no replacements. Its race-tested harness generated models,
  compiled with Java 25 warnings-as-errors and verified nominal parent evidence,
  generic target inference, recursive-read recovery, exact structured/UTF-16
  round trips, custom diagnostics, bypass revalidation and caller budgets at
  `-Xss256k`. Invalid and indeterminate results exposed no candidate payload.
- Checkpoint `fe8449b` passed the complete Linux/macOS
  [CI run](https://github.com/brain-fuel/refine/actions/runs/34666580549), including
  generation, race, vet, CLI and all fuzz gates. No product tag or Maven
  deployment was made; the full release checklist remains open.
- Java timestamps and regex remain explicitly unsupported. Complete models,
  native ingestion/exports, validated Jackson/Avro serde, English output,
  analysis, versioning, schema-derived tests, Maven wiring and the full CLI
  remain required. This checkpoint does not complete the release checklist.

## Java exact timestamps

- Generated `Timestamp` values preserve RFC 3339 spelling, numeric offset,
  unknown-local-offset metadata and arbitrary decimal fractional precision.
  Parsing uses UTC calendar arithmetic only, with the same pinned IERS C72
  leap-second knowledge as Go. Instant equality/order do not round or compare
  spellings; Java equality/hash codes agree for offset-equivalent instants.
- Timestamp payloads stay ordinary text in raw `Data`. Validator typed views,
  comparisons, canonical display/read, generic inferred reads, inline contracts
  and generated nominal models now execute timestamp semantics. Structural
  bypasses still reject invalid or unknown leap labels. Parsing, comparison,
  display and export charge the same logical costs as Go, including nested reads.
- Explicit primitive civil-coordinate and SI-duration methods return exact
  rationals. Civil arithmetic refuses leap-labelled endpoints; SI arithmetic
  refuses unknown history. These methods are not yet DSL duration builtins.
- Tests pass 14,495 Go/Java primitive comparisons and 29,912 complete
  report/read comparisons. They cover every month boundary in the pinned
  history, all 2,879 legal minute offsets around a known leap, malformed dates,
  year limits, fractions beyond nanoseconds, generic/inline reads, sibling
  unknown/invalid collection, private diagnostics and small budgets. Three
  fresh-seeded jetCheck suites add 6,000 cases for offset equivalence, typed
  round trips, exact durations, atomic updates and bypass revalidation. Java 25
  compilation treats warnings as errors; execution uses `-Xss256k`.
- Full local race tests, vet and deterministic GoPlus generation pass.
  A 10-second validator-emitter fuzz run passed 2,935,672 executions. Runtime
  generation measured 4,283 ns/op, 29,472 B/op and 27 allocations/op; validator
  generation measured 548,747 ns/op, 1,543,545 B/op and 11,388 allocations/op
  on Darwin/arm64 (Apple M5 Max). These are generation, not validation throughput,
  measurements. GoPlus latest remains v0.158.0.
- A fresh public consumer fetched `v0.0.0-20260912021947-4085e49dc264` with
  `GOWORK=off` and no replacements. Its race-tested harness compiled generated
  models with Java 25 warnings-as-errors and verified exact fractions/durations,
  leap rules, unchanged offset/precision spelling, nominal/generic reads, atomic
  booking updates, bypass revalidation and caller budgets at `-Xss256k`.
- Checkpoint `4085e49` passed the complete Linux/macOS
  [CI run](https://github.com/brain-fuel/refine/actions/runs/34667355483), including
  generation, race, vet, CLI and all fuzz gates. No product tag or Maven
  deployment was made; the full release checklist remains open.
- Java regex, complete model shapes, native formats, validated serde, English
  export, full language/conversions/imports, analysis, versioning, generated
  schema-derived tests, Maven wiring and the full CLI remain release obligations.
  No product tag or Maven deployment is implied by this checkpoint.

## Java regex instruction matcher

- `pattern.Regex.Program()` provides a detached, typed instruction snapshot with
  an explicit execution profile and Unicode version. Snapshot mutation cannot
  change the compiled Go regex. Adding the instruction enum preserves the
  original public Mode `Fold` helper through a GoPlus-authored forwarding API.
- Generated `RegexProgram` validates and freezes instruction plans, then runs
  full matching or substring search through iterative Thompson state sets.
  It preserves UTF-16 surrogate identity, ASCII word-boundary semantics, pinned
  Go Unicode simple-fold orbits and the exact Go matcher step-accounting order.
  Programs are immutable; invocation state and budget meters are local.
- Tests compare 420 compiled programs and 87,252 complete result/budget traces,
  including enclosing/nested used counts and recovery after exhaustion. Every
  Unicode code point is checked against Go's simple-fold mapping. Cases cover
  all opcodes, malformed plans, captures, zero-width assertions, nullable cycles,
  ambiguous repetition, lone surrogates and large programs at `-Xss256k`.
  Three fresh-seeded jetCheck suites add 6,000 literal/code-point/budget-law
  cases, with further mutation-isolation and concurrent-reuse checks.
- Full local race tests, vet and deterministic GoPlus generation pass.
  Ten-second fuzz runs passed 6,381,160 Go regex differential executions and
  2,907,444 validator-generation executions. Runtime generation measured
  12,355 ns/op, 115,137 B/op and 34 allocations/op; validator generation measured
  622,399 ns/op, 1,629,868 B/op and 11,394 allocations/op on Darwin/arm64
  (Apple M5 Max). These measure source generation, not match throughput.
  GoPlus latest remains v0.158.0. Generated simple-fold tables and rune/assertion
  semantics retain Go's full BSD-style notice; final binary attribution remains
  a release gate.
- A fresh public consumer fetched `v0.0.0-20260912023956-abbbe6d0af81` with
  `GOWORK=off` and no replacements. Its race-tested harness compiled generated
  Java 25 runtime sources and Go-exported plans with warnings-as-errors, then
  verified full/search results, Unicode folding, lone surrogates, code points,
  word boundaries, ambiguous repetition and exact budget thresholds at
  `-Xss256k`. It also checked the preserved Go `Fold` API and continued explicit
  rejection of incomplete Java DSL regex generation.
- Checkpoint `abbbe6d` passed the complete Linux/macOS
  [CI run](https://github.com/brain-fuel/refine/actions/runs/34668287773), including
  generation, race, vet, CLI and all fuzz gates. No product tag or Maven
  deployment was made; the full release checklist remains open.
- This is the shared instruction executor, not complete Java regex support.
  Dynamic pattern parsing/compilation and compile-cost parity remain required
  before enabling `matches`/`search`; Java generation still rejects those builtins.
  Native regex dialects, full language and model shapes, native schema formats,
  validated serde, English exports, analysis, versioning, automatic generated
  tests, Maven/project integration and complete CLI workflows remain required.

## Java parsed regex tree compiler

- Generated `RegexProgram.compileTree` compiles immutable, already parsed and
  normalized regex trees. Its simplifier and instruction allocation follow Go's
  `regexp/syntax`, including lazy/greedy branches, nullable loops, capture slots
  and counted repetition expansion. Explicit work queues avoid JVM recursion
  even when simplification produces trees deeper than their source.
- Compilation charges the same tree visits and unsigned-64-bit expansion bound
  as Go before expansion/allocation. Depth 512 and arithmetic overflow return
  `regex.limit`; budget exhaustion preserves the exact shared meter state.
  Source-size charging and source parsing are not part of this tree API.
- Instruction validation checks every reachable edge while preserving Go's
  unreachable fragment patch-list links. Shape/range checks still apply to all
  instructions. Frozen programs prevent dead fragments becoming reachable.
  Generated sources retain the full Go BSD-style notice for compiler/simplifier
  adaptations as well as matching and Unicode tables.
- Tests pass 20,454 exact instruction-digest/budget comparisons across 2,243
  parsed patterns and 2,021 synthetic/random trees. Cases cover all tree forms,
  empty/failing/dead fragments, capture ordering, repetition simplification,
  nested budgets and recovery, depth boundaries and expansion overflow. Three
  jetCheck suites add 6,000 repetition-language, budget and depth-law cases.
  The existing 87,252 matcher/budget comparisons and exhaustive Unicode folding
  checks still pass. Java 25 uses warnings-as-errors and `-Xss256k`.
- Full local race tests, vet and deterministic GoPlus generation pass.
  Ten-second fuzz runs passed 6,655,417 Go regex differential executions and
  3,250,366 validator-generation executions. Runtime generation measured
  16,351 ns/op, 147,906 B/op and 34 allocations/op; validator generation measured
  496,669 ns/op, 1,662,316 B/op and 11,393 allocations/op on Darwin/arm64
  (Apple M5 Max). These are source-generation measurements, not compilation or
  matching throughput. Latest published GoPlus remains v0.158.0.
- A fresh public consumer fetched `v0.0.0-20260912030447-a7093ec8f529` with
  `GOWORK=off` and no replacements. Its race-tested harness generated standalone
  Java 25 sources, compiled with warnings-as-errors, and verified exact Go
  instruction digests, compilation budgets, full/search results and match
  budgets at `-Xss256k`. Cases included captures, Unicode folding/surrogates,
  nullable cycles and large counted repetitions. Incomplete DSL regex generation
  remained explicitly rejected.
- Checkpoint `a7093ec` passed the complete Linux/macOS
  [CI run](https://github.com/brain-fuel/refine/actions/runs/34669397606), including
  generation, race, vet, CLI and all fuzz gates. No product tag or Maven
  deployment was made; the full release checklist remains open.
- Dynamic Java pattern-text parsing/normalization and source-compilation cost
  parity remain required before enabling DSL `matches`/`search`. Generation
  continues to reject those builtins explicitly. Full native formats, models,
  serde, English output, analysis, versioning, schema-derived tests, Maven wiring
  and CLI workflows remain release obligations; no product tag or Maven deploy
  is implied by this compiler checkpoint.

## Dynamic Java regex parsing and predicate execution

- Generated `RegexProgram.parseTree` and `compile` accept dynamic Go/RE2-dialect
  pattern text. The parser preserves Go's normalization and instruction choices:
  common-prefix factoring, safe repeated-class factoring, class merging, capture
  numbering/names, local/global flags, quoting, escapes and counted repetition.
  Explicit queues/stacks handle factoring, parser size/height checks and frozen
  tree construction without JVM recursion dependence.
- Source parsing charges the same UTF-16 quadratic prefix cost as Go, before
  scalar-text checking or parsing. Parser allocation/rune/size/height accounting,
  repeat limits, tree expansion charges, instruction order and matcher charges
  agree in the conformance suite. Invalid patterns yield sanitized `regex.syntax`
  diagnostics; deterministic resource failures use `regex.limit`/`regex.budget`.
  Each call charges its full cost; no result cache changes budget behavior.
- Generated Unicode category/script/alias lookup tables use the Go parser's
  actual accepted vocabulary and normalized ranges, including negation/folding
  and singleton categories. Names present in Go's Unicode tables but rejected by
  its regex parser remain rejected in Java. No JDK regex or Unicode version is
  substituted. Generated source retains Go's full BSD-style notice, including
  the 2013 ASCII-class attribution; binary attribution remains a release gate.
- Java `matches` and `search` now execute, including dynamic payload patterns,
  named/higher-order calls, inline assertions, typed reads, custom messages and
  three-outcome combinators. Invalid/unknown patterns are not false matches.
  Validated model construction/updates/read enforce predicates; explicit bypasses
  preserve raw values but subsequent validation/read still enforces the rules.
- Tests pass 104,422 exact normalized-tree/instruction/error/budget comparisons
  across 26,301 patterns and 30,390 complete validation/read report comparisons.
  They cover every available Unicode category/script/alias lookup, malformed
  sources, arbitrary syntax fragments, recursive generated expressions, deep
  alternative factoring, parser/compiler limits, privacy, clause budgets,
  recovery and model APIs. Two additional sets of jetCheck suites add 12,000
  fresh-seeded cases for scalar escapes, repetition languages, budgets, depth,
  model reads/updates and private-error recovery. Java 25 warnings are errors;
  execution uses `-Xss256k`, with additional concurrent-use checks.
- Full local race tests, vet and deterministic GoPlus generation pass.
  Ten-second fuzz runs passed 6,439,767 Go regex differential executions and
  2,909,320 validator-generation executions. Runtime generation measured
  66,961 ns/op, 852,429 B/op and 34 allocations/op; validator generation measured
  765,163 ns/op, 2,388,154 B/op and 11,398 allocations/op on Darwin/arm64
  (Apple M5 Max). These measure source generation, not predicate throughput.
  Unicode vocabulary increases emitted runtime size; GoPlus latest is v0.158.0.
- A fresh public consumer fetched `v0.0.0-20260912033535-3c0cfa08241a` with
  `GOWORK=off` and no replacements. Its race-tested harness generated and
  compiled standalone Java 25 models with warnings-as-errors, then checked exact
  Go compilation/matching budgets, full/search results, complete diagnostic
  reports, unknown recovery, validated construction/read, atomic updates and
  bypass revalidation at `-Xss256k`.
- Checkpoint `3c0cfa0` passed the complete Linux/macOS
  [CI run](https://github.com/brain-fuel/refine/actions/runs/34670789902), including
  generation, race, vet, CLI and all fuzz gates. No product tag or Maven
  deployment was made; the full release checklist remains open.
- Current Go/Java refinement regex conformance does not establish automatic
  compatibility with future Go parser/Unicode changes. Release-stable profile
  auditing and native-schema regex dialects remain required. Full model shapes,
  language/conversions/imports, native ingestion/exports, validated serde,
  English output, analysis, versioning, schema-derived tests, Maven wiring and
  CLI workflows remain release obligations. No product tag or Maven deploy has
  been made.

## Semantic Java tagged-union checkpoint

- `java/model_unions.gp` extends `GenerateModels` to monomorphic tagged unions,
  recursive alternatives and nominal refinement chains. Generated sealed
  interfaces and nested immutable classes preserve both the declared parent
  interface and each original alternative's class hierarchy. Typed constructor
  arguments/getters, immutable raw access, validation outcomes, validating
  canonical reads and explicitly named structural-only bypasses are retained.
- A closed `variant()` view returns the same object and supports exhaustive
  switches over the root alternatives without a default arm. This addresses
  Java's inability to infer that coverage directly over a root whose permitted
  subinterfaces include nominal refinements. Neither substitution nor the view
  performs validation or copying. Alternative-specific factories check the tag
  and arity; unrelated/parent/sibling evidence cannot manufacture a refined type.
- Typed creation and atomic-update drafts share the root alternative's shape.
  Only the completed candidate is validated; failed callbacks or validation and
  subsequently mutated escaped drafts cannot change old or returned values.
  Refined alternatives keep their dynamic predicates and covariant result types
  through parent references. Missing creation arguments fail structurally even
  through bypass builders. Native serde/discriminator behavior is not invented.
- More than 253 constructor arguments use draft builders/raw factories instead
  of invalid JVM method signatures. Dispatch and argument encoding use bounded
  helpers. Actual Java 25 warnings-as-errors compilation/execution passes for
  1,100 alternatives, a 260-argument constructor and its refinement, and the
  exact 253-argument positional boundary. Go-derived minimum budgets prove wide
  creation and updates each use one complete validation pass.
- The union suite passes 18,729 complete Go/Java validation/bypass/read reports,
  plus 6,000 jetCheck cases covering construction, updates and recursive trees.
  Tests include wrong alternatives, invalid/indeterminate predicates, caller and
  per-clause limits, nested collections/optional union fields, immutable drafts,
  nominal evidence isolation, negative Java compilation and exhaustive matching.
  Unnamed, Unicode and restricted-identifier package fixtures compile; collision
  escaping preserves original language constructor names.
- Full local race tests, vet and deterministic generated-source checks pass.
  A ten-second model-generation fuzz run passed 2,686,008 executions. Existing
  model source generation measured 1,655,637 ns/op, 2,999,998 B/op and 15,624
  allocations/op on Darwin/arm64 (Apple M5 Max); this is source generation,
  not payload-validation throughput. Latest GoPlus remains v0.158.0.
- A fresh external module fetched public pseudo-version
  `v0.0.0-20260912041112-e61d4efe226d` with `GOWORK=off` and no local
  replacements. Its race-tested harness generated standalone Java 25 models,
  compiled with all warnings treated as errors, and ran exhaustive nominal
  matching, raw identity, dynamic refinement updates, escaped-draft isolation,
  bypass/read rejection, exact single-pass budgets and recursive unions at
  `-Xss256k`. This is a tested development pseudo-version, not a product release.
- Checkpoint `e61d4ef` passed the complete Linux/macOS
  [CI run](https://github.com/brain-fuel/refine/actions/runs/34672340680), including
  generation, race, vet, CLI and all fuzz gates. Source and generated Go were
  pushed together; no product tag or Maven deployment was made.
- Generic domain models, anonymous nested record classes and wide regular
  record emission remain required; regular models still retain their 48,000-byte
  source guard. Native formats, validated serde, remaining language work,
  English output, analysis, schema-derived tests, versioning, Maven integration,
  CLI workflows and the full release audit are not completed by this checkpoint.
  No product tag or Maven deployment is made.

## Bounded Java record construction

- Regular record models now expose typed `create` and `createWithoutValidation`
  draft factories, with default/caller budget overloads. Creation starts from
  an empty record, stages final assigned fields in declaration order and validates
  once. Missing required fields remain ordinary structural failures; omitted
  optional fields stay absent in raw data, with getters exposing `Nothing`.
  Nullable fields are not silently optional. Callback exceptions propagate.
- Draft field encoders use bounded helpers, and records wider than 253 fields
  use builders/raw factories instead of exceeding JVM parameter slots. Smaller
  records retain positional constructors and bypass factories. The former
  48,000-byte model-source rejection is removed without erasing typed getters,
  setters, nominal inheritance or immutable snapshots.
- Draft helper names avoid domain/contract-name collisions. A domain type or
  contract class named `Draft` is no longer rejected wholesale; affected helpers
  are deterministically suffixed. Union alternative names also avoid the chosen
  helper name. Compile/run fixtures cover record and union types named `Draft`,
  suffixed-name collisions, unnamed/Unicode/restricted-identifier packages and
  fields colliding with new factory/helper methods.
- Java 25 warnings-as-errors tests compile and execute record widths 0, 1, 64,
  65, 253, 254, 260 and 1,100. Go-derived minimum budgets establish one complete
  validation pass for construction/update at every tested width, including
  multi-level nominal refinements. Wide getters, canonical reads, invalid
  bypasses, escaped drafts, caller failures and dynamic parent-reference updates
  are checked. Another 6,000 jetCheck cases exercise creation/update, bypass
  correction, reads, extra-field retention and absent optional-field preservation
  in language data; these do not define unimplemented native wire policies.
- Full local race tests, vet and deterministic generated-source checks pass.
  The final ten-second model-generation fuzz run passed 3,725,020 executions.
  Model source generation measured 924,444 ns/op, 3,073,549 B/op and 16,118
  allocations/op on Darwin/arm64 (Apple M5 Max), not validation throughput.
  Latest GoPlus remains v0.158.0. Generic domain models, anonymous nested record
  classes, remaining language/native/serde work, analysis, English output,
  schema-derived tests, versioning, Maven and CLI integration remain required.
  No product tag or Maven deployment is made.
- A fresh external module fetched
  `v0.0.0-20260912043040-acfc6c213327` with `GOWORK=off` and no replacements.
  Its race-tested harness compiled generated Java 25 with warnings-as-errors and
  ran a 262-field record with nominal parent refinements, a domain type named
  `Draft`, typed helper disambiguation, absent optional fields, exact single-pass
  budgets, immutable updates, structural bypass failures and canonical read
  revalidation at `-Xss256k`. This is a development pseudo-version, not a product
  release or Maven deployment.
- Checkpoint `acfc6c2` passed the complete Linux/macOS
  [CI run](https://github.com/brain-fuel/refine/actions/runs/34673194522), including
  generation, race, vet, CLI and all fuzz gates. Authored GoPlus and generated
  Go were pushed together. No product tag or Maven deployment was made.

## Checked instantiated payload types

- `Program.PayloadType(expression)` creates an immutable, closed validation/read
  target for instantiated generic declarations, anonymous records, collections,
  builtins and arbitrary statically checked refinements. `ParseTypeExpression`
  parses exactly one type under the existing parser/tree limits. Unbound
  parameters, arity errors, unknown names, function-valued payloads, invalid
  predicates and trailing declarations fail before a handle is returned.
- The checker is shared with ordinary module compilation. Additional target
  inference runs after the original module, preserving its generic scope symbols.
  Targets have private inference state and caller-owned syntax/checked snapshots;
  neither mutations nor same-named types in another program change a handle.
  Creating a handle evaluates no predicates and adds no synthetic alias layer.
  Existing named-root APIs retain their behavior. Nil/zero handles fail closed.
- Validation, structural-only bypass and canonical read use the existing Go
  evaluator. Failed reads expose no candidate. Tests cover generic/recursive
  structures, anonymous rules, inferred higher-order reads, inline assertions,
  unknown results, numeric boundaries, mutation isolation and concurrent use.
  There are 2,691 complete named-root budget/report comparisons plus 3,000
  property cases for validated versus explicit-bypass outcomes.
- `GenerateValidatorWithTypes` emits a deterministic registry of checked targets
  and private-constructor immutable Java handles with validation/bypass/read
  methods and default/caller budget overloads. Labels are nonempty Unicode map
  keys; unknown/null labels fail. Invalid registrations reject all output.
  Java consumes static metadata, not a runtime schema/type-expression parser.
- Tests pass 19,290 complete Go/Java target report and returned-read-value
  comparisons plus 6,000 jetCheck cases. These include recursive generic
  arguments, inline/whole-structure refinements, generic read inference,
  higher-order predicates, regex, custom messages, unknown recovery, structural
  bypasses and total/per-clause budget boundaries. Generated handles cannot be
  constructed directly. A 1,100-target registry and a contract named
  `PayloadType` compile and execute with Java 25 warnings-as-errors at `-Xss256k`.
- Full local race tests, vet and deterministic GoPlus generation pass. New
  ten-second fuzz runs passed 4,655,539 checked-type executions and 1,376,765
  Java target-generation executions; both gates are included in Linux/macOS CI.
  Baseline validator generation measured 649,169 ns/op, 2,389,787 B/op and 11,421
  allocations/op on Darwin/arm64 (Apple M5 Max), not payload throughput.
- This supplies instantiated validation/read targets needed by generic models;
  generic Java domain classes and their typed runtime witnesses remain required.
  Anonymous nested model classes, remaining language/native/serde functionality,
  English output, analysis, generated tests, versioning, Maven/CLI integration
  and the full release audit also remain required. No product tag or Maven deploy
  is made. GoPlus remains pinned to the latest v0.158.0.
- Checkpoint `00e853d` passed the complete Linux/macOS
  [CI run](https://github.com/brain-fuel/refine/actions/runs/34678640955), including
  generation, race, vet, CLI and all fifteen fuzz gates.
- A fresh external Go module fetched public pseudo-version
  `v0.0.0-20260912063805-00e853d1b2cd` with `GOWORK=off` and no replacements.
  Its race-tested harness generated Java 25 static payload-type handles, compiled
  with warnings-as-errors, and checked exact Go-derived budgets, recursive generic
  reads, inferred generic `read`, anonymous argument refinements, snapshots,
  structural bypasses, optional/extra-field read views and candidate privacy at
  `-Xss256k`. The initial consumer compile failure was its own incorrect plain-Go
  construction syntax for an exported GoPlus enum variant; correcting the
  harness required no production changes. No product tag or Maven deploy occurred.

## Typed generic Java roots

- `GenerateModels` now emits generic record/scalar/list/optional/result roots,
  including phantom parameters, recursive typed records and nested applications
  in monomorphic models. `ModelType<T>` and generated `ModelTypes.forName(...)`
  factories retain checked argument metadata alongside Java representations.
  Named refined arguments remain nominal; builtins and collection/optional/result
  witnesses compose without parsing schemas or accepting user callbacks.
- Generic constructors, raw-data factories, reads and draft creation take
  witnesses before ordinary arguments; instances retain them for validation,
  getters and immutable atomic updates. Validation/read target the application
  directly, with no synthetic alias. Bypasses retain structural checks; getters
  reconstruct structural-only views as in existing monomorphic models.
- Generic records reserve JVM parameter slots for witnesses. Positional APIs
  remain available when witnesses plus fields total at most 253; larger records
  retain typed drafts/getters and bounded encoder helpers. More than 250 type
  parameters reject explicitly. Named-source collision checks include the two
  witness helpers. Public witness and unchecked raw constructors are inaccessible.
- Tests pass 3,600 complete Go/Java reports across normal validation,
  construction, bypass and read with exact total-budget boundaries, plus 6,000
  JetCheck cases for invalid bypasses, atomic changes and recursive record views.
  They cover generic predicate scope (`show`), fixed-width witnesses sharing a
  Java representation, phantom/empty arguments, nested generic fields, mutable
  input isolation, escaped drafts, callbacks, missing/extra fields and negative
  nominal-argument compilation. An initial test assumed raw equality after
  canonical read; it was corrected to assert the existing checked-view policy
  that removes extras and fills optional fields, without changing production read.
- Java 25 warnings-as-errors compile/run checks pass for generic record widths
  0, 1, 64, 65, 252, 253 and 1,100, and unnamed/Unicode/contextual-keyword package
  layouts. Full local race tests, vet and deterministic GoPlus regeneration pass.
  A ten-second model-generation fuzz run passed 3,534,173 executions. Baseline
  model generation measured 1,033,835 ns/op, 3,132,456 B/op and 16,638 allocations
  per operation on Darwin/arm64 (Apple M5 Max), not payload throughput.
- Generic tagged unions, instantiated nominal inheritance (including closed
  generic aliases), inline-refined argument witnesses and anonymous nested model
  records still reject generation atomically. These remain release requirements,
  alongside the outstanding native/serde/language/English/analysis/versioning/
  generated-test/Maven/CLI work. No release gate is checked off, no product tag
  or Maven deployment is made, and GoPlus remains at latest v0.158.0.
- A fresh external module fetched public pseudo-version
  `v0.0.0-20260912114749-3e490612a7a6` with `GOWORK=off` and no replacements.
  Its race-tested harness compiled generated Java 25 with warnings-as-errors and
  ran at `-Xss256k`, checking exact Go-derived constructor/update budgets,
  fixed-width versus unbounded witnesses, generic `show` scope, nested generic
  fields, recursive typed reads, structural bypasses and immutable collections.
  The consumer's initial plain-Go compile needed an explicit `value.TextFromUTF8`
  conversion for `ReadData`; fixing that harness required no production change.
- Source checkpoint `3e49061` passed the complete Linux/macOS
  [CI run](https://github.com/brain-fuel/refine/actions/runs/34691980151), including
  generation checks, race tests, vet, CLI checks and all fifteen fuzz gates.
  Authored GoPlus and generated Go were pushed together. No product tag or
  Maven deployment occurred.

## Parallel native, Java serde, project, and analysis integration

- Native structure ingestion now uses explicit offline ecosystem validators for
  JSON Schema 2020-12, Avro 1.12, and published OpenAPI 3 versions. Immutable
  resource bundles preserve original bytes, checked editable source/imports,
  per-resource JSON Schema provenance, selectors, and wire metadata. Lowering
  validates its outputs and embeds complete algorithmic English for additional
  rules. Structural projection and generated native enforcement remain bounded;
  unsupported cases fail explicitly, as detailed in `docs/NATIVE.md`.
- Generic tagged unions now compose instantiated inheritance and model evidence.
  Jackson 3 generation covers nested/recursive/closed-generic models, separate
  absence/null, exact-number policies, explicit union discriminators, per-record
  extra preservation, duplicate rejection, and validation before writing payload
  bytes. Avro serde and complete native runtime enforcement remain required.
- `explain` exports immutable, demand-driven English instruction graphs, helper
  equations, separate where clauses and custom messages. `analysis` proves
  supported scalar interval cases, verifies concrete counterexamples with the
  complete validator, and returns unknown outside its sound subset. Logical
  payload inclusion is explicitly not native-wire or Java ABI compatibility.
- Offline language imports retain exact source digests and a deterministic
  dependency graph. Explicit exact integer/rational conversions, four rounding
  modes, and fallible civil/SI timestamp duration run in both Go and Java.
  The worked booking, invoice, batch, deployment, payment, expression, polygon,
  and evolution contracts have executable positive/negative tests.
- The release library checks exact comparison evidence, version-controlled
  overrides/fix acknowledgements, semantic version boundaries, immutable release
  targets and pinned dependencies. Promotion has recoverable ownership-aware
  journals; portable directory race limitations are documented. A complete
  schema-driven release CLI remains required.
- Project generation discovers all released/snapshot schema files and emits
  owned models and native/English resources under one Maven project. Confined
  imports, strict config, no-codegen, package/output overrides, read-only output
  checks, and collision/rollback safeguards are tested. A real pinned Maven
  build verifies repeatable unsigned JAR bytes and automatic snapshot
  regeneration without changing released source. General test/serde project
  integration remains required.
- Schema-derived JetCheck suites now exercise valid model factories and read
  round trips, invalid factory/read rejection, explicit bypass retention,
  targeted clauses, boundary values, executable examples and serialized replay.
  Exhaustion is an error, never skipped cases. The supported generator subset
  and remaining recursive/union strategies are recorded in
  `docs/GENERATED-TESTS.md`.
- Fresh ten-second fuzz runs passed 2,224,794 analysis, 2,711,511 English-export,
  and 1,616,294 native round-trip executions. These counts describe only those
  runs, not exhaustive conformance. Latest published GoPlus remains v0.158.0.
  No full-specification release gate is marked complete by this integration.
- Integration checkpoint `91d4af4` passed local race tests, vet and deterministic
  generation, then the complete Linux/macOS
  [CI run](https://github.com/brain-fuel/refine/actions/runs/34703383890), including
  all eighteen fuzz gates. The race suite exposed a multiline-infix parser
  discrepancy between Go and Java; the corrected generated reader passed
  34,575 read/report comparisons, 11,717 parser differential/resource cases,
  and 8,000 JetCheck cases before the full rerun passed.
- A fresh external module consumed public pseudo-version
  `v0.0.0-20260912154627-91d4af49a7a0` with `GOWORK=off` and no replacements.
  Its race-tested harness checked native-bundle exact-source recovery and native
  constraints, English export and satisfiability, then generated Java 25 and ran
  Jackson 3 valid/invalid read/write tests at `-Xss256k`. No product version tag
  or Maven deployment was made.

## Inline-refined Java argument witnesses

- Generic argument witnesses now retain anonymous refinements such as
  `Box (Int where it > 0)`. Containing constructors and reads enforce them;
  nested getters reconstruct the declared witness, so independent nested
  validation and atomic updates keep the predicate. Bypasses retain metadata
  while skipping predicate execution. Anonymous constraints do not manufacture
  nominal Java classes or change methods on the underlying argument class.
- The model emitter records deterministic paths into the checked declaration
  and union-argument metadata. Generated code binds enclosing parameters and
  their inferred scope symbols simultaneously in payload types, predicate
  signatures and local annotations. Incoming closed argument metadata is not
  rebound. Original clauses, codes, messages and step budgets remain intact;
  there is no schema parser, user predicate callback or synthetic alias layer.
- Metadata traversal is iterative and inferred signature links remain lazy.
  Each traversal has local state and immutable bindings, permitting concurrent
  validation of a shared witness without mutable inference state. Monomorphic
  inherited record and union arguments use their original declaration metadata.
- Tests pass 7,200 complete Go/Java report comparisons at total-budget boundaries
  and 6,000 JetCheck cases. These cover generic `show`, typed-read scope isolation,
  local refinements, recursive functions, separate clauses, unknown outcomes,
  custom messages, nominal arguments, optional/list/result composition,
  inherited record/union arguments, nested update bypasses and concurrent use.
  Java 25 warnings-as-errors scale checks pass for 1,100 inline-refined fields
  and a 200-level predicate at `-Xss256k`. A larger initial test correctly hit
  the existing parser nesting limit; no parser limit was weakened.
- Full local race tests, vet and deterministic GoPlus checks pass. A ten-second
  model-generation fuzz run passed 3,407,054 executions. Baseline model generation
  measured 1,162,255 ns/op, 3,165,994 B/op and 16,816 allocations/op on
  Darwin/arm64 (Apple M5 Max), not payload throughput. Latest GoPlus remains
  v0.158.0.
- Generic nominal inheritance, generic unions, anonymous nested model records
  and the remaining full-specification release gates remain required. The tests
  exposed existing frontend restrictions on local annotations naming enclosing
  type parameters and unconstrained generic equality; those were kept as separate
  language work rather than silently accepted by model generation. No product tag
  or Maven deployment is made.
- A fresh external module fetched public pseudo-version
  `v0.0.0-20260912130134-4cdee1963b60` with `GOWORK=off` and no replacements.
  Its race-tested harness compiled Java 25 with warnings-as-errors and ran at
  `-Xss256k`, verifying exact Go-derived nested validation/update budgets,
  retained inline predicates after bypass, canonical read enforcement, typed-read
  scope isolation between `Age` and `Int`, and refined union-argument access.
- Source checkpoint `4cdee19` passed the complete Linux/macOS
  [CI run](https://github.com/brain-fuel/refine/actions/runs/34695271103), including
  generation, race, vet, CLI and all fifteen fuzz gates. Authored GoPlus and
  generated Go were pushed together. No product tag or Maven deployment occurred.

## Instantiated Java record and wrapper inheritance

- Generic record/wrapper families now support closed aliases, renamed/reordered/
  repeated parameters, transformed parent arguments, inline-refined arguments,
  phantom parameters and mixed generic/monomorphic ancestor chains. Type/witness
  frames compose parent substitutions while retaining original field metadata
  and inline scope. Descendants extend their instantiated parent, inherit typed
  getters and share the immutable raw payload.
- Updates use the root's fully instantiated draft and preserve the dynamic
  nominal child and its predicates through parent references. Constructor,
  factory, read and bypass validation targets the complete child once. Explicit
  bypasses retain structural checks and subsequent validation finds violations.
- Each generic-family declaration has an independent immutable nested `Factory`
  for reads, raw-data validation, draft creation and bypasses. Root static
  shorthands remain available. Derived targets use their own factory because
  Java static generic methods cannot safely hide parent factories when type
  arguments are transformed; inherited static methods still target the root.
  Factory helper names are disambiguated against domain/contract names.
- Instantiated evidence retains a checked witness and raw value. Lazy ancestor
  witnesses and iterative structural keys compare declaration identities,
  arguments, inline origins and captured scopes without recursive supplier
  equality or unproved predicate equivalence. Wrong arguments, sibling/parent
  evidence and mismatched inline origins are rejected. Checking metadata does
  not repeat payload validation.
- Tests pass 18,000 complete Go/Java validation/construction/bypass/read reports
  at total-budget boundaries and 6,000 JetCheck cases. They cover parent-typed
  updates, immutable/escaped drafts, reordered arguments, closed aliases,
  phantom parameters, scalar wrappers, nested model getters, inline predicates,
  negative compilation and direct evidence isolation. A 1,100-field transformed
  hierarchy with twenty additional alias levels compiles and runs at `-Xss256k`,
  including factory-name collisions. Key comparison handles 2,000 nested lists;
  package tests include transformed parents in unnamed and Unicode packages.
- Full local race tests, vet and deterministic GoPlus generation checks pass.
  A ten-second model-generation fuzz run passed 3,353,044 executions. Baseline
  generation measured 897,722 ns/op, 3,184,963 B/op and 16,829 allocations/op on
  Darwin/arm64 (Apple M5 Max), not payload throughput. Latest GoPlus remains
  v0.158.0.
- Generic tagged unions (including generic descendants of monomorphic unions),
  anonymous nested model records, the outstanding language/native/serde/English/
  analysis/versioning/generated-test/Maven/CLI work and the full release audit
  remain required. No product tag or Maven deployment is made.
- A fresh external module fetched public pseudo-version
  `v0.0.0-20260912134911-c70912d79f6b` with `GOWORK=off` and no replacements.
  Its race-tested harness compiled Java 25 with warnings-as-errors and ran at
  `-Xss256k`, checking exact Go-derived constructor and parent-update budgets,
  transformed parent arguments, reordered fields, shared raw-payload identity,
  dynamic child updates, retained inline predicates, bypasses and read
  revalidation. The consumer passed without production or harness corrections.
- Source checkpoint `c70912d` passed the complete Linux/macOS
  [CI run](https://github.com/brain-fuel/refine/actions/runs/34697484327), including
  generation checks, race tests, vet, CLI checks and all fifteen fuzz gates.
  Authored GoPlus and generated Go were pushed together. No product tag or
  Maven deployment occurred.

## Release integration gaps — 2026-09-12

- Ordinary `project generate`, including the command invoked by the Maven
  snippet, does not call `PlanMavenVersion`. A `noCodegen` change can therefore
  remove owned Java classes during a normal Maven build without enforcing the
  required artifact-version change. The deletion gate currently exists only in
  `release promote`.
- `release.maven.previouslyGenerated` is manual and optional. There is no
  content-bound, persisted publication manifest proving which generated classes
  were in the prior published artifact, so an omitted history entry can hide a
  removal. Generated or locally built output must not be assumed published.
- The configured `release.maven.current` and `intended` versions are not checked
  against the Maven project's actual POM version or the version of the artifact
  being built. A valid plan therefore does not yet prove that Maven uses the
  accepted artifact version.
- A schema family's `change` classification is author-supplied and is not
  checked against a semantic structural diff. Compatibility evidence can force
  a boundary for a proven break, but a compatible API addition can still be
  labeled `documentation` and receive a patch suggestion.
- CLI dependency pins currently set `AffectsContract` for every Refine import.
  This is safe but conservative: a dependency release containing only
  documentation/original-text changes can prevent a documentation-only importer
  release even when the effective contract is unchanged.
- The library-level `PlanMavenVersion` validates family names and artifact
  versions but does not reject negative components in a `GeneratedVersion`'s
  schema version. Canonical CLI parsing prevents this through the current CLI,
  but direct library callers remain insufficiently validated.

These are concrete remaining gates, not claims that publication occurred. The
current implementation still performs no Maven deployment or product release.

## No-codegen publication gate — 2026-09-12

- Ordinary project generation and recoverable release promotion now invoke the
  same `release.PlanPublication` gate before owned main Java sources are removed.
  Fresh generation without a relevant removal remains configuration-free.
- `refine.publications.json` is a strict, versioned, checked-in ledger. Records
  distinguish `published` from `unpublished` and bind exact immutable schema
  bytes, generated-source inventories, reasons, and a canonical inventory
  digest. Published records additionally bind the Maven artifact bytes/version
  and the actual sorted JAR class-entry byte digests. Local generated output is
  never inferred to have been published.
- A missing record for an existing `noCodegen` exclusion or owned source
  deletion is reported as unknown and fails closed. Published removals retain
  the family-major Maven bump policy. Maven's effective group/artifact/version
  must be passed to the CLI and match both the ledger and accepted version;
  parsing a raw POM is intentionally not treated as proof.
- The generated Maven snippet passes the effective `${project.*}` values.
  Standalone release promotion requires the equivalent explicit flags.
  Publication ledger/schema inputs are rechecked under the common mutation lock
  (or the release transaction lock) before bytes are removed or installed.
- This closes the first three items in the preceding gap list for no-codegen and
  owned-source removal only. It does not claim general Java ABI comparison,
  publication execution, signing, deployment, or repository verification. The
  semantic change-classification and dependency-impact precision gaps require
  separate evidence; subsequent work is recorded below.

## Deterministic selection and release classification — 2026-09-12

- Checkpoint `a0bc5eb3ecdd6d8ce3b2dd5f26d1239a0ad3fd14` completed successfully
  on Linux and macOS in CI run `34715151520`, including the fuzz campaigns.
  That result does not cover the subsequent dirty map/publication/tooling batch.
- Added the GoPlus-authored `refine-testplan` development command. CI replaces
  its manually maintained fuzz list with a sorted, reasoned changed-input plan.
  It discovered all 23 current targets, including two omitted by the old list.
  Same-commit dry-run selected none; `--full` discovery selected all 23. Neither
  dry run executed tests or a fuzz campaign.
- Initial selector six-test selection passed in 0.357s. Independent review found
  omitted `TestMain`, receiver-method, blank-import, Markdown fixture, and Go
  fuzz-signature dependencies. Four new regressions and three affected existing
  tests passed in one 0.233s selection after the fixes. Unknown fixture roots,
  tooling changes, and missing baselines select all targets. Progress/test
  output stays on stderr; stdout remains the versioned JSON plan.
- `analysis.CompareContractSyntax` reports redacted named syntax differences
  and stable fingerprints without claiming arbitrary predicate equivalence.
  Its three focused tests passed (the two corrected explicit-signature fixtures
  were rerun alone, 0.188s). The CLI rejects false documentation-only claims even
  with compatibility overrides, including reachable function/type changes,
  source packages, and native metadata. Six new/affected CLI tests passed in
  one 0.725s selection. Native resource documentation equivalence and historical
  Java ABI proof remain explicitly unknown; this is not full semantic diffing.
- Direct Maven planner callers now cannot use negative schema versions as
  history or next-version evidence. The single new regression passed in 0.303s.
- No additional Maven lifecycle or whole-suite run was launched for these
  intermediate changes. Their source-consistent integration gate is pending.

## Typed maps and final audit follow-ups — 2026-09-12

- Added `Map String a`, contextual `map {"key" = value}` literals, eleven map
  operations, immutable exact UTF-16 key identity, canonical read/show and
  order-independent equality. JSON Schema/OpenAPI homogeneous maps and Avro
  maps now project, lower and decode without weakening native constraints.
  Heterogeneous or untyped value domains remain explicitly unsupported.
- Generated Java uses immutable `Map<String,T>` domain values, distinct raw
  `Data.Mapping`, native JSON/Avro serde and recursive generic property
  strategies. The grouped Java/JetCheck harness covers all operations, typed
  generic values, duplicate keys, surrogate rejection with zero output, stable
  ordering and 198 exact Go/Java budget reports. Final contextual parser checks
  passed with the function execution anchor in 7.958s; the later allocation
  audit required only the map parity anchor (2.145s), not both harnesses again.
- Independent review found collection allocations preceding budget checks.
  Map literals/quantifiers now precharge before allocation; JSON uses a
  nonallocating member count before one defensive member copy. JSON and Avro
  native decoding have a separate aggregate 67,108,864-unit UTF-16 ordering
  work ceiling across nested maps, not a reinterpretation of Nodes/Values.
  The single language preflight test passed in 0.266s; three affected native
  preflight/JSON/Avro checks passed in 0.294s.
- New `FuzzMapReadShow` and the additional map payload-type seed passed replay
  in 0.191s. Automatic discovery now finds 24 targets without modifying CI's
  target list. No local fuzz campaign was launched.
- Release classification review additionally found native import graphs were
  flattened before package comparison. Reachable source identities, imports,
  entry points and packages are now checked for both plain and native bundles.
  Five affected graph/classification/promotion tests passed in 1.847s. Native
  package/identity changes cannot use compatibility overrides as documentation
  approval; comment-only native import edits remain accepted by this check.
- Publication inventories reject Windows drive/alternate-stream-style colon
  paths; the exact new table test passed in 0.216s.
- Selector fuzz signatures were compared with a real `go test -list '^Fuzz'`
  oracle (no tests/campaign executed). After correcting the test fixture's
  alias/dot-import package collision, that sole test passed in 0.672s. A
  separate normal-import initialization regression passed in 0.272s; unchanged
  test import lists do not cause extra campaigns.
- The combined source-consistent race/Maven gate passed once with the pinned
  Java 25, Jackson, Avro, networknt, GraalJS, JetCheck and Maven directories:

  ```sh
  go tool goplus gen -check ./...
  REFINE_REQUIRE_JAVA=1 \
  REFINE_JAVA_HOME=/opt/homebrew/opt/openjdk@25 \
  REFINE_JETCHECK_DIR=/tmp/refine-jetcheck-sfZEQ7 \
  REFINE_JACKSON_DIR=/tmp/refine-jackson-dCP3wX \
  REFINE_AVRO_DIR=/tmp/refine-avro-1.12.0 \
  REFINE_NETWORKNT_DIR=/tmp/refine-networknt-jars \
  REFINE_GRAALJS_DIR=/tmp/refine-regex-maven/jars \
  REFINE_REQUIRE_MAVEN=1 \
  REFINE_MAVEN_HOME=/tmp/refine-maven-SoxP0H/apache-maven-3.9.16 \
  go test -race ./...
  go vet ./...
  git diff --check
  ```

  All packages passed. Java took 196.072s; native 35.808s; project, including
  the actual Maven lifecycle, 31.129s; CLI 6.059s; selector 3.953s. No separate
  Maven run or local fuzz campaign duplicated this gate. No release tag or
  Maven deployment is claimed; the full specification still has open gaps.

## Intrinsic JSON, operation derivation and dependency evidence — 2026-09-12

- Checkpoint `ab7cf86e298ab6b648e66f03100ecc2edf9ddfae` was pushed to `main`.
  CI run `34717661193` completed successfully on both Linux and macOS, including
  the selected fuzz campaigns. No unchanged job was rerun. The current changes
  below are a separate batch, not covered by that result.
- Dependency pin classification now uses conclusive documentation-equivalence
  evidence for the exact old/new dependency entries, including their policies.
  Unknown evidence remains contract-affecting. Evidence flags are not pin
  identity: changing only that flag cannot invent a pending version. Changing
  the actual pin still does. The single release regression passed in 0.190s;
  the three new/affected CLI dependency tests passed in 0.267s.
- Added intrinsic `JSON` with six explicit constructors, structured native
  decode, transparent JSON lowering, and carrier fallback for unconstrained,
  mixed-kind, heterogeneous object and tuple schemas. Native predicates remain
  authoritative, with separate editable refinements. Selected `false` roots
  are rejected as proven empty; empty arrays with impossible items still work.
  No implicit Avro carrier representation is invented.
- The initial native matrix passed its projection/precise-map/extra-policy
  checks in a 0.257s selection. Its separate refinement/lowering test had a
  fixture-only `!=` spelling error; after using the language's `/=`, only that
  test was rerun and passed in 0.259s. One earlier GoPlus generation failure was
  corrected before relying on new tests; a test invocation against the stale
  generated tree was not counted as evidence for the new projection code.
- Independent static review identified reference-sibling field loss and empty
  `patternProperties` inconsistency; focused regressions accompany their fixes.
  Explicit scalar types remain precise through applicators. The final focused
  review checks and combined integration gate are pending for this batch.
- The native review selection passed in 0.243s: the updated carrier matrix,
  reference-sibling regression, two existing applicator/reference anchors,
  two new Boolean export tests and four existing same-format export tests.
  Selected `true` schemas now retain their exact assertion inside `allOf`
  before adding refinements, including nested selected pointers; immutable
  originals remain unchanged. The caller-level project-generation matrix
  passed in 0.273s for unconstrained, mixed, heterogeneous-map and tuple roots,
  checking models, native gates, generated properties and both output forms.
- Intrinsic JSON language race tests passed in 1.235s; semantic explanation
  race test in 1.211s. The grouped Java race selection passed in 3.624s with
  Java 25, Jackson 3, networknt and JetCheck, including native/refinement null
  gates, iterative deep-model conversion, transparent serde and properties.
  The existing Jackson adapter anchor separately passed in 1.878s. Final
  allocation review then moved object node preflights before defensive entry
  copies and added a source-order regression; this tiny later edit is covered
  by the pending integration gate, not the preceding Java result.
- Added opt-in `Project.WithDerivedOpenAPIOperations` for existing selected-root
  OpenAPI projects. It creates readable deterministic request/response types,
  explicit field paths/media selections and authoritative native bindings,
  without inventing context predicates or enabling extra-field preservation.
  The four initial derivation tests passed in 0.263s. Naming and OAS 3.0
  directional-required review fixes passed their two exact anchors in 0.503s.
  Rootless documents, general structural applicator derivation, ambiguous
  transport encodings and direction-aware OAS 3.0 native validation are still
  explicit gaps, not capabilities inferred from a green focused test.
- The frozen combined gate uses the same pinned dependency environment and
  `go test -race ./...` command recorded at the previous checkpoint. Generation
  consistency and vet passed. No standalone Maven run or local fuzz campaign
  duplicates this gate; intrinsic JSON payload-type seeds replay in the normal
  language tests. The README no longer recommends a redundant ordinary full
  suite immediately before the full race suite.
- The combined run completed: Java 199.337s, language 6.527s, project (actual
  Maven lifecycle included) 30.288s, CLI 6.161s, analysis 4.197s, schemajson
  2.901s, release 2.382s, provenance 2.166s, explain 1.931s, OpenAPI 1.508s
  and examples 1.362s passed; unchanged selector/pattern/validation/value
  results were cached. Native's 33.704s run had exactly one failed test,
  `TestWireMetadataCheckedAndImmutable`: its unconstrained-object fixture
  relied on the old empty-record projection. The fixture now explicitly
  authors its intended record before applying record-only metadata. No
  production source changed after the combined run. After scoped generation,
  only `go test -race ./native -v -run '^TestWireMetadataCheckedAndImmutable$'`
  was rerun; it passed in 1.292s. Together these checks cover the frozen batch
  without repeating Java, Maven, or the full suite. This is checkpoint
  evidence, not completion of the entire specification or a Maven deployment.
- Checkpoint `bebb866b4ae67af88b4d5b0f5a607a0cff17c6ae` was pushed to `main`.
  Its dry-run fuzz plan selected 20 affected targets out of 24 for 88 changed
  paths (`full: false`); the dry run executed no tests. CI run `34730820365`
  is the corresponding cross-platform integration run.
- A separate temporary consumer fetched the public module through
  `goforge.dev/refine` as `v0.0.0-20260913013312-bebb866b4ae6` and ran with
  `GOTOOLCHAIN=local`, no workspace replacement or GoPlus generation step.
  It passed native mixed-kind JSON acceptance/rejection, ordinary lowering
  with the wire explanation, and semantic Java model generation. This is
  public pseudoversion-consumer evidence, not a tagged release or Maven deploy.
- In CI run `34730820365`, macOS passed native (99.002s), project/Maven
  (147.748s), and the other packages, but the Java package reached the default
  600s package timeout during `TestWorkedExamplesGenerateExecutableJava`, which
  had itself run only four seconds. No preceding assertion failure was logged.
  This is a failed CI checkpoint, not a success inferred from local evidence.
  The next workflow revision gives the same selection an explicit twenty-minute
  ceiling. No unchanged CI job or local full suite was rerun for this timeout.
- Linux completed CI run `34730820365` successfully, including the 20 selected
  fuzz campaigns. The overall run remains failed because of macOS's Java
  package timeout. Test-guide name auditing also corrected obsolete map and
  generated-property test names without launching any tests.

## Offline artifact evidence and directional native validation — in progress

- Added an independent immutable JAR inventory/ledger verification boundary.
  It checks actual explicitly supplied bytes, not filenames or publication
  claims alone, and does not fetch, extract, publish or infer Java ABI changes.
  EOCD/central-directory count and range checks run before ZIP metadata
  allocation; ZIP64 and multi-disk archives are explicitly unsupported.
  Streamed CRC checks, aggregate/per-entry expanded limits, unsafe paths,
  portable-name collisions and encryption/mode rejection are covered by
  parameterized cases, 64 deterministic property cases and bounded fuzz seeds.
- Initial five-anchor artifact selection passed in 0.255s. After the directory
  allocation/dot-path/encryption review fixes, only four changed-inspector
  anchors were rerun (0.237s); the unchanged digest-verification test was reused.
  Root's exact five-anchor race/seed selection then passed once in 1.272s.
  That source is frozen; no Maven, full suite or local fuzz campaign was run
  for the independent artifact API.
- OpenAPI 3.0 operation validators now use immutable, direction-specific native
  resource views. Required read-only fields become optional in requests;
  required write-only fields become optional in responses. Supplied values
  still undergo native validation. Derived records use `Maybe`, authored
  mandatory fields fail closed, and nested map/list/nullable/generic records
  are audited. Ambiguous applicator composition remains explicitly unsupported.
  OpenAPI 3.1/3.2 retain their canonical views. The seven-anchor native selection
  in TESTING.md passed in 0.251s with scoped generation consistency.
- The Java facade uses separate native helpers only when the two resource
  views differ. It preserves constructor/limit APIs and translates response
  failures into the existing native exception class, preserving code and cause.
  The new grouped direction harness passed in 1.735s; the affected existing
  native/serde/regex selection passed in 5.898s. These checks used Java 25 and
  the pinned NetworkNT/Graal/Jackson dependencies; no unrelated Java harnesses
  were rerun locally.
- After the native/Java source freeze, the exact seven-anchor project race
  selection passed in 28.438s, including the existing real Maven lifecycle.
  Its first artifact is now inspected for exact digest and the generated
  `Greeting.class` inventory, without adding another build. The two-anchor CLI
  caller race selection passed in 1.576s. Whole-tree GoPlus generation
  consistency, affected `native/java/release/project/cli` vet, and diff checks
  passed. The command selections and evidence-reuse boundaries are versioned
  in TESTING.md; this is not a second local full-suite run.
- Specification audit clarified that general historical Java classfile ABI
  comparison is optional future work. The agreed Maven version rule remains
  the explicit schema-family-major removal policy in SPEC.md, not a generic
  Java binary-compatibility rule. RELEASE.md no longer incorrectly lists a
  classfile comparator as a release prerequisite.
- The scope audit also corrected SPEC.md's overbroad "adapters for existing
  Java types" bullet to reflect the user's later explicit clarification:
  ecosystem connections are required at the serde boundary, while unrelated
  application-owned type adaptation is deferred. This does not defer generated
  semantic models or validated Jackson/Avro integration.
- Final read-only review found a false rejection of closed generic operation
  envelopes at both native field-path resolution and OpenAPI metadata checking.
  Bounded simultaneous specialization now handles these aliases while retaining
  the direct named closed metadata-type rule. Public tests exercise nested
  query mappings, present/absent optional response headers, and directional
  records under nullable/list/generic wrappers. The coordinated affected race
  selection passed for `openapi` (1.245s) and `native` (2.246s).
- The same review added a preflight before constructing additional OAS 3.0
  mutable resource trees: 64 MiB and 65,536 aggregate JSON values. The coordinated
  selection covers one-resource and split-resource overages, the exact boundary
  and one-over. Canonical parsing retains its existing bounds; these are not
  payload limits. No separate overlapping artifact or native test run followed.
- Closed generic envelopes are newly accepted inputs, so the existing grouped
  Java direction fixture was upgraded to use them and only
  `TestGeneratedOpenAPI30DirectionAwareNativeValidation` was rerun (2.624s,
  required Java 25 plus pinned Jackson/NetworkNT/Graal). It retained all native
  exactness/direction/immutability assertions. Other Java and Maven evidence was
  reused: those generator inputs and nongeneric fixtures did not change.
- Checkpoint `db4931447712a766eeb1e1aad16156b4089d21c6` was pushed to `main`.
  Its dry-run plan selected all 25 fuzz targets because the workflow changed;
  the dry run launched no tests. CI run `34732738854` passed generation, the
  complete race suite, vet and CLI gates on both platforms. Linux Java took
  617.896s, native 158.029s and project/Maven 161.856s. macOS also completed all
  25 fuzz campaigns successfully. Linux then failed `FuzzRuntimePackageNames`
  at its ten-second fuzz deadline with only `context deadline exceeded`; no
  failing input was reported. The overall CI run is therefore failed, not green.

## Counted fuzz execution and remaining contract boundaries — in progress

- The Linux fuzz result matches the upstream Go fuzz-deadline race in
  [golang/go#75804](https://github.com/golang/go/issues/75804). Local Go 1.26.5
  still has the affected deadline/error-suppression path. The test target has
  no context/deadline logic, and the planner used plain `exec.Command`.
  No successful suite or CI job was rerun, and no error is treated as success.
- The planner now defaults to a requested 10,000-iteration campaign budget,
  retains explicit duration opt-in, rejects conflicting/zero/out-of-range
  options, and always emits a two-minute test timeout. JSON records the exact
  execution policy; stderr prints each command. The focused argument/policy
  table passed in 0.384s. One `FuzzRuntimePackageNames` campaign with
  `-fuzztime=10000x -fuzzminimizetime=1000x -timeout=2m` passed in 0.681s
  (10,030 executions including in-flight worker work). This verifies the new
  counted path, not a retroactive success for the previous CI run.
- Added checked module-level `@limits total N clause N` declarations, canonical
  formatting, and component-wise minima across explicitly declared import
  limits. Effective limits flow through Go and generated Java validation/read
  boundaries, native bundles, explanations, and versioned syntax evidence.
  Initial focused checks passed for language (0.243s), analysis (0.460s),
  explanations (0.714s), and the Java schema-limit harness (1.780s). The native
  bundle case shared the operations selection below, not a separate rerun.
- Clause diagnostics now identify statically visible `it` field projections,
  with source-order deduplication and conservative enclosing-path fallback for
  opaque helpers or bounded extraction. A compound predicate still produces
  one diagnostic. Initial language selection passed in 0.319s; generated Java
  contract and inline-refinement harnesses passed in 5.839s. Independent review
  identified runtime prefix amplification and missing legacy runtime overloads;
  those are being corrected before the shared integration gate.
- Added native operations-only OpenAPI ingestion without inventing a payload
  root or `components/schemas` entry. Original resources and URI identities are
  retained; edited predicates survive v2 bundles and refined exports. Rooted
  projects retain the v1 bundle shape. The eight-anchor native selection passed
  in 0.299s. Review fixes reran only the zero/invalid-project bundle rejection
  anchor (0.263s) and the v2 edited-authority anchor (0.232s). A v2 bundle missing
  authoritative native bindings now rejects instead of silently deriving a new
  contract from replacement source.
- Operations-only project/Maven assembly remains explicitly unsupported until
  operation-aware generated property tests are integrated. Both normal and
  `no-codegen` assembly currently reject early and emit no output; the focused
  project guard test passed in 0.368s. Native ingestion, validation and export
  support must not be confused with completed CLI/project assembly support.
- Runtime diagnostic paths now preflight the complete prefixed output against
  a one-MiB UTF-8 byte cap before concatenating strings. Go/Java use the same
  scalar-Unicode byte accounting, including supplementary characters; this
  resource bound does not change language string-length semantics. The focused
  language race anchor passed in 1.271s. A Java test-only reflection target was
  corrected from the outer runtime to its private validator; the two affected
  Java race anchors then passed in 9.966s. That final focused run overlapped
  the root integration gate because its handoff arrived late; no additional
  focused rerun followed. Future gate starts must wait for the owner's explicit
  green/frozen handoff, not merely completion of shared generation.
- Restored the legacy six-argument `Rule` constructor and all caller-only public
  runtime validation/structure/read overloads as delegates. Generated contracts
  retain schema-aware limits. The existing schema-limit harness compiles and
  executes every restored method and passed in 1.411s. Whole-tree GoPlus
  generation consistency, vet and diff checks passed before the integration
  run; the subsequent reflection correction changed only its generated test.
- The single frozen local integration command from TESTING.md passed with
  required Java 25, pinned JetCheck/Jackson/Avro/NetworkNT/Graal dependencies,
  and required Maven 3.9.16. `go test -race -timeout=20m ./...` passed every
  package: Java 210.762s, native 37.459s, project/Maven 33.407s, language 6.932s,
  and CLI 6.147s. This includes the existing Maven regeneration/reproducibility
  lifecycle and all checked-in fuzz seeds, not extra local fuzz campaigns.
  No package or Maven rerun followed the successful integration result.
- Pushed checkpoint `011f4f00f7accbbb4cd3be1ad3179fd032d8c157` to `main`.
  [CI run 34734501665](https://github.com/brain-fuel/refine/actions/runs/34734501665)
  completed successfully on both Linux and macOS, including the counted selected
  fuzz campaigns. The earlier deadline-race failure was not retried or relabeled.

## Operation project assembly and explicit extra-field rejection — validated

- Added distinct `discard`/`preserve`/`reject` JSON wire policies. Discard now
  retains permissive native acceptance instead of incorrectly lowering to a
  closed record. Alias policies follow only their occurrence; shared generic,
  recursive and anonymous nested records do not inherit an enclosing policy.
  Conflicting explicit modes fail closed. Go decoding rejects extras before
  omission; Java also rejects normal and bypass writes before emitting bytes.
- The initial ten-anchor native selection passed existing regressions but
  exposed a pre-existing backend name-classification bug: `IntBox` was treated
  as a numeric primitive. Native classification now requires the same canonical
  positive 32-bit width spelling as the language checker. New JSON/OpenAPI and
  Avro cases retain the descriptive `IntBox` name instead of avoiding the bug.
  The seven-anchor follow-up passed all but a new Avro test's incorrectly typed
  literal comparison; changing that fixture to explicit `fromInt64` conversion
  required only its single anchor to rerun (0.343s). The other six results
  remain valid (package selection 0.260s); no broad native rerun followed.
- The Java extra-field grouped harness passed in 1.743s; the existing generic
  record and metadata-conversion selection passed in 1.489s. Replacing the
  temporary enum spelling with the identical public constant did not change
  emitted Java, so those JVM results were reused after generation consistency.
- Native operation property generation and rootless project/CLI assembly are
  being integrated. Review requires clause-targeted invalid request, response,
  and context cases as well as valid cases; a valid-only suite is insufficient.
  Rootless release comparison remains explicitly unsupported until genuine
  multi-entrypoint compatibility is implemented; no empty-root comparison or
  override route pretends otherwise.
- Independent review found alias-local closure overlays could multiply a large
  record's property inventory without charging emitted entries. The lowerer now
  charges those entries before allocating each overlay and reports `native.limit`
  for resource exhaustion. Exact/one-over/aggregate cases and required-property
  preservation passed in the three-anchor native review selection (0.350s).
- Operation property review corrections passed in the grouped Java harness
  (3.029s): clause-targeted invalid requests, responses and additional context
  rules; native-invalid filtering; hard negative-generation exhaustion; and
  fixed response examples paired with a compatible valid request token. The
  generator rejects unsupported example outcomes and replay pairs explicitly.
- Final rootless project anchors passed in 0.300s. Manifests now omit both
  top-level and nested target roots for operations while retaining payload roots;
  this required `omitzero` on the value-typed selector, not ineffective struct
  `omitempty`. The same Maven fixture now includes an additional rootless API family
  in its original single artifact and four lifecycle builds.
- Whole-tree generation consistency passed. Scoped vet found one unreachable
  Go return in the new Java policy resolver; removing it and regenerating only
  Java fixed vet without changing emitted Java. Existing JVM evidence was
  reused; no runtime test was rerun for dead-code removal.
- The augmented Maven test's first build succeeded but its new inventory
  assertion expected `example.test.health` without setting that fixture's
  publication namespace. The fixture now explicitly matches the other native
  families' `example.test` namespace. Only the Maven anchor is rerun; the first
  failed test had stopped before the remaining three lifecycle invocations.
- The corrected Maven anchor passed with race detection in 24.661s, completing
  all four lifecycle builds with Java 25 and the pinned dependency directories.
  Earlier successful native, Java, CLI and project selections were reused;
  neither a full local suite nor another Maven invocation followed this result.
- Pushed checkpoint `02bb5bd48e41565dd685a86af649bf7000cb9311`.
  [CI run 34736369351](https://github.com/brain-fuel/refine/actions/runs/34736369351)
  completed successfully on Linux and macOS, including their required Java/Maven
  integration and selected counted fuzz campaigns. This terminal successful run
  is not retried.

## Operation release evidence and property completion — validated locally

- Current source review corrected stale documentation that still described
  native Avro JSON, Java `big-decimal` physical-byte serde, and the composed
  native OpenAPI facade as absent. Their implementation and focused regressions
  already exist; no runtime test was repeated for these documentation edits.
  `RELEASE-READINESS.md` separates confirmed remaining scope from historical TODOs.
- A focused anonymous generic Jackson regression reproduced reuse of an integer
  descriptor for a string specialization. The initial direct-record fix passed
  in 1.544s. Review found the same source-offset hazard in applied anonymous type
  arguments and requested aggregate-bounded structural fingerprints. That
  extension changes the fixture and implementation, so only its affected harness
  and cheap key-bound tests are selected; the first green run is not claimed as
  coverage for the later changes.
- The final JSON descriptor selection passed in 1.421s: direct anonymous and
  applied-anonymous generic specializations plus exact/one-over/aggregate/DAG
  key-work bounds. Fingerprints stream framed wire-shape structure and charge
  both node visits and text bytes; no unbounded formatted-type expansion remains
  in this key path. Generation consistency passed and the owner froze the files.
- Read-only native regex review confirmed both false rejection and false
  acceptance relative to the generated ECMA-262 Unicode matcher. Upgrading
  regexp2 alone would not establish parity. A shared-engine feasibility study
  is separate from this checkpoint; no dependency or production regex change,
  repeated JVM gate, or regex fuzz campaign was made for that audit.
- The reviewed operation example/replay harness passed in 6.273s. It captures
  real minimized JetCheck data for both request values and request/response
  pairs, regenerates the same strategies with those values, and executes their
  `rechecking` paths. It also verifies invalid, exact-indeterminate and actual
  native-invalid examples, exact context envelopes, selector ambiguity rejection
  and hard invalid-generation exhaustion. Deliberate language-indeterminate
  examples use non-ASCII values outside the random text distribution, so random
  properties do not rely on a lucky seed avoiding those values. Native/resource
  failures remain fatal. Shared Java generation is consistent and frozen; the
  descriptor harness was not repeated.
- Rootless release comparison now uses the actual operation catalog. Requests
  and responses have opposite inclusion directions; effective status selection
  honors exact/class/default precedence. Changed relational contracts stay
  unknown unless supported identity evidence applies; marginal counterexamples
  do not falsely prove a request-response break. Native-wire and Java ABI
  evidence remain separate unknowns, subject to existing exact persisted policy.
  Initial/unchanged/all-baseline planning and verbatim promotion are supported.
- The initial release selection passed CLI in 2.440s, with one analysis alias
  fixture subsequently corrected and rerun alone (0.181s). Review then removed
  repeated module snapshots and restored initial payload-root validation that
  had been lost when removing the rootless guard. The five-anchor correction
  selection passed analysis in 0.436s and CLI in 0.896s. Final generic-context
  review replaced formatted/substituted expanding types with lazy bounded
  environments and explicitly framed operation/response counts. Only
  `TestCompareOperationsKeepsChangedRelationalContextUnknown` and
  `TestOperationContextResolutionBoundsGenericDAGWork` reran (0.188s); other
  successful CLI evidence was reused.
- Whole-tree generation consistency passed. Scoped vet identified an unreachable
  Go return after the descriptor helper's exhaustive match. Removing the return
  and regenerating Java fixed that scoped vet check without changing generated
  Java; no JVM test was repeated. The two changed rootless project callers then
  passed in 0.354s. This batch adds no local full-suite, Maven lifecycle or fuzz
  repeat; CI supplies the distinct cross-platform integration gate.
- Pushed checkpoint `ce77cf826aeaf56e166a747aa4a421aa5c11a34e`.
  [CI run 34737539642](https://github.com/brain-fuel/refine/actions/runs/34737539642)
  remained queued at the next checkpoint review; it was not restarted or
  represented as successful.

## Portable release authority and empty OpenAPI envelopes — validated locally

- Zero-native-part Java operation properties now use exact transport-first
  singleton envelopes decoded by the real generated codec. Required unmapped
  edited fields reject; optional fields remain `Nothing`. The grouped operation
  harness passed in 9.305s, covering request tokens, response validation,
  serialized singleton replay and rejection of extra parameters/headers/body.
  Native schema traversal yields no invented schema locations for a checked
  zero-part catalog. Scoped generation consistency and vet passed. Root review
  then requested bounded lazy type resolution for this new audit path; that
  Go-only correction has its own focused test and does not justify repeating
  the unchanged emitted-Java harness.
- The envelope audit's aggregate-work/DAG anchor passed in 0.268s. Root review
  then caught false cycle detection for finite repeated `Id` specializations.
  The corrected anchor also exercises `Id (Id record)` and
  `Id (Id (Maybe Int))`, and passed in 0.272s. Only that Go anchor reran;
  generated Java text was unchanged and its prior JVM result was reused.
- The language release-policy frontend adds strict, bounded version-1 metadata
  and an EOF-only footer with exact owned LF delimiters. Lexical recognition
  prevents comments from acquiring authority. Parsing retains the original
  source and every contract span; formatting and import flattening keep only
  entry-file authority. The four new `TestReleasePolicy...` anchors passed in
  0.323s, including strict keys, duplicate records, Unicode, byte restoration,
  immutable accessors, malformed footer placement and import noninheritance.
  Native-carrier and release-planner integration are a separate pending gate.
- Existing import/limit callers and `FuzzParseFormat` seeds passed in 0.270s.
  One additional parser campaign selected exactly `FuzzParseFormat`, requested
  1,000 iterations, and completed 1,030 executions in 0.326s with no failure
  (parallel workers finish in-flight cases). The target and budgets are explicit;
  generated fuzz inputs and wall-clock timing are not claimed deterministic.
- An isolated QuickJS-NG WASM prototype ran the same guest in Go/wazero and
  Java/Chicory, with identical Unicode/syntax vectors, interruption and recovery.
  It changes no repository dependency or production matcher. Edition-locked
  syntax, bounded compilation and failure classification must be established
  before considering a production replacement; prototype success is not regex
  conformance evidence for the current product.
- Native bundle authority and CLI integration are green: the selected carrier
  anchor passed in 0.254s and eleven planner/promotion/identity anchors passed
  in 2.505s. Review fixes reject case-folded carrier keys and empty append
  targets, preserve strict parsed authority, and keep stale approval hashes
  attached when testing changed contract bytes. The first migration selection
  exposed an overbroad native-project footer rejection and fixtures that removed
  mandatory policy; those failures were corrected within this scope. Generation
  consistency for native/analysis/CLI and the diff check passed. No Java or Maven
  harness was run by the release-policy owner.
- Root's payload/operation syntax-identity anchor passed in 0.253s. Whole-tree
  generation consistency, `go vet ./...`, and `git diff --check` passed. After
  freezing all source, one `go test -race -timeout=20m ./... -skip
  '^TestMavenRegenerationAndReproducibleArtifact$'` integration gate passed with
  Java 25 and every pinned Java dependency directory required. The Java package
  took 241.253s; native took 36.373s; all other packages passed. The shared
  parser/AST change warranted this one consumer-wide gate. The unchanged Maven
  lifecycle reused its earlier 24.661s result; no second Maven invocation or
  integration retry followed. The earlier `ce77cf8` CI run remained queued and
  is not represented as green.
- Pushed `443e36c7306e8b5a4b9dac8309283b36bb1a510b`.
  [CI run 34739135690](https://github.com/brain-fuel/refine/actions/runs/34739135690)
  completed successfully on both Linux and macOS, including their required
  integration and selected fuzz gates. That terminal run is not retried.
  The earlier `ce77cf8` run 34737539642 subsequently completed successfully too;
  neither terminal run needs further polling or reruns.

## Standalone OpenAPI authoring and shared native regex — in progress

- The language frontend accepts a contextual `openapi` declaration alongside
  ordinary request/response/context types. Existing functions named `openapi`
  or `operation` remain valid. Compilation checks closed named entrypoint types;
  native assembly separately checks protocol, envelope paths and wire semantics.
  Presence can be inferred or explicitly written `required`/`optional`.
- The three new declaration anchors passed in 0.504s. They cover stable
  parse/format, detached nested metadata, malformed syntax/types/limits,
  unchanged positions with a release footer, and entry-only API ownership across
  imports. Existing footer/import/limit callers and parser seeds passed in
  0.300s. One `FuzzParseFormat` campaign requested and completed 1,000 iterations
  in 0.296s, seeded with a complete authored API; no campaign was repeated.
- Native complete-document assembly and project/CLI normalization are being
  connected to this frontend. Source `.refine` bytes and imports remain release
  authority; a generated rootless native project is an execution view, not a
  substitute versioned source or an invented payload root.
- The production shared regex core is being implemented separately from the
  successful isolated prototype. Its intended Go/Java switch is atomic; current
  native matcher parity is not claimed until both hosts and consumers pass.
- Native standalone assembly now produces an operation-only document with exact
  source authority, inferred presence, explicit response-presence gotchas and a
  bounded lazy checked-type resolver. Its final lowering/budget selection passed
  in 0.333s; unchanged authority/error anchors reuse their earlier 0.278s result.
  Project normalization passed its two anchors in 0.315s; four CLI discovery,
  planning and exact-import promotion anchors passed in 0.671s. The standalone
  operation syntax-change anchor passed in 0.301s. These are scoped Go results,
  not yet a claim about the generated JVM facade.
- CI's native-regex provisioning now selects the two pinned Chicory 1.7.5 JARs
  for the pending shared-runtime switch. YAML parsing and `bash -n` of the
  changed provisioning step passed; this workflow-only check did not launch
  another Java or Maven test. The final paired-runtime gate remains pending.
- Review invalidated a reported 0.456s standalone Java result: it had skipped
  without required runtime settings. The single actual required-runtime anchor,
  `TestGeneratedStandaloneOpenAPIAuthoringFacadeAndProperties`, then failed in
  2.351s with targeted-invalid request generation exhaustion. Native lowering
  rejects the invalid body before the facade emits a Refine diagnostic. A second
  identified issue rejects reused refinement clauses as ambiguous property
  selectors even when no replay is supplied. Both are implementation failures
  to correct, not reasons to waive mandatory properties or repeat the full
  integration suite. The skipped run is not reused as evidence.
- Exact Draft 2020-12 `const`/`enum` provenance and structural inverse lowering
  passed seven focused anchors: provenance 0.272s, native 0.334s. The cases cover
  rational equality, unordered objects, ordered arrays, non-normalized strings,
  empty/duplicate enum recommendations, independent edit/removal, and builtin
  shadow protection. Oversized projections remain opaque rather than weakening
  native enforcement. Generated-source consistency passed. No unrelated
  Java/Maven or whole-suite test was run for this slice.
- Native source composition now inserts generated root aliases and operation
  declarations before the exact existing release footer. It leaves approval
  hashes unchanged and never promotes embedded source metadata into outer
  native-bundle authority. Six focused ingestion/derivation anchors passed in
  0.425s, including all three formats, both single/explicit-resource entrypoints,
  unchanged import bytes, bundle reload, malformed footer rejection and source
  bounds. This source-composition fix did not rerun the JVM or Maven.
- The corrected standalone Java anchor executed with required Java 25,
  JetCheck and NetworkNT dependencies and passed in 2.06s (package 2.380s).
  It uses the same explicit-code refinement in both a request parameter and
  body, proves targeted logical failure separately from real native-first
  rejection, and checks explicit occurrence replay selection. Subsequent review
  identified further automatic-code context-inheritance and repeated predicate
  identity cases; this focused result does not cover those pending corrections.
- The final automatic-code/map/list correction passed the required-Java
  `TestGeneratedStandaloneOpenAPIAuthoringFacadeAndProperties` anchor in 2.31s
  (package 2.754s). The affected
  `TestGeneratedProjectOpenAPIPropertiesExerciseEveryBinding` anchor passed in
  166.83s (package 167.261s), with Java 25 and checksum-verified JetCheck,
  NetworkNT and Chicory dependencies. Together these cover concrete collection
  paths, context inheritance, repeated-code occurrence selectors, legacy replay
  ambiguity rejection and real native-first rejection. These successful JVM
  results are retained for unchanged inputs, not repeated for documentation.

## Approved website publication — 2026-09-19

- Explicit user approval authorized the sibling `brain-fuel/dev.goforge` push.
  Normal and minified production Hugo/vanity checks passed (2 tests, no skips);
  the shared stylesheet rebuild produced no diff. Commit
  `8537d17eb9e68f54696f5653b95faa6cbc1bc023` was pushed to `main`, leaving that
  worktree clean.
- The live `/refine/?go-get=1` page now serves the new template and correct
  `goforge.dev/refine` import metadata. Deployed `css/refine.css` and
  `images/refine-social.png` bytes match the committed SHA-256 hashes. GitHub's
  status API was inaccessible to the integration; deployment confirmation came
  from the live output, not an inferred CI result. The page remains explicitly
  unreleased and pins its previously tested development checkpoint.

## Shared-runtime and native-provenance integration — 2026-09-19

- Rechecked `go list -m -json goforge.dev/goplus@latest`: the latest published
  module remains `v0.158.0`, matching the tool pin. Local integration uses
  Go 1.26.5 and Java 25.0.4.1.
- Review found and corrected two shared-regex lifecycle defects: Go initialized
  its first-match deadline before acquiring request ownership, and generated
  Java could retain its scope lock when request initialization failed. The Go
  nil/concurrent-first-match race anchor passed in 5.373s. The required-Java
  regex anchor covers acquired-lock/open failure and subsequent cross-thread
  recovery in addition to its existing adversarial cases. Its final completed
  result is reused; no property-catalog JVM was repeated for these fixes.
- Native regex/origin-adapter selection passed in 5.847s. The later lazy-scope
  correction passed its regex pair in 2.152s, affected syntax/map callers in
  1.720s, and bounded queue/recovery anchor in 0.297s. Conditional generated
  resource/Maven dependency checks passed in 4.151s. These focused checks do not
  replace the changed Maven lifecycle and coherent integration gate.
- Exact array-item and object-property count adapters now discover
  `minItems`, `maxItems`, `minProperties`, and `maxProperties`. Two JSON
  provenance anchors passed in 0.246s; the OpenAPI JSON/YAML token anchor passed
  in 0.541s. Native inverse lowering, independent scoped edits, bundle/export,
  old-project immutability, and builtin-shadow protection passed four selected
  anchors in 0.444s. String length is deliberately excluded because native
  code-point counts differ from refinement UTF-16 counts.
- An affected existing schema-position test still expected six constraints
  after `const` became a supported seventh unit. The corrected test asserts the
  entire `const` is one value and its contents are never traversed as schemas;
  that single test passed in 0.419s. The unchanged numeric canonical-form and
  deviation-isolation checks passed in the preceding selection. This was an
  outdated expectation, not a change to native semantics.
- The same lowering review found that a user-defined `isInteger` could acquire
  the builtin's `multipleOf` export authority. Lowering now rejects that false
  correspondence (or explicitly explains its loss), with the existing builtin
  multiple-of regression retained in the four-test selection above.
- The first whole-tree generation/vet attempt exposed the guest's standalone
  `embed_source.go` build helper as an ordinary Go package containing C files.
  The helper now has `//go:build ignore` (its explicit `go run` build-script
  invocation remains available). Whole-tree generation consistency and vet then
  passed. No runtime test was launched for the initial packaging error.
- Cardinality review found attempted bigint work was charged only for projected
  clauses and OpenAPI reset that meter per Schema Object. Work is now charged
  before materialization and shared across OpenAPI count discovery. The new
  aggregate/nonprojectable-work anchor passed in 0.301s; exhausted valid clauses
  stay opaque rather than weakening native validation.
- Started the coherent required-Java/Maven race gate with JSON evidence at
  `/tmp/refine-integration-20260919.jFDS4A`. The non-Markdown tracked/untracked
  input inventory was 765 files, framed SHA-256
  `9a5ad82e24f805e8a35d7bebe055fce6c9c81eebee9146da9994929b934f7f67`.
  Native completed successfully in 492.582s; the Java package was still running
  when the following measured regression was investigated.
- Maven's first lifecycle build spent over ten minutes in repeated fresh guest
  initialization (the previous complete lifecycle had taken about 25 seconds).
  Its verified test-only JVM was intentionally stopped; the Maven test reports
  failure after 651.88s and the project package after 719.986s. This is an
  incomplete verification, not an assertion failure or passing Maven evidence.
  Other package checks were left running. A separate lifecycle correction is
  now adding bounded reuse of clean initialized sessions, with fresh budgets
  and no compiled handles retained across requests. It does not reduce property
  case counts or relax validation limits.
- The remaining required-runtime race gate completed: Java passed in 859.254s,
  including the operation property catalog in 294.86s. Every package with tests
  passed except the intentionally interrupted Maven-containing project package;
  there were no test-level skips. The only package-level skips were the two
  packages without tests. This establishes old-runtime correctness evidence,
  not verification of the subsequent session-reuse changes.
- Registered the checked regex artifact/guest inputs with their production
  owner in the deterministic fuzz planner. Guest-only changes now follow the
  runtime's reverse imports instead of selecting unrelated campaigns; embedded
  NOTICE/license inputs are included and absent/unknown ownership remains
  fail-closed. The exact selection
  `^(TestSelectionScopesCheckedRegexGuestAndEmbeddedNotice|TestSelectionDocumentsBuildMetadataFixturesAndUnknowns|TestSelectionKeepsMarkdownFixturesAndUnknownConsumers|TestSelectionFollowsProductionAndBothTestImportKinds|TestSelectionIsStableUnderInputAndPackagePermutation)$`
  passed in `internal/testplan` in 0.239s after package generation.
- Added exact Avro provenance for fixed sizes and atomic ordered enum symbols,
  with source audit/recovery and a separate structural edited-unit inverse.
  Review hardened keyword-derived builtin/scope guards against mutable public
  descriptions and bounded aggregate attempted numeric expansion. The final
  four-anchor core selection passed in 0.326s; generation/diff checks passed.
  Native effective-resource integration is a separate subsequent step, not
  implied by these core tests.
- Shared regex lifecycle now has a frozen ABI 2 guest: 1,202,261 bytes, SHA-256
  `ee1ff0212d3a3bd28a72f00033f51dad747c8b36e9302edbbbd35cf6a58bfe8f`.
  A fixed trusted Unicode warmup stays within initialization budgets. Reset
  frees handles and checks the allocation watermark; uncertified but clean
  sessions use a nonfault discard status, while pending exceptions remain
  internal failures. Go reuses at most four initialized sessions, never compiled
  handles, and charges only actual blocking acquisition to compilation time.
  Fresh request budgets and timeout/cancel/trap/resource disposal passed the
  exact race selection
  `^(TestCheckedArtifactInventoryAndLimits|TestUTF16ECMA262SyntaxHandlesAndTypedFailures|TestRequestBudgetsBoundCompilationMatchingAndHandles|TestTrustedInitializationAndTrapFailuresFailClosed|TestFirstMatchDeadlineIsSerializedAndNilSafe|TestSessionsReuseOnlyAfterCleanBoundedReset)$`
  in 44.649s. Package generation consistency and scoped diff checks passed.
  OOM poisoning was tested through the zero-allocation-result boundary; this
  selection did not force an actual 32 MiB guest OOM. Java and native-consumer
  verification follow separately.
- The required Java regex lifecycle/adversarial anchor passed in 29.52s
  (package 29.954s) with Java 25, pinned NetworkNT and Chicory jars. Its owner
  checks require both the current thread and the held scope lock. Native's
  Unicode/lookaround/backreference, timeout and queue/recovery caller trio
  passed under race detection in 13.281s. Conditional project resource
  packaging passed in 1.313s; Java conditional emission passed in 0.46s.
- The affected real Java Avro enum/fixed harness passed in 2.91s and asserts
  effective symbol order and fixed width before binary/JSON round trips.
  The regex serde-limit harness initially failed setup because the coordinating
  command omitted `REFINE_NETWORKNT_DIR`; only that failed selector was rerun
  with pinned NetworkNT/Chicory inputs and passed in 7.23s (package 7.721s).
  Neither the successful Avro nor conditional-emission check was repeated.
- The required operation-property catalog passed in 32.61s (package 33.061s)
  on the new lifecycle, retaining its case counts. The earlier full race gate
  recorded 294.86s for that test; the runs are cycle-time observations under
  different surrounding workloads, not a controlled benchmark. Whole-tree
  generation consistency, vet and diff checks also passed before the remaining
  annotated-Avro atomic-edit follow-up.
- Avro effective-resource integration passed its three new runtime/export/
  bundle/immutability anchors in 0.369s and 21 selected existing Avro/native
  callers under race detection in 43.805s. Native originals remain unchanged;
  the effective view is revalidated and cached only on the new immutable
  project. Review found that annotated source with separate units could not
  atomically change both enum representations. The new
  `WithEditedSourceAndNativeConstraintSources` transition and atomic version-1
  bundle restoration close that gap: its new anchor passed in 0.491s and six
  existing bundle callers passed under race detection in 1.578s. The unchanged
  successful Java serde harness was not repeated.
- Final source generation, vet and diff checks passed after that atomic-edit
  follow-up. The one interrupted unsigned Maven lifecycle check is now rerunning
  against the coherent source/artifact state, with evidence at
  `/tmp/refine-maven-lifecycle-20260919.1inEL6`. No other whole-package or JVM
  campaign is being repeated during that check.
- The rerun progressed through its first three successful Maven builds. A
  bounded 24-validation probe against the existing generated classes confirmed
  one reused Java regex session and zero discards, with approximately 47–51 ms
  per native validation. Parsing alone was approximately 0.0017 ms per input.
  The default printable-ASCII generator accepts `^[a-z]+$` only about 1.51% of
  the time, explaining roughly five minutes per 100-case target through rejection
  sampling and fresh per-request pattern compilation. A native-aware candidate
  strategy is being implemented separately; no cases or validation boundaries
  have been removed from the running lifecycle gate.
- The Maven harness now logs its four phases and shares one child-process
  context ending five seconds before the Go package deadline. Future timeouts
  can terminate the Maven JVM before Go's alarm abandons it. Project generation
  and `go vet ./project` passed for this harness-only change; the already-running
  test uses its original binary and is not evidence for the context change.
- That Maven rerun reached the fourth, expected-exhaustion build but hit Go's
  20-minute deadline (package 1200.483s). The preceding three phases passed;
  the lifecycle gate as a whole failed by timeout and is not green. The exact
  JVM and test PIDs were absent afterward. Only this failed gate will rerun
  after the native-string generator optimization passes its focused checks.
- Native-root string candidate specialization is now implemented for the narrow
  anchored ASCII class/repetition grammar documented in GENERATED-TESTS. Its
  grammar/bounds and source-boundary selectors
  `^(TestNativeRootStringPropertyStrategyIsExactAndBounded|TestGeneratedNativeRootStringPropertyStrategyPreservesValidation)$`
  passed in 0.977s. The required-Java
  `^TestGeneratedNativeRootStringPropertyStrategyExecutesBoundaries$` passed in
  7.314s with eight required cases and eight attempts per case, including actual
  native/Refine validation and model/canonical/Jackson boundaries. Java/project
  generation consistency and owned-file diff checks passed. Standalone and
  complex-pattern strategies retain their existing bounded fallback.
- The JSON Schema keyword scan now uses the same physical/logical resource
  catalog as projection and sorts its output deterministically. Its two new
  canonical-ID/anchor and nested-resource-pointer tests first exposed missing
  oracle logical-ID loading and stale single-resource projection wiring; after
  those corrections, their exact two-test selection passed in 0.527s. Review
  also found that the oracle's default loader can read files. Explicit rejecting
  or in-memory-only loaders and filesystem-fallback regressions are being added;
  absence of a custom loader is not an offline guarantee.
- Explicit offline loading regressions passed in 0.250s:
  `^(TestNativeJSONCompilersNeverFallBackToFilesystem|TestJSONProjectUsesExplicitFileURIResourceWithoutReadingFile)$`.
  The temporary filesystem fixture deliberately disagrees with the supplied
  in-memory schema, proving that explicit content wins and a missing resource
  cannot fall back to the file. The affected existing caller selection
  `^(TestValidatedLosslessIngestion|TestStrictStructureVersionsAndOfflineRefs|TestOpenAPI31ExactJSONSchemaPayloadValidation|TestOpenAPIExactYAMLNumbersAndExternalResources|TestRootlessOpenAPIOperationsIngestAndBoundary)$`
  passed under race detection in 4.595s. This check did not repeat the full
  native, Java, or Maven suites.
- A new required-Java two-resource regression confirmed that the old generated
  loader could not resolve external canonical or nested `$id` identities even
  when Go validation succeeded. The corrected loader consumes the project's
  sorted, normalized offline alias inventory. The exact
  `^TestGeneratedNativeJSONValidatorLoadsCanonicalNestedIDsOffline$` anchor
  passed in 0.910s. Its JVM was not repeated for subsequent pure limit tests:
  `^TestNativeJSONCanonicalAliasEmissionIsBounded$` passed in 0.967s and checks
  exact/one-over combined physical-plus-alias resource and byte limits.
  Java generation consistency and scoped diff checks passed.
- External JSON Schema projection now shares an explicit-resource catalog with
  ingestion, payload validation and keyword scans. It supports recursive
  external references, canonical `$id`, static anchors and nested JSON Pointers.
  Review corrections retain existing sibling `$defs` names/metadata and the
  configured public name for a selected external root, and bound repeated
  physical-path storage before map-key allocation. Six new tests passed in
  0.298s:
  `^(TestJSONProjectionResolvesNestedExternalRecursiveReferences|TestJSONProjectionResolvesCanonicalNestedIDAnchorAndPointer|TestJSONProjectionNamesExternalCollisionsDeterministically|TestJSONProjectionCatalogRejectsAmbiguousAndNonSchemaTargets|TestJSONProjectionSelectedDefinitionRetainsSiblingLocalNameAndMetadata|TestJSONProjectionCatalogPreflightsRetainedLocationAmplification)$`.
  The exact affected existing-caller selection passed under race detection in
  4.646s:
  `^(TestJSONSchemaProjectEditBundleAndNativeEnforcement|TestApplicatorConstraintIsNotHoisted|TestLocalReferencesBecomeNamedRecursiveDeclarations|TestExplicitJSONSchemaResourceResolutionAndBundle|TestExternalJSONSchemaProvenanceRemainsResourceScoped|TestNativeConstraintUnitSourcesAreExplicitScopedAndBundled|TestResourceAndBundleFailuresAreExplicit|TestDecodeAndValidateJSONComposesNativeExactAndRefined|TestJSONCarrierDecoderPreservesNativeKindsAndPreflights|TestJSONTypedMapProjectionAndCheckedDecodePreserveNativeSchema|TestJSONMapProjectionUsesCarrierForHeterogeneousOrOpenValueDomains|TestJSONOrdinaryExtraFieldPoliciesRemainProjectable|TestJSONCarrierProjectionRetainsNativeApplicatorAndTupleAuthority|TestJSONCarrierReferenceSiblingsPreserveDeclaredMembers|TestProjectExportComposesEffectiveNativeAndEditableJSONSchema)$`.
  Alias inventories normalize only loader copies, preserve original resources,
  and use a conservative pre-materialization byte bound. OpenAPI's separate
  general-reference projection remains a subsequent task.
- OpenAPI 3.0 bounds now preserve numeric/exclusivity tokens as atomic
  provenance pairs. Edited strictness and values rebuild effective resources;
  untouched opposite bounds and OpenAPI 3.1/JSON Schema fingerprints retain
  their identity. Exact terminating literal fractions lower without floating
  point; nonterminating fractions and arbitrary arithmetic fail closed.
  Reference Object siblings are ignored consistently by the native oracle,
  3.0 adapter and provenance discovery. The selection
  `go test -count=1 ./provenance ./native -run '^(TestOpenAPI30.*|TestOpenAPIProvenanceRejectsAmbiguousAuthorityAndBounds|TestOpenAPIProvenanceIdentityFramesResourceAndPointer|TestOpenAPIProvenanceJSONEditsValidationExportBundleAndImmutability)$'`
  passed (provenance 0.485s, native 0.436s). After the final resource-catalog
  parity hook, only
  `^TestOpenAPI30ReferenceSiblingBoundIsIgnoredWithoutEditableAuthority$`
  was rerun and passed in 0.365s, covering direct and explicit-resource ingestion.
- Final coordinated generation, whole-tree `goplus gen --check`, `go vet`, and
  diff checks passed. The optimized Maven lifecycle runs against staged source
  tree `b4a3877e65c827689682705c5662e7b27d9f3d06`; only documentation changed
  afterward. Its log is `/tmp/refine-maven-optimized-20260919.LL3fhd`.
- The optimized Maven lifecycle passed all four phases in 72.26s (package
  72.556s): unsigned artifact build/inventory, byte-for-byte reproducibility,
  automatic regeneration after an edit, and expected failure on exhausted
  generated properties. It retained the default 100 cases and all validation
  boundaries. No previously green broad Java or native campaign was repeated.

## Checkpoint CI and native ingestion follow-up (2026-09-19)

- Checkpoint `954567975f664ceac4571c34ddba4521470dba4b` was pushed. CI run
  [35451073697](https://github.com/brain-fuel/refine/actions/runs/35451073697)
  passed source generation on Linux and macOS. Java passed in 599.705s and
  608.302s respectively; the project package, including required Maven, passed
  in 249.353s and 276.989s. The run was **not green**: Go regex session reuse
  failed on both platforms, Ubuntu also hit two trusted-initialization
  failures, and four native tests hit initialization failures on macOS.
  Subsequent vet/CLI/fuzz steps were skipped, not passed.
- The Go host forced Wazero's instruction-by-instruction interpreter, exposing
  trusted guest initialization to race-instrumented overhead. It now uses the
  pinned runtime's auto-selected compiler with interpreter fallback. The guest
  bytes, imports, memory ceiling, wall-clock and polling limits, request
  accounting, cancellation and disposal rules are unchanged. No ceiling was
  raised and no failure was retried automatically. Compiler host-code memory
  and the scope of race instrumentation are documented in NATIVE.md.
- The changed backend's exact regression selection passed in 21.622s:
  `go test -v -race -timeout=3m ./internal/ecmaregex -run '^(TestCheckedArtifactInventoryAndLimits|TestUTF16ECMA262SyntaxHandlesAndTypedFailures|TestRequestBudgetsBoundCompilationMatchingAndHandles|TestSessionsReuseOnlyAfterCleanBoundedReset|TestTrustedInitializationAndTrapFailuresFailClosed|TestStringConveniencesPreflightUTF16Units|TestFirstMatchDeadlineIsSerializedAndNilSafe)$'`.
  This covers all seven current backend tests, including the previously failing
  initialization/reuse paths. It does not newly exercise interpreter fallback
  on a compiler-capable host or cancellation during an active native-code call.
- The affected native caller selection, including all four macOS failures and
  shared singleton initialization, passed in 4.416s:
  `go test -v -race -timeout=3m ./native -run '^(TestExplicitScalarWireEncodings|TestCheckedECMA262GuestSupportsUnicodeLookaroundAndBackreferences|TestJSONSchemaKeywordLocationsUseCanonicalReferencesAndStablePhysicalLocations|TestJSONSchemaKeywordLocationsResolveNestedResourcePointerScopes|TestRegexpTimeoutNeverBecomesBooleanResult|TestRegexScopeQueueAcquisitionIsBoundedAndRecovers|TestNativeECMAPatternSyntax)$'`.
  Java's Chicory backend and the Maven generator were unchanged by this fix;
  their successful checkpoint evidence was reused, not rerun locally.
- JSON Schema dynamic references now project to the intrinsic JSON carrier at
  the affected occurrence. Native dynamic and sibling assertions remain
  authoritative; no static target is invented. The exact selection
  `go test ./native -run '^(TestJSONProjectionCatalogRejectsAmbiguousAndNonSchemaTargets|TestJSONDynamicReferenceCarrierPreservesNativeFirstValidationAndExport|TestJSONDynamicReferenceCanonicalScopesRemainNativeAuthority)$'`
  passed in 0.545s, covering ordinary/refined export/reingestion and canonical
  nested-ID dynamic-scope overrides. This no-regex fixture evidence preceded the
  Go backend correction and remains applicable to the projection contract.
- Required Java 25 regression
  `REFINE_REQUIRE_JAVA=1 go test -v ./java -run '^TestGeneratedDynamicJSONCarrierPreservesNativeFirstBoundaries$'`
  passed in 2.022s with the existing pinned NetworkNT dependencies. One grouped
  compilation/execution checked native and refinement rejection on reads,
  staged writes with zero output on failure, and a canonical nested-ID dynamic
  override that differs from static anchor lookup. No prior green Java tests
  were repeated for this slice.
- Project ingestion now audits executable JSON Schema/Avro annotations in all
  explicit resources. Only the selected explicit-root annotation is consumed;
  source-only roots, nested/competing annotations and dependency annotations
  reject instead of being silently ignored. Parse APIs remain inspection and
  type-checking boundaries. Both JSON inventories include the same legacy
  `definitions`/`additionalItems` positions as the projection catalog.
  Aggregate schema-position and pre-concatenation retained-path bounds prevent
  per-resource budget resets and long-ancestor path amplification.
- Initial four-test annotation selection passed in 0.275s after correcting an
  ill-typed test fixture, not production behavior:
  `go test ./native -run '^(TestProjectRejectsUnconsumedJSONSchemaAnnotationsAcrossResources|TestProjectRejectsUnconsumedAvroAnnotationsAcrossResources|TestProjectAnnotationAuditHasAggregateSchemaPositionBound|TestOrdinaryProjectExportErasesOnlyRefineSchemaAnnotations)$'`.
  Review added missing source-only, malformed-dependency and competing-root
  cases plus the retained-path guard. Only the two expanded tests and new
  path-bound test were run again:
  `go test ./native -run '^(TestProjectRejectsUnconsumedJSONSchemaAnnotationsAcrossResources|TestProjectRejectsUnconsumedAvroAnnotationsAcrossResources|TestProjectAnnotationAuditBoundsRetainedPathAmplification)$'`
  passed in 0.327s. The unchanged aggregate/ordinary tests' passes were reused.
  Edited packages' generation consistency, vet and diff checks passed.
- Checkpoint `44d8e0a2d64d167900bb93e6cadc4f72796711eb` was pushed. CI run
  [35452304602](https://github.com/brain-fuel/refine/actions/runs/35452304602)
  confirms the changed Go regex backend passes on both platforms (65.656s
  macOS, 86.566s Linux). Java and required Maven also pass on both platforms.
  Its sole reported failing test is
  `TestLowerRecursiveGenericAvroDefinesBeforeReference`: the annotation selector
  incorrectly excludes a checked closed expression such as `Node Int32` because
  it expects a simple name. This is not a source-only annotation and must not be
  fixed by weakening unconsumed-annotation rejection. The selector correction
  now accepts the already type-checked closed root expression. The exact
  `go test ./native -run '^(TestGenericAnnotationRootExpressionsComposeAndEnforceAcrossFormats|TestGenericAnnotationRootExpressionsMustBeClosed|TestLowerRecursiveGenericAvroDefinesBeforeReference|TestNativeAnnotationRootAliasesPreserveReleaseFooter)$'`
  selection passed in 0.432s. It covers JSON Schema, Avro and OpenAPI, single and
  bundled resources, native-first rejection and open-generic rejection. No
  Java/Maven rerun was needed locally for this selector correction.
- Additional existing annotation callers passed in 0.398s:
  `go test ./native -run '^(TestNativeAnnotationRootAliasesPreserveReleaseFooter|TestRootAnnotationSeedsEditableSourceWithoutChangingSelector|TestProjectRefinedExportSupportsOpenAPI30AndAvroWithoutReplacingNative)$'`.
  These cover ordinary named roots; they did not cover the closed generic root
  expression subsequently exposed by CI.
- Exact `uniqueItems: true` correspondence is implemented for explicit singleton
  array domains as a detached `[JSON] where unique it` unit. It is deliberately
  not imposed on arbitrary projected typed arrays whose decoding can discard
  information. The original keyword remains native authority. Exact token
  recovery, builtin shadowing, constrained inverse/removal, and unaffected
  sibling units are covered by
  `go test ./provenance -run '^(TestUniqueItemsIntrinsicJSONMatchesNativeEquality|TestUniqueItemsProjectionIsExplicitDetachedAndShadowAware|TestOpenAPIUniqueItemsPreservesExactTrueAndNullableBoundary)$'`
  (0.196s) and
  `go test ./native -run '^(TestUniqueItemsLowersOnlyDetachedIntrinsicJSON|TestUniqueItemsDetachedEditRemovalIsAtomicAndIsolated)$'`
  (0.270s). The required-Java
  `TestGeneratedIntrinsicJSONUniqueMatchesJSONSchemaEquality` anchor passed in
  2.540s after correcting a test-only assertion about detached source units.
- OpenAPI graph foundation, not yet general end-to-end ingestion support:
  `provenance.IndexOpenAPISchemaRoots` reuses the wrapper walker to identify
  physical Schema Object roots and inherited dialects without interpreting
  schema references or examples as wrapper structure. Its four exact
  `TestOpenAPISchemaRootIndex{CoversWrapperRoles,ResolvesOnlyWrapperReferences,LeavesSchemaReferencesOpaque,KeepsWrapperFailuresAndBounds}`
  tests passed in 0.170s. The native OpenAPI catalog shares JSON indexing and
  resolution, adds physical-fragment closure before logical-ID resolution, and
  preserves inherited dialects in normalized loader copies. Both static and
  dynamic anchors can be ordinary static reference targets.
- Four new native catalog/anchor tests passed in the first focused selection:
  `TestOpenAPICatalogIndexesPhysicalClosureBeforeLogicalReferences`,
  `TestOpenAPICatalogKeepsSchemaAnchorsSeparateFromExamples`,
  `TestOpenAPICatalogRejectsAmbiguousMissingAndNonSchemaTargets`, and
  `TestJSONCatalogResolvesDynamicAnchorsAsStaticReferenceTargets`.
  The fifth fixture initially hit upstream YAML key and syntax-depth limits
  before the intended retained-path guard. After replacing it with a shallow,
  wide schema, only
  `go test -v ./native -run '^TestOpenAPICatalogRetainedPathFailureCannotBecomePartialSuccess$'`
  was rerun and passed in 0.324s. No production correction was needed for those
  fixture failures. The six existing JSON external-reference/catalog anchors
  passed in 0.549s after the shared catalog extraction.
- Catalog review found that repeated physical schema positions could silently
  retain the first inherited base URI or dialect. Repeated indexing now compares
  effective contexts after applying the node's own `$id` and `$schema`: local
  convergence is accepted and ambiguity fails closed. The four affected
  catalog/anchor tests above plus
  `TestOpenAPICatalogRejectsConflictingContextsButAcceptsLocalConvergence`
  passed in 0.360s. The unchanged retained-path fixture was not repeated.
  Final `go tool goplus gen --check ./provenance ./native ./java`,
  `go vet ./provenance ./native ./java`, and `git diff --check` passed for this
  checkpoint. No unrelated JVM or Maven lifecycle was rerun.
- Checkpoint `61b21cd362c91a503d9e1565fb56c327ab410cb3` was pushed; its
  [CI run](https://github.com/brain-fuel/refine/actions/runs/35453768722)
  passed both Linux and macOS jobs, including generation consistency, the
  required Java/Maven integration suite, vet, CLI checks and selected fuzz
  targets. This is a green development checkpoint, not a completed release.
- OpenAPI 3.0 now discovers exact collection cardinality units for explicit
  non-nullable arrays/objects. The new provenance anchor
  `go test ./provenance -run '^TestOpenAPI30CollectionCardinalityRequiresNonnullableExplicitCollections$'`
  passed in 0.190s; the native edit/validation/export/bundle/immutability anchor
  `go test ./native -run '^TestOpenAPI30CollectionCardinalityEditsEffectiveResourcesAtomically$'`
  passed in 0.412s. Existing inverse/effective-resource paths are reused; no
  Java production code changed and no JVM/Maven lifecycle was repeated.
- The OpenAPI Schema-root index now walks every explicit Document under its
  own version and dialect, including wrapper transitions into another Document.
  Fragments inherit the caller context; visited keys include that context and
  budgets remain aggregate. `DiscoverOpenAPI` retains its existing traversal
  behavior. After correcting only expected-order slices in new fixtures,
  `go test ./provenance -run '^TestOpenAPISchemaRootIndex(CoversWrapperRoles|ResolvesOnlyWrapperReferences|LeavesSchemaReferencesOpaque|KeepsWrapperFailuresAndBounds|UsesEveryDocumentContext|WrapperDocumentAndFragmentContexts|DocumentContextWorkIsAggregate)$'`
  passed in 0.198s. Four affected existing provenance callers also passed in
  0.218s:
  `go test ./provenance -run '^(TestOpenAPI32MediaAndEncodingSchemaPositions|TestOpenAPIExplicitResourcesReferencesAndIDs|TestOpenAPIWrapperReferencesAreChainedWithoutDroppingSiblings|TestOpenAPICollectionCardinalityPreservesJSONAndYAMLTokens)$'`.
- A private, not-yet-integrated OpenAPI oracle view relocates indexed Schema
  Objects into one ordinary JSON Schema container per physical resource. It
  preserves existing resource boundaries and dynamic anchors, normalizes
  existing IDs, rewrites static references only in known schema positions,
  and exposes checked selector mappings. Exact originals are untouched.
  Independently referenced schemas overlapping opaque data fail closed.
  Retained selectors and total materialized container/alias bytes have separate
  aggregate 16 MiB ceilings; JSON quoting checks escaped size before allocation.
  The initial three oracle proofs passed in 0.324s; review then tightened
  containment and allocation checks. The resulting exact selection passed in
  0.421s:
  `go test -v ./native -run '^(TestOpenAPICatalogIndexesCompleteSecondaryDocuments|TestOpenAPIOracleViewPreservesPhysicalAndLogicalScope|TestOpenAPIOracleViewPreservesDynamicScope|TestOpenAPIOracleViewChargesAggregateAliasesAndOutput|TestOpenAPIOracleViewRejectsOverlappingDataInterpretations|TestOpenAPIOracleViewQuotesBeforeAllocatingEscapes)$'`.
  These are Go-oracle proofs, not generated-Java or end-to-end ingestion claims.
  Further review added common inherited dialects for physical fragment
  containers (mixed no-ID dialects reject), explicit dialects at existing ID
  boundaries, cached semantic-parent mapping, and collection-copy preflights.
  Fresh alias-loader entry points are covered as well as physical selectors.
  Only the affected oracle tests and new dialect test were rerun:
  `go test -v ./native -run '^(TestOpenAPIOracleViewPreservesPhysicalAndLogicalScope|TestOpenAPIOracleViewPreservesDynamicScope|TestOpenAPIOracleViewChargesAggregateAliasesAndOutput|TestOpenAPIOracleViewRejectsOverlappingDataInterpretations|TestOpenAPIOracleViewRetainsFragmentDialects)$'`
  passed in 0.326s. Generation consistency and vet passed for native/provenance;
  the unchanged quote and secondary-document passes were reused.
- Checkpoint `2b52c79` CI exposed one stale expectation on both platforms:
  `TestOpenAPI30NumericBoundsProjectWhileOtherFamiliesRemainOpaque` still
  expected collection cardinalities to be opaque. It now asserts the two
  collection units plus paired numeric bounds and retains a YAML-enum opacity
  check. No production failure was reported by that CI run; its failed test
  gate is not represented as a green checkpoint.
- The OpenAPI catalog projection adapter preserves local declaration names,
  resolves external scopes, and retains strict operation-shape failures.
  `go test -v ./native -run '^(TestOpenAPICatalogProjectionPreservesLocalDomainNames|TestOpenAPICatalogProjectionUsesExternalScopesAndOccurrences|TestOpenAPICatalogOperationProjectionKeepsStrictShapeFailures|TestJSONProjectionResolvesNestedExternalRecursiveReferences|TestJSONMapProjectionUsesCarrierForHeterogeneousOrOpenValueDomains)$'`
  passed in 0.754s. The default JSON Schema projector behavior is unchanged.
- Catalog annotation auditing and selection were checked separately before
  production integration: `go test ./native -run '^TestOpenAPICatalogAnnotation(SelectionMatchesRootAndOperationAuthority|AuditsDynamicInitialAndOverrideTargets|BudgetsAreAggregateAndCyclesFailClosed)$'`
  passed in 0.313s. Dynamic override candidates are audited but never selected
  as though their initial static target were guaranteed at runtime.
- A separate kin structural view rewrites only static Schema Object references
  to physical locations; it retains wrapper, default and example checks.
  `go test -v ./native -run '^(TestOpenAPIKinOracleViewRewritesOnlyCatalogStaticReferences|TestOpenAPIKinOracleViewFailsClosedOnMissingResolvedTarget|TestOpenAPIKinOracleViewPreservesKinDefaultAndExampleValidation)$'`
  passed in 0.393s after correcting a quote-helper scratch-variable bug found
  during review. Exact originals remain untouched.
- OpenAPI 3.0 JSON enum units now reuse intrinsic JSON equality with ordered
  native token recovery. Nullable still permits only values admitted by enum;
  YAML enum and 3.0 const remain opaque. `go test ./provenance -run '^(TestOpenAPI30JSONEnumPreservesOrderedTokenAndNullableSemantics|TestOpenAPI30EnumIgnoresReferenceSiblingsAndYAML)$'`
  passed in 0.226s, and `go test ./native -run '^TestOpenAPI30JSONEnumEditsEffectiveResourcesAtomically$'`
  passed in 0.362s.
- Modern OpenAPI provenance now consumes authoritative catalog locations while
  reading tokens from exact originals. `go test -v ./provenance -run '^TestOpenAPIIndexedProvenance(PreservesPhysicalTokensAndOrdering|RejectsInvalidAuthorityAndBounds)$'`
  passed in 0.430s, covering JSON/YAML, stable index order, data opacity,
  missing/scalar/conflicting locations, explicit dialect disagreement and work
  bounds. `go test -v ./native -run '^(TestOpenAPICatalogProvenanceEditsLogicalTargetsAndRebuildsBundles|TestOpenAPICatalogKeywordLocationsFollowAnchorsWithoutReadingData|TestOpenAPIProvenanceJSONEditsValidationExportBundleAndImmutability|TestOpenAPIProvenanceYAMLExternalRootlessRebuildsOperationIndex)$'`
  passed in 1.062s, including existing edit/bundle regressions. Keyword discovery
  now follows static/logical anchors and dynamic candidates through actual
  schema edges; unused component patterns and instance data are not scanned.
- The three new Go production-ingestion/runtime anchors passed in 0.551s:
  `go test -v ./native -run '^(TestOpenAPICatalogRootedIngestionAndRuntimeUsePhysicalValidationView|TestOpenAPICatalogStructuralValidationRetainsExternalDefaults|TestOpenAPICatalogOperationBoundaryUsesPhysicalValidationView)$'`.
  Review caught and restored the OpenAPI 3.0 legacy projection branch before
  this run. One coherent affected integration race selection then passed in
  11.108s:
  `go test -race ./native -run '^(TestOpenAPI31ExactJSONSchemaPayloadValidation|TestOpenAPI321ResourceIngestionAndNativePayload|TestOpenAPIExactYAMLNumbersAndExternalResources|TestOpenAPI30AdapterUsesOnlyExplicitExternalResources|TestOpenAPIOperationIndexAndSemanticBoundary|TestRootlessOpenAPIOperationsIngestAndBoundary|TestOpenAPICatalogProvenanceEditsLogicalTargetsAndRebuildsBundles)$'`.
- Generated Java uses the same validation-only resources and mapped selectors,
  including trusted generated operation wrappers. The single grouped harness
  passed in 9.636s with
  `REFINE_REQUIRE_JAVA=1 REFINE_JAVA_HOME=/opt/homebrew/opt/openjdk@25 REFINE_NETWORKNT_DIR=/private/tmp/refine-networknt.fPEK2h go test ./java -run '^TestGeneratedOpenAPIValidationViewPreservesLogicalStaticDynamicAndOperationBoundaries$'`.
  It covers logical IDs/static anchors, dynamic scope, rooted serde,
  native/refinement-invalid zero-output writes, operation wrappers, defensive
  resources and unsafe-wrapper rejection. This invocation omitted `-v`; the
  named test has no optional skip path after its Java/networknt checks, and
  both checks fail rather than skip under `REFINE_REQUIRE_JAVA=1`. The result
  is therefore an executed required-runtime pass, not an optional-runtime skip;
  it was not repeated solely to change log verbosity. The stale OpenAPI 3.0
  assertion also passed after test-only regeneration with
  `go test ./native -run '^TestOpenAPI30NumericBoundsProjectWhileOtherFamiliesRemainOpaque$'`;
  its combined generation/test wall time was 66.971s (separate package duration
  was not retained). No unrelated Java harness or Maven lifecycle was repeated.
- Independent review found that the new offline loader could overwrite the
  trusted OAS dialect adapter with a caller-supplied physical resource or
  logical-ID alias. The shared validation-view constructor now rejects that
  identity (including empty-fragment normalization) before either runtime can
  load it. `go test -v ./native -run '^(TestOpenAPIValidationViewRejectsTrustedDialectShadowing|TestOpenAPICatalogRootedIngestionAndRuntimeUsePhysicalValidationView)$'`
  passed in 0.357s. The redundant pre-validation canonical-slice copy was
  removed. Unchanged Java successes were not rerun for this constructor guard.
- Export integration exposed two existing scope/authority bugs: generated
  local component refs were rebased by a selected native `$id`, and refined
  export introduced a competing top-level annotation beside a selected scoped
  annotation. Generated refs now use the absolute physical document URI;
  an existing selected annotation is updated with the complete checked source
  and metadata in its existing location. The three export anchors
  `TestOpenAPIProjectAdditionKeepsNativeReferencesAndLiteralValues`,
  `TestOpenAPIProjectExportRecursiveCompositionRetainsNativeOracle`, and
  `TestOpenAPIProjectExportKeepsGeneratedReferencesOutsideNativeIDScope` passed
  in the initial four-test selection (0.418s overall, failed only on the
  competing-annotation case). After that correction, only the failed anchor
  was rerun: `go test -v ./native -run '^TestOpenAPICatalogAnnotationsComposeRootAndDerivedLogicalOperationAcrossExportBundle$'`
  passed in 0.719s. The new recursive-scope anchor covers both ordinary and
  refined export/reingestion plus original-resource immutability.
- Operation-index review found a direct-annotation authority bypass: an
  unrelated checked field type could previously claim the annotation had been
  consumed. The checked part must now bind the annotation's nominal root,
  allowing transparent aliases, refinements and the occurrence's optional
  wrapper without requiring original predicate text to remain unchanged.
  Aggregate audit budgets apply across each derivation/index build.
  `go test -v ./native -run '^(TestOpenAPICatalogOperationDerivationRejectsDynamicAnnotationTargets|TestOpenAPICatalogOperationIndexAuditsUnconsumedAnnotations|TestWithDerivedOpenAPIOperationsFailsClosedAtomically|TestWithDerivedOpenAPIOperationsVersionMatrix|TestOpenAPISchemaObjectAnnotationControlsSelectedPayload|TestOpenAPISchemaObjectAnnotationControlsDerivedOperationPart|TestOpenAPISchemaObjectAnnotationAuditFailsClosed)$'`
  passed in 0.530s after updating one old malformed-ID fixture to expect its
  earlier catalog rejection. A separate new positive edit-authority proof,
  `go test -v ./native -run '^TestOpenAPICatalogOperationAnnotationKeepsIntentionalEditsAcrossBundleAndExport$'`,
  passed in 0.585s: edited named-root predicates remain enforced after bundle
  and refined-export reconstruction, while the old project remains immutable.
  Final `go tool goplus gen --check ./native ./provenance ./java`,
  `go vet ./native ./provenance ./java`, and `git diff --check` passed for the
  coherent integration state. New, unintegrated `dependentRequired` helpers
  are kept out of this checkpoint and are not included in its support claims.
