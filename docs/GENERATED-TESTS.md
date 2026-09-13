# Schema-derived Java property tests

`java.GeneratePropertyTests` emits an executable Java 25 test class backed by
JetBrains jetCheck 0.3.0. The generator consumes checked Refine syntax; schema
authors do not provide Java generator classes or method names.

## Inputs and generated checks

`PropertyTestOptions` controls:

- `Targets`: closed named schema types. When omitted, every closed declaration
  is selected.
- `CaseCount`: the required number of cases for every generated property
  (default 100).
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
Response-origin invalid clauses use the response selector even when validated
inside a context; additional context clauses use the context selector. Valid
pairs use the context selector when bound to a context and the response selector
otherwise.

The current operation generator rejects caller target narrowing, standalone
adapter overrides and catalogs with no semantic native parts. The last case
remains fail-closed because the current response facade does not expose the
assembled response `Data`; crediting an arbitrary typed candidate for an empty
transport response would weaken the property claim.

### Shared generator behavior

The requested case count is mandatory. For each case, the generated `requiring`
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
must preserve the raw payload and stable wire text. Each targeted invalid case
must throw a validation exception carrying the targeted diagnostic (possibly
wrapped by Jackson) and leave the caller's byte buffer empty. These checks run
automatically in the Maven-bound project launcher.

With an Avro adapter, valid cases cross both binary and Avro JSON codecs and
must preserve raw payloads and stable re-encoded bytes/text. Targeted invalid
binary writes must report the intended refinement and leave the output empty.
Before selecting a positive case, the adapter's native-only candidate predicate
also rejects values that cannot inhabit the Avro reader schema. Codec resource
limits and unexpected failures propagate rather than being filtered out.
These are properties of the generated adapter, not merely compilation checks.
