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
| Generated tests and examples | JetCheck strategies, clause-targeted invalid properties, explicit generation exhaustion, and worked example families. Zero-part OpenAPI occurrences use real empty transport envelopes and singleton replay. Operation-specific coverage has its own API and limitations. See [GENERATED-TESTS.md](GENERATED-TESTS.md). |
| Release workflow | Immutable histories, schema-carried content-bound approvals, semantic-version planning, recoverable promotion, publication-ledger and Maven class-removal gates. Rootless operation comparison checks opposite request/response directions and retains unknown relational/native-wire/ABI evidence. See [RELEASE.md](RELEASE.md). |

The entries above identify existing code and tests, not unrestricted support for
every schema construct. In particular, an explicit unsupported error is safer
than silent weakening but is still a gap when the agreed first-release scope
requires that operation.

## Confirmed unfinished first-release work

- Finish the checkpoint integration gate for complete OpenAPI operations authored directly in
  Haskell-like source without a companion native API document. The frontend,
  native assembly, project/release workflow and first real generated-Java
  authoring anchor are implemented. Repeated/inherited clause identities and
  the affected operation-property replay contracts passed their required-Java
  anchors and the Java integration package. The unsigned Maven lifecycle passed
  all four phases in 72.26s. Pushed-checkpoint Java and Maven packages passed on
  both CI platforms, but Go regex initialization failed; the next checkpoint
  must verify its focused-tested backend correction in CI.
- Per-constraint native correspondence beyond the documented JSON Schema and
  OpenAPI numeric, `const`/`enum`, and collection-count subsets, Avro fixed sizes
  and ordered enum symbols. Paired OpenAPI 3.0 bounds are now implemented.
  Resource-scoped edits now
  rebuild effective validation/export/bundle views; exact whole-document
  retention alone does not satisfy editable, per-constraint bijection.
- Complete the shared native ECMA-262 regex integration gate. Go and generated
  Java now use the same pinned guest artifact, syntax and Unicode data through
  Wazero and Chicory respectively. Go race, Java lifecycle/adversarial,
  native-consumer, resource, serde and operation-catalog checks pass. The final
  Maven lifecycle and both CI Java packages pass. CI exposed forced-interpreter
  initialization failures in Go; the corrected auto-selected Wazero backend and
  affected native callers pass locally, with the next CI gate outstanding.
- Remaining native ingestion and enforcement boundaries documented in
  [NATIVE.md](NATIVE.md), including general OpenAPI reference projection.
  Selected Schema Objects and direct operation-part annotations are implemented
  and fail closed on unsupported reachable OpenAPI annotations. The equivalent
  JSON Schema/Avro project-boundary audit now rejects annotations outside the
  selected explicit root rather than accepting source it would not enforce.
  JSON Schema external recursive references,
  canonical IDs and static anchors are implemented across Go projection,
  validation and generated Java offline loaders. Dynamic references now use
  the intrinsic JSON carrier while retaining native authority; Go and required
  Java tests cover dynamic-scope overrides and validated serde boundaries.

## Requirements audit distinctions

The native-translatable subset needs an explicit exactness inventory, not an
assumption that every similarly named builtin is equivalent. For example,
native regex validation now shares an ECMA-262 engine across Go and Java, but
the refinement language's regex syntax still uses its separate RE2-based
parser. That integration does not establish an exact native `pattern` to
language-regex correspondence. Native string length and Refine UTF-16 length
also have different semantics.

Per-object embedded annotation composition and arbitrary replacement of a
scoped provenance unit are not separately agreed first-release APIs. The
required authoring forms can express field and whole-structure refinements in
the selected embedded module or standalone source. Arbitrary additional rules
must remain enforced and explained, and untouched native constraint units must
retain their correspondence. Unsupported annotation placements must reject;
unsupported scoped rewrites must not retain a stale assertion as though the
edit succeeded. These safety obligations remain release requirements even when
the more convenient composition or scoped-rewrite APIs are deferred.

General satisfiability and compatibility may correctly remain `unknown` under
the agreed contract. A sound unknown result, enforced through the existing
checked-in override policy, is not a requirement to solve arbitrary recursive
proofs before release. Likewise future target languages, lambdas, HTTP stubs and
application-owned Java adaptation beyond serde are explicitly deferred.

## Publication boundary

The current goal excludes Maven deployment. Maven coordinates remain a user
choice; that does not block implementation or unsigned artifact verification.
No product tag should be represented as release-ready until the required gaps
above and the final integration audit are resolved. The sibling Hugo page and
vanity imports were explicitly approved, pushed as `8537d17` in
`brain-fuel/dev.goforge`, and verified live on 2026-09-19. That page describes an
unreleased development checkpoint, not a completed product release.

## Test evidence policy

Use [TESTING.md](TESTING.md) for exact selections and input-sensitive reuse.
Record the command, covered behavior, tool/dependency inputs, outcome and source
checkpoint. Reuse successful focused evidence on unchanged relevant inputs;
rerun failed checks only after a relevant correction. A documentation correction
alone does not justify another JVM, Maven lifecycle or fuzz campaign.
