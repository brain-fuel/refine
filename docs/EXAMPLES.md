# Checked executable examples

Refine examples are versioned metadata containing canonical typed Refine value
text and an expected validation outcome. They are not arbitrary JSON examples,
Java fixture classes, or samples that the generator silently assumes are valid.

```json
{
  "examples": {
    "version": "refine.examples/v1",
    "cases": [
      {"name": "positive", "target": "Score", "value": "2"},
      {
        "name": "below-minimum",
        "target": "Score",
        "value": "-1",
        "expected": "invalid",
        "diagnosticCodes": ["score.positive"]
      }
    ]
  }
}
```

Omitted `expected` and `nativeExpected` fields mean `valid`. Version 1 supports
only conclusive Refine `valid` and `invalid` expectations. An invalid example
names exactly one required diagnostic code. Its complete invalid report must
contain that code; other conclusive violations may also be present. An
indeterminate or incomplete report never satisfies either expectation.

`value` must be the exact output of Refine's canonical value formatter for the
closed named `target`. Metadata validation parses it through the target's
structure while deliberately bypassing `where` clauses, then runs normal
validation to check the expectation. Shape, exact numeric and timestamp
representation, UTF-8, parser, and deterministic resource checks are never
bypassed. Structurally invalid, noncanonical, or over-budget values reject the
whole metadata update. A catalog contains at most 64 cases, each value is at
most 64 KiB, and all values together are at most 1 MiB. Case names are unique
stable ASCII identifiers.

`nativeExpected: "invalid"` is permitted only for a Refine-valid example with
no refinement diagnostic claim. It is retained as intent during native project
ingestion: the language checker cannot prove a format-specific wire outcome.
A generated JSON or Avro adapter executes the assertion through its staged
normal model/wire boundary. Generation fails if the example requests native
rejection but no such adapter is configured.

Rooted project generation emits the configured wire property target. OpenAPI
operation generation instead executes each case at every authoritative request,
response, or context occurrence of its checked target type. Response values are
paired with a compatible valid request; context values contain the exact
request/response pair. A case outside the generated target set rejects
generation instead of being skipped. Metadata catalog v1 retains its one-code
conclusive valid/invalid contract; library callers may additionally supply an
indeterminate `PropertyExample`, which must produce an exact indeterminate
Refine outcome while native resource failures remain fatal. `NoCodegen` retains
and validates the metadata but intentionally emits no executable Java test, so
native expectations remain unevaluated.

For `.refine` catalogs, `families.<name>.wire.examples` in
`refine.project.json` is family-wide and therefore must be valid for every
discovered released and snapshot version. Native `.refined.json` bundles carry
their own per-version metadata and reject an external family wire override.
Examples participate in exact bundle and release-policy identity, so changing a
case invalidates content-bound compatibility approvals.

Standard JSON Schema/OpenAPI `examples`, Avro defaults, and similar native
annotations remain byte-for-byte native resources. Refine never guesses their
typed representation or labels them invalid. To opt a sample into executable
classification, author a canonical typed case explicitly under
`x-refine.metadata.examples` (or the corresponding strict project metadata).
