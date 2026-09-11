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
timestamp validation/comparison now have an in-memory implementation. The Java
implementation remains unfinished. See [runtime semantics](RUNTIME.md) for the
refinement regex dialect, timestamp precision, and leap-second policy.
`read` needs an inferable target type; for example:

```haskell
positiveText :: String -> Bool
positiveText text =
  let parsed :: Result String Int = read text in
  case parsed of { Err _ -> False; (Ok n) -> n > 0 }
```

Still required: constraint-qualified polymorphism for overloaded operations,
full conversion/fixed-width literal semantics, import resolution, remaining execution,
schema lowering, English explanation, and cross-runtime conformance. Currently
underconstrained equality/length/numeric operations request a concrete annotation;
they are not silently accepted with invented semantics. In particular, functions
and collections containing functions cannot be compared for value equality.

## Formatting and diagnostics

`refine fmt` writes deterministic, explicitly parenthesized source to stdout.
It preserves declarations, types, rules, metadata, and equation order, but not
comments or original Haskell-like whitespace. Native document preservation is
handled separately by the lossless JSON layer.

The command `refine typecheck --json file.refine` reports its phase explicitly.
Success means static checking succeeded; it does not claim native schema validity,
satisfiability, compatibility, or successful payload validation. Those commands
and gates must be implemented before a product release.
