# Schema-derived Java property tests

`java.GeneratePropertyTests` emits an executable Java 25 test class backed by
JetBrains jetCheck 0.3.0. The generator consumes checked Refine syntax; schema
authors do not provide Java generator classes or method names.

## Inputs and generated checks

`PropertyTestOptions` controls:

- `Targets`: closed named schema types. When omitted, every closed declaration
  is selected.
- `CaseCount`: the required number of cases for every generated property
  (default 100).
- `AttemptBudget`: the maximum candidates examined for each required case
  (default 10,000).
- `Seed`: the deterministic jetCheck seed used for replayable runs.
- `Examples`: typed `value.Data` payloads with expected valid, invalid, or
  indeterminate outcomes and optional required diagnostic codes.
- `Replays`: a serialized jetCheck counterexample bound to one valid property,
  or to one invalid property by target and diagnostic code.

For every target, the emitted suite derives a structural `Data` generator. A
valid candidate must pass the contract filter, the normal generated model
factory, preserve its raw `Data`, validate through the model, and survive a
canonical show/read/show round trip. It also emits one invalid property per
discovered `where` clause. A targeted invalid candidate must be invalid with
exactly one diagnostic carrying that clause's explicit or deterministically
derived code. The normal factory and canonical reader must both reject it with
that diagnostic, while the explicit without-validation factory must preserve
the raw value and retain the same diagnostic on validation. Thus a property is
not satisfied merely because the validator used to select candidates returns
the same result a second time.

The generator supports booleans, strings, exact rational reals, integers,
lists, records, nominal aliases, closed applications of generic aliases,
refinements, and `Maybe`/`Nullable` payload constructors. Record fields may
contain tagged unions, including directly recursive unions with at least one
finite base alternative; jetCheck's bounded recursive generator controls their
depth. Real generation includes genuine fractions rather than only integer-valued
reals. Integer refinements mix broad random values with arbitrary-precision
predicate literals and their adjacent boundary values. Generated Java constructs
those samples from decimal `BigInteger` strings, so a schema bound is not
silently truncated to Java `int`. Lists are bounded to eight elements and
generated strings currently use printable ASCII up to 24 characters. These are
generation distributions, not restrictions on the schema or runtime.

Top-level tagged-union targets, recursion outside the direct-union strategy,
recursive unions without a finite base, functions as payloads, open generic
targets, and unknown type constructors are currently rejected before any file
is returned. They are not replaced with fixed examples, raw `Object`, or a
vacuously passing property. Arbitrary refinements that are structurally
generatable use rejection sampling against the real generated validator.

## Exhaustion and invalid targeting

The requested case count is mandatory. For each case, the generated `requiring`
generator evaluates at most `AttemptBudget` candidates. If it cannot find a
valid or clause-targeted invalid payload, it throws an `AssertionError` naming
the target and attempt count. The property does not skip, reduce its case count,
or report success. A satisfiable schema outside the current distribution—for
example a string constrained to more than 100 characters while the current text
distribution stops at 24—therefore fails explicitly and calls for a better
strategy or explicit input adjustment.

Embedded examples run through the same generated contract validator and assert
their declared outcome and diagnostic codes. They are supplied through typed
options until native schema metadata exposes a stable, unambiguous executable
example API; native `examples` annotations are not guessed or treated as Refine
metadata.

## jetCheck dependency and replay

Generated sources directly reference `org.jetbrains.jetCheck.Generator` and
`PropertyChecker`. Maven/test integration must provide
exactly `org.jetbrains:jetCheck:0.3.0` on the generated-test classpath. Refine
does not download it during generation.

Normal schema properties run with the configured seed and case count. A failing
jetCheck property reports a minimized serialized counterexample. Supplying that
text in a matching `PropertyReplay` makes the generated property invoke
jetCheck's real `rechecking` path instead of its seeded run; replay entries that
do not identify an emitted target/property are rejected atomically. Deliberately
failing framework smoke properties are kept in Refine's own generator tests and
are never inserted into a user's emitted suite.

The generated class has a `main` method so it can run under a plain Java test
execution as well as a Maven-bound launcher. A generation caller should combine
it with the matching `GenerateModels` output for the same program, namespace,
and contract class.
