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
