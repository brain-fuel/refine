# Changelog

## v0.1.0

Initial supported release scope. A release tag is issued only after the exact
source commit passes the required cross-platform verification workflow.

- GoPlus-authored compiler and Go-consumable generated sources, using the
  pinned GoPlus module tool.
- Checked Haskell-like refinement language with exact arithmetic, immutable
  values, deterministic evaluation budgets, reusable functions and recursion.
- Refined and ordinary JSON Schema, OpenAPI 3 and Avro workflows, with native
  validation, offline resources, loss accounting and English explanations.
- Canonical, individually editable native constraints within the explicit
  [correspondence matrix](docs/NATIVE-PROVENANCE.md). Native character counts
  use `codePointLength`; language `length` retains UTF-16 semantics.
- Java 25 immutable domain models, validators, Jackson 3 JSON and Apache Avro
  serde, with validation on construction, reading and writing.
- JetCheck-generated property tests, checked examples, automatic Maven source
  generation and reproducible unsigned artifacts.
- Schema-history compatibility analysis, semantic-version planning, snapshot
  promotion and publication-ledger checks. Unknown proofs require the
  applicable explicit, version-controlled policy override.

Support is bounded, not a claim of unrestricted schema conversion. Unsupported
wire representations, ambiguous projections and inexact native rewrites reject
explicitly; native constraints outside the editable subset retain native
authority. See [release boundaries](docs/RELEASE-READINESS.md).

Maven deployment, future target languages, inline lambdas and generated HTTP
clients/server stubs are not included.
