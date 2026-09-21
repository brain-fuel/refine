# Maven 0.4.0

This Maven release packages `refine-parent`, `refine`, `refine-engine`, and
`refine-maven-plugin` under `dev.goforge`. It does not change the separately
published Go CLI v0.1.0 tag.

## Generated test evidence

Generated suites omit inapplicable codec stubs and report executed properties,
case evaluations, examples, and coverage gaps. Zero-case checks, exhausted
required generators and unexpected failures fail the suite.

Additional payload checks exercise top-level non-generic model getters, JSON
node/depth limits through a plain Jackson mapper, and native JSON rejection
probes. The native-invalid corpus is classified at generation time by the Go
native validator, independently of the emitted Java validator under test.
Limit-test mappers are reused so pattern-bearing schemas do not repeatedly
initialize their regex validators for every case.

Generator regressions inject broken validators, constructors, getters, native
validation, JSON codecs and Avro codecs. A separate regression substitutes a
no-op property runner. These faults must fail executed generated checks, not
merely cause compilation failures.

## Consumer mutation verification

`refine:mutate` runs a healthy control, compiles catalogued production-source
mutations in isolated builds, runs generated properties and application JUnit
separately, and exports evidence for Rice's Tax. It rejects missing/duplicate or
zero-case suite evidence, incomplete/skipped application tests, and process
errors without assertion evidence. Survivors and inconclusive results fail the
goal. No verdict is automatically marked equivalent.

Offscript's eight selected faults cover text loss, getter loss, native validator
bypass and traversal-guard bypass across Country and Holiday. The 0.4.0 candidate's
generated properties caught all eight. Its healthy suites each executed five
properties and 411 case evaluations, plus 12 application JUnit tests across the
project. This is evidence for that finite catalog, not full mutation coverage.

## Limits

Generic/union accessor checks remain a reported gap. Nested getter bodies are not
individually checked merely because their returned model data is compared. Native
rejection probes do not enumerate all schema constraints and do not replace
authored native-invalid model/wire examples. The mutation goal currently supports
standard single-module Java 25 Maven layouts and requires a catalog; it is not an
automatic discovery engine. Rice's Tax verdicts do not suppress survivors in the
mutation goal. Spring clients/servers and Kafka transports remain handwritten.
