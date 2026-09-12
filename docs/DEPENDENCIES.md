# Dependency roles

Refine's own source remains MIT-licensed. Third-party packages retain their own
licenses; a final artifact-specific attribution/dependency audit remains a
release gate.

- `goforge.dev/goplus v0.158.0`: pinned source-generation tool. Ordinary users
  compile the checked-in generated Go without running that tool.
- Go's `unicode` classification tables are embedded in generated Java contract
  support so canonical identifiers do not change with the target JDK's Unicode
  version. Generated sources include the table version and Go's full BSD-style
  copyright/license notice. The current toolchain supplies Unicode 15.0.0.
  Packaging must preserve this notice in binary artifact attribution as well;
  the final Maven artifact audit remains required.
- Go's Unicode simple-fold tables and `regexp/syntax` rune/empty-width matching
  semantics also underpin generated `RegexProgram`. Its sources retain the
  complete Go BSD-style notice (2009/2011 copyrights). Programs carry an explicit
  execution profile and Unicode version; the Java matcher does not inherit
  JDK case-folding behavior. Binary artifact attribution remains a release gate.
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
- `org.jetbrains:jetCheck:0.3.0`: Java runtime property-test harness, not a
  generated production dependency. Upstream is
  [Apache-2.0](https://github.com/JetBrains/jetCheck/blob/master/LICENSE).
  `org.jetbrains:annotations:13.0` is its Apache-2.0 transitive dependency.
  Both Maven Central jars are SHA-256 pinned in `java/properties_test.gp` and
  verified before test execution. No JUnit or Vavr dependency is needed by this
  standalone harness. Published annotations 13.0 SHA-1 was also checked while
  establishing its SHA-256 pin; jetCheck publishes its SHA-256 directly.

Dependency declarations are not evidence that an upstream component supplies
the full Refine contract. In particular, native regex semantics, deterministic
payload budgeting, and Java conformance still require their own implementation
and verification.
