# Semantic Java models (development)

`java.GenerateModels(program, packageName, contractClassName)` emits Java 25
domain classes together with the contract validator and runtime they use. It is
a pure Go API returning `[]java.File`: callers choose where to write sources.
There is no separate runtime Maven artifact, deployment, or implicit filesystem
operation. This is a development backend, not a completed native schema compiler.

For this checked source:

```haskell
type AccountId = String
type Age = Int where it >= 0
type AdultAge = Age where it >= 18
type Booking = { checkIn :: Int, checkOut :: Int }
  where it.checkIn < it.checkOut
```

the generated Java supports:

```java
AccountId id = new AccountId("account-21");
String rawId = id.value();
Age age = new AdultAge(BigInteger.valueOf(21)); // Ordinary parent substitution.

Booking old = new Booking(BigInteger.ONE, BigInteger.TWO);
Booking updated = old.update(draft -> {
    draft.setCheckIn(BigInteger.valueOf(3));
    draft.setCheckOut(BigInteger.valueOf(4));
});
```

## Types and boundaries

- Named declarations remain nominal even without a predicate. An `AccountId`
  field has type `AccountId`, not `String`. Anonymous refinements retain the
  underlying field representation and are enforced by the containing validator.
- Primitive integer representations use `BigInteger`, including explicitly
  bounded integer types; those bounds remain validated constraints. Real values
  use exact `Rational`, text uses `String`, and Boolean values use `Boolean`.
  This does not choose a JSON/Avro wire encoding or silently round anything.
- Scalar/list wrappers expose `value()`. All models expose immutable `rawData()`
  for the underlying language payload. `fromData` retains that exact object;
  field access and parent substitution do not rewrite it. Records expose typed
  field accessors rather than an untyped map replacing their domain API.
- Refinements of generated named types extend their declared parent. Hierarchies are
  sealed (leaf classes are final). Internal validation evidence is tied to the
  nominal root/ancestor chain, so evidence for an unrelated equivalent-looking
  type cannot construct another type. Upcasting does not run validation.
- Normal constructors and `fromData` validate. Overloads accept caller
  `Budget.Limits`; defaults require no configuration. `validate()` and static
  `validateData(raw[, limits])` return non-throwing validation outcomes.
- `createWithoutValidation`, `fromDataWithoutValidation`, and
  `updateWithoutValidation` explicitly skip predicates. They still check shape,
  declared numeric representability and structural resource limits. A later
  normal validation still detects invalid or indeterminate bypass-created values.
  Failures use `ValidationException`; no Vavr dependency or adapter is added.
- Java null is not implicitly converted into absence or a nullable constructor.
  Invalid host arguments produce a coded structural exception during input
  conversion. Once a language payload exists, contract validation collects its
  structural/refinement diagnostics using the shared validator.

Lists are encoded into copied immutable payload trees. Getters return immutable
lists, including nested collections, and semantically named element wrappers.
`ModelMaybe<T>` (`Nothing`/`Just`), `ModelNullable<T>` (`Null`/`NonNull`) and
`ModelResult<L,R>` (`Err`/`Ok`) keep those states distinct. These generic carriers
do not promise to freeze arbitrary host objects in isolation; model boundaries
encode their contents into the immutable representation.

Nested named getters currently reconstruct their view through structural-only
factories. They do not rerun predicates. Caching proven nested views is a possible
performance improvement, not a reason to weaken their structural checks.

## Atomic updates

Record drafts stage typed values without validating intermediate states. Only
explicitly set fields are encoded and replaced when the callback finishes; the
completed candidate is then validated once. A null or invalid intermediate value
can be replaced with a valid final value in the same callback.

The old object is unchanged if the callback or validation fails. The completed
new object shares no mutable draft/collection state. Retaining a draft and changing
it later cannot alter either object. No-op updates preserve the original raw
payload, including absent optional fields and untouched extras. Setting an absent
optional field explicitly can add it to the language payload.

This raw-data behavior does not define native JSON extra-field serialization.
The required discard-by-default/preserve-opt-in JSON policy belongs to the
still-unimplemented native codecs; language `Data` is not a JSON object encoding.

Refined record subclasses retain their dynamic type and predicates during an
update, including when accessed through a parent reference. Their update methods
return the refined subtype and share the root record's draft shape.

Field names that conflict with Java keywords or generated/Object APIs are given
deterministic escaped/suffixed member names; original payload keys are preserved.
Setter case collisions receive distinct suffixes. Case-insensitive source-name
collisions are rejected. The generation CLI still needs complete output ownership,
host-filesystem planning, project-layout detection and naming override support.

## Coverage and remaining scope

Current models cover monomorphic named scalars, records, lists and aliases,
nominal refinement chains, recursive records through named references/optional
fields, and composed optional/nullable/result values. Generic domain declarations,
tagged-union model alternatives and anonymous nested record classes still reject
model generation explicitly. The validator can already handle more structural
forms than the model emitter. Unsupported predicate execution and source-size
limits remain as described in [JAVA-RUNTIME.md](JAVA-RUNTIME.md).

Tests compile generated sources with Java 25 and all warnings treated as errors.
They cover normal/bypass constructors, parent substitution, negative compilation
for unrelated nominal types, evidence isolation, snapshots of nested lists,
escaped drafts, callback failure, untouched field preservation and covariant
updates. A boundary derived from Go's validator proves one completed update uses
exactly the budget required for one validation pass. Two jetCheck suites add
4,000 fresh-seeded construction/update cases. Model source generation also has
determinism, collision, rejection, fuzz and benchmark coverage.

The complete release still requires all model shapes and language execution,
typed compound show/read, validated Jackson and Avro serde, native schema formats,
English exports, generated schema-derived tests, versioning, Maven/project/CLI
integration and the full [specification](../SPEC.md). No Maven deployment or
product release is implied by these model tests.
