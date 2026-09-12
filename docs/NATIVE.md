# Native schema ingestion and lowering

The `native` package is the validated, immutable boundary for JSON Schema,
Avro, and OpenAPI. Its complete Go boundaries decode and validate JSON and Avro
payloads, but it does not perform compatibility analysis or schema evolution.
It can bundle caller-supplied resources, but never fetches resources itself.

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
and the JSON Schema compiler is not given a URL loader. Consequently an
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

JSON Schema numeric-bound correspondences delegate to the existing `provenance`
package. There is one identity and recovery check per native keyword. Editing one
canonical constraint does not invalidate an untouched constraint. Avro and
OpenAPI provenance adapters are not implemented and return an explicit
`native.provenance` error rather than an empty success.

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

The currently recognized locations are schema positions in JSON Schema, schema
positions in Avro, and the OpenAPI root object. Objects carried in examples,
defaults, arbitrary extension payloads, and documentation are not executed or
mistaken for declarations. Per-OpenAPI-object annotations are a stated gap.

## Checked type lowering

`LowerPayload(format, payloadType, options)` accepts only a
`language.PayloadType`, so unchecked ASTs cannot reach a backend. Generated bytes
are ingested through the same native validator before they are returned.

Implemented JSON Schema Draft 2020-12 and OpenAPI 3.1/3.2 mappings include:

- `Int`, `IntN`, `UIntN`, `String`, and `Bool`;
- lists, records, required fields, `Maybe` record-field absence, and `Nullable`;
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
records, `Nullable` unions, aliases, closed generic record applications, and
recursive named records. Closed applications use simultaneous substitution, so
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
provenance, OpenAPI 3.0 lowering, and Avro JSON encoding.
The package reports these as errors and does not narrow, round, add discriminators,
turn absence into null/default, or strip constraints silently.

## Editable native projects and bundles

`IngestProject` combines one validated native document with a required
`ResourceSelector` and produces checked editable source. `IngestProjectResources`
does the same for an ordered, explicit resource set. Resource IDs must be
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
  required/optional fields, nullable forms, named definitions, and local refs;
- Avro primitives, arrays, records, enums, fixed byte sequences, nullable and
  general unions, named references, and ordered fields/branches;
- root-level external JSON Schema/OpenAPI reference chains whose fragments are
  JSON Pointers, and ordered Avro dependency schemas.

Projection deliberately requires enough native structure to choose a language
type. It does not infer a type from `minimum`, `properties`, or another keyword;
does not turn Boolean schemas into a guessed payload type; and rejects tuples,
maps, anchor-based root refs, unsupported field identifiers, and nested external
refs that it cannot yet express. Those errors are `native.projection`, not a
silent broadening.

Native constraints remain authoritative in the immutable sidecar. For JSON
Schema, each resource has independently scoped `NativeConstraints`,
`ResourceConstraintSource`, `AuditResourceSource`, and
`RecoverResourceNative` operations. Constraint declaration names are scoped by
resource; callers must not concatenate colliding resource projections. Numeric
rules under `not`, `allOf`, conditionals, or other applicators are emitted only
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
numeric scope and lower to exactly one native numeric assertion at its original
Schema Object position; unsupported scoped edits fail `native.enforcement`
instead of leaving the stale original constraint active. Arbitrary refinements
should be added to the payload type until scoped evaluation under native
applicators is implemented.
`Project.ValidateAvroBinary` validates exactly one binary datum against the
selected writer schema and its ordered named dependencies. Its independent byte
cursor enforces exact EOF, Boolean/int/enum/union encodings, declared collection
block sizes, duplicate map keys, UTF-8, decimal precision, UUID text, time-of-day
ranges, and caller-bounded bytes, depth, values, and string/bytes sizes. Avro
1.12 nanos timestamps retain their exact signed `long`; unknown or invalid
logical types use their underlying type as the Avro specification requires.
The known `big-decimal` logical type remains explicitly gated with
`native.enforcement` until its value-carried scale encoding is implemented.
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

If a reachable native Schema Object uses `pattern` or `patternProperties`, the
validator conditionally emits a GraalJS Community 25.0.1 adapter configured for
ECMA-262 2020 Unicode regular expressions. Native ingestion's regexp2 syntax
oracle still rejects some valid ECMA-262 Unicode-property spellings before Java
generation; the Graal adapter does not erase that documented native limitation.
Non-regex validators contain no Graal class
reference and retain their smaller runtime closure. A regex validator exposes
separate tighten-only `RegexLimits` for pattern and subject UTF-16 units,
evaluation count, aggregate charged units, and the whole schema-evaluation
deadline. It creates one isolated context and one request-owned virtual
watchdog per validation; the watchdog inherits neither thread-local state nor
the caller's context class loader, and is interrupted during request cleanup.
GraalVM documents that
[`Context.close(true)`](https://www.graalvm.org/sdk/javadoc/org/graalvm/polyglot/Context.html#close(boolean))
may cancel a context executing on another thread. Timeout, cancellation, and budget
exhaustion are `RESOURCE_LIMIT`/indeterminate outcomes; combinators never see
them as ordinary false matches. The context denies host access, class lookup,
IO, environment, processes, native access, polyglot access, value sharing, and
guest-created threads. The composed Jackson module preserves its no-argument
and native-`Limits` constructors and additionally accepts `(Limits,
RegexLimits)` or `(CodecLimits, Limits, RegexLimits)` when regex support is
present, so callers can tighten every boundary without constructing a sidecar.
The shared Graal engine lives for the generated helper's class lifetime.
Missing or incompatible Graal deployment artifacts and static engine
initialization failures are fatal deployment errors, not payload-validation
outcomes.

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
of every native resource and its URI, root selector, editable source, original
language import graph where present, and wire metadata. `ParseBundle` revalidates
native resources, rebuilds and checks the language graph, verifies its flattened
source, restores explicit per-resource native constraint-unit edits, and
rechecks metadata. Bundle JSON duplicate keys are rejected.

`Project.Export(LowerOptions)` emits an immutable same-format `ProjectExport`.
The result retains resource URI/order, root selector, metadata, the exact
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

- `ExtraFields` maps record type names to `discard` or `preserve`;
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
