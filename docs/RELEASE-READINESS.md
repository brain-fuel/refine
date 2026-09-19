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

The source-authored OpenAPI operation frontend, assembly, project/release
workflow, generated Java and unsigned Maven integration gate is complete at
`61b21cd362c91a503d9e1565fb56c327ab410cb3`. Its
[CI run](https://github.com/brain-fuel/refine/actions/runs/35453768722) passed
both Linux and macOS, including selected fuzz targets. That checkpoint also
includes the corrected Go regex backend and checked closed generic annotation
roots. Later edits still require their own affected checks; this does not
substitute for the release gates below.

## Supported native correspondence matrix

The first release does not claim that every native keyword is an editable
Refine clause. Its native-translatable subset is the exact, tested matrix in
[NATIVE-PROVENANCE.md](NATIVE-PROVENANCE.md):

- numeric bounds and `multipleOf`, including paired OpenAPI 3.0 exclusivity;
- `minItems`/`maxItems` and `minProperties`/`maxProperties` on explicit
  singleton collection domains, including non-nullable OpenAPI 3.0 collections;
- bounded intrinsic-JSON `const`/`enum` for Draft 2020-12 and OpenAPI 3.1/3.2
  JSON, plus OpenAPI 3.0 JSON `enum`;
- detached intrinsic-JSON `uniqueItems: true` and JSON-source
  `dependentRequired` units in their documented array/object domains;
- native string `minLength`/`maxLength` through the explicit
  `codePointLength` builtin for JSON and OpenAPI JSON/YAML; the existing UTF-16
  `length` builtin is unchanged; and
- Avro fixed sizes and ordered enum symbols.

Each supported unit has exact token recovery, canonical inverse recognition,
builtin-shadow protection, isolated edits and effective validation/export/bundle
coverage. Resource-scoped edits rebuild those effective views. Constraints
outside this matrix remain byte-exact, native-enforced authority but do not gain
an editable canonical clause. An attempted unsupported scoped rewrite or exact
cross-format claim fails rather than retaining a stale assertion or weakening
the native contract. Adding another sound adapter extends this matrix; it is not
an open-ended prerequisite for the first release.

Native ingestion similarly has an explicit supported boundary rather than an
unfinished promise to infer every OpenAPI shape. Selected Schema Objects and
direct operation-part annotations are composed; unsupported reachable annotation
placements reject. Explicit-resource JSON Schema and OpenAPI 3.1/3.2 references,
recursive logical IDs, static anchors and dynamic validation scope are preserved
across Go and generated Java. Automatic operation projection requires a
statically describable checked shape. Ambiguous structural applicators or dynamic
projections require explicit checked metadata or fail closed; they are never
assigned a guessed payload type. See [NATIVE.md](NATIVE.md) for accepted syntax,
versions and resource limits.

## v0.1.0 release gates

No additional native keyword family is scheduled merely because a convenience
adapter might be possible. A candidate is eligible for a `v0.1.0` tag only when
all of these finite gates are satisfied on one exact commit:

1. Every selected semantic batch, including `codePointLength` and native string
   provenance, is coherently integrated or absent; authored and generated files
   agree and the candidate worktree is clean.
2. The final generation-consistency, race, vet, required Java, selected fuzz,
   CLI and real unsigned-Maven gates pass on that exact commit. Cached focused evidence
   is reusable only when its relevant inputs are unchanged. The pinned
   [GitHub Actions workflow](../.github/workflows/ci.yml) is the source of truth
   for this Linux/macOS release-candidate gate.
3. The actual distributable/JAR dependency and attribution inventory is audited,
   including the embedded Go Unicode/regex notices and regex guest notices
   described in [DEPENDENCIES.md](DEPENDENCIES.md).
4. The documentation support matrix matches the candidate behavior. The green
   commit and `v0.1.0` tag are pushed, and public
   `goforge.dev/refine@v0.1.0` module resolution is verified.

## Documented fail-closed limitations

The supported release is intentionally narrower than the set of every syntactically
legal native document or every possible conversion:

- YAML aliases, merge keys, multiple documents, non-scalar keys and ambiguous
  duplicate keys reject at the bounded syntax boundary. Exact JSON and the
  documented JSON-compatible YAML subset are supported; no expansion is guessed.
- A native constraint outside the correspondence matrix remains enforced and
  byte-preserved, but cannot be advertised as an editable canonical clause.
  Cross-format generation rejects unless the target representation is proven or
  the agreed documented-loss path applies to a refinement rather than a base
  wire-value mismatch.
- Native values that need an undeclared wire convention—such as a repeating
  `Real` in JSON, arbitrary `Int` in Avro, or a union without required explicit
  discriminator metadata—reject instead of acquiring an implicit conversion.
- Automatic OpenAPI projection is limited to statically describable checked
  shapes. Explicit checked operation metadata/source remains available; ambiguous
  applicators and dynamic type projection are not guessed.
- General satisfiability, relational compatibility, native-wire compatibility
  and Java ABI compatibility can be `unknown`. An enforced unknown fails unless
  the exact comparison has a schema-carried, content-bound reviewed override.

These are supported error boundaries, not a backlog whose mere existence blocks
the tag. A limitation becomes a release defect if the tool silently weakens the
contract, accepts an unsupported edit as exact, skips required enforcement, or
claims proof it did not establish.

The native-translatable subset is deliberately the explicit inventory above,
not an assumption that every similarly named builtin is equivalent. For example,
native regex validation now shares an ECMA-262 engine across Go and Java, but
the refinement language's regex syntax still uses its separate RE2-based
parser. That integration does not establish an exact native `pattern` to
language-regex correspondence. Native string length and Refine UTF-16 `length`
also have different semantics; the separate `codePointLength` builtin provides
the exact native string-bound measure without changing that agreed contract.

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
No product tag should be represented as release-ready until the finite gates
above are complete. The sibling Hugo page and
vanity imports were explicitly approved, pushed as `8537d17` in
`brain-fuel/dev.goforge`, and verified live on 2026-09-19. That page describes an
unreleased development checkpoint, not a completed product release.

## Test evidence policy

Use [TESTING.md](TESTING.md) for exact selections and input-sensitive reuse.
Record the command, covered behavior, tool/dependency inputs, outcome and source
checkpoint. Reuse successful focused evidence on unchanged relevant inputs;
rerun failed checks only after a relevant correction. A documentation correction
alone does not justify another JVM, Maven lifecycle or fuzz campaign.
