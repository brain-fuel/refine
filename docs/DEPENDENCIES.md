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
- Go's Unicode categories/scripts/aliases, simple-fold tables and
  `regexp/syntax` parsing/normalization, ASCII classes, rune/empty-width matching,
  tree simplification and instruction compilation also underpin generated
  `RegexProgram`. Its sources retain the
  complete Go BSD-style notice (2009/2011/2013 copyrights). Programs carry an explicit
  execution profile and Unicode version; the Java matcher does not inherit
  JDK case-folding behavior. Binary artifact attribution remains a release gate.
- `github.com/santhosh-tekuri/jsonschema/v6 v6.0.3`: production JSON Schema
  Draft 2020-12 structure compiler for `native` and independent test oracle for
  native-constraint translation. Native installs no URL loader, selects Draft
  2020-12 explicitly, and supplies the ECMAScript-oriented regex engine below.
  This dependency does not implement Refine provenance or prove translation
  equivalence. Upstream license:
  [Apache-2.0](https://github.com/santhosh-tekuri/jsonschema/blob/v6.0.3/LICENSE).
- `github.com/getkin/kin-openapi v0.149.0`: production offline parsing and
  structural validation for published OpenAPI 3.0, 3.1, and 3.2 documents.
  Refine separately retains the exact source and rejects YAML constructs whose
  expansion it does not yet preserve. Upstream license:
  [MIT](https://github.com/getkin/kin-openapi/blob/v0.149.0/LICENSE).
- `github.com/hamba/avro/v2 v2.31.0`: production Avro 1.12.0 schema parser and
  structure/default/name validation oracle. Each ingestion gets a private schema
  cache. The project was archived in 2026, which is a maintenance/replacement
  risk and makes independent Apache conformance coverage especially important.
  Upstream license: [MIT](https://github.com/hamba/avro/blob/v2.31.0/LICENSE).
- `github.com/dlclark/regexp2 v1.12.0`: production ECMAScript-mode syntax engine
  supplied to JSON Schema and OpenAPI validators instead of silently treating
  Go RE2 syntax as native `pattern` syntax. A 250 ms match timeout bounds schema
  default/example checks. ECMAScript mode is a compatibility implementation,
  not proof of complete parity with every ECMA-262 edition or JavaScript host.
  Upstream license: [MIT](https://github.com/dlclark/regexp2/blob/v1.12.0/LICENSE).
- `golang.org/x/text v0.14.0`: a transitive dependency, under Go's BSD-style
  license. Other `golang.org/x/*` entries support the pinned GoPlus module tool;
  see `go.mod`/`go.sum` for the exact graph. `kin-openapi` and `hamba/avro` also
  bring JSON pointer, YAML, mapstructure, and JSON decoding implementation
  dependencies recorded exactly in those files; the final artifact audit must
  cover that transitive graph.
- `org.jetbrains:jetCheck:0.3.0`: Java runtime property-test harness, not a
  generated production dependency. Upstream is
  [Apache-2.0](https://github.com/JetBrains/jetCheck/blob/master/LICENSE).
  `org.jetbrains:annotations:13.0` is its Apache-2.0 transitive dependency.
  Both Maven Central jars are SHA-256 pinned in `java/properties_test.gp` and
  verified before test execution. No JUnit or Vavr dependency is needed by this
  standalone harness. Published annotations 13.0 SHA-1 was also checked while
  establishing its SHA-256 pin; jetCheck publishes its SHA-256 directly.

Dependency declarations are not evidence that an upstream component supplies
the full Refine contract. In particular, complete native regex semantic
conformance, deterministic payload budgeting, translation bijections, and Java
conformance still require Refine-owned implementation and verification.
