# Validated Apache Avro serde

`java.GenerateProjectAvroSerde` emits the shared semantic models and a direct
Apache Avro 1.12 adapter for a checked native Avro project. The adapter supports
both Avro binary encoding and Avro's JSON encoding. It embeds the project's exact
reader schema resources; reads accept an explicit writer `Schema` and use
`GenericDatumReader(writer, reader)`, so aliases and reader defaults are applied
before conversion to language `Data` and refinement validation.

Normal writes validate first, construct and structurally check the complete
generic Avro datum, and encode into a private byte buffer. The `OutputStream`
overload publishes those staged bytes only after validation, exact
representability checks, Avro encoding, and the output-byte limit all succeed.
Normal reads and writes accept caller validation and codec limits.
`withoutRefinementValidation` is the explicit bypass: it still enforces model
structure, schema representability, input/output size, traversal limits, logical
types, UTF-8, and trailing-data rejection.

`acceptsNativeCandidate(Data)` is the property-generation prefilter. It checks
only structural Avro representability and logical wire constraints, without
evaluating Refine predicates. A structurally unrepresentable candidate returns
false; codec resource limits and unexpected enforcement failures propagate, so
bounded or indeterminate checks cannot be mistaken for schema rejection.

The adapter supports records (including recursive records), arrays, maps, `int`,
`long`, `float`, `double`, `string`, `boolean`, bytes, fixed, enums, two-branch
nullable unions, and native-projected named unions. Avro floating values become
their exact binary rational values; non-finite inputs and writes that would need
rounding are rejected. General union constructors are paired to the reader
schema by branch order during generation and registered by schema object
identity at runtime, so branches are not guessed from JSON labels or collapsed
after decode. Enum constructors are similarly paired with exact wire symbols.
Avro maps correspond only to `Map String a`. Keys are decoded as exact strings,
duplicate decoded keys are rejected, semantic maps use canonical UTF-16 key
order, and binary/JSON writes reject unpaired surrogate keys before output.

Explicit native scalar metadata supports canonical decimal strings for
arbitrary `Int`, exact RFC 3339 strings for `Timestamp`, reduced rational records
whose integer components use minimal signed two's-complement bytes, and Avro
bytes/fixed decimal for `Real`. Decimal writes reject values requiring rounding
or exceeding precision. Logical UUID, time-of-day, and decimal constraints are
checked; standard date/timestamp integer logical types retain their exact Avro
integer representation. Avro 1.12 `big-decimal` is supported only as its native
physical `[UInt8]` value: an outer Avro `bytes` datum containing a nested Avro
`bytes` two's-complement unscaled integer followed by a signed 32-bit Avro
`int` scale. The nested value must contain exactly those two fields, the
unscaled byte sequence must be nonempty, and all lengths and varints remain
bounded. Legal redundant sign-extension bytes and negative scales are preserved
exactly. This does not imply a fixed scale, precision, canonical byte spelling,
or a mapping to semantic `Real`; those still require an explicit representable
wire policy.

Binary input is schema-walked before Apache Avro decoding. This bounds declared
lengths and collection blocks before allocation, validates UTF-8 and the entire
writer datum (including fields reader resolution will discard), and requires
exactly one datum. The resolved datum is independently bounded and validated.
Avro JSON is pre-scanned with duplicate detection and byte, depth, node, and
single-root limits, then decoded once against the writer for whole-datum checks
and again with writer-to-reader resolution. Embedded schema strings are split
into runtime-joined chunks so a large resource cannot exceed the JVM constant
pool UTF-8 entry limit.

Generated production code uses `org.apache.avro:avro:1.12.0`. The focused gate
pins Avro's Jackson 2.17.2, Commons Compress 1.26.2 dependency closure, and SLF4J
2.0.13 jars by SHA-256. Jackson 2 is an Avro implementation dependency and can
coexist with the separately generated Jackson 3 adapter, whose packages are
`tools.jackson.*`.

Remaining unsupported representations include semantic `Real` coercion for
`big-decimal`, open generic roots,
and edited union declarations
that do not retain the native projection's one-value-per-branch shape. Unknown
logical types follow their underlying supported Avro representation, consistent
with Avro 1.12. This generator does not replace native schema validation;
callers that accept untrusted native payloads should keep the checked native
project and its `ValidateAvroBinary` boundary alongside generated Java
validation.
