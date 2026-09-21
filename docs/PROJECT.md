# Java/Maven project generation

The `project` package assembles one repository-level Java artifact from several
independently versioned schema families. It is a generation and owned-output
layer only: it does not edit a POM by default, invoke Maven, sign, deploy, or
publish anything.

Checked metadata examples and their generated-test behavior are specified in
[EXAMPLES.md](EXAMPLES.md).

## Typed contracts and layouts

`Generate(GenerateInput)` accepts a list of `Contract` values. Each contract
identifies its family, released version or snapshot status, logical namespace,
optional Java-specific package override, native formats, and `NoCodegen`
setting. A contract supplies either a checked `language.Program` and root
payload type or a self-contained `native.Project` imported from a native bundle.
When a checked program contains a standalone `openapi` declaration it instead
normalizes to the same operations-only native project internally, with no
payload root. Its ordinary Request, Response, and Context declarations remain
the authored model; the OpenAPI block supplies the method, path, parameter,
header, body, response, and relational-context bindings.
The native project remains the authority for its original resources, sidecar
metadata, native constraint units, target, and publication namespace. Its target
is either one selected payload root or an operations-only OpenAPI entry resource;
the latter never receives a synthetic root.

Package selection is deterministic:

1. a contract's Java override;
2. its logical namespace;
3. the project base Java package.

The family and stable version suffix are then appended. Released `1.2.3` uses
`<base>.<family>.v1_2_3`; snapshots always use
`<base>.<family>.snapshot`, independent of an intended release version. The
generator never modifies a released source contract.

The default Maven-oriented layout is:

```text
target/generated-sources/refine/
target/generated-resources/refine/
target/generated-test-sources/refine/
```

All paths can be overridden. `Layout.Flat` places Java basenames directly in the
chosen source directory and rejects collisions; it is intended for explicit
current-directory/export workflows, not a normal multi-family Maven build.
`DetectRoot` walks upward to the nearest `pom.xml` for project-oriented defaults.

For code-generating contracts, Java generation supplies the Java 25 domain
models and validators. JSON Schema/OpenAPI targets additionally include a
`RefineJSONModule` for validated Jackson 3 serde. Safe wire defaults apply unless
`Contract.Wire` (or family-level `wire` in `refine.project.json`) supplies explicit
scalar, extra-field, or discriminator metadata. The same metadata drives native
lowering and serde; unsupported policies fail the whole bundle. Named integer,
exact rational-record, and timestamp encodings follow aliases, list elements,
and closed generic fields without changing unrelated primitive fields.
Wire configuration participates in release comparison fingerprints, so changing
it invalidates an earlier override. `NoCodegen` suppresses Java classes but retains
contract resources. Every contract resource set contains the checked Refine
source and English explanation in Markdown and JSON. Requested native formats
contain both ordinary and Refined exports; ordinary lowering explicitly allows
documented loss and includes its companion explanation. Omitting `Formats`
requests JSON Schema, Avro, and OpenAPI, so an unrepresentable target rejects the
entire bundle instead of silently omitting it.

A standalone source OpenAPI declaration is the exception to that format
default: its intrinsic origin is `openapi`, so omitted `Formats` selects only
OpenAPI. An explicit selection must contain exactly that one format. A payload
`RootType` or externally supplied `Wire.OpenAPI` is rejected because either
would compete with source authority. Other explicit scalar, discriminator,
extra-field, example, numeric, and publication metadata is validated and
retained; it never supplies an implicit encoding.

Avro targets also emit `RefineAvroSerde`, using the lowered checked ordinary
schema as its embedded reader schema. Shared semantic models appear once even
when both JSON and Avro adapters are requested. Generated properties exercise
Avro binary and Avro JSON round trips plus targeted invalid binary writes that
must emit no bytes. This standalone-source path does not substitute for importing
an existing native sidecar with aliases, defaults, or opaque native constraints.

Generation is pure and all-or-nothing in memory. Files are sorted by path, and a
failure returns an empty `Bundle`. Each code-generating payload contract also
emits a schema-derived JetCheck suite for its root under the test directory.
An operations-only OpenAPI contract instead emits one mandatory suite derived
from every checked request and response binding. Those tests call the generated
native-first operation facade and cannot be narrowed through explicit targets.
Library
callers may supply `Contract.PropertyTests` to configure cases, attempt budgets,
explicit targets, embedded examples, and serialized counterexample replay.
The same all-or-nothing rule applies to unsupported test-generator strategies.
`NoCodegen` suppresses models, facades, launchers, and generated tests when no
other contract emits code, but retains resources.

## Owned output safety

`WriteOwned(root, bundle, manifestPath)` writes a fully generated bundle. The
default manifest is `.refine-generated.json`; it records each owned relative path
and the SHA-256 of the exact generated bytes.

Generation and release promotion share the exclusive `.refine-release.lock`.
The lock and private transaction/staging paths cannot be claimed as outputs or
as a custom ownership manifest. Clear a crash-stale lock only after confirming
that no generator or promoter is active.

Before staging, the writer checks every desired and formerly owned output:

- an unowned existing path is a collision, even if its bytes happen to match;
- a prior generated path may be replaced or deleted only when its current bytes
  still match the recorded digest;
- missing or user-modified prior generated files stop the operation;
- absolute/escaping paths, non-regular files, duplicate destinations, and known
  symbolic-link traversal are rejected; and
- the bundle cannot claim its own ownership manifest.

All replacement bytes and the new manifest are staged before output mutation.
Existing owned files receive same-inode hard-link backups. A returned install
failure rolls installed outputs back and restores backups; stale files are
deleted only after every desired file was installed. Re-running the same bundle
is deterministic.

The writer is in-process transactional, not crash-atomic and not safe against a
malicious concurrent directory-swap race through portable path APIs. Run it with
exclusive control of the project root. A machine/process crash may require
regeneration after inspecting the staging directory. This narrower guarantee is
intentional; it does not claim the durable journal semantics of schema release
promotion.

## Maven integration

`MavenSnippet` emits an opt-in POM fragment rather than modifying `pom.xml`. It:

- sets Java compiler release 25;
- binds the caller-provided Refine CLI executable to `generate-sources`;
- adds the generated source, resource, and test-source directories; and
- supplies a fixed ZIP-compatible `project.build.outputTimestamp` for reproducible
  archive timestamps, overridable by the project's build policy.
- passes Maven's evaluated `${project.groupId}`, `${project.artifactId}`, and
  `${project.version}` to generation for publication-sensitive removal checks.

It also adds Jackson databind 3.2.1, networknt 3.0.7, Apache Avro 1.12.0,
test-scoped `org.jetbrains:jetCheck:0.3.0`,
and runs the generated
`refine.generated.RefineGeneratedTests` launcher during Maven's `test` phase.
The launcher invokes every generated family/version suite; it is not merely
compiled and forgotten. A failing property or required-generation exhaustion
fails Maven. The standard explicit `-DskipTests` override skips this execution.
For JSON outputs the properties exercise Jackson payload-preserving round trips
and targeted invalid writes that must emit no bytes. Wire comparisons preserve
exact numeric values and payload structure; they disregard Refine-only numeric
literal tags that JSON and Avro do not encode. Model boundaries still require
exact raw-data equality. See [generated test evidence](GENERATED-TESTS.md) for
execution reports, explicit coverage gaps, and mutation checks.

The default remains a single Maven project/artifact containing every family.
There is no signing or publication execution. The application CLI must provide
the actual project-generation command and argument/configuration contract.

`PlanNoCodegen` delegates to `release.PlanMavenVersion`, preserving the required
schema-family-major removal policy: removing generated classes from a previous
family major requires a major artifact bump, while removal within the current
family major requires a minor artifact bump. A newly present `no-codegen` family
major still establishes the current family major.

Ordinary `project generate` and `release promote` additionally use the same
`release.PlanPublication` gate before an owned Java source can be deleted. The
default checked-in ledger is `refine.publications.json`; it can be changed with
`release.maven.publicationLedger`. A fresh project with no removal and no ledger
needs no release configuration. Once a released version is excluded by
`noCodegen`, however, that exact family/version must have either a `published`
or `unpublished` record. Each record is bound to the immutable schema SHA-256,
the sorted generated-source path/digest inventory, a reason, and a canonical
`inventorySha256` computed by `release.PublicationInventoryDigest`. A published
record must also contain the exact artifact version and SHA-256 plus a sorted,
nonempty inventory of actual JAR `.class` entry paths and byte digests.

Published removals require the artifact bump selected by `PlanMavenVersion` and
effective Maven coordinates supplied as `--maven-group-id`,
`--maven-artifact-id`, and `--maven-version`. The generated Maven snippet passes
these automatically. Standalone promotion must pass values obtained from the
Maven effective model; Refine deliberately does not interpret a raw `pom.xml`,
whose parent properties and active profiles may change all three values.
Generated files and local builds never imply publication. Missing or stale
attestations are `unknown` and fail before staging or deletion.

Suggested CLI wiring is:

1. detect or accept the project root;
2. parse/type-check each configured contract and construct `GenerateInput`;
3. call `Generate` and surface any whole-bundle error;
4. call `WriteOwned` only for an explicitly mutating generate command; and
5. expose `MavenSnippet` separately for opt-in POM integration.
# CLI and verified Maven execution

`refine project generate` discovers the nearest Maven project, then all
`schemata/<family>/vX.Y.Z.refine`, `SNAPSHOT.refine`,
`vX.Y.Z.refined.json`, and `SNAPSHOT.refined.json` files. A `.refined.json`
file is the exact self-contained bundle returned by `native.Project.Bundle`;
its original native resources, metadata, editable source graph, URI identities,
and native constraint units are retained. Defining the same family/version with
both extensions is an error. It accepts an
explicit `--root` for non-Maven callers. One-type schemas infer their root;
multi-type families declare it in optional `refine.project.json`:

```json
{
  "package": "com.example",
  "families": {
    "foo": {"root": "Thing", "noCodegen": ["v0.1.0"]}
  }
}
```

Each family can additionally set `package`, `javaPackage`, and `formats`.
The top-level `schemaDir` defaults to `schemata`. Unknown configuration keys,
duplicate JSON keys, missing families and missing excluded versions reject.
By default all three native formats are generated, and unsupported exact wire
representations stop generation before any output is written. `formats` may
select outputs explicitly; it does not make an unsupported representation safe.

`--package` overrides schema/config namespaces. `--output` changes the Java
source directory; `--flat` omits package subdirectories. `--check` verifies the
complete owned output set and bytes without writes. `--json` emits a build-tool
report. Imports are read through an OS root handle confined to the project and
bundled using `language.CompileSources`; imports do not grant predicates I/O.
For a native bundle, family `wire` overrides are rejected because the bundle is
the published wire authority. A configured `root` must exactly match a payload
bundle root. An operations-only OpenAPI bundle requires an empty `root` and the
explicit origin format `openapi`; generation emits the composed operation facade
and its mandatory request/response properties. `package`, `javaPackage`, and `--package` remain explicit publication/code
generation overrides with the normal priority. Selecting only the bundle's
origin format is the currently supported exact path. Omitting `formats` still
requests all three formats and therefore fails closed when opaque native details
cannot be represented cross-format; no target is silently skipped.

A `SNAPSHOT.refine` or released `.refine` file may instead carry the standalone
OpenAPI declaration directly. Discovery resolves its imports first, requires no
configured `root`, defaults its effective format to OpenAPI, and builds a
checked rootless execution view without replacing the authored file. Generated
resources include the deterministic self-contained OpenAPI project, facade,
operation-wide explanation, and mandatory properties. The original source
bundle—not that derived project—remains the versioned identity and import
authority.

Native project resources include `contract.refined.json` (the complete original
bundle), the effective ordinary/refined selected target resource set, and a
`<mode>-<format>-resources.json` manifest. That manifest preserves ordered URI
identities, the typed project target, its entry resource, an optional payload
root, and checked wire metadata. Dependency filenames
are deterministic numeric names, never paths taken from schema URIs. Consumers
of an external-reference schema must retain this resource set; the root file
alone is not advertised as a self-contained bundle. Native JSON property
candidates are filtered against the independent native oracle before testing
the Refine predicates; resource/enforcement failures propagate instead of being
mistaken for ordinary rejected samples.

Release planning treats an operations-only bundle as its checked operation
catalog and never invents a payload root. Backward checks retain old operations,
accept old requests, and ensure new server responses remain acceptable to old
consumers; forward checks reverse those roles. Exact status, status-class and
`default` response selectors use OpenAPI precedence. Changed relational context
predicates, native wire resources and generated Java ABI remain conservative
unknowns and use the same exact content-bound override policy as payload
families. Promotion still copies the checked bundle verbatim and retains its
editable snapshot.

`refine project maven` emits an opt-in POM fragment; it does not edit a POM.
The fragment invokes the real `project generate` command during `generate-sources`,
registers source/resource/test directories, pins the Java 25 compiler plugin,
and sets a reproducible ZIP-compatible output timestamp. The example timestamp
can be overridden by the user's reproducible-build policy. Plugin versions are
Maven Compiler 3.15.0, Exec 3.6.3, and Build Helper 3.6.1.

Inside a Maven project, the command inspects its schema catalog (`--root` and
`--config` override discovery). Native JSON/OpenAPI schema `pattern` or
`patternProperties` positions automatically add pinned Chicory 1.7.5 runtime
and parser dependencies plus the content-addressed checked ECMA-262 WebAssembly
guest, build manifest, and full upstream notices. Example payloads and
`no-codegen` entries do not trigger them. Outside a project, `--native-regex`
opts into the dependencies in a bootstrap fragment. They are omitted for
projects that do not need native regex execution. Generated JSON property tests
use the module's bounded `strictMapper()`.

The integration test uses SHA-512-pinned Maven 3.9.16 to build an unsigned fixture
artifact with released and snapshot schema packages and an imported native JSON
bundle. It verifies byte-identical
unchanged builds, automatic regeneration after a snapshot edit, and preservation
of the released schema. Set `REFINE_MAVEN_HOME` to run this test; CI requires it
through `REFINE_REQUIRE_MAVEN=1`. It additionally changes the snapshot to a
contract outside the automatic generator's distribution and requires Maven to
fail with the named exhaustion error, proving the generated tests actually run.
No fixture coordinates are publication defaults,
and neither generation nor this test deploys an artifact.
