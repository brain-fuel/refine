# Native schema ingestion and lowering

The `native` package is the validated, immutable boundary for JSON Schema,
Avro, and OpenAPI. Its complete Go boundaries decode and validate JSON and Avro
payloads, but it does not perform compatibility analysis or schema evolution.
It can bundle caller-supplied resources, but never fetches resources itself.
Executable typed metadata examples are documented in [EXAMPLES.md](EXAMPLES.md);
ordinary native `examples` annotations remain opaque resources.

## Supported inputs

| Format | Accepted version | Representation | Structural validator |
| --- | --- | --- | --- |
| JSON Schema | Draft 2020-12 only | JSON | `github.com/santhosh-tekuri/jsonschema/v6` v6.0.3, with Draft 2020-12 selected explicitly |
| Avro | Apache Avro 1.12.0 schema semantics | JSON | `github.com/hamba/avro/v2` v2.31.0 |
| OpenAPI | 3.0.0–3.0.4, 3.1.0–3.1.2, and 3.2.0–3.2.1 | JSON or YAML | `github.com/getkin/kin-openapi` v0.149.0 |

OpenAPI tooling is required by the specification to interpret the declared
`openapi` version. This package accepts only published, stable version strings;
it does not treat an unknown future `3.x` value as a familiar version. OpenAPI
3.2.1 is the current published specification, dated 2026-09-10. OAS patch
versions correct or clarify the specification without changing the feature set,
and tooling is advised not to distinguish patches within a minor line. Refine
still enumerates published patches so an invented future patch cannot silently
claim verified support. The authoritative
version lists are the [OpenAPI specification index](https://spec.openapis.org/oas/)
and [OpenAPI 3.2.1](https://spec.openapis.org/oas/v3.2.1.html).

Avro schemas contain no specification-version member. A successfully imported
schema therefore reports the semantics against which Refine validated it,
currently `1.12.0`; this is not a version inferred from the input. See the
[Apache Avro 1.12.0 specification](https://avro.apache.org/docs/1.12.0/specification/).
Hamba is used as an ecosystem validation oracle and not as proof that Refine's
own translations preserve every Avro semantic. Its repository was archived in
2026, so replacement or independent conformance coverage remains a maintenance
risk.

All formats first pass Refine's bounded syntax layer. JSON duplicate decoded
keys are rejected, including escape-equivalent keys. YAML duplicate scalar keys,
aliases, merge keys, multiple documents, non-scalar keys, and configured
depth/node/byte excesses are rejected. Alias and merge expansion is intentionally
not claimed yet. Strings containing unpaired UTF-16 surrogate escapes are
rejected because the native validators cannot retain their semantics faithfully.

Single-document validation is offline: OpenAPI external references are disabled
and the JSON Schema compiler explicitly rejects missing resource loads, overriding
the underlying library's filesystem-loader default. Consequently an
unresolved external `$ref` is an error, not a network or filesystem read.
Internal references are supported. `IngestProjectResources` enables external
references only against an explicit bounded in-memory resource set; `Project.Bundle`
then retains that exact set for offline redistribution and revalidation.

## Immutable API

Use `Parse`, `ParseJSONSchema`, `ParseAvro`, or `ParseOpenAPI`. `Options.Limits`
uses the same byte, depth, and node defaults as `schemajson`. A `Document` exposes:

- `Format()` and `Version()`;
- `Original()` and `ExportOriginal()`, which return the exact accepted source;
- immutable copies from `Annotations()` and `Constraints()`;
- JSON Schema provenance operations `ConstraintSource`, `AuditSource`, and
  `RecoverNative`.

`ExportOriginal` returns a fresh byte slice. Mutating it cannot change the
document. Import followed by unchanged export therefore preserves whitespace,
member order, number spelling, Avro field/union order, YAML presentation, unknown
extensions, and documentation byte for byte.

Document-level JSON Schema correspondences delegate to the `provenance`
package. Editing one canonical constraint does not invalidate an untouched
constraint. The `Document` provenance methods remain JSON-Schema-only; Avro and
OpenAPI use resource-scoped `Project` methods. Those project adapters support
Avro fixed sizes and ordered enum symbols, OpenAPI 3.0 paired numeric bounds,
and OpenAPI 3.1/3.2 numeric, `const`/`enum`, and collection-count constraints within their documented exact
subsets. See [NATIVE-PROVENANCE.md](NATIVE-PROVENANCE.md).

## Refined annotations

An annotation has exactly one of these forms:

```yaml
x-refine: |
  type Positive = Int where it > 0
```

```yaml
x-refine:
  source: |
    type Positive = Int where it > 0
  root: Positive
```

The string or `source` member must compile as a complete Refine language module.
When `root` is present it must type-check as a closed payload type in that module.
An object permits only `source`, `root`, and checked `metadata`; malformed or
untyped annotations are rejected. Accessors preserve the exact source and also
provide its deterministic formatted form. Embedded metadata is restored on
ingestion, while a conflicting caller-supplied policy is rejected.

Recognized locations include schema positions in JSON Schema and Avro, and the
OpenAPI root object. OpenAPI 3.1/3.2 projects also compose annotations on the
selected Schema Object or a directly bound operation Schema Object (including
supported references). Such annotations require an explicit closed `root`.
Reachable nested annotations beneath fields or applicators currently reject
rather than being silently ignored; OpenAPI 3.0 retains document-level
annotation support. Objects carried in examples, defaults, arbitrary extension
payloads, and documentation are not executed or mistaken for declarations.

## Checked type lowering

Automatic JSON Schema/OpenAPI projection retains precise primitive, record,
and homogeneous-map types when available. The intrinsic `JSON` algebra is the
fallback for unconstrained or mixed-kind values and structural applicators;
unconstrained arrays and tuples use `[JSON]`, and heterogeneous/open map value
domains use `Map String JSON`. Native `oneOf` is still exact-one schema matching,
not an inferred tagged union. All original native constraints run before the
editable language type. A selected `false` schema is proven empty and rejected;
an empty array whose item schema is `false` remains representable.

Declared records retain their ordinary discard-extra-fields default. A JSON
object carrier, by contrast, represents all object members as its actual value;
it does not change a record's extra-field policy. Native resources remain
byte-identical in the immutable project and its bundle. This fallback does not
claim general reference projection or broaden the explicitly bounded automatic
OpenAPI-operation derivation API.

`JSON` lowers to an unconstrained JSON Schema/OpenAPI Schema Object with an
English wire explanation. Transparent JSON serialization requires exact finite
decimal numbers and Unicode scalar text, rejecting nonrepresentable raw values.
There is no implicit Avro encoding for this carrier; Avro lowering and serde
generation fail explicitly until a lossless wire policy is supplied by a future
implementation.

`LowerPayload(format, payloadType, options)` accepts only a
`language.PayloadType`, so unchecked ASTs cannot reach a backend. Generated bytes
are ingested through the same native validator before they are returned.

Implemented JSON Schema Draft 2020-12 and OpenAPI 3.1/3.2 mappings include:

- `Int`, `IntN`, `UIntN`, `String`, and `Bool`;
- lists, records, exact-string-keyed `Map String a`, required fields, `Maybe`
  record-field absence, and `Nullable`;
- non-generic named aliases/records and recursive `$ref` definitions;
- canonical integer comparisons against exact numeric literals as
  `minimum`, `maximum`, `exclusiveMinimum`, and `exclusiveMaximum`;
- canonical exact divisibility forms as `multipleOf`.

Emitting fixed-width bounds is capped at 65,536 bits to bound backend memory and
document growth; wider checked language types receive an explicit lowering error.

OpenAPI 3.0 ingestion is supported, but generation currently requires 3.1.x or
3.2.0 or 3.2.1 because its Schema Object can express the implemented JSON Schema forms
without a separate 3.0 nullable/keyword adapter.

Implemented Avro mappings include `Int32`, `Int64`, `String`, `Bool`, lists,
`Map String a`, records, `Nullable` unions, aliases, closed generic record
applications, and recursive named records. Closed applications use simultaneous substitution, so
transformed generic aliases retain their argument order. Generated
specialization names are deterministic and cannot overwrite authored names.
Record and union ordering is deterministic and is validated after generation.

Native lowering permits at most 512 distinct closed generic specializations by
default. `LowerOptions.MaxGenericSpecializations` can select a smaller bound or
raise it to the hard maximum of 4,096. Recursive uses of the same specialization
reuse its definition; families such as `Grow [a]` that continually construct a
new specialization fail with `native.limit` instead of expanding indefinitely.

`Ordinary` is the default export mode. A rule with no exact native keyword causes
`native.unrepresentable`. A caller may explicitly set `AllowDocumentedLoss`; the
export then returns one `Loss` per rule, embeds a warning in the native schema,
embeds the complete relevant English contract in the native documentation field,
and exposes the same complete `explain` Markdown through `CompanionMarkdown`.
This is an explicit lossy operation, not silent keyword removal. `Refined` mode retains
the checked source and selected root in `x-refine`; its loss list still identifies
rules not enforced by the ordinary portion.

Base value domains that the selected wire format cannot represent exactly always
fail, even in Refined mode and even when documented loss is allowed. Current
examples are exact `Real` values such as `1/3`, arbitrary-precision `Int` in Avro,
and `Timestamp` without an explicit offset/spelling wire policy. Other explicit
gaps include tagged unions without declared discriminator metadata, tagged
discriminator objects in Avro, open generic roots, OpenAPI operations
authored from standalone language source, Avro/OpenAPI native-constraint
provenance and OpenAPI 3.0 lowering. Native Avro JSON validation and decoding
are implemented separately; see [AVRO-JSON.md](AVRO-JSON.md).
The package reports these as errors and does not narrow, round, add discriminators,
turn absence into null/default, or strip constraints silently.

## Editable native projects and bundles

`IngestProject` combines one validated native document with a required payload
`ResourceSelector` and produces checked editable source. `IngestProjectResources`
does the same for an ordered, explicit resource set. OpenAPI documents that have
operations but no payload schema root use `IngestOpenAPIOperations` or
`IngestOpenAPIOperationResources`; their target is the entry resource and they do
not acquire a fake component schema or payload root. Resource IDs must be
absolute URIs without fragments. Resolution is confined to supplied bytes:
there is no filesystem or network fallback. A bundle accepts at most 10,000
resources and 64 MiB total, in addition to each parser's per-document limits.
Before any exact-number or schema oracle parsing, JSON and YAML documents also
receive an aggregate numeric-expansion budget. Each numeric token costs its
source length plus the absolute decimal exponent; the hard schema/resource-set
budget is 65,536. This rejects compact inputs such as `1e1000000000` before a
large `big.Rat`/`BigDecimal` allocation.

After language compilation, every zero-parameter type declaration passes the
conservative satisfiability analysis. A proven contradiction rejects ingestion
or an edit as `native.schema` and retains the underlying `analysis.SchemaError`.
Unsupported proofs, recursive predicate budgets, structural types, and open
generic declarations remain explicit `Unknown` findings; they are never called
valid. `Project.SchemaChecks` returns an immutable-copy `analysis.SchemaReport`
in declaration order. Bundles do not trust serialized proof state and recompute
the report from their checked source when loaded.

The initial safe structural projection covers:

- JSON Schema/OpenAPI explicitly typed primitives, homogeneous arrays, records,
  homogeneous exact-string-keyed maps, required/optional fields, nullable
  forms, named definitions, and local refs;
- Avro primitives, arrays, maps, records, enums, fixed byte sequences, nullable and
  general unions, named references, and ordered fields/branches;
- nested and recursive external JSON Schema references, canonical `$id`
  resource identities, static `$anchor` names, and resource-relative JSON
  Pointers, using only explicitly supplied resources;
- root-level external OpenAPI reference chains whose fragments are JSON
  Pointers, and ordered Avro dependency schemas.

Projection does not infer an object or number type merely from `properties` or
`minimum`: those keywords permit other JSON kinds. It instead uses the explicit
`JSON` carrier described above. Tuples, heterogeneous map value domains, open
pattern maps and non-identifier field names also have carrier projections.
Schema-valued `additionalProperties` and closed `patternProperties` retain a
more precise homogeneous map when possible. Explicit scalar kinds remain
precise even through applicators, whose native constraints are not hoisted into
unconditional refinements. OpenAPI anchor-based roots and nested external
references that its named projector cannot express still fail explicitly with
`native.projection`; no resources are fetched to resolve them. Dynamic JSON
Schema references are not guessed as static language types.

JSON Schema projection and keyword scans share a bounded schema-position
catalog. Logical IDs and anchors are aliases of physical resource/pointer
identities, so multiple references to one definition do not duplicate it.
Existing local `$defs` names remain available when selecting a nested root;
external names include deterministic identity hashes. Duplicate IDs or anchors,
references into non-schema data, and missing explicit resources reject.
The catalog caps aggregate retained-location accounting at 16 MiB in addition
to source, node and depth limits, preventing repeated long ancestor paths from
amplifying memory use. `Project.JSONSchemaResourceAliases` exposes a sorted,
defensive inventory for offline runtimes that need canonical `$id` loader
entries; it does not replace or mutate the original physical resources.

Map identity is the decoded exact UTF-16 key sequence: alternate JSON escape
spellings are duplicates, while case and Unicode normalization remain distinct.
Entry order is never semantic and canonical Refine display sorts exact UTF-16
code units. JSON and Avro wire boundaries reject keys that cannot be represented
as Unicode scalar text rather than replacing unpaired surrogates. Native checked
decoding also applies one aggregate per-payload fixed 67,108,864-unit
conservative UTF-16 ordering-work cap across all nested maps, reported as
`native.limit`; structural `Nodes`/`Values` retain their stated
meaning and are not silently reinterpreted as CPU budgets.

Native constraints remain authoritative in the immutable sidecar. For JSON
Schema, each resource has independently scoped `NativeConstraints`,
`ResourceConstraintSource`, `AuditResourceSource`, and
`RecoverResourceNative` operations. Constraint declaration names are scoped by
resource; callers must not concatenate colliding resource projections. Numeric
and intrinsic-JSON `const`/`enum` rules under `not`, `allOf`, conditionals, or other applicators are emitted only
as provenance units and are never attached unconditionally to the projected
root. `Project.ValidateJSON` evaluates the selected schema with every explicit
resource installed, enforcing retained opaque JSON Schema keywords.
`NativeConstraintSources` exposes the canonical units as an ordered,
resource-scoped editable snapshot, including units from external resources and
units omitted from an annotation-authored root module.
`WithEditedNativeConstraintSource` is the explicit edit boundary; absence of a
unit from `EditableSource` is never inferred as removal. Bundles retain these
edits, while older bundles with no unit field reconstruct the canonical defaults.
Untouched units keep their original keyword. Explicit removal deletes only that
keyword from the effective validator. A changed unit currently must retain its
scope and lower to exactly one supported native assertion at its original
Schema Object position; unsupported scoped edits fail `native.enforcement`
instead of leaving the stale original constraint active. Arbitrary refinements
should be added to the payload type until scoped evaluation under native
applicators is implemented.
For `const` and `enum`, an edited unit must retain its original keyword family;
the inverse recognizes intrinsic JSON constructors, not arbitrary equivalent
functions. See [NATIVE-PROVENANCE.md](NATIVE-PROVENANCE.md) for exact supported
forms and bounds.
`Project.ValidateAvroBinary` validates exactly one binary datum against the
selected writer schema and its ordered named dependencies. Its independent byte
cursor enforces exact EOF, Boolean/int/enum/union encodings, declared collection
block sizes, duplicate map keys, UTF-8, decimal precision, UUID text, time-of-day
ranges, and caller-bounded bytes, depth, values, and string/bytes sizes. Avro
1.12 nanos timestamps retain their exact signed `long`; unknown or invalid
logical types use their underlying type as the Avro specification requires.
The Avro 1.12 [`big-decimal`](https://avro.apache.org/docs/1.12.0/specification/#decimal)
logical type is enforced as an outer Avro `bytes` value containing an Avro
`bytes` two's-complement unscaled integer followed by an Avro `int` scale, in
agreement with Apache's `BigDecimalConversion`. The unscaled integer must be
nonempty, the scale must fit signed 32 bits, and the nested value must consume
the carrier exactly. Redundant sign extension remains legal; scale and
precision are intentionally unrestricted. Existing payload byte/depth/value
limits bound this check without expanding a power of ten. Automatic projection
and the checked Go boundary preserve this value as its exact physical `[UInt8]`
carrier. `AvroBytesDecimal` metadata has a fixed schema scale and therefore
cannot truthfully represent per-value-scale `big-decimal`; editing that carrier
to `Real` fails `native.decode` instead of silently rounding or discarding the
scale. A dedicated exact-rational wire policy remains future work.
Generated Java Avro serde enforces the same nested representation and preserves
the physical bytes on binary and Avro-JSON round trips. Semantic `Real` coercion
remains unsupported; see [SERDE-AVRO.md](SERDE-AVRO.md).
Native schema ingestion also audits every field default from the exact source
node, closing numeric truncation, overflow, and obsolete branch-zero union
default behavior in the ecosystem parser. Hamba receives a private structural
copy with only record-field defaults removed; Refine retains and exports the
original bytes and applies Avro 1.12's ordered first-matching rule itself.
Nested omitted record fields resolve through the exact raw default index by
full name, including explicitly ordered dependency resources. The structural
copy is used only for schema shape and writer-binary validation; it never
synthesizes a missing field into writer bytes.
Default matching has three outcomes: match, mismatch, or resource exhaustion.
One budget of 1,000,000 work items and a separate aggregate budget of 16 MiB of
scalar, object-key, and enum-symbol input are shared across every field and
ordered resource in an ingestion; nested matching is capped at depth 256.
Object members are indexed once per record comparison instead of rescanned for
each field. Exhaustion is `native.limit`; it is never treated as a mismatch or
used to select a later union branch. Avro `int` and `long` defaults require an
integral JSON token, so lexically floating values such as `1.0` and `1e0` can
match a later `float` or `double` branch but not an integer branch.
For each reachable default, project compilation encodes the first matching Avro
1.12 union branch, decodes it through the checked field type and wire metadata,
and evaluates the field refinements. A conclusive violation is
`native.default-refinement` and rejects ingestion or an edit. Evaluation
exhaustion is retained as an explicit `indeterminate` entry from
`Project.AvroDefaultChecks`; it is never reported as a valid proof. The same
checks are recomputed after source, imported-source, metadata, and bundle edits.
The checked-type traversal has its own depth/substitution bounds. Exhaustion
adds a `native.limit` indeterminate check rather than silently omitting deeper
defaults; malformed checked substitutions remain compilation errors. Defaults
inside a `rational-record` scalar carrier are also retained: nonminimal integer
bytes, nonpositive denominators, nonreduced complete pairs, and complete pairs
that conclusively fail the named scalar refinement reject compilation.
Encoding-valid component defaults whose final scalar depends on reader
resolution are recorded as `native.default.unknown` instead of being relabeled
as proved valid.

`Project.ValidateAvroBinary` is deliberately native-only. The complete Go
boundary is `Project.DecodeAndValidateAvro`: after native validation it performs
a second bounded, schema-guided decode into exact `value.Data`, checks that the
editable record/union/scalar shape is compatible with the writer schema, and
runs the editable root's three-state refinements. It supports ordered dependency
resources, recursive records, arrays, byte/fixed lists, enums, nullable and
general unions, exact finite float/double values, and the explicit decimal
string, rational record, Avro decimal, and timestamp string wire policies.
Rational integers must be minimally encoded, denominators positive, and the
fraction reduced. Exact-number materialization and decoded byte-list allocation
are bounded before allocation. Avro permits NaN and infinities, so native-only
validation accepts them; the refined boundary returns `native.decode` because
finite exact rational `value.Data` cannot represent them. This distinction is
intentional and never changes the native-only result.

Avro JSON has corresponding `ValidateAvroJSON` and
`DecodeAndValidateAvroJSON` boundaries. They use strict Avro JSON tags and byte
encodings, bounded transcode, then the same native binary and checked refinement
gates. See [AVRO-JSON.md](AVRO-JSON.md) for framing, limits, strict-input semantics
and Apache/Hamba conformance evidence. They do not guess a reader schema.

For OpenAPI 3.1 and 3.2, `ValidateJSON` compiles the
selected Schema Object and all explicit resources with the exact-number Draft
2020-12 oracle. YAML scalars are converted to an exact JSON value without a
`float64` intermediary, including hexadecimal integers. The standard OAS 3.1
base dialect (also used by OAS 3.2) is supported because its OAS-specific
vocabulary contributes annotations rather than assertions. Draft 2020-12 is
also accepted explicitly. Other dialects are gated instead of having required
vocabularies ignored.

For every published OpenAPI 3.0 patch version, validation first uses kin-openapi
as the complete structural oracle, then rewrites only actual reachable Schema
Object positions to equivalent Draft 2020-12 assertions. The adapter converts
3.0 Boolean exclusive bounds and `nullable`, retains exact numeric source text,
and gives Reference Object siblings their specified non-asserting behavior.
`nullable` does not override `enum`, `allOf`, or another constraint that rejects
null. Documentation/default/example objects are never traversed as schemas.
This implements the normative [OpenAPI 3.0.4 Schema Object](https://spec.openapis.org/oas/v3.0.4.html#schema-object)
subset; OpenAPI extensions remain annotations unless a separately supported
extension contract says otherwise.

`Project.ValidateJSON` is intentionally native-only. The complete Go boundary is
`Project.DecodeAndValidateJSON`: it first runs `ValidateJSON`, decodes the
checked JSON wire shape directly from `schemajson.Node` (never through
`float64`), and returns the editable root's three-state refinement report.
Missing required properties, malformed explicit scalar encodings, unknown union
tags, and other wire/type mismatches are `native.decode` errors. Optional record
properties become explicit `Nothing`; present ones become `Just`. Nullable
values, preserved extras, rational records, named scalar encodings, and explicit
union discriminators are decoded according to checked `WireMetadata`. Avro has
a distinct binary representation and is rejected by this JSON API.

Native OpenAPI operation composition is opt-in and versioned separately from
the pure Refine operation facade. `openapi.Schema.Native` uses
`refine.openapi.native/v1`; when absent, the existing operation facade validates
only already-decoded Refine request and response records. When present, project
compilation reconciles every operation, response, parameter, header, media type,
Schema Object location, and checked field path against the validated OpenAPI
document. `Project.OpenAPIOperationIndex` returns immutable stable part IDs,
their proven resource/pointer selectors and the canonical offline resource
closure. Operation Schema Objects are explicit seeds for OpenAPI 3.0 adaptation,
dialect checks, and regex keyword discovery. Examples and defaults are never
scanned as schemas.

`Project.WithDerivedOpenAPIOperations` is an explicit, immutable convenience for
ordinary `/paths` operations whose semantic JSON shape is unambiguous. It
derives deterministic request and response record declarations, records every
inferred field path and JSON media type in the versioned bindings, and then runs
the same full metadata/index checks as authored bindings. Native constraints are
not converted into unconditional `where` clauses: their original resource and
Schema Object pointer remain authoritative and run first. Existing wire metadata
is retained, including explicit per-record extra-field policies; derived records
use the normal discard-by-default JSON policy. No response context predicate is
invented.

The helper fails closed for missing operation IDs when deriving all operations,
ambiguous or non-JSON media, non-default parameter serialization, parameter
`content`, field-name collisions, and structural schema applicators that lack a
single safe language type. Structural projection follows inline schemas and
local named definitions in the Schema Object's containing explicit resource;
cross-resource Schema Object `$ref` projection remains an authored-source case,
even though the native validator continues to resolve and enforce such bundled
references. An explicit operation-ID selection may intentionally bind a subset.
Callback operations and webhooks remain outside this helper. Operations-only
OpenAPI projects need no `/components/schemas/...` payload root: direct ingest
derives checked source and authoritative bindings, while annotation/configured
source may supply complete bindings. Root-only APIs such as `PayloadType` and
`ValidateJSON` reject these projects; operation request/response boundaries use
the entry-resource target instead.

For OpenAPI 3.0, a required `readOnly` property is response-only and a required
`writeOnly` property is request-only. Checked operation compilation creates
separate immutable request and response resource views, removing only the
inapplicable name from each affected `required` list. The original resources,
property schemas, and supplied values remain unchanged: a wrong-direction
property is still validated when present because OpenAPI says it SHOULD NOT be
sent rather than forbidding it. Derived record fields use `Maybe`; authored
mandatory fields are rejected when they would restore the removed requirement.
Direction annotations distributed ambiguously across schema applicators fail
closed. Constructing the additional OpenAPI 3.0 mutable resource view is
preflighted at 64 MiB and 65,536 aggregate JSON values before the second tree is
allocated; these are schema-view construction limits, not payload limits.
OpenAPI 3.1/3.2 resources remain canonical and unchanged; no comparable
annotation-based direction policy is claimed for those versions.

`DecodeAndValidateOpenAPIRequest` and `DecodeAndValidateOpenAPIResponse` accept
semantic JSON values, enforce each native Schema Object first, assemble and
decode the checked request/response record, and then run Refine validation.
Exact status has precedence over class status and `default`. Header names are
case-insensitive; path, query, and cookie names are case-sensitive. Duplicate,
missing-required, unexpected, null-invalid, and media-mismatched parts are
native payload failures. Aggregate part, byte, depth, and node limits are
caller-tightenable below fixed hard caps; exhaustion remains `native.limit`.
A request token is issued only after a completely valid request report. Context
validation rejects foreign, stale, or wrong-operation tokens, while an absent
token produces the same explicit indeterminate request-context diagnostic as
the pure facade. These APIs do not parse HTTP URI, query, cookie, or header
encodings: callers must supply semantic JSON values. Non-default parameter
serialization styles, parameter `content`, ambiguous media types, and non-JSON
body media are rejected during project compilation rather than guessed.

`java.GenerateProjectOpenAPIContext` consumes this immutable index and composes
native validation, structural JSON decoding, and request/response/context
refinements. Project generation selects this facade for checked native bindings,
including operations-only projects; it does not substitute the Refine-only
facade. See [OPENAPI-CONTEXT.md](OPENAPI-CONTEXT.md) and
[GENERATED-TESTS.md](GENERATED-TESTS.md) for the execution and test boundaries.

Generated language-only validators report `GeneratedEnforcement().Supported ==
false`. `java.GenerateProjectJSONSerde` is the narrower composed path. It emits
an offline networknt validator and invokes it on
reads before model construction and on staged writes before bytes reach the
caller's generator. Jackson decoding/model construction then runs the editable
Refine rules. The module constructor accepts native JSON resource limits; there
is no implicit native-validation bypass. Its numeric-expansion limit is checked
over the whole request before Jackson or networknt materializes exact numbers.
Standalone `GenerateJSONSerde` remains language-only and makes no
native-sidecar claim.

Native JSON Schema and OpenAPI `pattern`/`patternProperties` use one checked
ECMA-262 2020 Unicode engine in both hosts. The embedded WebAssembly guest is
built reproducibly from QuickJS-NG 0.15.1 plus regexpp 4.12.2, has a fixed
SHA-256, a declared 32 MiB maximum memory, and imports only
`refine.should_interrupt(i32)`. Go executes it through wazero 1.12.0; generated
Java 25 executes the identical bytes through Chicory 1.7.5. Pattern and subject
text cross the ABI as exact little-endian UTF-16 code units. This admits
`Script=Greek`, lookaround, named backreferences, astral escapes, and escaped
lone-surrogate pattern units without relying on a host regex translation.
Ordinary JSON payload decoding still rejects unpaired UTF-16 before matching.

Each validation owns fresh request state and an aggregate request budget.
Initialized guest sessions may be reused from a fixed bounded pool only after
the guest releases every compiled handle, clears request failure/interrupt
state, runs GC, and returns to its exact post-warmup allocation watermark. A
cleaned session that cannot prove that watermark is discarded without changing
the completed validation outcome; timeout, OOM, trap, cancellation, dirty reset,
or cleanup failure also prevents reuse. Fixed guest initialization uses only a
trusted built-in Unicode pattern and has a hard 10-second/one-million-poll
deployment ceiling;
checked-pattern compilation has a separate caller-tightenable aggregate
10-second/one-million-poll ceiling; matching retains the caller-tightenable
one-second deadline, one-million polls, pattern/input UTF-16 limits, handle and
evaluation counts, and aggregate charged work. None of these limits resets for
another pattern or match in the same request. Waiting for a cached schema's
single request slot is charged to the appropriate aggregate deadline. All
guest allocation and release paths are bounded; a trapped request is disposed
and never reused. The four-session Go pool and each generated Java scope bound
retained memory and acquisition. Go deducts blocking acquisition from the
compilation budget; Java deducts it from the selected construction or validation
request budget. Syntax failure is a schema error. Queue, initialization,
compilation, matching, memory, or work exhaustion is a resource/indeterminate
outcome and is never converted into false inside `not`, `anyOf`, or another
combinator. Internal/trap failures are enforcement outcomes. There is no retry.

The guest exposes no general JavaScript evaluation API, WASI import,
filesystem, network, clock, random, environment, process, native, or host-class
capability. Generated helpers verify the guest size and digest before parsing
it. They preserve the no-argument and native-`Limits` constructors and also
accept `(Limits, RegexLimits)` or `(CodecLimits, Limits, RegexLimits)` so callers
can tighten the payload and compilation boundaries. A regex-bearing generated
project automatically packages the content-addressed `.wasm`, build manifest,
and complete upstream notices as classpath resources and adds pinned Chicory
dependencies. Schemas without reachable regex keywords emit no Chicory class
reference, regex resource, or optional dependency.

Schema keyword and dialect scans traverse only real Schema Object positions and
follow bundled JSON Pointer references. A payload property named `pattern` or
`$schema`, or the same spelling inside `examples`/`default`, is ordinary data and
does not affect the schema scan. OpenAPI roots must select a Schema Object under
`/components/schemas`; arbitrary example/default objects cannot be promoted to
payload schemas.

`WithEditedSource` replaces the complete single-module source, not merely the
root declaration. A provenance unit is linked to that module only when every
corresponding declaration is present and canonically unchanged according to the
checked AST; matching text in a comment or string grants no edit authority. To
add a root refinement while retaining linked native units, edit the existing
`EditableSource` rather than replacing it with a root-only module.
`WithEditedSources` uses `language.CompileSources` to resolve reusable language
imports only from the supplied bounded source map. `PayloadType` exposes the
checked root to Java and other generators.

`Project.Bundle` emits one versioned JSON distribution containing the exact text
of every native resource and its URI, the payload-root or operations-entry target,
editable source, original language import graph where present, and wire metadata.
Rooted projects retain the version-1 root form. Operations-only projects use a
version-2 target and must carry complete authoritative native operation bindings;
`ParseBundle` never silently rederives missing bindings from bundled resources.
It revalidates native resources, rebuilds and checks the language graph, verifies
its flattened source, restores explicit per-resource native constraint-unit
edits, and rechecks metadata. Bundle JSON duplicate keys are rejected.

`Project.Export(LowerOptions)` emits an immutable same-format `ProjectExport`.
The result retains resource URI/order, its payload-root or operations-entry
target, metadata, the exact
resource-scoped native constraint sources, complete English companion text, and
an explicit loss list. JSON Schema exports start from the
effective provenance-aware resources; opaque and untouched native keywords are
retained. JSON Schema and OpenAPI 3.1/3.2 conjunctively embed exactly lowerable
root rules in a collision-isolated embedded schema. Refined exports also embed
the checked source and checked wire metadata as `x-refine`; re-ingestion restores
that metadata and rejects a conflicting caller override. OpenAPI 3.0 and Avro
retain their native schema and embed Refine source/documentation without
claiming unsupported ordinary assertions. Because the edited payload structure
is not composed on those paths, they always report an explicit structural loss;
ordinary exports require `AllowDocumentedLoss`. An Avro union root is rejected because adding properties would
change its wire schema. Cross-format conversion remains a separate,
fail-closed `LowerPayload` operation and never silently consumes a project's
opaque native sidecar.

## Wire metadata

`WireMetadata` is checked against the editable module and deep-copied at every
boundary:

- `ExtraFields` maps record type names to `discard`, `preserve`, or `reject`;
- `Scalars` maps named scalar types to an explicit `json-number`,
  `decimal-string`, `rational-record`, `avro-bytes-decimal`, or
  `timestamp-string` representation. JSON numbers require integer backing,
  decimal strings are canonical base-10 integer strings (including a single
  `0` spelling and no negative zero), rational records
  require `Real`, timestamp strings require `Timestamp`, and
  Avro decimal precision/scale are validated;
- `Discriminators` maps a tagged-union type to its explicit member name, unique
  constructor wire values, and ordered JSON member names for every positional
  constructor argument. Coverage and arity must be exact; names may not collide
  with the discriminator;
- `PublicationNamespace` is a dot-separated logical namespace.
- `NumericExpansion` is the aggregate exact-number expansion budget for one
  payload. Zero selects 65,536; explicit values are checked and capped at
  1,000,000. Go JSON native validation, Avro exact scalar decoding, and generated
  Java native validation use the same metadata value.

The APIs never derive discriminator fields, constructor argument names, numeric
rounding, timestamp conversion, or unknown-field preservation from naming
conventions. Missing policy remains an explicit generation error for consumers
that require it.

Record wire policies are per nominal occurrence. The default and explicit
`discard` accept undeclared JSON members and omit them from the decoded record;
`preserve` retains them; `reject` refuses them before omission. Only `reject`
closes an ordinary JSON Schema/OpenAPI record with `additionalProperties:false`.
The native sidecar still runs first: a permissive wire policy cannot weaken an
imported schema that already forbids extra members.

Policies compose along one transparent alias/application chain until its first
record. Equal explicit modes coalesce; conflicting modes reject instead of
silently choosing one. With `type IntBox = Box Int`, a policy on `IntBox` does
not change separate `Box Int` or `Box String` occurrences. Nested fields,
anonymous records, and recursive occurrences independently select their own
policy. Bounded lexical argument resolution supports closed generic aliases
without rewriting the metadata map. An alias-local reject schema keeps the
original reference and adds a local closed-record overlay rather than mutating
the shared generic definition. Java decoding and normal or explicit-bypass
serialization enforce the same policy before emitting bytes. Language-only
in-memory record validation remains permissive; these are checked wire policies.
Avro does not accept JSON extra-field metadata.

`LowerPayloadWithMetadata` applies these checked scalar encodings. JSON rational
records use arbitrary-size integer numerator and positive denominator fields.
Avro rational records document and tag minimal signed two's-complement big-endian
byte encodings (with zero as `0x00`) for both integers. Timestamp strings document
that RFC 3339 spelling and offset are preserved. Avro decimal encodings always
carry explicit precision and scale; codecs must reject non-representable values
instead of rounding them implicitly.

For JSON Schema and OpenAPI, the same lowering API applies named-record
extra-field policy and emits tagged unions as `oneOf` object variants with the
declared discriminator member, exact constructor wire value, and ordered member
names for positional arguments. OpenAPI additionally receives its discriminator
metadata. Avro lowering rejects these JSON object policies explicitly instead of
ignoring them. Publication namespace is generator metadata and is not silently
injected into a native schema.
