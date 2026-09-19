# Native constraint provenance

The `provenance` package implements exact native-constraint projection and
recovery units, not complete native-schema validation. The separate `native`
package supplies ingestion, ordinary/Refined export and schema/payload validation;
see [NATIVE.md](NATIVE.md). The original document is not replaced by these units.

## Current API

```go
projection, err := provenance.DiscoverJSONSchema(
    []byte(`{"type":"integer","minimum":0,"maximum":100,"const":50}`),
    schemajson.Limits{},
)
if err != nil {
    panic(err)
}
source := projection.ConstraintSource()
constraints := projection.Constraints()
findings, err := projection.AuditSource(source)
if err != nil {
    panic(err)
}
// All findings are Unchanged. Each constraint records its native JSON Pointer,
// schema-context pointer, exact native token, scope, predicate and fingerprint.
nativeMinimum, err := projection.RecoverNative(constraints[0].Name, source)
// nativeMinimum == "0". Errors are explicit if that canonical clause was edited.
_ = findings
_ = nativeMinimum
_ = err
```

Import paths are `goforge.dev/refine/provenance` and
`goforge.dev/refine/schemajson`. `Original()` retains the entire input document
byte-for-byte, including unsupported clauses, references and unknown metadata.
It returns the **original** document, not an export of subsequent source edits.
The returned constraint/finding slices cannot mutate the stored provenance.

`DiscoverAvro(input, limits)` exposes the same single-document discovery,
audit and exact-recovery operations for fixed `size` and ordered enum `symbols`.
Fixed size maps to `[UInt8] where length it == N`; enum symbols map to one
atomic `String where oneOf it ["A", "B"]` clause. Keeping the symbols together
preserves their wire-significant order. The original JSON token, including
escape spelling, is recovered only while its canonical clause remains intact.
`LowerAvroConstraint(program, constraint)` is a separate structural inverse for
edited units: it returns an updated JSON token, not the original token or a
claim of logical equivalence. Keyword-derived scope/builtin checks reject
shadowing, and attempted fixed-number expansion is bounded in aggregate.
Only actual Avro schema positions are traversed; defaults, docs and custom
metadata remain opaque. This API does not itself validate a complete schema.

Avro projects install these units per resource. `Resources()` retains the exact
baseline, while `EffectiveResources()` supplies the checked edited schema to
native binary/JSON validation, default checking, export and generated Java
serde. Enum constructor order and native symbol order must agree. Auto-projected
source can change its linked canonical unit and constructors together;
annotated source with separate units uses
`WithEditedSourceAndNativeConstraintSources(source, edits)` for that atomic
transition. Bundles restore the source/import graph and explicit units in one
validation. Removing required native attributes or adding unsupported scoped
rules rejects the edit; independent refinements on payload types remain allowed.

OpenAPI 3.1/3.2 discovery uses explicit, in-memory resources:

```go
projection, err := provenance.DiscoverOpenAPI(
    []provenance.OpenAPIResource{
        {
            URI:    "https://example.test/openapi.yaml",
            Source: openAPIBytes,
            Syntax: provenance.OpenAPIYAML,
            Role:   provenance.OpenAPIDocument,
        },
        {
            URI:    "https://example.test/parts.json",
            Source: partsBytes,
            Syntax: provenance.OpenAPIJSON,
            Role:   provenance.OpenAPIFragment,
        },
    },
    provenance.OpenAPIOptions{
        EntryResource: "https://example.test/openapi.yaml",
        Limits:        schemajson.Limits{},
    },
)
```

Syntax and role are never inferred. A `document` is an OpenAPI document, a
`schema` is an explicitly rooted standalone Schema Object, and a `fragment`
is loaded only as a target of a typed OpenAPI or Schema Object reference.
Fragments are not guessed to be schemas merely because their JSON/YAML happens
to look schema-like. Every URI must be absolute and fragment-free. Discovery
performs no filesystem or network access.

`DiscoverOpenAPIIndexed(resources, options, locations)` is the lower-level
lexical discovery API for embedders that already have a complete, checked
Schema Object catalog. Each location supplies its physical resource, pointer,
and effective dialect. It does not resolve references or establish that a
location is a Schema Object. Native OpenAPI 3.1/3.2 projects obtain those
locations from the same logical-ID/anchor catalog used by validation, then
discover exact tokens in the original JSON/YAML resources. This avoids a
second, inconsistent reference resolver and preserves physical provenance
through validation-only relocation. Missing/conflicting locations and
aggregate work/path-limit failures reject instead of silently erasing units.

OpenAPI constraints record both the resource URI and JSON Pointer. Identity is
framed over both, so the same pointer in two resources cannot collide. Returned
resource bytes are defensive copies. The default aggregate resource-byte,
per-resource parse, aggregate traversal, 1,024-resource, 100,000-reference and
generated-source ceilings apply before projection; caller limits may tighten
the byte, depth and node ceilings.

OpenAPI traversal is schema-position aware. It covers component schemas,
parameters, headers, request bodies, responses, callbacks and path items;
path/operation parameters; request/response media types and headers; callbacks
and webhooks; and Schema Objects reached through explicit references. For
OpenAPI 3.2 it additionally covers reusable component media types,
`itemSchema`, `prefixEncoding`, `itemEncoding`, and nested Encoding Object
headers, plus Path Item `additionalOperations`. Annotation/example/default/extension values are never scanned as
schemas. Meaningful siblings of wrapper `$ref` values are rejected until exact
merge semantics are available rather than silently discarded, except OpenAPI
3.0 Reference Object siblings, which its specification requires ignoring.

JSON numeric tokens and JSON `const`/`enum` values use the same exact
correspondences described below. YAML numeric units retain their exact scalar
lexeme, including spellings such as `0x10`, `1_000`, and `.5`; normalization
uses exact integers/rationals and never `float64`. YAML columns are converted
from Unicode-character positions to UTF-8 byte offsets before slicing the
original input. Quoted/tagged values and YAML `const`/`enum` remain opaque;
anchors and aliases are rejected because they do not provide an unambiguous
owned lexical token.

The standalone `DiscoverOpenAPI` traversal supports local JSON Pointer
references and nested relative references across explicitly supplied resources.
A local `$id` changes the base and root for references within that schema.
In that standalone API, references to another schema's logical `$id`, anchors,
dynamic anchors and dynamic references fail explicitly; they are never guessed
from physical resource URIs or declaration order. Native OpenAPI projects do
not use that incomplete resolver: their checked catalog handles logical IDs and
anchors, and `DiscoverOpenAPIIndexed` recovers provenance at the catalog's
physical Schema Object locations.

OpenAPI 3.0 numeric bounds are separate atomic pairs: `minimum` with its
Boolean `exclusiveMinimum`, and `maximum` with its Boolean `exclusiveMaximum`.
Each pair becomes one canonical comparison. `Constraint.Native` retains the
number token; `PairedKeyword` and `PairedNative` retain the exclusivity member
and its exact token (empty when omitted). Changing the bound or strictness
invalidates only that pair's recovery guarantee. The opposite bound remains
independent. Changed units lower atomically to a number plus Boolean, preserving
omitted versus explicit false when possible; switching a lower bound into an
upper bound rejects. An orphan exclusivity Boolean has no assertion to project.
Ignored Reference Object siblings never acquire editable constraint authority.

OpenAPI 3.0 collection counts use the same exact units as Draft 2020-12.
They require an explicit array/object type and `nullable` absent or false;
`nullable: true` extends the instance domain beyond the collection scope and
therefore remains opaque. Exact JSON/YAML integer spellings are retained.

OpenAPI 3.0 JSON-source `enum` uses the ordered intrinsic-JSON membership unit.
`nullable` does not weaken `enum`: null is accepted only when the explicit type
is nullable and the enum itself contains null. The exact native enum array is
retained. OpenAPI 3.0 `const` and YAML `enum`/`const` are not claimed by this
adapter.

`native.Project` integrates this exact subset after the complete native OpenAPI
resource closure has already been validated. Each projected resource receives
its own canonical constraint source. Edits are applied at the recorded Schema
Object pointer to a private canonical-JSON view used by payload validation,
operation indexes, generated consumers and export. `Project.Resources()` still
returns the exact immutable original JSON/YAML bytes. Rootless operation bundles
carry the resource-scoped unit sources explicitly and rebuild their checked
operation index while loading.

Discovery is deliberately best-effort at this integration boundary. A valid
supported OpenAPI document containing an unsupported
provenance dialect/reference/lexical construct, or a resource set over the
projection limits remains a valid native project with opaque constraints and no
claimed editable bijection. Native validation remains authoritative for those
constraints.

## Exact supported correspondences

Discovery covers `minimum`, `maximum`, `exclusiveMinimum`,
`exclusiveMaximum` and `multipleOf` on a schema with an explicit local `integer` or `number`
type (including a singleton type array). It also covers Draft 2020-12 `const`
and `enum` over the intrinsic `JSON` algebra without inventing a scalar type.
Its traversal recognizes Draft 2020-12
subschema positions, including `$defs`, property/schema maps, array applicators,
conditional branches and negation. It does not mistake objects in `examples`,
`default`, `const`, or extension metadata for schemas.

Canonical expressions retain native number spelling and exact numeric domains:

| Native constraint | Scope | Canonical predicate |
| --- | --- | --- |
| integer, minimum 0 | Int | `it >= 0` |
| integer, minimum 1.1 | Int | `it / 1 >= 1.1` |
| number, minimum 1 | Real | `it >= (1 / 1)` |
| number, maximum 1e+20 | Real | `it <= 1e+20` |
| integer, multipleOf 1.5 | Int | `isInteger ((it / 1) / 1.5)` |
| number, multipleOf 0.1 | Real | `isInteger (it / 0.1)` |
| array, minItems 2 | `[JSON]` | `length it >= 2` |
| array, maxItems 10 | `[JSON]` | `length it <= 10` |
| object, minProperties 1 | `Map String JSON` | `size it >= 1` |
| object, maxProperties 20 | `Map String JSON` | `size it <= 20` |
| const 1 | JSON | `(it == (JSONNumber (1 / 1)))` |
| const {"a": [true]} | JSON | `(it == (JSONObject map {"a" = (JSONArray [(JSONBoolean True)])}))` |
| enum [null, "x"] | JSON | `((oneOf it) [JSONNull, (JSONString "x")])` |

The formatter adds explicit grouping. Exact division is a domain conversion,
not rounding. In particular, importing an integer's fractional minimum does not
replace the native bound with its ceiling. Native spellings `0`, `0.00`, and
`0e0` remain separately recoverable.
`multipleOf` tests exact integral quotients, so `0.3` is a multiple of `0.1`
without floating-point tolerance. Nonpositive divisors are rejected lexically
without expanding arbitrarily large exponents during discovery.

`minItems`/`maxItems` and `minProperties`/`maxProperties` are projected only
for an explicit singleton `array` or `object` type, respectively. Their bounds
must be nonnegative integer values. Integer-valued decimal/exponent spellings
normalize to an integer in the predicate while the exact original token remains
recoverable. Oversized exact-number expansion stays opaque. Shadowing `length`
or `size` invalidates the corresponding guarantee. String bounds use their own
`codePointLength` adapter because the ordinary `length` builtin measures UTF-16
units rather than native Unicode code points.

`const` and `enum` use JSON Schema equality exactly: numbers compare as exact
mathematical rationals (`1` equals `1.0`), array order is significant, object
member order is not, and strings are not Unicode-normalized. Empty enums and
duplicate enum values are retained: Draft 2020-12 recommends nonempty unique
values but does not require them. Canonical constructors are `JSONNull`,
`JSONBoolean`, `JSONNumber`, `JSONString`, `JSONArray`, and `JSONObject`.
The exact original const token or enum array remains in `Native` and is returned
by unchanged recovery, even when its spelling or object order differs from the
canonical refinement expression.

Projection has an aggregate one-million-expression-node ceiling, a 512-level
language-tree ceiling, 65,536 units of exact-number expansion, and a 16 MiB
generated constraint-module ceiling (tighter caller JSON limits still apply at
parse time). A const/enum value that cannot fit this bounded mapping remains an
opaque native constraint; it is not partially projected. Native JSON ingestion
continues to apply its own scalar-text and exact-number bounds, including the
existing rejection of isolated UTF-16 surrogates. These are provenance/source
materialization limits, not payload-validation limits.

A numeric keyword alone does not imply numeric type: natively it does not reject
nonnumeric instances. Discovery therefore does not invent `Int` for an untyped
bound or a nullable/heterogeneous type union. It also does not translate native
`pattern` into the RE2 refinement predicate. Unsupported native clauses stay
intact pending exact adapters.

The context pointer matters. A bound under `not`, `if`, `anyOf`, or a property
schema is a **local unit**, never an unconditional predicate on the document's
root payload. Full contract assembly must preserve those applicator semantics.
Generated `Native_<hash>` declaration names are stable internal unit identities,
not final user-facing Java names or a complete schema type model.

## Exact string length

`minLength` and `maxLength` project only for an explicit singleton `string`
domain. Their canonical units are `String where codePointLength it >= N` and
`String where codePointLength it <= N`. `codePointLength` counts a valid UTF-16
surrogate pair as one Unicode code point; it does not normalize text. Native
wire ingestion independently rejects unmatched surrogates, so no replacement
character can change the comparison.

Bounds must be nonnegative integer values. Integer-valued decimal and exponent
spellings normalize to the canonical integer predicate while unchanged recovery
returns the exact original JSON or accepted OpenAPI YAML scalar token. Discovery
uses the shared aggregate exact-number expansion budget. Untyped schemas,
mixed/nullable type unions, and OpenAPI 3.0 schemas with `nullable: true` remain
opaque. OpenAPI 3.0 requires `nullable` to be absent or exactly false.

Ordinary lowering and the checked edit inverse recognize only the structural
`codePointLength it >=/<= N` form with a bounded nonnegative integer literal.
Shadowing `codePointLength` invalidates only string-length authority. Changed
units may switch between the lower- and upper-bound keywords, but cannot cross
into numeric or collection-count families; removal deletes only its original
keyword. Effective resources drive validation, export, and bundles without
mutating the retained original.

## Exact array uniqueness

An explicit singleton array domain with `uniqueItems: true` has the canonical
detached unit `[JSON] where unique it`. Intrinsic JSON equality preserves exact
numeric value, array order, order-independent object members, and exact strings
without normalization. Go and generated Java are checked against native schema
validation for those equality cases. The original Boolean token is preserved,
including accepted YAML spelling. `uniqueItems: false`, untyped or mixed-kind
domains, and OpenAPI 3.0 nullable arrays remain opaque for this adapter.

The unit is not applied to a generally projected typed array: record decoding
can discard extra fields, and other wire policies can make different JSON
values become equal after decoding. The original native keyword still validates
the wire payload. The inverse recognizes only intrinsic `[JSON]` with the
unshadowed canonical `unique it` predicate. Removing the unit removes only
`uniqueItems`; arbitrary replacement predicates reject rather than silently
retaining stale authority. In particular, `not (unique it)` never means
`uniqueItems: false`.

## Adapter inventory boundary

`dependentRequired` is one atomic exact unit over the detached
`Map String JSON` domain for explicit singleton object schemas. Its canonical
predicate is a balanced conjunction of `if member "trigger" it then ... else
True` presence tests; names are ordered by decoded UTF-16 units. A property
whose value is null is present. Empty dependency lists remain explicit so their
native token can be recovered independently of logical simplification. Typed
records are not given this clause: discarding unknown fields would change its
meaning. Discovery covers Draft 2020-12 and OpenAPI 3.1/3.2 JSON resources;
OpenAPI YAML and 3.0 retain native validation without this editable unit.

`LowerDependentRequiredConstraint` recognizes only that bounded canonical form
with an unshadowed `member`. Changes replace the complete keyword; removal
deletes only it, preserving adjacent bounds and exact recovery of other units.
Ordinary lowering also recognizes the same clause on `Map String JSON`.
Native project edits rebuild effective validation, export and bundle views.
Discovery bounds source expansion before copies, uses a fixed aggregate
UTF-16 comparison-work ceiling for sorting, and leaves unrepresentable domains
opaque. It never converts an arbitrary user-defined presence function into
native schema authority.

| Category | Status | Exact boundary |
| --- | --- | --- |
| Numeric bounds and `multipleOf` | Implemented | Explicit singleton integer/number domains; OpenAPI 3.0 lower/upper bounds retain the paired exclusivity Boolean. |
| `minItems`/`maxItems`, `minProperties`/`maxProperties` | Implemented | Explicit singleton collection domains. OpenAPI 3.0 additionally requires `nullable` to be absent or false. |
| `minLength`/`maxLength` | Implemented | Explicit singleton string domain using Unicode-code-point `codePointLength`; OpenAPI 3.0 additionally requires `nullable` to be absent or false. |
| `const`/`enum` | Implemented subset | Draft 2020-12 and OpenAPI 3.1/3.2 JSON values support both. OpenAPI 3.0 supports JSON-source `enum` only. All values must fit the bounded intrinsic JSON algebra. |
| `uniqueItems: true` | Implemented | Detached explicit singleton array domain over intrinsic JSON equality. |
| Avro fixed size and enum symbols | Implemented | Atomic exact size and ordered-symbol units; remaining Avro defaults, aliases, order and logical-type parameters are structural/wire metadata, not interchangeable `where` clauses. |
| `dependentRequired` | Implemented subset | Detached explicit singleton object domain; Draft 2020-12 and OpenAPI 3.1/3.2 JSON only; whole-keyword token recovery and canonical presence inverse. |
| JSON-compatible YAML `const`/`enum` | Candidate exact adapters | Exact subtree lexical recovery is not yet implemented. These remain natively enforced without editable canonical units. |
| `required` | Structurally representable, no detached unit yet | Projected record presence is already checked. A separate editable unit would require atomic coordination with that structural source so removal cannot leave stale requiredness. |
| `pattern`, `patternProperties`, `format` | No general editable equivalence | Native regular expressions are ECMA-262 rather than the DSL's RE2 syntax; format assertion depends on dialect/runtime configuration. |
| `contains` families, `propertyNames`, `dependentSchemas`, `unevaluated*`, references and schema applicators | Native/structural preservation | General exactness requires subschema evaluation and, for unevaluated keywords, annotation state. JSON Schema `oneOf` is not the DSL membership function of the same name. |

This inventory does not turn a similarly named language function into native
authority. A new row moves to implemented only with semantic-oracle tests,
structural inverse recognition, builtin-shadow checks, per-unit edit isolation,
and effective validation/export/bundle evidence.

## Granularity and edits

Each unit has a stable path-derived name and a fingerprint of its dialect,
pointer, numeric scope, and exact native token. Changing a native minimum does
not change the maximum's fingerprint. Discovery and projection do not execute
predicates or load references from the filesystem/network.

`AuditSource` compiles a self-contained edited projection and checks each captured
declaration independently. Formatting/parenthesis changes preserve its canonical
form. Changing the predicate or its numeric scope breaks that unit's guarantee;
an arbitrary logically equivalent rewrite is deliberately not considered
canonical. Removing the declaration reports `Removed`. Adding other functions,
types, or `where` rules does not break untouched native correspondences.
Bindings are part of the correspondence: shadowing the `isInteger` builtin
breaks `multipleOf` recovery, shadowing `oneOf` breaks enum recovery, and
shadowing `length`, `size`, or `codePointLength` breaks the corresponding
collection- or string-count recovery, while unrelated units stay intact.

`RecoverNative` refuses to return a native token for a changed/removed unit, while
still recovering untouched units. It does not guess an inverse for arbitrary
new predicates. The native project exporter structurally recognizes only the
canonical intrinsic-JSON equality/membership forms (and the established numeric
forms); it never evaluates arbitrary user code to infer `const` or `enum`.
Edited units are deleted/replaced independently, so changing or removing const
does not discard an adjacent minimum. The native project exporter separately
lowers supported representable edits and explains unrepresentable refinements; this package never
silently exports the old constraint in place of an edited rule.

## Evidence and remaining work

Tests cover canonical token recovery, both directions of the number/domain
mapping, every intrinsic JSON constructor, exact rational/object/array/string
semantics, empty and duplicate enums, deviation isolation, builtin shadowing,
added rules, native metadata/context retention, duplicate-key rejection,
immutable/concurrent reuse, and fuzzed projection round trips. A pinned
independent Draft 2020-12 validator checks numeric-bound, collection-count and const/enum behavior
against executable refinement clauses.

Remaining provenance work includes additional keyword adapters,
inferred/intersected type domains, scalar-Unicode-independent subschema-key
provenance, standalone `DiscoverOpenAPI` logical-ID/anchor resolution, and Avro
adapters beyond fixed sizes and ordered enum symbols. Native OpenAPI 3.1/3.2
projects already use their shared checked catalog plus `DiscoverOpenAPIIndexed`
for logical-ID/anchor-aware validation and provenance. The native package also
provides explicit-resource reference resolution, bundles, editable projection,
native output and English generation within its documented boundaries; those
integrated capabilities do not broaden the standalone discovery API's
documented correspondence guarantee.
Custom/older `$schema` dialects are
explicitly unsupported in this discovery entry point; they are not silently
interpreted as Draft 2020-12. No full native-ingestion gate is checked off here.
