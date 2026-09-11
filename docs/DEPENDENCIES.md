# Dependency roles

Refine's own source remains MIT-licensed. Third-party packages retain their own
licenses; a final artifact-specific attribution/dependency audit remains a
release gate.

- `goforge.dev/goplus v0.158.0`: pinned source-generation tool. Ordinary users
  compile the checked-in generated Go without running that tool.
- `github.com/santhosh-tekuri/jsonschema/v6 v6.0.3`: independent JSON Schema
  Draft 2020-12 **test oracle** for native-constraint translation. It is imported
  by the provenance tests, not by production provenance code. Upstream license:
  [Apache-2.0](https://github.com/santhosh-tekuri/jsonschema/blob/v6.0.3/LICENSE).
  The production implementation does not inherit the oracle's default regex
  engine, format policies, or reference loader.
- `golang.org/x/text v0.14.0`: the oracle's transitive dependency, under Go's
  BSD-style license. Other `golang.org/x/*` entries support the pinned GoPlus
  module tool; see `go.mod`/`go.sum` for the exact graph.
- `github.com/dlclark/regexp2 v1.11.0` checksum entries come from the oracle's
  upstream test dependencies. Refine's own production code and provenance tests
  do not import it.

Dependency declarations are not evidence that an upstream component supplies
the full Refine contract. In particular, native regex semantics, deterministic
payload budgeting, and Java conformance still require their own implementation
and verification.
