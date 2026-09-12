# Qualified polymorphism

Named polymorphic functions may use `Eq`, `Show`, `Read`, `Num`, `Integral`, and `Ord`
capabilities. A source signature can state them explicitly:

```haskell
same :: Eq a => a -> a -> Bool
same left right = left == right

roundTrip :: (Show a, Read a) => a -> Result String a
roundTrip value = read (show value)

twice :: Num a => a -> a
twice value = value + value

before :: Ord a => a -> a -> Bool
before left right = left < right

remainder :: Integral a => a -> a -> a
remainder left right = left % right
```

The same constraints may be omitted. The checker infers the least set required
by the function body and propagates it through forward, higher-order, recursive,
and mutually recursive named-function references. `CheckedSyntax` exposes the
effective set in `FunctionCapabilities`; `Syntax` and formatting preserve only
the constraints the author wrote. English export uses the effective set, so an
inferred requirement is not lost from generated documentation.

`Eq`, `Show`, and `Read` are structural. Scalars, lists, records, optional/result values,
aliases, and algebraic data constructors are supported when every value-bearing
component supports the capability. Phantom type parameters do not acquire an
unnecessary requirement. Recursive types are checked finitely. Functions, and
structures containing functions, support none of `Eq`, `Show`, or `Read`.

Every use is checked at its concrete instantiation. For example, a generic
`same` function is valid, while `same not not` is a static type error. A generic
parser can return `a` under `Read a`, but instantiating it as `Int -> Int` is a
static error. An unresolved non-signature variable is also rejected rather than
deferred to an indeterminate runtime codec target.

`Num` admits only an already-bound numeric type. `Integral` is narrower and
admits `Int` and fixed-width signed/unsigned integers, but not `Real`; it governs
`%`. `Ord` admits an already-bound numeric type, `String`, or `Timestamp`.
Nominal aliases retain their underlying capabilities. None performs a conversion.

Capability checking does not execute a predicate or inspect a runtime value.
The existing inferred expression types still carry concrete call-site target
bindings to the Go and generated Java evaluators; in particular, `read` receives
the exact instantiated result type. Go/Java conformance tests exercise canonical
show/read round trips with explicit qualified signatures.

Numeric literals remain concrete: integral syntax has type `Int` and decimal or
exponent syntax has type `Real`. Thus `x + x` may infer `Num a`, while `x + 1`
still fixes `x` to `Int` and cannot pretend the literal was polymorphically
defaulted. Arithmetic retains exact conversion rules and never inserts an
implicit numeric coercion. Anonymous lambdas also remain deferred.
