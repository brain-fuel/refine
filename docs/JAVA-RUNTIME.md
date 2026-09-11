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

These are runtime primitives, **not yet generated domain models or a Java
predicate evaluator**. The evaluator must precharge numeric parsing/expansion;
calling `Rational.parse` directly does not provide sandbox resource isolation.
The current 65,536-bit integer-width guard matches Go's development primitive,
not the final shared resource policy. Java regex/timestamps, schema-derived
models, typed compound read/show, Jackson/Avro codecs, validated update APIs,
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
