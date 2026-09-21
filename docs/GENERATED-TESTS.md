# Schema-derived Java property tests

`java.GeneratePropertyTests` emits an executable Java 25 test class backed by
JetBrains jetCheck 0.3.0. The generator consumes checked Refine syntax; schema
authors do not provide Java generator classes or method names.

## Inputs and generated checks

`PropertyTestOptions` controls:

- `Targets`: closed named schema types. When omitted, every closed declaration
  is selected.
- `CaseCount`: the requested JetCheck iteration count for every generated
  property (default 100); execution reports count actual predicate evaluations.
- `AttemptBudget`: the maximum candidates examined for each required case
  (default 10,000).
- `Seed`: the deterministic jetCheck seed used for replayable runs.
- `Examples`: typed `value.Data` payloads with expected valid, invalid, or
  indeterminate outcomes and required diagnostic evidence for refinement-invalid
  examples. `NativeExpected` defaults to native-valid when a native adapter is
  configured; explicit `ExampleNativeInvalid` instead requires native or
  structural rejection and cannot claim a refinement diagnostic.
- `Replays`: a serialized jetCheck counterexample bound to one valid property,
  or to one invalid property by target and diagnostic code.
- `JSONModule`: the generated Jackson module for a single target, enabling
  wire round-trip and no-bytes-on-invalid-write checks. Project generation sets
  this automatically for JSON Schema/OpenAPI outputs.
- `AvroSerde`: the generated Apache Avro adapter for a single target. Project
  generation sets this automatically for Avro outputs; it can coexist with the
  JSON module in the same suite.
- `NativeJSONValidator`: the explicit generated native-validator helper name.
  Together with `JSONModule`, it enables that module's native-only candidate
  predicate before positive and clause-targeted-invalid refinement filtering.
  Native-invalid structure returns false; limits, indeterminate outcomes,
  unexpected runtime failures, and errors propagate instead of becoming
  discarded candidates.

For every target, the emitted suite derives a structural `Data` generator. A
valid candidate must pass the contract filter, the normal generated model
factory, preserve its raw `Data`, validate through the model, and survive a
canonical show/read/show round trip. It also emits one invalid property per
discovered `where` clause. A targeted invalid candidate must have a complete
`INVALID` outcome containing that clause's explicit or deterministically
derived code. Other conclusive violations may coexist: dependent predicates can
make an isolated single-rule counterexample mathematically impossible. An
incomplete invalid result never receives credit. The normal factory and
canonical reader must both reject it with the requested diagnostic, while the
explicit without-validation factory must preserve the raw value and retain the
same diagnostic on validation. Thus a property is not satisfied merely because
the validator used to select candidates returns the same result a second time.

The generator supports booleans, strings, exact rational reals, finite exact
`Float32`/`Float64`, RFC 3339 timestamps, arbitrary and fixed-width integers
(through the backend's 65,536-bit resource bound), lists, records, nominal
aliases, closed applications of generic aliases and tagged unions, refinements,
exact string-keyed maps, and `Maybe`/`Nullable`/`Result` payload constructors.
Intrinsic `JSON` strategies cover all six constructors recursively; generated
numbers use finite base-10 rationals so positive JSON wire properties exercise
the codec instead of being discarded as unrepresentable.
Map strategies generate bounded unique canonical keys and recursively use the
value strategy. Closed recursive generic
unions and records use a derived finite-base strategy: lists cut to empty,
optional/nullable values cut to their empty constructor, unions retain finite
alternatives, and required record fields must themselves have a finite base.
jetCheck's bounded recursive generator controls subsequent growth. Real
generation includes genuine fractions rather than only integer-valued reals.
Float strategies mix exact dyadic samples with zero, subnormal/normal edges,
precision boundaries, maximum finite values, and rejected halfway/overflow/
non-dyadic probes; values are constructed as rationals without a host-floating
conversion. Timestamp samples cover epoch,
offset, long-fraction, leap-second, and upper civil-date forms. Integer
refinements mix broad random values with arbitrary-precision
predicate literals and their adjacent boundary values. Generated Java constructs
those samples from decimal `BigInteger` strings, so a schema bound is not
silently truncated to Java `int`. Lists are bounded to eight elements and
generated strings currently use printable ASCII up to 24 characters. These are
generation distributions, not restrictions on the schema or runtime.

For a native JSON Schema or OpenAPI payload root whose checked Refine type is
`String`, project generation recognizes a deliberately small exact subset of
anchored ASCII character-class repetition patterns. It specializes the raw
JetCheck alphabet and length distribution before rejection sampling, including
the direct schema's `minLength` and `maxLength` bounds. Generated lengths remain
bounded to 1,024 characters and the native validator's 1 MiB default string
limit. Every candidate still passes through the real native adapter, Refine
validator, model and wire boundaries. Unknown keywords, composition, references,
non-ASCII or complex regular expressions, malformed bounds, and larger required
lengths retain the ordinary bounded rejection sampler and its explained
exhaustion behavior; the optimizer never treats them as proved constraints.

Distinct expanding specializations are capped at 512 while deriving a strategy,
so a family such as `Grow [a]` fails closed instead of exhausting the generator
process. Top-level closed tagged unions also use their generated validating factories
and readers. Recursive structures without a finite base, functions as payloads, open generic
targets, and unknown type constructors are currently rejected before any file
is returned. They are not replaced with fixed examples, raw `Object`, or a
vacuously passing property. Arbitrary refinements that are structurally
generatable use rejection sampling against the real generated validator.

## Exhaustion and invalid targeting

### OpenAPI operation projects

`java.GenerateProjectOpenAPIPropertyTests` generates a single JetCheck launcher
for the authoritative operation catalog, including projects without a payload
root. Request, response and context checks use the generated native-first
facade and real validated-request tokens. Every request/response binding gets
valid properties; discovered clauses get targeted-invalid properties. Candidate
exhaustion and indeterminate validation fail the suite rather than skip cases.
Each invalid occurrence is identified by its diagnostic code, bounded affected
path list, and authored source offset. When native lowering also represents the
clause, the property records dual evidence: the checked contract must produce
that exact code and path for the logical value, and the real native-first facade
must reject the same request or response. This proves both logical targeting and
boundary enforcement; it does not claim that a native validator reports Refine
diagnostic codes. Native limits and indeterminate outcomes remain fatal.
Valid, refinement-invalid, indeterminate, and native-invalid examples execute
explicitly through the real facade at every matching catalog occurrence.
Response examples search within `AttemptBudget` for a compatible valid request;
context examples carry their exact request/response pair. Native resource or
enforcement failures remain fatal and cannot satisfy an expected Refine
indeterminate outcome. Metadata catalog v1 supports conclusive valid/invalid
Refine outcomes only; the caller `PropertyExample` API additionally supports
indeterminate expectations. Rootless Maven assembly includes this launcher in
the same artifact as the project's other schema families.

Operation replays use opaque selectors returned by
`OpenAPIRequestReplayTarget`, `OpenAPIResponseReplayTarget`, or
`OpenAPIContextReplayTarget`. Request replays carry one `Data` generator value;
response and context replays carry the generated request/response pair. Each
selector, kind, and diagnostic must identify exactly one emitted property;
unmatched or ambiguous entries reject generation atomically.
Reusing one refined type at several paths does not make mandatory property
generation ambiguous. When the same code occurs more than once in one role,
use the corresponding `OpenAPI*OccurrenceReplayTarget` helper with the checked
affected paths and clause source offset. A supplied legacy role selector then
rejects as ambiguous; without such a replay, every occurrence is still emitted.
The exported `OpenAPIPropertyElementPathSegment` marks one concrete list index
or map key inside an occurrence path pattern; it is a reserved non-JSON-Pointer
escape and cannot alias an authored object field. Runtime diagnostics must match
the complete path pattern, code, and predicate. Indistinguishable emitted
diagnostics reject generation instead of crediting the wrong clause.
For an automatic `refine.*` code below a collection, the generator substitutes
the concrete diagnostic key or index before recomputing the same checked code;
the static element marker is never treated as the runtime code path.
Response-origin invalid clauses use the response selector even when validated
inside a context; additional context clauses use the context selector. Valid
pairs use the context selector when bound to a context and the response selector
otherwise.

The current operation generator rejects caller target narrowing and standalone
adapter overrides. Operations with no semantic native parts use an exact
transport-first singleton: the checked codec decodes the authoritative empty
request or response envelope, and that value crosses the real facade. It never
credits an arbitrary typed value whose fields were discarded while constructing
an empty transport message. Required edited fields without a native mapping
reject generation; absence-capable `Maybe` fields canonicalize to `Nothing`.
Supplying any undeclared parameter, header, or body is still rejected by the
closed empty native wrapper.

### Shared generator behavior

Every generated property is mandatory; the configured iteration count is passed
to JetCheck, and the suite rejects zero predicate evaluations. For each case, the generated `requiring`
generator evaluates at most `AttemptBudget` candidates. If it cannot find a
valid or clause-targeted invalid payload, it throws an `AssertionError` naming
the target and attempt count. The property does not skip, reduce its case count,
or report success. A satisfiable schema outside the current distribution—for
example a string constrained to more than 100 characters while the current text
distribution stops at 24—therefore fails explicitly and calls for a better
strategy or explicit input adjustment.

Embedded valid and refinement-invalid examples run before random properties and
through the same generated model construction/bypass, canonical read, and JSON
or Avro wire boundaries as generated candidates. Native-valid examples must
also pass every configured native candidate predicate. Valid examples are mixed
only into their named target's positive candidate distribution, after these
assertions, so a difficult but supplied valid case can satisfy generation
without being relabelled or weakening exhaustion. Each refinement-invalid
example names exactly one requested diagnostic and is mixed only into that
target-and-code invalid distribution. It cannot be credited unless the payload
is native-compatible and its complete invalid result contains that code.
Positive, native-invalid and indeterminate examples never enter an invalid seed
pool; invalid, native-invalid and indeterminate examples never enter the
positive pool.
An explicit native-invalid example names no refinement diagnostic: a
Refine-valid value must be rejected by staged wire output with zero published
bytes, while a Refine-invalid value must be classified as structurally invalid
by both normal and bypass model construction. Library callers may supply typed
examples directly, and project generation also adapts versioned
`native.WireMetadata.Examples` after canonical structural and expected-Refine-
outcome checks. A declared native-invalid outcome remains unevaluated metadata
intent until a configured generated JSON or Avro adapter executes it; ordinary
native `examples` annotations are never guessed or classified.

## jetCheck dependency and replay

Generated sources directly reference `org.jetbrains.jetCheck.Generator` and
`PropertyChecker`. Maven/test integration must provide
exactly `org.jetbrains:jetCheck:0.3.0` on the generated-test classpath. Refine
does not download it during generation.

Normal schema properties run with the configured seed and case count. A failing
jetCheck property reports a minimized serialized counterexample. Supplying that
text in a matching `PropertyReplay` makes the generated property invoke
jetCheck's real `rechecking` path instead of its seeded run; replay entries that
do not identify an emitted target/property are rejected atomically. Deliberately
failing framework smoke properties are kept in Refine's own generator tests and
are never inserted into a user's emitted suite.

The generated class has a `main` method so it can run under a plain Java test
execution as well as a Maven-bound launcher. A generation caller should combine
it with the matching `GenerateModels` output for the same program, namespace,
and contract class.

With a JSON module, every valid case also crosses Jackson write/read/write and
must preserve the wire payload and stable wire text (see numeric-tag semantics below). Each targeted invalid case
must throw a validation exception carrying the targeted diagnostic (possibly
wrapped by Jackson) and leave the caller's byte buffer empty. These checks run
automatically in the Maven-bound project launcher.

With an Avro adapter, valid cases cross both binary and Avro JSON codecs and
must preserve wire payloads and stable re-encoded bytes/text. Targeted invalid
binary and Avro JSON writes must report the intended refinement; binary writes
must also leave the output empty.
Before selecting a positive case, the adapter's native-only candidate predicate
also rejects values that cannot inhabit the Avro reader schema. Codec resource
limits and unexpected failures propagate rather than being filtered out.
These are properties of the generated adapter, not merely compilation checks.

## Execution evidence and coverage limits

This reporting ships in Maven `0.4.0`. It is not present in `0.3.0`.

Generated payload and OpenAPI operation suites report execution to stderr. The
report distinguishes properties, embedded examples, inapplicable adapters, and
coverage gaps. These messages are test evidence, not a claim that all possible
inputs or failures were exercised.

For an unconstrained JSON-only `Name` contract, a seven-case run reports:

```text
REFINE_COVERAGE NOT_GENERATED refinement-negative target=Name reason=no-refinement-predicates suite=...
REFINE_COVERAGE NOT_APPLICABLE avro-wire reason=no-avro-adapter suite=...
REFINE_PROPERTY PASS valid Name cases=7 mode=generated suite=...
REFINE_PROPERTY PASS model-accessors Name cases=7 mode=generated suite=...
REFINE_PROPERTY PASS json-node-limit cases=7 mode=generated suite=...
REFINE_PROPERTY PASS json-depth-limit cases=7 mode=generated suite=...
REFINE_SUITE PASS properties=4 cases=28 examples=0 suite=...
```

An imported native contract without explicit native-invalid examples also reports
`GAP native-negative reason=no-native-invalid-examples`. OpenAPI operation suites
identify request, response, and context checks and disclose that randomized
native-invalid properties are not generated. Explicit examples can cover native
rejection, but their existence is not randomized rejection coverage.

## Execution accounting

- `cases` counts actual property predicate evaluations on a successful run. It is
  not a count of distinct inputs, helper methods, requested iterations, or covered
  branches. Replay runs say `mode=replay` and report their actual count.
- A failing property reports `evaluations`, which can include shrinking attempts.
  Failure during generation can legitimately report zero evaluations and still
  fails the process. No passing suite summary follows a failure.
- `examples` counts fully completed embedded/caller example checks. Compatible
  request sampling for an OpenAPI response example is separately reported as a
  property check with its own observed count.
- Reports include the suite's qualified class name, including its family/version
  namespace in a generated Maven project.
- A property runner that returns without evaluating any cases fails. A suite
  that completes without any property checks also fails.

Each generated refinement-negative property is required. If its bounded generator
cannot find a matching input, the suite fails with an exhaustion diagnostic; it
does not silently skip the property. This can also happen for a tautological
predicate whose negation has no example in the generated domain.

## Applicable checks only

The generator emits JSON and Avro checks only when those adapters are configured.
An absent adapter does not receive a constant-success substitute. Negative model
and codec helpers are omitted when no corresponding refinement-negative property
or example requires them. Native-negative helpers require explicit native-invalid
examples.

Positive model checks require preservation of the original `Data`, validation,
and text round trips. Configured JSON and Avro codecs are exercised for wire
round trips. Avro positive checks exercise both binary and Avro JSON encoding;
refinement-negative checks require rejection from both writers. JSON invalid
writes and Avro binary invalid writes must publish no bytes.

Wire equality preserves exact rational values and payload structure, including
keys, field names, variants, and collection contents. It disregards only
`Data.Number.numericType`, a Refine literal tag not encoded by JSON or Avro.
For example, integer 7 tagged `Int64` and integer 7 decoded as `Int` have the same
wire value; 7 and 8, or 7 and 7/2, do not. Model boundary checks still require exact
raw-data equality, including numeric tags.

## Tests of the tests

The regression harness compiles and runs healthy generated implementations, then
activates narrowly scoped mutations in implementation code, leaving generated
assertions intact. It requires nonzero process status and an executed-property
failure for each mutation:

- a contract validator that accepts every value;
- a model validator that accepts every value;
- a constructor that bypasses validation;
- a JSON writer that bypasses validation or loses numeric data;
- an Avro writer that bypasses validation, loses binary/JSON data, or bypasses
  validation only on the Avro JSON path;
- a getter that returns the wrong value;
- a JSON module with its traversal guard disabled;
- a native validator that discards an invalid schema result.

Another test substitutes a broken property runner that never invokes its
predicate. It must fail rather than produce an empty green run. Separate tests
cover positive and negative generation exhaustion and preservation of payload
differences by wire equality. OpenAPI regression tests exercise report labels,
replays, examples, and request/response/context bindings.

These are finite mutation checks, not a claim of comprehensive mutation coverage.
Running a generated suite is still necessary: compiling it alone establishes no
property-test evidence. The Maven test launcher must be bound to the test phase,
as in Offscript and the generated Maven snippet.

## Consumer mutation verification

The reusable harness lives in Refine's Maven plugin as `refine:mutate`.
See [Mutation testing](MUTATION-TESTING.md) for the catalog, result classifications,
and Offscript demonstration. Offscript configures and exercises the harness;
it does not own its implementation.

## Generated boundary checks in 0.4.0

Top-level non-generic model accessor values are encoded and compared with the
original data; this is independent of the accessor body. Nested model data is
compared, but this does not independently exercise every nested getter. Generic
and union accessor checks are reported as a gap.

JSON node and depth limits are tested separately through a plain Jackson mapper
so strict-mapper parser limits cannot mask a missing module guard. Small nested
probes must produce an indeterminate `validation.limit` diagnostic before structural
or native-schema rejection; an unrelated exception is not a pass.

For native JSON projects, a bounded corpus of JSON values is evaluated by the Go
native validator during generation. Only definite native-payload rejection becomes
an expected-invalid fixture; enforcement errors abort generation. Java directly
checks that the emitted native validator rejects those fixtures as `INVALID`.
The number of requested cases is capped by the finite corpus. The corpus is not
a complete enumeration of schema constraints. The existing `native-negative`
gap with reason `no-native-invalid-examples` refers to authored model/wire examples;
it does not erase the separately reported `native-json-rejection` probe evidence.
