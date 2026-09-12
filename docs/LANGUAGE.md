# Refinement language front end

This describes the implemented parser and static checker. The initial in-memory
evaluator is documented in [RUNTIME.md](RUNTIME.md); neither document claims the
full language, native backends, or Java generation are complete. The release
contract remains [SPEC.md](../SPEC.md).

## Declarations

```haskell
package com.example.contracts

type Person = {
  name :: String,
  age :: Int where it >= 0,
  nickname :: Maybe (String where length it > 0)
}

type Child = Person
  where it.age >= 0 && it.age < 18
    @code "person.child_age_range"
    @message "Expected 0 <= age < 18; got " ++ show it.age

data Payment = Card CardDetails | BankTransfer BankDetails

nonEmpty :: [a] -> Bool
nonEmpty [] = False
nonEmpty (_ : _) = True
```

Declarations are separated by newlines or semicolons. Records use comma-separated
fields. Type and data names start uppercase; functions and binders start lowercase.
Type parameters are explicit on type declarations and inferred from named variables
in function signatures. Named functions require signatures. `--` line comments and
nested `{- ... -}` block comments are supported.

`where` binds `it` locally. Repeated clauses stay separate; `&&`/`||` remain ordinary
Boolean expressions within a clause. Optional per-clause metadata uses `@code`,
`@message`, and positive integer `@steps`. This metadata syntax makes the agreed
behavior concrete; it does not make metadata mandatory.

`import "relative/path.refine"` is parsed and formatted without file access.
The standalone static checker currently refuses unresolved imports. The bundler
and multi-module compilation stage remain required work.

## Expressions and patterns

- Application is curried: `every isAdult people`. Named functions can be passed
  as arguments; anonymous lambdas remain deferred as agreed.
- Field projection: `it.age`. Application binds more tightly than arithmetic;
  field projection binds more tightly than application.
- Operators: `||`, `&&`, `==`, `/=`, `<`, `<=`, `>`, `>=`, `:`, `++`, `+`, `-`,
  `*`, `/`, `%`. Cons and concatenation associate right; arithmetic associates
  left. Unary minus is supported. The in-memory evaluator tests eager arguments
  and short-circuit Boolean execution.
- Lists: `[1, 2, 3]`; record expressions: `{age = 21, name = "A"}`.
- Exact string-keyed maps have type `Map String a` and literal syntax
  `map {"key" = value, "other" = value}`. Decoded UTF-16 key sequences are
  compared exactly: escape spelling and entry order are not semantic, while
  case and Unicode normalization are never changed. Canonical display sorts
  entries by UTF-16 code units.
- Conditional: `if predicate then value else alternative`.
- Local binding: `let n :: Int = expression in body`; omit the annotation when
  inference suffices.
- Case analysis uses explicit braces/semicolons:
  `case value of { Nothing -> 0; (Just n) -> n }`.
- Patterns include binders, `_`, literals, `[]`, list literals, cons patterns,
  and nested data constructors. Constructor applications used as a function's
  argument pattern are parenthesized: `f (Just n) = ...`.

`Maybe`, `Nullable`, and `Result` have constructors `Nothing`/`Just`,
`Null`/`NonNull`, and `Err`/`Ok`. These are language forms, not an extra JSON or
Avro wire wrapper. Wire lowering remains a separate, required compiler stage.

## Static checks

The current checker checks declared names and arities, nominal types, parent
substitution, function bodies, ordinary polymorphic instantiation, annotations,
Boolean predicates, String messages, and exhaustive nested patterns. It refuses
direct field access through `Maybe` or `Nullable`; authors must handle both cases.
It also rejects unproductive alias cycles while allowing recursive records/data.

Pattern coverage is a constructor-specializing matrix analysis. Tests compare it
with an independent finite Boolean truth-table oracle. Integer/string patterns
need a binder/wildcard fallback to cover their open domains. Deterministic work
and nesting limits produce resource-limit diagnostics, not a false claim that
unexplored patterns are certainly incomplete.

The front end recognizes signatures for collection operations, predicate
combinators, show/read, and regex predicates. Collection operations and typed
show/read, budgeted full-string `matches`/substring `search`, and RFC 3339
timestamp validation/comparison have conforming Go and generated Java execution.
Map operations are `lookup`, `member`, `keys`, `values`, `size`, `insert`,
`delete`, `mapValues`, `filterValues`, `allValues`, and `anyValues`. They return
new immutable maps and traverse entries in canonical key order; predicate
resource failures remain indeterminate rather than becoming false.
See [runtime semantics](RUNTIME.md) for the refinement regex dialect, timestamp
precision, and leap-second policy.
`read` needs an inferable target type; for example:

```haskell
positiveText :: String -> Bool
positiveText text =
  let parsed :: Result String Int = read text in
  case parsed of { Err _ -> False; (Ok n) -> n > 0 }
```

Named functions support explicit and inferred `Eq`, `Show`, `Read`, `Num`,
`Integral`, and `Ord`
constraints. See [qualified polymorphism](CAPABILITIES.md). Inference propagates
through named forward, higher-order, and recursive references, while a concrete
unsupported instantiation is rejected statically. Numeric literals remain
concretely `Int` or `Real`; `Integral` permits polymorphic remainder without
admitting `Real`; and no implicit numeric coercion is introduced. Length still requests a concrete type.
Anonymous lambdas, symbol-qualified imports, and remaining native integration
are still required.

## Formatting and diagnostics

`refine fmt` writes deterministic, explicitly parenthesized source to stdout.
It preserves declarations, types, rules, metadata, and equation order, but not
comments or original Haskell-like whitespace. Native document preservation is
handled separately by the lossless JSON layer.

The command `refine typecheck --json file.refine` reports its phase explicitly.
Success means static checking succeeded; it does not claim native schema validity,
satisfiability, compatibility, or successful payload validation. Those commands
and gates must be implemented before a product release.

## Code-generation snapshots

`Program.Syntax()` returns detached source syntax without inference metadata.
`Program.CheckedSyntax()` instead returns a caller-owned `CheckedModule`: its
syntax tree, inferred expression types keyed by that same tree's expression
pointers, and the generic-variable scopes for functions and declarations.
The snapshot is produced by checking a fresh tree. Mutating its syntax, type
nodes, maps or scopes cannot change the original `Program` or another snapshot.
Backends can therefore retain the type information needed for polymorphic calls
and typed codecs without gaining access to the evaluator's private checked AST.
# Offline reusable source imports

`language.CompileSources(entry, sources)` accepts an explicit map of canonical,
project-relative source IDs to original source strings. It resolves relative
imports offline, includes shared dependencies once in deterministic dependency
order, and returns an immutable `SourceBundle` containing the checked flattened
program plus original source files, content hashes, import edges and namespaces.
Recompiling `Entry()` with `Sources()` reproduces the same bundled program.

Imports cannot escape the supplied root, open URLs, or access the filesystem.
The CLI's project boundary separately reads project-confined files. Cyclic module
imports and cross-module name collisions reject; mutually recursive declarations
can live in a single module. Package declarations are output namespaces rather
than automatic symbol qualification: the entry package controls the flattened
program, while imported namespaces remain recorded in the bundle. Symbol aliases
and qualified imports remain future language work.

## Scoped local generic annotations

A local annotation may name a type parameter from its enclosing named function
or generic declaration. It does not introduce an unrelated fresh type variable:

```haskell
copy :: a -> a
copy x = let y :: a = x in y

roundTrip :: a -> Result String a
roundTrip x = let restored :: Result String a = read (show x) in restored
```

An undeclared `b`, a value inconsistent with `a`, or a parameter from a different
function is a static error. Inline predicates on the local annotation retain
the same runtime type environment and validation behavior.

## Explicit fixed-width conversions

For canonical widths `N` from 1 through the current backend resource bound of
65,536, signed and unsigned integer conversion families are available:

```haskell
toInt8    :: Int -> Result String Int8
fromInt8  :: Int8 -> Int
wrapInt8  :: Int -> Int8
toUInt8   :: Int -> Result String UInt8
fromUInt8 :: UInt8 -> Int
wrapUInt8 :: Int -> UInt8
```

Checked narrowing returns `Err` on overflow. Widening preserves the exact value.
Wrapping is modulo `2^N`, interpreted in the target's signed or unsigned range.
These operations change only the newly calculated value, not the original
payload. Use `wrapInt8 (fromInt8 x + fromInt8 y)` for explicitly wrapping addition;
ordinary `x + y` on `Int8` still fails on overflow. Fractional inputs require an
explicit exact or rounding conversion to `Int` first. User-defined functions
take precedence over built-in names, including these families.

`Float32` and `Float64` are separate finite, exact-representability domains;
they do not change the default exact `Real` arithmetic. Their exact narrowing,
explicit ties-to-even rounding, widening, arithmetic, and canonical codec rules
are specified in [numeric domains and explicit precision](NUMERICS.md).

Limits are 10,000 supplied files, 16 MiB reachable original/flattened source and
256 import levels. Original parse errors identify their source; cross-module
type errors identify the source owner but use canonical flattened positions.
Automatic source-offset-based diagnostic codes may differ from standalone
compilation. Native per-constraint provenance remains tied to original resource
metadata, not a claim that flattening preserves original byte offsets.
