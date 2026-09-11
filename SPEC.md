# Refine — agreed requirements

This document records decisions from the requirements interview. It describes
the intended product, not implemented capabilities. Concrete syntax and APIs
shown below are illustrative unless explicitly identified as agreed behavior.

## Purpose and scope

Refine is a GoPlus-authored tool for Refined OpenAPI, Refined Avro, and Refined
JSON Schema: extensions of the underlying schema formats with substantially
richer refinement types.
The GoPlus implementation reference is `../goforge/goplus`.

The first release covers all three schema formats. OpenAPI support is version 3 only;
Swagger/OpenAPI 2 is excluded. Java 25 is the initial and only code-generation
target. Python, JavaScript, TypeScript, and Go generation are future work.
JSON Schema initially supports Draft 2020-12 only; older drafts are deferred.

Required outputs and capabilities:

- Refined and ordinary versions of all three schema formats: Avro, OpenAPI 3,
  and JSON Schema. Ordinary exports explicitly account for lost rules.
- Automatically generated English explanations of constraints the ordinary
  schema cannot represent, embedded in schema documentation fields and also
  emitted as companion documentation.
- Schema structure validation and refinement type checking.
- Satisfiability and compatibility analysis, including an explicit unknown result.
- Generated Java domain types, payload validators, serde, and adapters for
  existing Java types.
- Generated Java tests, examples, and Maven build/publication support.

An ordinary exported schema plus its explanations must provide enough information
to implement the additional contract without the Refined source. Arbitrary
recursive rules may require detailed algorithmic English, not merely a summary.
Export is intentionally lossy in machine-enforceable expressiveness, but must not
silently omit the explanation of lost constraints.

Dynamic loading of Refined schemas in Java and generation of HTTP clients/server
stubs are deferred. The original distribution objective includes pkg.go.dev for
the Go tool/libraries; the current product priority is Java generation. Actual
publication follows successful validation of the implementation.

## Authoring and refinement language

The initial workflow stage supports ingesting existing ordinary JSON Schema,
Avro, and OpenAPI 3 documents within the supported format versions. No existing
Refine annotations are required. Their native definitions, constraints,
references, and applicable API metadata form the starting contract for subsequent
refinement, analysis, and generation.
Ingestion produces editable Haskell-like source so authors can add refinements
to an existing contract.
Importing a schema and exporting it back without edits to the same format must
preserve the original semantics, including ordering that affects wire encoding.
This round-trip guarantee is part of the required test coverage.
When an already released schema has a known version, ingestion creates an
immutable baseline at that version and an editable `SNAPSHOT` alongside it.
Ingestion translates native constraints into editable `where` clauses wherever
an exact translation exists, such as an integer's `minimum: 0` becoming
`Int where it >= 0`. The mapping between native constraints and their
corresponding refinement forms must be bijective, with round-trip tests in both
directions. This requirement applies to the native-translatable subset;
additional refinements without a native equivalent retain the separately agreed
lossy-export and explanation behavior.
The bijection must be deterministic and based on the actual original schema.
Native constraints have a canonical refinement form derived from that schema;
arbitrary logically equivalent rewrites are not covered by the guarantee.
The granularity is each individual native constraint. Changes to its canonical
refinement form break that constraint's round-trip guarantee, with deviations
made at the programmer's risk; untouched constraints retain their guarantees.
For example, editing an imported `minimum` clause does not invalidate the
guarantee for an untouched `maximum` on the same field. Tests must cover this
isolation as well as unchanged round trips.
This guarantee does not restrict the ability to add arbitrary refinements.
Constraints not explicitly supported by the original native schema format have
no native round-trip guarantee in the first place; their absence from ordinary
machine-enforced schema constraints is expected, not itself a warning condition.
They remain enforced by refinement-aware validators and generated Java code,
and explained in the ordinary export's English documentation. Adding such a
refinement does not break the bijection for untouched imported native constraints.

Both authoring forms are required:

- A native OpenAPI YAML/JSON, Avro JSON, or JSON Schema document containing
  Haskell-like refinement declarations and expressions.
- A standalone Haskell-like source defining types and refinements and generating
  Refined or ordinary OpenAPI 3, Avro, or JSON Schema. For OpenAPI, the source
  also defines HTTP paths, methods, parameters, and responses, so a complete API
  document can be generated without companion YAML.

The shared validation, compatibility, versioning, documentation, Java generation,
and testing requirements apply to JSON Schema as well as OpenAPI and Avro.

Reusable definitions may be imported from other files. The tool must be able to
bundle imports into a single self-contained Refined schema for distribution.

The language favors Haskell/ML-family syntax and idioms. CUE may provide relevant
schema-design inspiration, but is not the preferred surface-language model.
Record types support this compact declaration form:

```haskell
type Person = {
  name :: String,
  age  :: Int
}
```

Records authored in the standalone language permit undeclared fields by default
to reduce forward-compatibility problems. Rejecting extra fields is explicit.
For JSON, generated objects discard undeclared fields by default. Preserving
those fields and writing them back during serialization is opt-in per record type.

Tagged unions use Haskell-style declarations:

```haskell
data Payment
  = Card CardDetails
  | BankTransfer BankDetails
```

Each tagged union generates a sealed Java interface with a named, immutable
implementation for each alternative, suitable for Java pattern matching.
When a JSON union needs a discriminator field, its name and values must be
explicitly declared in the schema. Generation must not silently add discriminator
fields to the wire format.

The language supports a substantial built-in predicate vocabulary, user-defined
functions, generics, higher-order functions, collection operations, quantifiers,
and recursion. Predicates are deterministic and have no network or filesystem
access. Termination is the programmer's responsibility; the language does not
require a termination proof.

The first release supports inline refinement syntax with `it` referring to the
value being refined:

```haskell
type Positive = Int where it > 0
type Adult = Person where it.age >= 18
```

Multiple `where` clauses are combined by conjunction, and each failed clause
produces its own diagnostic:

```haskell
type Percentage = Int
  where it >= 0
  where it <= 100
```

Boolean expressions using `&&` remain supported, including a single clause such
as `where it >= 0 && it <= 100`. Repeated clauses do not replace expression-level
conjunction. The diagnostic unit is the `where` clause: each failed clause is
reported separately, but a compound expression within one clause produces one
violation, not a separate violation for each Boolean operand. For example:

```haskell
type Child = Person where it.age >= 0 && it.age < 18
```

This clause reports one age-range violation when its combined predicate fails.
Each clause may declare an author-defined error code, such as
`person.child_age_range`; the tool generates a code when none is supplied.
Authors may also customize a clause's runtime error message. The exported
English documentation includes that custom message alongside the automatically
generated explanation of the predicate.
Custom messages may compute text from the failing value using explicit `show`,
for example:

```haskell
"Expected 0 <= age < 18; got " ++ show it.age
```

Message expressions are type-checked, but authors remain responsible for the
accuracy and completeness of their wording. The generated contract explanation
still describes the full predicate independently of that wording.
If computing a custom message fails or exhausts its budget, reporting falls back
to the generated message and preserves the original `Invalid` result.

Named functions require explicit Haskell-style signatures and use explicit
parameters. Types inside their bodies are inferred where possible; when inference
cannot determine a type, an annotation is required:

```haskell
isAdult :: Person -> Bool
isAdult person = person.age >= 18

type Adult = Person where isAdult it
```

Named functions support pattern-matched definitions:

```haskell
nonEmpty :: [a] -> Bool
nonEmpty [] = False
nonEmpty (_ : _) = True
```

The compiler rejects pattern definitions that leave possible inputs unhandled;
authors must supply exhaustive cases or an explicit fallback case.

Ordinary function arguments are evaluated eagerly. An evaluation error or budget
exhaustion in an argument is reported even if the function does not use it.
Boolean `&&` and `||` retain short-circuit evaluation. For example,
`it.denominator /= 0 && it.numerator / it.denominator > 0` does not evaluate the
division when the denominator is zero.

Anonymous lambda syntax is deferred to a later release. Higher-order functions
remain in scope and can accept named functions in the first release.

Refinements can constrain fields, entire structures, and relationships between
fields. A condition on a field has equivalent enforcement whether expressed on
that field or on its enclosing structure. Examples include `bar >= 21` and an
enclosing condition equivalent to `it.bar >= 21`, or `start < end`.

Named refinements:

- Generate distinct nominal Java types. Identical predicates do not make
  differently named types interchangeable.
- Expose the underlying payload as its basic type without modifying its value.
- May refine other named types and inherit all their predicates.
- Are usable wherever their declared parent type is expected, without revalidation
  merely for that substitution.

Anonymous refinements keep ordinary Java field types and are enforced through
the containing object's validation.

Named scalar declarations are nominal even without an explicit predicate:
`type AccountId = String` generates a distinct Java wrapper, not a plain alias.
Generated Java models prioritize clear, semantically descriptive domain types.
A field declared as `AccountId` remains `AccountId` in the Java model, with
explicit access to its underlying `String` value. Fields declared directly with
a primitive/base type use that declared type's Java representation. Public
APIs retain the agreed underlying-value access and validation behavior.
First-release ecosystem interoperability is at the serde boundary, through
validated Jackson and Avro integrations. Additional interoperability interfaces
on domain types, such as `CharSequence` for string-backed wrappers, are out of
scope for this release and are not promised for a later release.

Java model design and ordinary-schema export are separate concerns. The lowering
described below applies to standard schema/wire representations; the generated
Java model retains its semantically descriptive types.
Regular JSON Schema, Avro, and OpenAPI exports lower these types to the ordinary
representations supported by each target format, retaining expressible constraints
and documenting any additional rules the target cannot represent.
Lowering follows the underlying definitions recursively through named types and
composed structures to the target's existing schema constructs and primitives.
Standard records/objects, collections, enums, and references remain standard
constructs; recursive definitions use the target's reference mechanisms rather
than infinite expansion. Fields may use underlying types directly without an
extra named wrapper. Java nominal wrappers do not by themselves add wire-level
wrappers or invent new base-format semantics. Additional refinements accompany
the base contracts through Refined variants, documentation, and generated
enforcement as specified above.

Predicate combinators have these meanings:

| Operation | Meaning |
| --- | --- |
| `oneOf` | Membership in an enum or collection of permitted values |
| `satisfiesOnlyOneOf` | Exactly one predicate succeeds |
| `satisfiesAll` | All predicates succeed |
| `satisfiesOneOf` | At least one predicate succeeds |
| `satisfiesAtLeastOneOf` | Alias of `satisfiesOneOf` |

Native schema keywords retain their standard meanings. In particular, native
JSON Schema `oneOf` requires exactly one matching subschema; only `oneOf` inside
refinement expressions denotes enum/allowed-value membership.

Combinators use three-outcome logic. For example, at-least-one is valid when one
predicate succeeds even if another is indeterminate.

## Values, arithmetic, and conversions

Absent fields and explicitly null fields are distinct and separately testable.
They use independent type constructors:

```haskell
nickname :: Maybe String             -- may be absent; cannot be null
alias    :: Nullable String          -- required field; may be null
note     :: Maybe (Nullable String)  -- may be absent or null
```

Refinements compose inside type constructors. For example,
`nickname :: Maybe (String where length it > 0)` permits absence but requires a
present nickname to be a non-null, nonempty string.

Predicates must handle possible absence/null explicitly; unsafe access is a
compile-time error.

Implicit coercions are rejected. Explicit conversions are supported and affect
only predicate calculations, not the payload. Fallible conversions return typed
success/error values that the author must handle explicitly, including deciding
whether failure means invalid or indeterminate.

`show` and typed, fallible `read` use a canonical language-neutral text format,
separate from JSON and Avro serde. Reading a shown valid value must recover the
same value, including named refinements whose predicates are revalidated, subject
to sufficient evaluation resources. Invalid bypass-created values can be shown
but are not covered by that round-trip guarantee and must not be accepted by a
validating read.

Integers default to arbitrary precision. Fractional arithmetic defaults to exact
arithmetic, including exact `1 / 3`; rounding must be explicit. Fixed-width and
fixed-precision numeric types must be explicitly requested. Overflow in an
explicit n-bit integer operation is an evaluation error unless wrapping is
explicitly requested.

Serialization must reject values that the selected wire representation cannot
represent exactly unless the contract explicitly specifies a conversion/rounding
policy. When a target format cannot directly represent an arbitrary-precision
number, the schema must specify a lossless wire encoding, such as a decimal
integer string or a rational numerator/denominator pair.

String `length` in the refinement language counts UTF-16 code units, as requested
to match JavaScript's length convention. This does not change the semantics of
imported native length constraints.
String equality compares exact Unicode sequences without implicit normalization.
For example, precomposed `"\u00E9"` and decomposed `"e\u0301"` are unequal.
The default refinement regex predicate matches the entire string. Substring
searching uses a separately named function. Imported native regex constraints
retain their native matching semantics.
Timestamp values follow [RFC 3339](https://www.rfc-editor.org/rfc/rfc3339).

## Validation and Java API behavior

Validation runs on construction, deserialization, serialization, and immutable
updates. Explicitly named bypass APIs skip refinements while preserving structural
decoding and representability requirements. Exact bypass API spellings remain to
be designed.

Generated refined values are deeply immutable, including nested objects and
collections. Changes compute a new value from an old value. An atomic update API
collects several field changes and validates the completed new structure once:

```java
Booking updated = booking.update(draft -> {
    draft.setCheckIn(newCheckIn);
    draft.setCheckOut(newCheckOut);
});
```

The draft cannot modify the original or the returned value after the operation.
Per-field update methods alone are insufficient for cross-field invariants.

Non-throwing validation has explicit `Valid`, `Invalid`, and `Indeterminate`
outcomes with collected diagnostics. Validation collects all violations it can
within its budget. A conclusive failure makes the aggregate invalid even if some
other checks remain indeterminate; diagnostics must then be marked incomplete.
Evaluation errors, such as division by zero, produce indeterminate results with
the failing predicate and evaluation error identified, unless explicitly handled.

Each violation includes a machine-readable code, affected field path(s), the
failed predicate, and an English explanation.
Default validation diagnostics omit actual payload values unless the schema
explicitly opts into including them. Author-defined messages that explicitly
include values constitute such an opt-in.
CLI validation and compatibility reports support optional machine-readable JSON
output for build tooling.

Throwing Java construction/update/serde APIs use a dedicated validation exception
carrying diagnostics, alongside non-throwing APIs. Both invalid and indeterminate
prevent normal construction/serde. These APIs must work naturally with try/catch
and with caller-side Vavr adaptation. Refine has no Vavr-specific integration
code, dependency, or separate integration artifact.

Contracts and callers can both specify evaluation budgets. Limit exhaustion has
explained behavior and is indeterminate unless a conclusive invalid result is
already known. Caller-supplied budgets may tighten, but must not relax,
schema-declared limits.
Budgets count deterministic logical evaluation steps so their
outcomes do not depend on machine speed. Step accounting must be consistent
across implementations; the detailed operation-cost model remains to be specified.
Each `where` clause can have its own step limit in addition to the overall
validation limit. Ship sensible, documented defaults at both levels so normal use
requires no budget configuration. Per-clause settings are optional overrides,
not mandatory boilerplate.

Generated Java may depend on a small versioned `refine-runtime` Maven library for
shared behavior including results, budgets, and exact arithmetic.

JSON serde integrates directly with Jackson 3; Jackson 2 support is deferred.
JSON decoding rejects duplicate object keys, including duplicates whose values
are equal.
Normal Jackson deserialization and
serialization paths must enforce refinements and propagate validation failures
with their diagnostics. Validation bypasses remain explicit operations.
Clarity takes priority over performance. The selected default is to complete
validation successfully before serialization emits payload bytes, so a validation
failure does not leave partial output. Optimize while preserving that behavior;
this does not promise atomic output in the event of a later I/O or encoding error.

Avro serde supports both binary encoding and Avro's JSON encoding in the first
release. Normal reads and writes enforce refinements on both encoding paths.
During Avro schema evolution, refinement validation runs on the resolved reader
value, after reader-schema aliases and defaults have been applied.

## OpenAPI execution context

Refinements apply to the full OpenAPI document, not only isolated body schemas.
They can relate request parameters, headers, bodies, and responses. Response
validation may reference the original request, such as requiring a returned ID
to equal the requested path parameter. Missing required request context produces
indeterminate and fails normal validating operations.

Predicates cannot obtain external state through network/filesystem access.

## Schema analysis and compatibility

A schema proven unsatisfiable is rejected. If satisfiability is unknown,
compilation proceeds with an explicit unknown diagnostic.
An Avro default that conclusively fails its field's refinements is also a schema
compilation error.

Compatibility analysis reports both directions. Backward compatibility determines
required version bumps by default. Forward compatibility is reported and becomes
enforced only when the schema opts into that guarantee.

An unknown enforced compatibility result fails by default. Overrides:

- Are stored in the schema file and retained in version control.
- Identify the specific comparison and the contents of both schema versions.
- Require review again if either compared schema changes.
- Require a human-written reason.
- Can explicitly acknowledge proven breaking changes as well as unknown results.

Breaking fixes can be annotated to avoid requiring a major bump, and may be
released as patches. A compatibility override and a fix annotation must have
clearly specified interactions; arbitrary acknowledgement of a break must not
implicitly be treated as an assertion that it is a fix.
A breaking-fix annotation requires its own written justification, distinct from
the acknowledgement of the compatibility break.

## Version history and promotion

Schema families have independent histories in the same repository:

```text
schemata/
  foo/
    v0.1.0.<extension>
    v0.2.0.<extension>
    v1.0.0.<extension>
    SNAPSHOT.<extension>
  bar/
    ...
```

A snapshot declares its intended release version when a release is pending. The
tool validates that version against the changes or rejects it with a suggested
version. A suggested change requires explicit acceptance.

Compatibility is checked against every earlier release in the same major,
subject to explicit breaking-fix exceptions. Before 1.0, minor versions are
compatibility boundaries: `0.1.4 -> 0.2.0` can break without a fix annotation,
while patches retain compatibility guarantees.

Documentation-only changes qualify for a patch release. Imported-schema changes
affect version recommendations when they change the effective contract, even if
the importing schema's own fields/predicates are unchanged. An existing release
pinned to an old dependency is unaffected by a new dependency release.

Published versioned schema files are immutable. Promotion creates the versioned
schema and its version-qualified code while retaining an editable snapshot.
After promotion, an unchanged snapshot has no pending next version. Its next
version is derived from actual changes and fix annotations; promotion must not
blindly advance it to the next patch.

Released imports must resolve to exact released versions. Snapshot dependencies
and floating ranges cannot survive promotion. Several families may be promoted
atomically, with dependencies pinned to the exact versions promoted together;
validation failure must leave all of them unpromoted.

## Java packages, generation, and Maven

The default is one repository, one Maven project/artifact, and several Java
packages such as `com.me.project.foo` and `com.me.project.bar`. The Maven artifact
has its own release version, independent of schema-family versions. Separate
artifacts per family are opt-in and must not be required for normal use.

Every schema version generates code unless explicitly marked `no-codegen`.
Generation controls can also live in project configuration, allowing an old
version to be excluded without editing its immutable schema file.

Versions coexist in version-qualified Java packages, for example
`com.me.project.foo.v0_1_0` and `com.me.project.foo.v0_2_0`. Snapshots use a stable
package such as `com.me.project.foo.snapshot`, independent of intended version.

Schemas support an optional logical namespace/package and language-specific
overrides. Explicit CLI output settings take precedence over schema metadata;
project-layout detection supplies defaults. Output can be explicitly directed to
the current directory instead of project-oriented source directories. The
configuration design must accommodate future output languages without requiring
their generators in the first release.

Normal Maven builds automatically regenerate sources and tests when schemas
change. Generated sources normally remain outside version control and must be
reproducible from checked-in inputs. Generated Java artifacts include the bundled
Refined schema, ordinary exported schema, and English explanations as resources.

For Maven builds, artifact version checking also accounts for removing previously
published Java classes through `no-codegen`. The agreed policy is based on schema
family majors, not the artifact's own major:

- Removing classes associated with a previous schema-family major requires a
  major artifact bump, e.g. published `foo.v1_*` when `foo.v2_*` exists.
- Removing a published version within the current schema-family major requires
  a minor artifact bump, e.g. removing `foo.v2_0_0` while retaining `foo.v2_1_0`.

This is the explicitly requested artifact policy; it must not be silently
replaced by a different interpretation of Java API versioning.

## Tests and examples

The implementation must be properly tested with property-based, parameterized,
and data-driven tests and worked examples. Java property testing is based largely
on JetBrains jetCheck, including shrinking and reproducible failure replay.

Schemas support embedded valid/invalid payload examples that become executable
Java tests. The tool automatically derives generators from the schema; authors
must not have to supply Java generator class/method names. Custom generator
authoring, including generators written in the refinement language, is deferred.

Generated tests include valid payloads and deliberately invalid payloads targeting
individual predicates. A property test fails if it cannot generate its required
number of valid cases within its generation budget.

All of these worked example families are in scope:

| Example | Main behavior exercised |
| --- | --- |
| Booking | Cross-field date ordering and bounded stay duration |
| Invoice | Exact arithmetic, explicit rounding, collection totals |
| Batch import | Uniqueness, quantifiers, references within a batch |
| Deployment plan | Graph references, recursion, cycle rejection |
| Payment instruction | Tagged alternatives and conditional field constraints |
| Recursive expression tree | Recursive structure and inferred-type consistency |
| Geographic polygon | Closure, distinct vertices, nonintersecting edges |
| Schema evolution | Directional compatibility and breaking/compatible changes |

## Publication identity and license

- Go module path: `goforge.dev/refine`.
- Public repository: `https://github.com/brain-fuel/refine`.
- The user confirms the repository exists; Git SSH URL:
  `git@github.com:brain-fuel/refine.git`.
- Project license: MIT.
- Maven `groupId`: to be determined; this does not block implementation.

Vanity module discovery is configured in the sibling Hugo site at
`../goforge/dev.goforge/content/refine.md`. Deployment and live resolution must be
verified separately; this does not imply that artifacts have been published.

## Details still to resolve

The behavioral decisions above are the requirements. Remaining design work must
make them concrete without silently reducing scope:

- Exact grammar, type system, schema metadata vocabulary, and canonical show/read
  representation.
- Supported OpenAPI 3 minor/patch and Avro versions, and conformance fixtures
  including JSON Schema Draft 2020-12.
- Complete numeric, text, regex, timestamp, and explicit fixed-precision semantics.
- Sound proof boundaries, unknown diagnostics, and evaluation-budget accounting.
- Automatic generation strategies and useful failures for difficult predicates.
- Exact Java/runtime APIs, serde ecosystem bindings, and Maven integration.
- Compatibility/fix annotation format, stable comparison fingerprints, and
  promotion/release transaction mechanics.
- Maven publication coordinates, vanity module-path hosting, and release tooling.

Implementation has begun; see `docs/IMPLEMENTATION.md` for concrete evidence and
remaining release gates. No product release or Maven publication has occurred.
