# Numeric domains and explicit precision

`Int` is an arbitrary-precision integer and `Real` is an exact rational. A
decimal literal denotes its exact mathematical value, and division returns
`Real`; neither operation passes through a host floating-point value.

`Float32` and `Float64` are explicit finite IEEE-754 binary domains. Their
runtime representation remains an exact rational, but validation admits only
values which are exactly representable in binary32 or binary64. NaN and
positive or negative infinity are not language values. Positive and negative
IEEE zero have the single language value `0`, so signed-zero identity is not
preserved.

Conversions make every precision change visible:

```haskell
toFloat32      :: Real -> Result String Float32
toFloat64      :: Real -> Result String Float64
roundToFloat32 :: Real -> Result String Float32
roundToFloat64 :: Real -> Result String Float64
fromFloat32    :: Float32 -> Real
fromFloat64    :: Float64 -> Real
```

`toFloat32` and `toFloat64` are exact and fail if their argument is not already
representable in the requested finite domain. `roundToFloat32` and
`roundToFloat64` explicitly round to nearest, with ties to an even significand;
values below the subnormal range may round to zero, and they fail when the
rounded result would be infinite. `fromFloat32` and
`fromFloat64` widen without changing the mathematical value.

Addition, subtraction, multiplication, and negation of a fixed-precision value
retain its type only when the exact result is representable. Otherwise
evaluation reports `evaluation.precision`; these operators never silently
round. Division continues to produce exact `Real`. Fixed-precision values have
`Num`, `Ord`, `Eq`, `Show`, and `Read` capabilities, but not `Integral`.

Canonical `show` uses the exact reduced rational form and typed `read`
revalidates the target domain. Consequently, showing then reading a valid
fixed-precision value preserves it exactly.

Native floating-point wires must enforce the same domain. Avro float/double
decode only finite bit patterns and encode only exactly representable values.
JSON and OpenAPI `format: float` or `format: double` are annotations rather than
validators, so generated validation still enforces finite exact
representability. Since every finite binary float has a terminating decimal,
JSON encoding can be lossless without a separate `Real` wire policy.

Exact-number parsing is an unmetered value primitive whose callers must bound
literal length and exponent expansion before parsing. Language evaluation does
this against its validation budget. The conservative interval analyzer declines
an over-budget numeric literal with `analysis.resource` and `unknown`; resource
exhaustion is never reported as unsatisfiable or as a compatibility proof.
