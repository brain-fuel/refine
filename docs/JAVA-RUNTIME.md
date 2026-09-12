# Java runtime generation (development)

`goforge.dev/refine/java.GenerateRuntime(packageName)` returns deterministic
`File{Path, Source}` values for five Java 25 source files. It performs no I/O.
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
not the final shared resource policy. Java regex/timestamps, schema-derived
complete model shapes, typed compound read/show, Jackson/Avro codecs,
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
`*language.Program` and emits eight files: the five primitives above, immutable
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

Implemented builtins are `not`, `isInteger`, `length`, `reverse`, `map`, `filter`,
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

Java builtin `show`/`read`, regex `matches`/`search`, and timestamps still reject
generation with `java.unsupported` and a source position.
Function-valued payload fields are not serializable payload types.
Unsupported rules are never dropped. The missing execution forms remain release
obligations, not optional extensions.

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
