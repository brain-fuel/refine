# Release readiness

This is a source audit, not a replacement for [SPEC.md](../SPEC.md) or a claim
that passing CI completes the product. The implementation log is chronological;
an old entry saying a feature is missing may have been superseded. Check the
current API and its focused regression before scheduling more implementation
or repeating an expensive integration test.

## Implemented boundaries

| Requirement area | Current implementation and evidence location |
| --- | --- |
| GoPlus and Go distribution | Authored `.gp` and generated Go; pinned module tool; generation consistency and ordinary Go consumers. See [IMPLEMENTATION.md](IMPLEMENTATION.md). |
| Language and Java domain model | Exact arithmetic/text, checked functions and recursion, nominal/generic models, immutable updates, raw-value access, three-outcome validation and schema/caller budgets. See [LANGUAGE.md](LANGUAGE.md), [JAVA-MODELS.md](JAVA-MODELS.md), and [JAVA-RUNTIME.md](JAVA-RUNTIME.md). |
| Native ingestion and wire validation | Explicit offline resource sets, exact originals, editable projects, and composed JSON/Avro boundaries. Native semantics and projection are separate guarantees. See [NATIVE.md](NATIVE.md). |
| Java serde | Jackson 3 and Apache Avro binary/JSON adapters; validated construction/read/write, staged output, explicit refinement bypasses. Avro `big-decimal` physical bytes are supported; semantic `Real` conversion is not implicit. See [SERDE-JSON.md](SERDE-JSON.md) and [SERDE-AVRO.md](SERDE-AVRO.md). |
| English and ordinary output | Algorithmic explanations and explicit documented-loss controls; unsupported exact wire representations reject. See [EXPLANATIONS.md](EXPLANATIONS.md). |
| OpenAPI execution | Checked semantic-JSON request/response/context facade, real request tokens, rootless operation projects and same-artifact Maven assembly. See [OPENAPI-CONTEXT.md](OPENAPI-CONTEXT.md) and [PROJECT.md](PROJECT.md). |
| Generated tests and examples | JetCheck strategies, clause-targeted invalid properties, explicit generation exhaustion, and worked example families. Operation-specific coverage has its own API and limitations. See [GENERATED-TESTS.md](GENERATED-TESTS.md). |
| Release workflow | Immutable histories, content-bound approvals, semantic-version planning, recoverable promotion, publication-ledger and Maven class-removal gates. Rootless operation comparison checks opposite request/response directions and retains unknown relational/native-wire/ABI evidence. See [RELEASE.md](RELEASE.md). |

The entries above identify existing code and tests, not unrestricted support for
every schema construct. In particular, an explicit unsupported error is safer
than silent weakening but is still a gap when the agreed first-release scope
requires that operation.

## Confirmed unfinished first-release work

- Complete OpenAPI operations authored directly in Haskell-like source, without
  a companion native API document. Current payload lowering and metadata-bound
  operation execution do not implement this authoring path.
- Per-constraint native correspondence beyond the documented JSON Schema numeric
  subset, including OpenAPI/Avro adapters. Exact whole-document retention does
  not itself satisfy editable, per-constraint bijection.
- Native ECMA-262 regex conformance: the Go ingestion oracle and generated
  GraalJS matcher are different engines. The current oracle both rejects valid
  Unicode-property patterns and accepts non-ECMA syntax; generated Java support
  does not repair ingestion. A replacement must match syntax, matching semantics
  and Unicode data across both boundaries, not just accept one extra spelling.
- Remaining native projection/annotation and scoped-edit boundaries documented
  in [NATIVE.md](NATIVE.md), including general reference projection, per-OpenAPI-
  object annotations, and unsupported scoped changes beneath applicators.
- All-zero-semantic-part OpenAPI Java catalogs still reject generation. Supporting
  them must validate the actual empty transport envelopes, not credit unrelated
  generated payloads that are discarded before validation.
- Compatibility approvals and breaking-fix policy currently live in checked-in
  `refine.project.json`. That satisfies persistence and content binding, but not
  the stricter agreed schema-file-carried approval requirement. A portable schema
  annotation needs an explicit identity rule that excludes the approval itself
  without excluding any contract content; a self-referential raw-file digest
  cannot serve that purpose.

General satisfiability and compatibility may correctly remain `unknown` under
the agreed contract. A sound unknown result, enforced through the existing
checked-in override policy, is not a requirement to solve arbitrary recursive
proofs before release. Likewise future target languages, lambdas, HTTP stubs and
application-owned Java adaptation beyond serde are explicitly deferred.

## Publication boundary

The current goal excludes Maven deployment. Maven coordinates remain a user
choice; that does not block implementation or unsigned artifact verification.
No product tag should be represented as release-ready until the required gaps
above and the final integration audit are resolved. Prepared sibling Hugo edits
do not imply that those edits have been pushed or deployed.

## Test evidence policy

Use [TESTING.md](TESTING.md) for exact selections and input-sensitive reuse.
Record the command, covered behavior, tool/dependency inputs, outcome and source
checkpoint. Reuse successful focused evidence on unchanged relevant inputs;
rerun failed checks only after a relevant correction. A documentation correction
alone does not justify another JVM, Maven lifecycle or fuzz campaign.
