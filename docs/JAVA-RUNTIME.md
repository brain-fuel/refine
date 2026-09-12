# Java runtime generation (development)

`goforge.dev/refine/java.GenerateRuntime(packageName)` returns deterministic
`File{Path, Source}` values for seven Java 25 source files. It performs no I/O.
The caller owns output placement; generation does not deploy a Maven artifact.
Runtime source is authored in GoPlus templates and emitted with an MIT header.

```go
files, err := java.GenerateRuntime("com.me.project.refine.runtime")
// Each Path is relative, e.g. com/me/project/refine/runtime/Rational.java.
// A Maven caller can place it under target/generated-sources/refine/.
// A flat-output caller can use filepath.Base(file.Path).
```

An empty package selects Java's unnamed package. Package validation rejects
keywords, source/path injection, invisible format characters, and `java.*`.
Unicode identifiers are accepted using the pinned Go toolchain's character
tables: this is a conservative subset, not all identifiers in newer Java Unicode
versions. Generation tests also compile unnamed, Unicode, dollar-sign and
contextual-keyword packages with Java 25.

## Implemented sources

- `Rational`: immutable normalized `BigInteger` numerator/denominator, exact
  arithmetic and comparison, canonical literal read/show, checked/wrapping
  fixed-width integers, and finite decimal output with explicit rejection of
  repeating decimals. No silent floating-point conversion or rounding.
- `TextCodec`: unchanged Java UTF-16 strings, copying unit-array access,
  canonical ASCII-escaped read/show, strict UTF-8 boundaries. Escaped lone
  surrogates survive read/show but are rejected by UTF-8 encoding.
- `Timestamp`: immutable RFC 3339 values with exact fractions, retained spelling
  and offset metadata, instant equality/order, and pinned leap-second knowledge.
  Explicit civil-coordinate and elapsed-SI duration methods do not silently
  substitute for one another.
- `RegexProgram`: Go/RE2-dialect source parsing, normalization, compilation and
  metered full matching/search, with pinned Unicode classes and simple folding.
  The same engine executes dynamic Java DSL `matches` and `search` predicates.
- `Validation`: sealed outcomes and checks, immutable diagnostics, ordered
  collection and the three predicate combiners. Invalid dominates unknown while
  retaining an incomplete flag and all collected diagnostics.
- `ValidationException`: an ordinary unchecked exception carrying the outcome.
  `Outcome.orThrow()` rejects both invalid and indeterminate results. Messages
  do not automatically interpolate payloads. Callers can use try/catch or wrap
  calls in Vavr themselves; the runtime has no Vavr dependency.
- `Budget`: nested logical-step meters matching Go's unsigned 64-bit limits,
  defaults, caller tightening and failed-step behavior. Successful work charges
  every enclosing meter and the overall budget once. Instances belong to one
  execution; they are not shared mutable global state.

These are runtime primitives; [semantic models](JAVA-MODELS.md) are emitted by a
separate generation API. The initial
generated contract validator below uses them and precharges literal expansion;
calling `Rational.parse` directly does not provide sandbox resource isolation.
The current 65,536-bit integer-width guard matches Go's development primitive,
not the final shared resource policy. Native schema regex dialects, schema-derived
complete model shapes, Jackson/Avro codecs,
schema-derived test generators, Maven wiring and the full CLI generation path
remain required. Nothing here establishes full product conformance.

## Verification

Tests compile emitted sources with `javac --release 25 -Xlint:all -Werror`.
The shared fixtures and 5,670 Go/Java vectors exercise arithmetic, malformed
literals, text/UTF-8, all check sequences through length five, and nested budget
traces including values above signed 64-bit range.

JetBrains jetCheck 0.3.0 runs four 2,000-iteration law suites with fresh random
seeds on each invocation. A separate intentionally false property verifies
shrinking and serialized minimal-case replay. Only that infrastructure regression
uses a fixed replay seed; real property failures retain jetCheck's replay hints.
The validation generator grows before capping its size, avoiding exhaustion of
the finite set of small three-state lists. Small cases remain exhaustively
covered by the cross-runtime vectors.

Provide Java 25 via `REFINE_JAVA_HOME`, `JAVA_HOME`, or `PATH` (the test helper also
recognizes Homebrew's `openjdk@25`). Provision the two test jars from Maven Central
into a directory, then run:

```sh
REFINE_REQUIRE_JAVA=1 REFINE_JETCHECK_DIR=/path/to/test-jars go test -race ./...
```

Required jars: `org.jetbrains:jetCheck:0.3.0` and
`org.jetbrains:annotations:13.0`. Tests verify pinned SHA-256 digests before
executing either jar. Tests and generation do not download dependencies.
CI provisions them explicitly and requires the Java gate on Linux and macOS.
Without `REFINE_REQUIRE_JAVA=1`, a missing Java compiler or absent dependency
directory produces an explicit skip, not release evidence. Incorrect/missing
jars in a configured directory are failures.

The Java production runtime depends only on the JDK. jetCheck and annotations
are test-only; see [dependency roles](DEPENDENCIES.md).

## Compiled contract validators

`GenerateValidator(program, packageName, className)` accepts a statically checked
`*language.Program` and emits ten files: the seven primitives above, immutable
`Data` payload trees, `ContractRuntime` execution support, and the named contract
class. It returns no files if generation fails and performs no filesystem writes.
The generated contract holds a private immutable definition graph; it does not
read schema source, load plugins, or call Go at runtime.

```go
program, err := language.Compile("type Age = Int where it >= 0")
// Handle err, then:
files, err := java.GenerateValidator(program, "com.me.project", "Contract")
```

After writing those sources to a Java 25 project:

```java
Data age = new Data.Number(Rational.of(21));
Validation.Outcome result = Contract.validate("Age", age);
Data unchanged = Contract.requireValid("Age", age); // Same object, or exception.
String canonical = Contract.showWithoutValidation(age); // "21", without checking Age.
```

`validate` also accepts caller `Budget.Limits`. Each invocation owns its meters,
typed view and diagnostics. The input is never modified, even when the typed
record view excludes extras or supplies an absent optional field. This API uses
explicit language payload constructors, **not JSON or Avro wire conventions**.

Supported structural forms include records, aliases, lists, generic/recursive
tagged unions, `Maybe`, `Nullable`, `Result`, Bool/String, arbitrary integers and
rationals, and checked fixed-width integers. Primitive-looking user declarations
such as `Int01` remain ordinary named types. Field and whole-structure predicates
share Go's per-clause reporting, stable generated codes, default/custom messages,
invalid-plus-unknown aggregation, and structural/expression budget accounting.
Custom-message failure preserves the conclusive violation and generated fallback.

The expression emitter handles literals, `it`, field projection, numeric/Boolean
operators, equality, concatenation/cons, conditionals, record/list literals, and
local bindings with ordinary and inline-refined type annotations. Named functions support generic
instantiation, recursion, partial application, higher-order arguments/results,
zero-argument definitions and ordered equations. Case/function patterns support
bindings, wildcards, literals, constructors, lists and cons patterns.

Implemented builtins are `not`, `isInteger`, `show`, `read`, `length`, `reverse`, `map`, `filter`,
`foldl`, `oneOf`, `elem`, `unique`, `all`, `any`, `satisfiesAll`,
`satisfiesOnlyOneOf`, `satisfiesOneOf`, and `satisfiesAtLeastOneOf`. Quantifiers
preserve three-outcome behavior: a later decisive result can survive an earlier
unknown; nested attempts resume at the correct outer continuation/depth.
Arguments are eager, even when the function ignores them. First-class functions
remain private execution values, never variants in the public `Data` payload API.

Anonymous refinements execute at local binding and function boundaries, including
fields, lists, optional/result types and generic constructors. Immutable function
guards enforce preconditions at each curried application and postconditions on
results, including higher-order and returned functions. Named parent predicates
are not re-run merely for substitution. Every inline `where` executes; a false
predicate dominates unknown inner clauses, even if its custom message fails.
An inline assertion failure is an evaluation error: the enclosing payload rule
reports indeterminate, rather than mistaking a failed computation for `False`.
Nested clauses share their enclosing budgets and the continuation queue, so
recursive contract predicates obey logical depth limits without JVM recursion.

Java regex `matches`/`search` execute both literal and payload-supplied patterns,
including named/higher-order use, inline assertions and typed reads. Malformed
patterns and resource exhaustion produce indeterminate evaluation diagnostics,
not false matches; conclusive predicate-combination results retain Go's recovery
behavior. Pattern text is omitted from parser errors.
Function-valued payload fields are not serializable payload types.
Unsupported rules are never dropped. The missing execution forms remain release
obligations, not optional extensions.

### Canonical display

`show` executes directly and through higher-order functions, local aliases and
guarded functions. Exact numbers use reduced fractions; text quotes and escapes
every non-ASCII UTF-16 code unit, including lone surrogates. Lists and constructor
arguments retain order. Record fields sort by Unicode scalar order, not Java's
UTF-16 lexicographic order. Negative and fractional constructor arguments receive
parentheses so the reader cannot mistake them for arithmetic.

`Contract.showWithoutValidation(data[, limits])` also displays raw `Data` without
checking a named schema or reasserting refinements. It can therefore show an
invalid bypass-created model through `model.rawData()`. It does not mutate or
coerce that value. Resource or representation failures throw `ValidationException`
with a diagnostic outcome and no partial text; names that cannot be represented
in the language's canonical grammar are rejected. This API is not JSON/Avro
serialization and is not evidence of a successful validating read.

Display and structural transfer use the same logical-step/depth policy as Go,
without host recursion. The generated contract embeds Go's Unicode classification
tables and their upstream license notice so identifiers do not change meaning
when the target JDK upgrades its Unicode tables.

Verification includes 71,400 Go/Java report and raw-display comparisons over
exact fractions, structured values, optional/null/result variants, higher-order
display, escaped surrogates, scalar ordering, invalid names, deep values and
budget boundaries. The Java classifier is checked against Go for all 1,114,112
code points. Another 4,000 jetCheck cases exercise arbitrary UTF-16 strings,
rational display, higher-order equivalence and raw-value preservation.

### Typed, validating reads

The `read` builtin uses its inferred `Result String target` type, including
generic, higher-order and local-reader bindings. It interprets only data forms:
numbers and exact fractions, quoted text, Booleans, lists, records and tagged
constructors. It parses but never executes function calls, arithmetic, `let`,
`if` or `case` expressions supplied as text. Syntactic variants such as comments,
whitespace and parentheses follow the same grammar as Go.

Successful target validation produces `Ok value`. Malformed data or a conclusive
target violation produces `Err message`; an indeterminate target or exhausted
execution budget remains an evaluation failure, not an accepted value or a
misleading parse error. Recursive reads share the enclosing meters and logical
depth. Validation, predicate execution and custom messages use one continuation
queue, so nested reads cannot reset budgets or recurse on the JVM stack.

The public boundary is `Contract.read(root, text[, limits])`, which returns a
`ContractRuntime.ReadResult`. Its `outcome()` carries the full validation report;
`data()` is non-null only for a valid read. `orThrow()` returns that value or
throws the ordinary `ValidationException` for invalid/indeterminate outcomes.
Generated models also have direct `Model.read(text[, limits])` factories, which
construct from the reader's nominal evidence without repeating validation.

```java
var result = Contract.read("Age", "21");
Data value = result.orThrow();
Age age = Age.read("21");
String canonical = age.showWithoutValidation();
```

Reads check all declared refinements, including values previously created via a
bypass. They return the checked typed view: undeclared record fields are omitted
and absent `Maybe` fields become `Nothing`. This differs from `fromData`, which
retains the supplied raw payload. A raw lone surrogate in input text is rejected;
surrogate payload units must appear inside a quoted escaped string. Timestamp
reads accept quoted RFC 3339 text and preserve the original spelling.

Verification compares 34,575 complete reports and read values against Go, plus
11,717 parser differential/resource cases. The parser tests compare complete
expression/type/pattern tree structure and test the 512-level, 16 MiB UTF-8 and
one-million-token limits. All run with `-Xss256k`. Four 2,000-case jetCheck suites
cover arbitrary UTF-16 round trips, exact rationals/refinement enforcement,
structured recursive/optional payload round trips and deterministic handling of
arbitrary text. Model tests cover direct typed factories, parent evidence,
method/field collisions, failed reads and invalid-bypass revalidation.

### Exact timestamps

`Timestamp` is an immutable value rather than `Instant` or `OffsetDateTime`:
those Java types cannot retain all supported fractional precision, unknown-local-
offset metadata and leap-second labels. Boundary payloads remain ordinary
`Data.Text`; the evaluator parses a separate typed view and never rewrites the
caller's raw data. Named timestamp models expose `Timestamp` through `value()`;
its `raw()` accessor returns the original RFC 3339 text.

```java
Timestamp leap = Timestamp.parse("2016-12-31T23:59:60.000000000001Z");
String unchanged = leap.raw();
String canonical = leap.show(); // Quoted canonical text, retaining spelling.
```

The parser follows the agreed [RFC 3339](https://www.rfc-editor.org/rfc/rfc3339)
profile: years 0000–9999, lower-case `t`/`z`, exact decimal fractions, minute
offsets through ±23:59, and `-00:00` metadata. Equality and ordering compare
instants, not spellings. Equal instants have equal Java hash codes even when
precision/offset metadata differ. `Timestamp.EPOCH` is the Unix epoch.

Leap labels use the same `IERS-C72-2026-07-06` table as Go. A known-invalid leap
label is invalid; a possible leap beyond the announced interval is indeterminate,
including during structural bypass validation. No network, clock or timezone
database participates. The table is based on
[IERS Bulletin C](https://hpiers.obspm.fr/iers/bul/bulc/bulletinc.dat) and its
[historical leap dates](https://hpiers.obspm.fr/iers/bul/bulc/Leap_Second.dat).

Generated validation charges `1 + UTF16Length²` before parsing. Timestamp
comparison charges `1 + len(leftFraction.show()) * len(rightFraction.show())`;
display and read export charge the retained spelling length, matching Go.
All target checks and nested reads retain the shared caller/per-clause budgets.
Primitive `Timestamp.parse` itself is unmetered and throws `Timestamp.Error`
with a sanitized `code()`/message; generated APIs translate failures into their
ordinary validation outcomes/exceptions.

`civilSecondsUntil` rejects leap-labelled endpoints and excludes inserted leaps.
`siSecondsUntil` includes known leaps, but rejects endpoints outside the pinned
post-1972 announced interval. Both return exact `Rational` values. These are
explicit primitive APIs, not yet a DSL duration vocabulary.

Timestamp tests compare primitive parsing, metadata, ordering and durations with
Go, then compare full validation/typed-read reports and budget boundaries.
Every UTC month boundary in the pinned history and every legal minute offset
around a known leap are covered. Three 2,000-case jetCheck suites exercise offset
equivalence, typed model round trips, exact durations, atomic multi-field updates,
bypass revalidation and arbitrary UTF-16 inputs, with a 256 KiB JVM stack.

### Regex parsing, compilation and execution

`pattern.Regex.Program()` exports a detached Go instruction snapshot with
`Profile`, `UnicodeVersion`, `Start`, and typed `Instructions`. Mutating any
snapshot field, instruction or rune range cannot affect the compiled Go regex.
The original `pattern.Fold` helper remains available for existing Go consumers.
This development instruction profile is not a native schema encoding or a
promise that different compiler versions produce identical instruction graphs.

Java `RegexProgram` takes the matching instruction profile/Unicode version,
entry point, and immutable instructions. It rejects unknown profiles, invalid
reachable targets, malformed rune ranges and unsupported assertion masks before
execution. Unreachable fragments may retain Go compiler patch-list links; they
are frozen and cannot become reachable after construction.
Go `OpcodeName` supplies the corresponding Java enum names. Captures are traversed
but not exposed: the current predicate API returns only a Boolean match result.

`match(subject, Mode.FULL | Mode.SEARCH, Budget.Meter)` uses iterative state sets,
not backtracking. It preserves UTF-16 surrogate identity while treating valid
pairs as one code point. Word boundaries remain ASCII, as in the Go refinement
dialect; case folding uses embedded Go Unicode tables, not JDK case conversion.
Programs can be shared concurrently; mutable state belongs to each invocation.
Direct instruction-plan construction is an unmetered trusted-compiler boundary.
Matching charges
the same traversal, instruction, rune-range and folding costs as Go. Exhaustion
throws `RegexProgram.Error` with `code() == "regex.budget"`, retaining the shared
meter's exact used/exhausted state and allowing enclosing-scope recovery when
the budget permits.

Tests compare 420 Go-compiled programs and 87,252 full match/budget traces,
including nested scopes, post-failure recovery, both matching modes, all
instruction kinds, zero-width assertions, surrogate subjects, nullable cycles,
large programs and ambiguous repetition. They compare simple folding for every
Unicode code point. Three 2,000-case jetCheck suites check literal matching,
code-point matching and exact budget thresholds; further checks cover immutable
snapshots, malformed plans and concurrent reuse, at `-Xss256k`.

`RegexProgram.compileTree(Tree, Budget.Meter)` compiles already parsed and
normalized trees into the same instruction graph as Go's `regexp/syntax`
compiler. Immutable `Tree` values describe literals, inclusive rune ranges,
assertions, captures, concatenation, alternation and greedy/lazy repetitions.
The method meters tree traversal and an unsigned-64-bit expansion bound before
simplifying counted repetitions or allocating instructions. Nesting at depth 512
and expansion overflow produce `regex.limit`; exhaustion produces `regex.budget`.
Simplification and compilation use explicit work queues, including repetition
expansions deeper than the source tree, so execution does not depend on JVM stack
depth. Source parsing and the initial source-size cost are not part of this API.

Compiler tests compare 2,243 parsed patterns and 2,021 synthetic/random trees,
with 20,454 exact instruction-digest/budget comparisons. They cover dead fragments,
nullable loops, greedy/lazy bounded and unbounded repetitions, large expansions,
nested scope recovery and depth/overflow boundaries. Another 6,000 jetCheck cases
check repetition languages, exact compilation budgets and depth guards at
`-Xss256k`. Digest comparisons include all instructions, even unreachable ones.

`RegexProgram.compile(String, Budget.Meter)` accepts dynamic pattern text.
`parseTree(String, Budget.Meter)` exposes the immutable normalized tree; it
charges `1 + sourceUTF16Length²` and checks scalar pattern text before parsing.
Calling `compileTree` on that result charges the remaining expansion/compiler
work. Each compilation charges its full logical cost; no cache makes budget
outcomes depend on previous calls.

The source parser follows Go's Perl-mode regex dialect and normalization:
literal-prefix factoring, safe simple-prefix factoring, class merging, captures,
flags, Unicode categories/aliases, POSIX/Perl classes, quoted literals and
greedy/lazy repetition. Parser allocation/repetition/height limits are checked
before compilation. Work queues handle recursive factoring and explicit stacks
handle size/depth checks, tree freezing and instruction execution. Unicode
vocabulary and ranges come from the Go parser, not JDK Unicode or Java regex.
Some Unicode table names are not accepted by that parser; Java retains those
rejections instead of introducing a different vocabulary.

The source suite passes 104,422 exact normalized-tree/instruction/error/budget
comparisons across 26,301 patterns, including malformed text, every available
Unicode category/script/alias lookup, nested syntax, deep alternative factoring
and compiler resource boundaries. A further 30,390 complete report/read
comparisons cover dynamic evaluation, higher-order calls, inline contracts,
short-circuiting, three-outcome recovery, private/custom messages, clause limits
and typed reads. Each suite adds 6,000 jetCheck cases. Model tests cover validated
construction, atomic updates, raw values, bypass revalidation and concurrent use.
All generated Java compilation uses warnings-as-errors and `-Xss256k` execution.

These establish current Go/Java refinement-dialect conformance, not automatic
compatibility with future changes to Go's regex compiler or Unicode tables.
Release-stable cross-toolchain profile auditing remains required. Native schema
regex dialects are separate requirements and are not silently replaced by this
refinement engine.

Canonical reading is not JSON/Avro serde or native schema ingestion; those remain
separate release obligations.

### Initialization and execution evidence

Contract initialization is emitted as dependency-ordered
chunks: bounded static initializers, bounded list construction, sequential class
loading, and split long string constants. This removes the former 48,000-byte
contract-source guard without raising JVM stack or method-size limits. Helpers
are package-private implementation classes in the same contract source file;
the public API and eight-file validator source set are unchanged. This does not
remove the separate development limits on semantic model shapes/source sizes.
Expression-to-signature links use a deferred, finite metadata table: a function's
contract may refer recursively to the same function without infinite expansion
during generation or class initialization. Declaration lookup retains source
order because the Go evaluator charges for that traversal.

Verification compares **26,500 complete Go/Java validation reports**, including
diagnostic paths, codes, predicates and messages, across successful, malformed,
unknown, tiny-budget, overflow and deep-tree cases. Three jetCheck suites add
5,000 fresh-seeded cases for generated age, interval and recursive tree contracts.
The all-leaves-checked tree law deliberately generates trees within the documented
resource limits; separate over-limit cases require Go/Java agreement instead.
Emitter tests cover all-or-nothing rejection, unsafe class names, detached syntax
copies, escaped controls/lone surrogates, and deterministic output. A multi-megabyte
generated-contract fixture covers 1,100 named refinements, a 1,100-field record,
a 1,100-alternative tagged union, 70,000-character custom messages and constants,
and a long supplementary-Unicode diagnostic code. Large collection literals and
70 separately reported rules verify list/diagnostic ordering across chunks.
Its complete reports match Go,
including inactive-branch behavior, with a 256 KiB JVM stack. Property tests also
cover string splitting across supplementary characters, NUL and Java escapes.

Traversal and expression execution use explicit continuation frames, not Java
recursion. The logical 512-level guard and budget charges remain the same as Go's
current evaluator policy. Full-report tests run with a deliberately small
`-Xss256k` JVM stack; an additional 18,534 comparisons stress deep record equality,
deep mismatches, long arithmetic expressions and their total/per-clause budget
boundaries. Within-policy inputs must still produce conclusive results.

Function execution adds 166,054 complete-report comparisons across recursion, generic
and higher-order calls, patterns, all quantifier truth-table sequences through
length four, tiny budgets, nontermination/depth recovery, fixed-width overflow,
eager ignored arguments and custom-message functions. These include 84,006
inline-contract comparisons covering eager partial-application checks, guarded
arguments/results, nested containers, anonymous local function annotations,
recursive contracts, rule aggregation and failing/budget-limited messages.
An additional 3,000 jetCheck cases exercise recursive sum, higher-order/unknown
composition, inline boundary enforcement, bypasses and inner-rule aggregation.
Generated semantic model tests also enforce function-backed predicates in normal
constructors while preserving explicit bypass behavior.

The report comparisons exercise both normal validation and structural-only
bypasses. Java `validateStructure` corresponds to Go's explicit
`ValidateDataWithoutRefinements`; both preserve structural traversal/limits while
skipping predicate execution.

[Semantic models](JAVA-MODELS.md) now connect this validator to typed construction
and atomic updates. Complete model shapes, serde, schema-derived test generation,
native-format ingestion/exports, Maven integration and the generation CLI remain
outstanding. `Data` is payload plumbing, not a replacement for domain types.
