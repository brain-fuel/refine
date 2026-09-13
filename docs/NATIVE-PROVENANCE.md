# Native constraint provenance

The `provenance` package implements exact native-constraint projection and
recovery units, not complete native-schema validation. The separate `native`
package supplies ingestion, ordinary/Refined export and schema/payload validation;
see [NATIVE.md](NATIVE.md). The original document is not replaced by these units.

## Current API

```go
projection, err := provenance.DiscoverJSONSchema(
    []byte(`{"type":"integer","minimum":0,"maximum":100}`),
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
// Both findings are Unchanged. Each constraint records its native JSON Pointer,
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

## Exact supported correspondences

Discovery currently covers `minimum`, `maximum`, `exclusiveMinimum`,
`exclusiveMaximum` and `multipleOf` on a schema with an explicit local `integer` or `number`
type (including a singleton type array). Its traversal recognizes Draft 2020-12
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

The formatter adds explicit grouping. Exact division is a domain conversion,
not rounding. In particular, importing an integer's fractional minimum does not
replace the native bound with its ceiling. Native spellings `0`, `0.00`, and
`0e0` remain separately recoverable.
`multipleOf` tests exact integral quotients, so `0.3` is a multiple of `0.1`
without floating-point tolerance. Nonpositive divisors are rejected lexically
without expanding arbitrarily large exponents during discovery.

A numeric keyword alone does not imply numeric type: natively it does not reject
nonnumeric instances. Discovery therefore does not invent `Int` for an untyped
bound or a nullable/heterogeneous type union. Nor does it translate native
`minLength` into UTF-16 `length`, or native `pattern` into the RE2 refinement
predicate. These native clauses stay intact pending exact adapters.

The context pointer matters. A bound under `not`, `if`, `anyOf`, or a property
schema is a **local unit**, never an unconditional predicate on the document's
root payload. Full contract assembly must preserve those applicator semantics.
Generated `Native_<hash>` declaration names are stable internal unit identities,
not final user-facing Java names or a complete schema type model.

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
breaks `multipleOf` recovery, while unrelated minimum/maximum rules stay intact.

`RecoverNative` refuses to return a native token for a changed/removed unit, while
still recovering untouched units. It does not guess an inverse for arbitrary
new predicates. The native project exporter separately lowers supported
representable edits and explains unrepresentable refinements; this package never
silently exports the old constraint in place of an edited rule.

## Evidence and remaining work

Tests cover canonical token recovery, both directions of the number/domain
mapping, deviation isolation, added rules, native metadata/context retention,
duplicate-key rejection, immutable/concurrent reuse, and fuzzed projection
round trips. A pinned independent Draft 2020-12 validator verifies 1,000 generated
numeric-bound cases against the executable refinement clauses.

Remaining provenance work includes additional keyword adapters,
inferred/intersected type domains, scalar-Unicode-independent subschema-key
provenance and OpenAPI/Avro per-constraint adapters. The native package already
provides explicit-resource reference resolution, bundles, editable projection,
native output and English generation within its documented boundaries; their
existence does not broaden this package's numeric correspondence guarantee.
Custom/older `$schema` dialects are
explicitly unsupported in this discovery entry point; they are not silently
interpreted as Draft 2020-12. No full native-ingestion gate is checked off here.
