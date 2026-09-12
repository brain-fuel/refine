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
Age parsed = Age.read("21"); // Validating canonical text, not JSON/Avro serde.
String canonical = parsed.showWithoutValidation();

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
  Timestamp values use the immutable runtime `Timestamp`, whose `raw()` exposes
  the retained RFC 3339 text, including precision and offset spelling.
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
- Static `read(text[, limits])` parses canonical language text and validates the
  target before constructing the model from nominal evidence. It does not repeat
  that validation. Instance `showWithoutValidation([limits])` displays raw values
  without asserting refinements; a subsequent `read` checks invalid bypass-created
  values again. Failed reads throw `ValidationException` and expose no candidate.
  For non-throwing reads, use `Contract.read(typeName, text[, limits]).outcome()`.
  Canonical reads use the checked view (dropping undeclared fields and filling
  absent `Maybe` fields), unlike raw-preserving `fromData`.
- `createWithoutValidation`, `fromDataWithoutValidation`, and
  `updateWithoutValidation` explicitly skip predicates. They still check shape,
  declared numeric representability, timestamp validity and structural resource
  limits. Unknown future leap labels still fail structural bypasses. A later
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

The same typed draft supports construction:

```java
Booking booking = Booking.create(draft -> {
    draft.setCheckIn(BigInteger.ONE);
    draft.setCheckOut(BigInteger.TWO);
});
```

`create(initialize[, limits])` begins with an empty record, encodes the final
assigned fields in declaration order, and validates the complete candidate once.
Omitted required fields fail with the ordinary structural diagnostics; optional
fields may remain absent, with getters exposing `Nothing` without inserting a
field into the raw payload. Nullable fields are not implicitly optional.
`createWithoutValidation` also accepts a draft callback but still enforces
structure and representability. Both APIs retain nominal refinement result
types, and callback exceptions propagate unchanged.

Records with up to 253 fields also retain positional constructors and bypass
factories. Wider records use typed drafts or raw-data factories because a
constructor plus caller budget would exceed the JVM's 255 parameter slots.
Draft encoders are split into bounded helpers, eliminating the previous
48,000-byte model source rejection without replacing domain fields with an
untyped map. All widths expose the same typed getters and draft setters.

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
collisions are rejected. A generated record helper is normally named `Draft`;
if that name would shadow a domain declaration or the contract class, it is
deterministically suffixed (`Draft_`, then `Draft__`, and so on), including in
the unnamed package. The generation CLI still needs complete output ownership,
host-filesystem planning, project-layout detection and naming override support.

## Tagged unions and nominal refinements

Monomorphic tagged unions generate a sealed interface and nested immutable
alternative classes. For example:

```haskell
data Payment = Cash Int | Split Int Int | Free
type Paid = Payment
  where (case it of { Cash n -> n > 0; Split a b -> a + b > 0; Free -> False })
```

```java
Paid paid = new Paid.Cash(BigInteger.ONE);
Payment parent = paid; // Same object, no copying or revalidation.
BigInteger total = switch (parent.variant()) {
    case Payment.Cash cash -> cash.value();
    case Payment.Split split -> split.value1().add(split.value2());
    case Payment.Free ignored -> BigInteger.ZERO;
};
Paid.Split split = Paid.Split.create(draft -> {
    draft.setValue1(BigInteger.ONE);
    draft.setValue2(BigInteger.TWO);
});
```

`Paid` extends `Payment`; `Paid.Cash` extends `Payment.Cash` and implements
`Paid`. Longer refinement chains preserve both relationships. The closed
`Payment.Variant` view permits only the original alternative classes. `variant()`
returns the exact same object with that view type, making a switch over the
original alternatives exhaustive even when nominal refinement interfaces extend
the root. Java's exhaustiveness analysis does not recognize that coverage for
a switch directly over the root interface with those additional permitted
refinement interfaces. No fallback arm, wrapper allocation or validation is
needed for the view. All nominal refinement views use the root family's
alternatives for exhaustive matching.

A single constructor argument has a typed `value()` getter; several arguments
have `value1()`, `value2()`, and so on, in declaration order. Alternative classes
support validated construction, `fromData`, canonical `read`, validation outcomes,
explicit bypasses and atomic `update` drafts. Factories on an alternative reject
another constructor even when it is valid for the overall union. Refinement
alternatives retain their dynamic predicates and covariant update result when
accessed through a parent reference. Recursive union arguments retain their
declared nominal types. These language constructors do not select JSON
discriminators or alter native wire representations.

`create(initialize[, limits])` stages every constructor argument and validates
once after the callback completes. Missing arguments fail structurally, including
optional/nullable arguments: those require their explicit language constructors.
`createWithoutValidation` also supports drafts but skips only predicates.
Creation and update drafts have the same snapshot/callback-failure guarantees
as record updates. Nullary alternatives accept empty drafts. Alternatives with
more than 253 arguments use these builders or raw-data factories instead of
positional constructors, respecting the JVM parameter-slot limit without dropping
typed getters or setters. Large alternative dispatch tables and draft encoders
are emitted in bounded helper methods.

Nested constructor class names are deterministically suffixed when they would
shadow runtime helpers, top-level domain types or each other. For example,
`data Token = Token String` emits `Token.Token_` but retains the language tag
`Token`. If a domain declaration is named `Variant`, the closed view is named
`Variant_` (with further suffixes as needed); its method remains `variant()`.

## Generic records and wrappers

Generic roots retain typed fields and explicit immutable witnesses for their
type arguments. Witnesses distinguish constraints that Java erases: `Int` and
`UInt8` both use `BigInteger`, for example. Empty collections and phantom
parameters do not require guessing a type from a runtime value.

```haskell
type Box a = { value :: a, note :: Maybe String }
type Items a = [a]
type Node a = { value :: a, next :: Maybe (Node a) }
```

```java
ModelType<Age> ageType = ModelTypes.forAge();
Box<Age> box = new Box<>(ageType, new Age(BigInteger.ONE),
    new ModelMaybe.Nothing<>());
Box<Age> changed = box.update(draft -> draft.setValue(new Age(BigInteger.TWO)));
Box<Age> parsed = Box.read(ageType, "{value = 21}");
Items<Age> empty = new Items<>(ageType, List.of());
ModelType<Box<Age>> boxType = ModelTypes.forBox(ageType);
Validation.Outcome outcome = boxType.validateData(candidate);
```

`ModelTypes.forName(...)` is generated for every emitted domain declaration.
Builtin witnesses include `integer()`, signed `integer(bits)`,
`unsignedInteger(bits)`, `text()`, `bool()`, `real()` and `timestamp()`;
`list`, `maybe`, `nullable` and `result` compose witnesses. Integer-width
factories accept the language's positive unsigned-32-bit width range; payload
validation still enforces resource/backend limits rather than promising support
for enormous integer allocations. Witnesses have private constructors and no
public arbitrary-name, schema-parser, predicate or encoder/decoder factory.
They belong to the generated package's checked contract.

Generic constructors, static factories and reads take one witness per declared
parameter, in declaration order, before ordinary arguments. Caller budgets remain
the final optional argument. Instances retain witnesses for validation, typed
getters and atomic updates. Normal construction, raw-data factories and reads
validate the instantiated target without a synthetic alias; bypasses skip only
predicates. Recursive record getters reconstruct structurally checked typed views
without executing predicates, just like monomorphic getters.

Generic record drafts retain their field types (`Box.Draft<Age>`). Positional
construction is available when fields plus witnesses total at most 253; wider
records use typed draft factories. The current backend explicitly rejects more
than 250 type parameters. Generic scalar, list, optional/result wrappers,
phantom parameters, named refined arguments and nested generic record fields are
supported. No public field is erased to `Object` or `Data`.

Inline-refined arguments are also supported. For example:

```haskell
type Positive = { box :: Box (Int where it > 0) }
```

```java
Positive positive = new Positive(new Box<>(ModelTypes.integer(), BigInteger.ONE,
    new ModelMaybe.Nothing<>()));
Box<BigInteger> nested = positive.box();
// Throws: the nested model retains the inline argument's predicate.
nested.update(draft -> draft.setValue(BigInteger.ZERO));
```

The containing model enforces the inline constraint even when supplied a box
constructed with a weaker witness. Its getter reconstructs the declared witness
from checked metadata; subsequent nested validation and updates retain that
constraint. Explicit bypasses skip predicates without forgetting them. No new
nominal class is created for the anonymous refinement. Named arguments remain
nominal: `Box Age` retains `Age`, while `Box (Age where it < 18)` retains the
same Java argument type with an additional predicate on the containing box.

Inline witnesses inside generic declarations bind the enclosing type parameters
in both payload metadata and inferred predicate signatures. This includes generic
`show`, typed `read`, custom messages, local refinements and recursive calls.
Binding is simultaneous and immutable; existing argument metadata is not rebound.
Original predicate text, codes, messages and budgets are preserved. Traversal is
iterative, recursive inferred signatures stay lazy, and shared witnesses are
safe for concurrent validation. There is no runtime schema parser or user-supplied
predicate factory. Inline constraints on a nominal value itself still belong to
its containing model; they do not change the methods of that value's Java class.

## Generic inheritance and factories

Record and wrapper hierarchies support closed aliases, renamed/reordered/repeated
parameters, transformed arguments and phantom parameters. For example:

```haskell
type Nonempty a = Box [a] where length it.value > 0
type AgeBox = Nonempty Age
```

```java
AgeBox ages = new AgeBox(List.of(new Age(BigInteger.ONE)),
    new ModelMaybe.Nothing<>());
Box<List<Age>> parent = ages; // Same object and raw payload.
AgeBox parsed = new AgeBox.Factory().read("{value = [21]}");
Nonempty<Age> built = new Nonempty.Factory<Age>(ModelTypes.forAge())
    .create(draft -> draft.setValue(List.of(new Age(BigInteger.TWO))));
// Throws even through the parent reference: dynamic child predicates survive.
parent.update(draft -> draft.setValue(List.of()));
```

Generic-family classes have their own immutable nested `Factory`, taking that
declaration's witnesses in order. It provides `fromData`, `read`, `validateData`,
draft `create`, and explicit bypass methods, with default/caller budgets. Closed
aliases need no witnesses. Positional constructors remain on the domain class.
Root static shorthands such as `Box.read(witness, text)` remain available.
For a derived target, use its own factory: inherited Java static methods still
target their declaring root and do **not** become child factories. This avoids
Java static-method erasure clashes when a child transforms its parent's arguments.

Factories are independent nested types, not covariant static methods. If a domain
or contract is named `Factory`, the helper is deterministically suffixed, just
like `Draft`. Derived records share the root's fully instantiated draft type,
for example `Box.Draft<List<Age>>`, and updates return the dynamic nominal child.
Getters and raw access are inherited without copying or rerunning predicates.
Validation, reads, bypasses and atomic updates still use the complete child target.

Internal evidence checks the instantiated declaration, argument identities and
inline-refinement provenance/captured scope. It rejects parent-to-child evidence,
unrelated types and wrong arguments even when their Java representations match.
Evidence comparison uses immutable structural keys and an iterative traversal;
it does not compare recursive inferred-signature suppliers or claim to prove
predicate equivalence. Ancestor witnesses are built lazily without recursive
factory calls. Evidence checks do not add another payload-validation pass.

Generic tagged unions, including instantiated nominal descendants, use the same
closed witness and evidence design; see [GENERIC-UNIONS.md](GENERIC-UNIONS.md).

## Coverage and remaining scope

Current models cover monomorphic named scalars, records, lists and aliases,
nominal refinement chains, recursive records through named references/optional
fields, tagged unions and their recursive/refined alternatives, and composed
optional/nullable/result values, plus the generic roots described above.
Anonymous nested records produce deterministic descriptive model classes from
their checked owner and field/item/argument path. They retain typed getters,
validating and explicit-bypass construction, immutable drafts, generic owner
witnesses, and the original checked inline type metadata; their witness identity
includes the owner and exact type path. Wide regular records and union
alternatives use bounded draft emission rather than a model source-length guard.
Unsupported predicate execution and source-size limits remain as described in
[JAVA-RUNTIME.md](JAVA-RUNTIME.md).

Closed generic validation/read targets are now available through Go's
`Program.PayloadType` and Java's `GenerateValidatorWithTypes` registration API.
This supplies checked target metadata without an extra named-alias validation
layer. `GenerateModels` additionally emits the typed generic-root models and
witnesses described above; validator-only generation does not emit them.

Model predicates may call the generated named/recursive/higher-order function
engine. Those calls run under the same construction/update validation budget;
explicit bypass factories still skip predicates. Functions are private evaluator
values and do not replace the domain types or appear in the public payload tree.

Tests compile generated sources with Java 25 and all warnings treated as errors.
They cover normal/bypass constructors, parent substitution, negative compilation
for unrelated nominal types, evidence isolation, snapshots of nested lists,
escaped drafts, callback failure, untouched field preservation and covariant
updates. A boundary derived from Go's validator proves one completed update uses
exactly the budget required for one validation pass. Two jetCheck suites add
4,000 fresh-seeded construction/update cases. Model source generation also has
determinism, collision, rejection, fuzz and benchmark coverage.

The union suite adds 18,729 complete Go/Java report and canonical-read
comparisons, including caller/per-clause budget boundaries, and 6,000 jetCheck
cases for construction, atomic updates and recursive trees. It compiles exhaustive
switches without defaults, rejects illegal nominal assignments and unpermitted
implementations, and checks parent/sibling/alternative evidence isolation.
Separate scale tests compile and execute a 1,100-alternative union, a
260-argument constructor and its nominal refinement, and the exact 253-argument
positional-constructor boundary. Go-derived minimum budgets prove wide draft
creation and update each perform one complete validation pass.

Regular-record scale tests compile and execute widths 0, 1, 64, 65, 253, 254,
260 and 1,100, with exact Go-derived construction/update budgets at every width.
They cover multi-level nominal refinements, typed getters, canonical reads,
missing-field/bypass behavior, escaped drafts and helper-name collisions.
Another 6,000 jetCheck cases exercise draft construction, immutable updates,
invalid bypass correction, canonical reads and preservation of undeclared fields
and absent optional fields in the language payload.

The generic suite adds 3,600 complete Go/Java reports across validation,
construction, bypass and read budget boundaries, plus 6,000 JetCheck cases for
immutable updates, invalid bypasses and recursive typed records. Negative Java
compilation checks distinguish unrelated nominal arguments and prevent public
witness/private-raw construction. Generic scale tests cover 0, 1, 64, 65, 252,
253 and 1,100 fields, including the positional boundary after reserving a witness.
Package tests compile generic fields in unnamed, Unicode and contextual-keyword
packages with all Java warnings treated as errors.

Inline-witness tests add 7,200 complete Go/Java reports at exact budget boundaries
and 6,000 JetCheck cases. They cover nested validation/updates, typed-read scope
isolation, unknown results, separate clauses, custom messages, nominal arguments,
optional/result/list composition, inherited record/union fields and concurrent
use. Scale tests compile and execute 1,100 inline-refined fields and a 200-level
predicate with Java 25 warnings-as-errors at `-Xss256k`.

Generic-inheritance tests add 18,000 complete Go/Java reports across validation,
construction, bypass and read budget boundaries, plus 6,000 JetCheck cases.
They cover transformed/reordered/repeated arguments, closed aliases, phantom
parameters, scalar wrappers, inline predicates, parent-typed updates, escaped
drafts and nested model views. Negative compilation and direct evidence checks
reject invalid substitutions. A 1,100-field transformed hierarchy with twenty
additional alias levels compiles and runs at `-Xss256k`, including `Factory`
name collisions. Structural key comparison also handles 2,000 nested list types
without recursive Java equality.

The complete release still requires all model shapes and language execution,
validated Jackson and Avro serde, native schema formats,
English exports, generated schema-derived tests, versioning, Maven/project/CLI
integration and the full [specification](../SPEC.md). No Maven deployment or
product release is implied by these model tests.
