# Generic Java tagged unions

Generic tagged unions use the same closed, nominal model boundary as ordinary
tagged unions and the same `ModelType<T>` witnesses as generic records and
wrappers. A declaration such as:

```haskell
data Choice a = None | One a | Pair a a
type Selected a = Choice a where selected it
type Lists a = Selected [a]
type AgeLists = Lists Age
```

emits generic sealed interfaces and nested alternatives. The root's generic
`Variant` view remains exhaustive and allocation-free:

```java
Choice<Age> choice = new Choice.One<>(ModelTypes.forAge(), new Age(value));
var result = switch (choice.variant()) {
    case Choice.None<Age> ignored -> BigInteger.ZERO;
    case Choice.One<Age> one -> one.value().value();
    case Choice.Pair<Age> pair -> pair.value1().value().add(pair.value2().value());
};
```

Every generic declaration has a witness-bound `Factory`. Root interfaces also
provide static shorthand methods; nominal descendants use their own factories
because erased Java static methods cannot safely hide factories whose parent
arguments have been transformed.

```java
var selected = new Selected.One<>(ageType, age);
var read = new Selected.Factory<Age>(ageType).read("One 21");
var onlyOne = new Selected.One.Factory<Age>(ageType).read("One 21");
```

An alternative factory validates both the requested constructor and the fully
instantiated nominal target. Its `fromData`, `read`, `create`, bypass, validation,
and budget overloads follow the monomorphic union behavior. A child alternative
is the same object as all of its parent views. Updates use the root alternative's
typed draft and return the dynamic nominal subtype even through an alternative
parent reference. Transformed arguments, closed descendants, recursive unions,
phantom parameters, and inline-refined constructor arguments retain exact
witnesses; no public argument is lowered to `Object` or `Data`.

The JVM boundary is explicit: at most 250 declared type parameters are emitted,
positional constructors are omitted when witnesses plus arguments exceed 253,
and wide alternatives remain available through typed drafts. Dispatch and draft
encoding are split into bounded helper methods.

This model API still does not choose JSON/Avro discriminators or provide native
schema codecs. As with other generated models, nested getters reconstruct a
structurally checked view rather than caching an earlier Java object.
