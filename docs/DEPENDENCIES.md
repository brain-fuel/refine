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
- `github.com/hamba/avro/v2 v2.31.0`: production Avro 1.12.0 structure/name
  parser. Its compiled schema graph also drives Refine's separately implemented
  bounded binary validator; hamba's generic decoder is not treated as complete
  logical-type enforcement. Hamba implements the obsolete union-default branch
  zero rule, so Refine removes record-field defaults only from the private
  parser input and validates the unchanged original source with its exact,
  ordered first-matching Avro 1.12 default checker. Each ingestion gets a
  private schema cache. The project was archived in 2026, which is a maintenance/replacement
  risk and makes independent Apache conformance coverage especially important.
  Upstream license: [MIT](https://github.com/hamba/avro/blob/v2.31.0/LICENSE).
- `github.com/dlclark/regexp2 v1.12.0`: production ECMAScript-mode syntax engine
  supplied to JSON Schema and OpenAPI validators instead of silently treating
  Go RE2 syntax as native `pattern` syntax. A 250 ms match timeout bounds schema
  default/example checks. Timeout or engine failure propagates as
  `native.enforcement`; it is never converted to a false match result.
  ECMAScript mode is a compatibility implementation,
  not proof of complete parity with every ECMA-262 edition or JavaScript host.
  Upstream license: [MIT](https://github.com/dlclark/regexp2/blob/v1.12.0/LICENSE).
- `com.networknt:json-schema-validator:3.0.7`: generated Java's Jackson 3
  JSON Schema Draft 2020-12/OpenAPI 3.1 validation engine. Generated code
  supplies an exact `BigDecimal` node factory, a resource loader that cannot
  fall back to classpath/files/network, strict duplicate/trailing-token parsing,
  and caller limits, including a whole-request numeric-expansion preflight
  before either Jackson or networknt can expand a compact exponent. Schemas
  without `pattern` or `patternProperties` do not link or load GraalJS.
  Runtime tests pin this artifact and its Jackson 3.2.1, ITU 1.14.0, and SLF4J
  2.0.17 dependencies by SHA-256. Upstream license:
  [Apache-2.0](https://github.com/networknt/json-schema-validator/blob/3.0.7/LICENSE).
- `org.graalvm.polyglot:js:25.0.1` (Community): conditionally supplies the
  GraalJS `RegExp` implementation configured for ECMA-262 2020 for generated
  Java validators whose native schemas contain `pattern` or
  `patternProperties`. Refine does not use
  networknt's process-wide Graal context. Each validation gets a locked-down
  context, deterministic aggregate evaluation/work/UTF-16-unit limits, and a
  watchdog deadline that cancels guest execution. Patterns and subjects cross
  the host boundary only as values to a fixed generated program; host classes,
  IO, environment, processes, native access, polyglot access, and guest-created
  threads are disabled. Resource exhaustion remains indeterminate and is never
  converted into a non-match inside `not`, `anyOf`, or `patternProperties`.
  The runtime closure consists of the 25.0.1 `js-language`, `regex`, `polyglot`,
  `truffle-api`, `truffle-runtime`, `truffle-compiler`, `collections`,
  `jniutils`, `nativeimage`, `word`, and shadowed `icu4j`/`xz` jars. Java tests
  verify SHA-256 for every jar before execution. Upstream licenses are
  [UPL-1.0 and MIT](https://github.com/oracle/graaljs/blob/vm-25.0.1/LICENSE);
  the shadowed ICU data retains its upstream Unicode/ICU notices.
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
the full Refine contract. In particular, native ingestion's regexp2 syntax
oracle does not yet admit every valid ECMA-262 2020 Unicode-property spelling,
even when GraalJS would execute it. Complete regex-language parity, translation
bijections, and Java conformance still require Refine-owned implementation and
verification.
