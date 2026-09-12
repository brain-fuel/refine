# Validated Jackson 3 JSON serde

`java.GenerateJSONSerde` emits the semantic models, validator/runtime, and a
Jackson 3 `SimpleModule` for one checked, closed root. The module is registered
through Jackson's ordinary builder API:

```go
files, err := java.GenerateJSONSerde(program, "com.example", "Contract",
    "SampleJacksonModule", java.JSONSerdeOptions{Root: "Sample"})
```

```java
var mapper = JsonMapper.builder()
    .addModule(new SampleJacksonModule())
    .build();
Sample value = mapper.readValue(json, Sample.class);
String json = mapper.writeValueAsString(value);
```

`GenerateProjectJSONSerde` is the native-project entry point. It takes the
checked root, publication namespace, per-record extra-field modes, discriminator
metadata, and scalar wire
encoding from `native.Project.Metadata()` rather than accepting an unvalidated
side channel. Metadata encodings not yet implemented by the adapter fail
generation explicitly.

Normal reads construct the semantic model through its validating `fromData`
boundary. Normal writes validate the model and finish an in-memory wire-value
conversion before calling the output generator, so a refinement or
representability failure emits no bytes. Jackson I/O failures after output begins
are not claimed to be atomic. Java `null`, malformed wire shapes, and duplicate
keys at any object depth (including equal-valued duplicates) are rejected.

Record decoding discards undeclared fields by default. Preservation can be
enabled independently for named record types; preserved JSON objects, arrays,
numbers, strings, Booleans, and nulls remain in the immutable model's raw data
and are written back. A preserved value that was later changed to a language
value with no exact JSON representation is rejected before output begins.

Nested named and anonymous records, recursive records, and closed nested generic
specializations share a bounded descriptor graph. `Maybe` record fields use
absence versus presence, while `Nullable` uses JSON `null` versus a non-null
value. Integer JSON numbers are arbitrary precision and exact; decimal strings
can instead be selected with `JSONIntegerString`. `Real` requires an explicit
choice between exact finite JSON decimals and canonical rational strings.
`Timestamp` requires the explicit RFC 3339 string policy. Exact-decimal writes
reject repeating rationals before output begins.

Tagged unions require an explicit discriminator field, a distinct wire value for
every constructor, and an ordered JSON member name for every positional
argument. No names or tags are inferred. The same policy represents a `Result`
when direct generation supplies an explicit `Result` mapping. Unknown and
missing tags or arguments are structural validation failures. Union records
discard undeclared members.

The dependency used by generated production code is
`tools.jackson.core:jackson-databind:3.2.0`, which brings Jackson core and
annotations transitively. Jackson 3 uses the `tools.jackson.*` packages and has a
JDK 17 baseline; generated Refine sources remain Java 25. Tests additionally pin
the exact core, databind, and annotations jars by SHA-256 and never download them.

## Current explicit limits

The adapter deliberately fails generation instead of guessing wire semantics
for:

- tagged unions without complete discriminator field, wire value, and
  argument-name metadata;
- generic roots that are not closed by a nominal declaration;
- native per-nominal scalar policies beyond the selected project root;
- native-project `Result` policies (native discriminator metadata intentionally
  names declared union types, while the direct API can explicitly map the
  built-in `Result`);
- caller-selected serde validation limits and explicit refinement-bypass serde
  instances;
- registering more than one closed root in a single generated module.

These are release obligations, not silently selected conventions. Structural
decoding and exact wire representability remain mandatory even for the future
explicit refinement-bypass path.

Jackson's official project documentation identifies 3.x as the actively
maintained line, and `SimpleModule` documents that registration is class-erased;
this is why the current module registers a closed nominal root rather than
pretending to infer generic witnesses at runtime:

- <https://github.com/FasterXML/jackson>
- <https://github.com/FasterXML/jackson-databind>
