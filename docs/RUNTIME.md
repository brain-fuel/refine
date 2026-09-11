# In-memory validation checkpoint

The GoPlus-authored execution core now connects the checked language to immutable
in-memory payloads. This is **not** the finished native-schema/Java validator.
The full release gates remain in [IMPLEMENTATION.md](IMPLEMENTATION.md).

## Library entry point

```go
program, err := language.Compile(`
type Person = { age :: Int where it >= 0 }
type Child = Person
  where it.age < 18
    @code "person.child_age"
    @message "Age must be less than 18"
`)
if err != nil {
    // Handle schema syntax/static type errors.
    panic(err)
}
payload, err := value.Record([]value.DataField{
    {Name: "age", Value: value.OfNumber(value.Integer(21))},
})
if err != nil {
    panic(err)
}
report := program.ValidateData("Child", payload, validation.Limits{})
// report.State(): Invalid; one child-age diagnostic.
// The original payload is unchanged.
```

Imports in this example are `goforge.dev/refine/language`,
`goforge.dev/refine/value`, and `goforge.dev/refine/validation`. The root is a
declared type with no unbound parameters; generic types may occur inside it.

`value.Data` is an immutable, function-free payload tree, not a claim of prior
validation. Constructors/accessors copy slices, nested values cannot be mutated,
and `ReplaceFields` prepares several existing-field changes together without
changing the original. That low-level operation does **not** run refinements;
the completed candidate must be passed through validation. The generated Java
validating update/draft API remains required work.

`Maybe`, `Nullable`, and tagged data alternatives use explicit `value.Variant`
constructors here, with the language's names and arities. The zero `Data` value
is `Null`, not `Nothing`. An omitted record field is accepted only when its type
is optional (including generic aliases). Standalone records allow extra fields;
the typed predicate view contains declared fields, while the caller's raw tree
is unchanged. None of this specifies or adds a wire-level wrapper.

## Execution and reports

Implemented execution includes exact integers/rationals; UTF-16 text; immutable
records, lists, and constructors; eager curried application; named polymorphic
and higher-order functions; pattern equations/cases; recursion; conditionals and
local bindings. `&&`/`||` short-circuit. Unused ordinary arguments and local
bindings still evaluate, so their failures are not hidden.

Collection operations include `map`, `filter`, `foldl`, `reverse`, `length`,
membership, uniqueness, `all`, `any`, and the four agreed `satisfies…` names.
Predicate combinators use three-outcome logic in input order. A decisive result
survives a previously unknown predicate; evaluation stops once the combination
is conclusive. `oneOf` means membership, not exactly-one predicate success.

Arithmetic uses exact rationals. `/` returns `Real`, even for integer operands.
`%` is integer remainder with a quotient truncated toward zero. Fixed-width
results are checked, not silently wrapped. Numeric conversions are not implicit.
Text ordering is lexicographic by UTF-16 code units; equality does not normalize.

Structure is checked before executing rules that depend on that structure.
Inherited, nested, and repeated `where` clauses each retain their diagnostics.
One compound `&&` clause is one violation. Sibling structural/rule failures are
collected as resources permit; known invalid dominates indeterminate and sets
`incomplete` when some checks could not finish. A malformed structure is invalid,
whereas evaluation failure/resource exhaustion is indeterminate.

Default diagnostics contain source predicates but not actual payload values.
Custom message expressions are the explicit opt-in to include values. Failure,
budget exhaustion, or an unrepresentable text result during message computation
falls back to the generated message without discarding a conclusive violation.
Reports support JSON encoding. Default generated messages currently describe the
source condition; they are not yet the required complete English export backend.

## Deterministic resource accounting

The development operation-cost model is executable in `language/eval*.gp` and
tested at exact thresholds. It must be mirrored by the future Java runtime:

- Entering an expression, function invocation/application, pattern, recursive
  equality/display operation, or structural visit costs one logical step.
- Numeric literals additionally charge their source length and absolute decimal
  exponent **before** parsing/expanding the number.
- Arithmetic and ordered numeric comparison additionally charge
  `1 + leftCanonicalDigits * rightCanonicalDigits`; the counted lengths include
  signs and fraction separators. Negation charges its operand length. A
  fixed-width range check charges its declared width. Numeric equality charges
  the sum of canonical lengths.
- Text operations charge the relevant UTF-16 lengths; literal decoding charges
  source bytes. Record field scans charge each inspected member. Collection
  allocation/copy operations charge their element counts before allocating.
- Recursive operations charge every visited child. Record display sorting
  charges `fieldCount * (1 + floor(log2(fieldCount)))` for nonempty records, plus
  emitted field-name lengths. Display also charges its resulting UTF-8 length
  when converting to a language String.
- Structural transfer consumes the overall budget, not an individual clause's
  allowance. Each `where` gets a fresh clause meter sharing that total. Its
  custom message uses the **same** meter as its predicate.

Defaults remain 1,000,000 overall and 100,000 per clause. Caller limits can only
tighten these; `@steps` overrides the schema's clause default while retaining
the caller cap. An unaffordable operation does not run or consume another
clause's allowance. These are logical work units, not milliseconds or a complete
bound on host memory/CPU usage.

There is also a deterministic 512-frame nesting safety cap. It yields
indeterminate, never a claim of nontermination or a violation. Replacing recursive
interpreter dispatch with a trampoline remains required work so recursive
predicates can use the full logical budget without this temporary host-stack cap.

## Remaining integration

The following are explicitly unfinished, not silently interpreted as success:

- Typed `read`, regex execution, RFC 3339 timestamp values, and explicit
  conversion/rounding vocabulary.
- Enforcement of refinements in function signatures and local annotations.
  Encountering these forms during execution currently yields indeterminate.
- Full numeric literal typing and removal/replacement of the current
  65,536-bit numeric-backend guard with a consistent resource policy.
- Source-level overall budget/record-policy metadata, complete affected-path
  analysis, native payload decoding, HTTP request/response context, and CLI
  payload validation.
- Complete English export, Java runtime/code generation/serde, typed validating
  canonical read/show round trips, compatibility, versioning, Maven, and all
  other unchecked release gates.

Tests cover table-driven execution, all three-outcome sequences of up to four
predicates, exact budget thresholds, recursive/generic payload checks, message
fallback, private diagnostics, concurrent immutable reuse, transformation laws,
field-versus-record constraint equivalence, and evaluator/data fuzz properties.
