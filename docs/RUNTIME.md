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

Refinements inside local annotations and function argument/result types run at
their assertion boundaries. Function contracts survive higher-order passing,
returning functions, and partial application: each curried argument is checked
when supplied, and each result when produced. A failed assertion is an evaluation
error (the containing predicate is indeterminate), not an implicit Boolean false.
Named parent predicates are not rerun merely for nominal substitution.

Collection operations include `map`, `filter`, `foldl`, `reverse`, `length`,
membership, uniqueness, `all`, `any`, and the four agreed `satisfies…` names.
Predicate combinators use three-outcome logic in input order. A decisive result
survives a previously unknown predicate; evaluation stops once the combination
is conclusive. `oneOf` means membership, not exactly-one predicate success.

Arithmetic uses exact rationals. `/` returns `Real`, even for integer operands.
`%` is integer remainder with a quotient truncated toward zero. Fixed-width
results are checked, not silently wrapped. Numeric conversions are not implicit.
`isInteger :: Real -> Bool` tests exact integrality, without rounding or a
floating-point tolerance. It charges the canonical number length before testing.
Text ordering is lexicographic by UTF-16 code units; equality does not normalize.

### Regex and timestamps

`matches pattern subject` requires the entire string to match; `search pattern
subject` permits a substring match. Refinement patterns use the
[Go/RE2 syntax](https://pkg.go.dev/regexp/syntax) with Perl-style flags, Unicode
categories/scripts, ASCII shorthand classes and word boundaries, and no
lookaround or backreferences. An invalid/unsupported pattern is an evaluation
error (indeterminate), never a false match. Dynamic payload-supplied patterns
are allowed; errors do not disclose them. This dialect applies only to added
refinements: native-schema regex semantics are not replaced by it.

The `pattern` package uses the ecosystem parser/compiler with a separately
metered, iterative state-set matcher. It does not use a backtracking engine or
wall-clock timeout. Valid UTF-16 pairs match as Unicode code points; lone
surrogates retain their own identity instead of becoming U+FFFD. A pattern
targeting a lone surrogate uses an explicit escape such as `\\x{d800}` in a
language string. Literal unpaired surrogates in pattern source are rejected.
The current program representation and Unicode tables come from the pinned CI
Go toolchain; a versioned cross-runtime regex profile remains required before
claiming Java parity or release-stable cross-toolchain cost identity.

`Timestamp` accepts [RFC 3339](https://www.rfc-editor.org/rfc/rfc3339) text at
payload/read boundaries. It validates the Gregorian date, timezone, and leap
label; decimal fractional seconds have arbitrary precision. Comparisons and
equality use UTC instants, not lexicographic text or host nanosecond rounding.
`-00:00` preserves unknown-local-offset metadata while still identifying the
UTC instant. The raw `value.Data` representation stays text, unchanged;
only the private typed evaluator view is parsed. Expressions do not implicitly
coerce a String to Timestamp: use typed `read`.

Leap knowledge is pinned to `value.LeapTableVersion`, IERS Bulletin C72
(2026-07-06). The implementation includes all 27 positive leap seconds through
2016 and the announced absence of a December 2026 leap. Known impossible
labels are invalid; a possible future month-boundary leap outside this table is
indeterminate. Ordinary future timestamps do not require a leap prediction.
No validation reads a clock, timezone database, filesystem, or network.
Sources: [IERS leap table](https://hpiers.obspm.fr/iers/bul/bulc/Leap_Second.dat)
and [Bulletin C](https://hpiers.obspm.fr/iers/bul/bulc/bulletinc.dat).

The public `value.Timestamp` primitive also distinguishes `CivilSecondsUntil`
(exact civil-coordinate difference, excluding intervening leaps and rejecting
leap-labelled endpoints) from `SISecondsUntil` (exact elapsed duration within
the pinned post-1972 history, through the start of 2027). The latter returns an
explicit unknown-history error beyond that range. These duration methods are
not yet DSL built-ins. Timestamp arithmetic never silently conflates these two
meanings. The zero primitive value is the Unix epoch.

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

## Canonical typed read/show

`read` obtains its target from static inference, including named generic functions
and higher-order uses such as `map read`. The compiler retains immutable inferred
types and resolves type parameters at each call; it does not guess a type from
the input text. For example:

```haskell
type Positive = Int where it > 0

accepts :: Positive -> Bool
accepts _ = True

positiveText :: String -> Bool
positiveText text = case read text of {
  (Ok n) -> accepts n;
  Err _ -> False
}
```

Here the use of `accepts` fixes the read target to `Positive`. Syntax, structure,
and refinement failures return `Err` with a payload-private explanation. Successful
reads return `Ok` with the checked value. Indeterminate validation/resource
exhaustion propagates as an evaluation failure, not a misleading malformed-input
`Err` that an ordinary failure branch could accidentally treat as conclusive.

The public Go library exposes `program.ReadData(root, text, limits)`, returning
`(value.Data, validation.Report)`. Only a valid report supplies a candidate;
invalid/indeterminate returns do not expose an unchecked payload. The separate
`language.ShowDataWithoutValidation(data, limits)` operation can display invalid
bypass-created values, but those values still cannot pass validating read.

The canonical representation is independent of JSON/Avro serde:

- Numbers use reduced integer/fraction spelling, e.g. `42` or `-1/3`.
- Text is quoted ASCII with exact `\uXXXX` UTF-16 escapes.
- Timestamps use quoted RFC 3339 text, retaining their original offset, case,
  and decimal precision. Typed read recovers the timestamp and its raw payload;
  instant-equivalent timestamps with different offset metadata can have different
  displays. Display does not normalize the payload to UTC.
- Booleans are `True`/`False`; lists are `[1, 2]`.
- Record identifiers are sorted by Unicode scalar value (equivalently UTF-8 byte
  order for valid identifiers): `{a = 1, z = True}`. This is distinct from UTF-16
  payload text ordering; a conformance fixture covers supplementary identifiers.
- Constructors preserve argument order: `Nothing`, `(Just Null)`,
  `(Leaf (-2))`, `(Just (-1/3))`. Signed/fractional constructor arguments are
  parenthesized so their display is unambiguous to the reader.

The reader accepts whitespace and noncanonical numeric spellings that represent
exact values; display selects the canonical spelling. It admits only literal
data, signed numbers, exact integer fractions, and constructor applications.
Function calls, projections, arithmetic calculations, conditionals, and local
bindings in read input never execute. Named refinements are revalidated. Function
values are not readable payloads, even when nested in a record or collection.
Structurally unrepresentable names fail display rather than producing ambiguous
canonical text. Cross-runtime vectors live in `testdata/canonical-values.json`
under the language package; Java must consume the same expectations later.

## Deterministic resource accounting

The development operation-cost model is executable in `language/eval*.gp` and
tested at exact thresholds. It must be mirrored by the future Java runtime:

- Entering an expression, function invocation/application, pattern, recursive
  equality/display operation, anonymous assertion, or structural visit costs one
  logical step. Runtime type instantiation and signature binding charge each
  visited type node; record signature matching charges each field comparison.
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
- Nested read validation and anonymous assertions charge every enclosing meter
  and the overall budget exactly once. A nested `@steps` override cannot reset or
  relax the enclosing predicate's allowance. Decoding charges input UTF-16/UTF-8
  lengths before parsing, plus each visited literal node.
- Timestamp boundary parsing charges `1 + UTF16Length²` before conversion and
  exact fraction parsing. Timestamp comparisons charge
  `1 + leftFractionCanonicalLength * rightFractionCanonicalLength`; display and
  raw transfer charge retained text length.
- Regex compilation charges `1 + patternUTF16Length²` before parsing, each AST
  node, and an overflow-checked conservative expansion bound before expanding
  counted repeats. Matching charges the subject length plus program size before
  allocation, each input position, each visited instruction (including duplicate
  states), and rune-class work. Exact accounting is in `pattern/regex.gp`; fixed
  threshold and differential tests guard it. Budget exhaustion is indeterminate.

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

- Explicit conversion/rounding and timestamp duration vocabulary; release-stable
  cross-runtime regex/Unicode profile and matching cost conformance.
- Full constraint-qualified polymorphism and inference of all necessary codec
  capabilities through generic function signatures. Unresolved runtime target
  variables currently fail indeterminate; they must never silently pick a type.
- Full numeric literal typing and removal/replacement of the current
  65,536-bit numeric-backend guard with a consistent resource policy.
- Source-level overall budget/record-policy metadata, complete affected-path
  analysis, native payload decoding, HTTP request/response context, and CLI
  payload validation.
- Complete English export, Java runtime/code generation/serde, cross-runtime
  canonical read/show conformance, compatibility, versioning, Maven, and all
  other unchecked release gates.

Tests cover table-driven execution, all three-outcome sequences of up to four
predicates, exact budget thresholds, recursive/generic payload checks, message
fallback, private diagnostics, concurrent immutable reuse, transformation laws,
field-versus-record constraint equivalence, and evaluator/data fuzz properties.
