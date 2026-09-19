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
- `github.com/tetratelabs/wazero v1.12.0`: pure-Go WebAssembly interpreter for
  the checked native ECMA-262 regex guest. Runtime configuration fixes guest
  memory to at most 512 pages and closes trapped instances; the guest has one
  interrupt import and no WASI or ambient capabilities. Upstream license:
  [Apache-2.0](https://github.com/tetratelabs/wazero/blob/v1.12.0/LICENSE).
- Checked `internal/ecmaregex/refine-ecma262.wasm`: one reproducibly built
  regex-only ABI shared by Go and generated Java. Its manifest pins QuickJS-NG
  0.15.1 (`fd0a0210b7be00957751871e7e01b8291268fc29`) and
  `@eslint-community/regexpp` 4.12.2, wasi-sdk 33.0 and every input SHA-256.
  Refine carries the interrupt patch, build script, exact 1,202,261-byte guest,
  full MIT/Apache/LLVM-exception texts, and aggregate NOTICE. Generated copies
  carry the guest, manifest, and same notices. The guest SHA-256 is
  `ee1ff0212d3a3bd28a72f00033f51dad747c8b36e9302edbbbd35cf6a58bfe8f`.
- `com.networknt:json-schema-validator:3.0.7`: generated Java's Jackson 3
  JSON Schema Draft 2020-12/OpenAPI 3.1 validation engine. Generated code
  supplies an exact `BigDecimal` node factory, a resource loader that cannot
  fall back to classpath/files/network, strict duplicate/trailing-token parsing,
  and caller limits, including a whole-request numeric-expansion preflight
  before either Jackson or networknt can expand a compact exponent. Schemas
  without `pattern` or `patternProperties` do not link Chicory or load the
  checked regex guest.
  Runtime tests pin this artifact and its Jackson 3.2.1, ITU 1.14.0, and SLF4J
  2.0.17 dependencies by SHA-256. Upstream license:
  [Apache-2.0](https://github.com/networknt/json-schema-validator/blob/3.0.7/LICENSE).
- `com.dylibso.chicory:runtime:1.7.5` and
  `com.dylibso.chicory:wasm:1.7.5`: conditionally execute and parse that exact
  checked guest in generated Java validators. The generated host exposes only
  the interrupt import, enforces the declared 32 MiB memory maximum, transfers
  exact UTF-16 units, verifies resource size/SHA-256, and applies the same
  typed initialization, compilation, matching, work, evaluation, and queue
  limits as the Go host. Tests pin runtime SHA-256
  `cdbb2bd4e353eacff78da5dd3454694316eaa6d2950aab3d1517dca41ae4a0b2`
  and wasm-parser SHA-256
  `16558a66bac04f7e00ea06950f52d87ce2cfff535a54bac2115f2c13e0b3050b`.
  Upstream license:
  [Apache-2.0](https://github.com/dylibso/chicory/blob/1.7.5/LICENSE).
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
the full Refine contract. Refine owns the fixed regex ABI, pinned guest build,
host capability inventory, typed failure mapping, bounded lifecycle, and
cross-host vectors; neither wazero nor Chicory alone establishes native regex
conformance.
