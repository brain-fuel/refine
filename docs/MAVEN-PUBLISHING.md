# Maven Central publication

The Maven distribution is a small reactor under `maven/` with three artifacts:

- `dev.goforge:refine:0.4.0`, the Java 25 runtime primitives used by generated
  validators; and
- `dev.goforge:refine-engine:0.4.0`, the compiler running entirely on the JVM; and
- `dev.goforge:refine-maven-plugin:0.4.0`, which runs `refine project generate`
  during Maven's `generate-sources` phase.

The plugin is also usable from Gradle through the normal `Exec` task; it has no
Gradle-specific runtime dependency and the CLI remains the stable integration
boundary.

## Local publication

Maven Central requires a verified `dev.goforge` namespace, a Central Portal user
token, and an available signing key. Keep those values outside the repository.
The settings file supplied to Maven must contain a `central` server whose
username is the Central Portal token username and whose password is its token:

```xml
<settings><servers>
<server>
  <id>central</id>
  <username>...</username>
  <password>...</password>
</server>
</servers></settings>
```

The settings file must be a complete Maven settings document, not a standalone
`<server>` element. Set `MAVEN_SETTINGS` to its path.

The Refine **producer** build needs Java 25, Maven, Go 1.26+, and Python 3.
Go builds a WASI intermediate; Chicory compiles it to JVM bytecode before
publication. Consumers need only Java 25 and Maven.

Run from the repository root:

```sh
MAVEN_OPTS=-Xmx3g mvn -s "$MAVEN_SETTINGS" \
  -f maven/pom.xml -Pcentral-release -DperformCentralRelease \
  -Dgpg.signer=bc -Dgpg.keyFilePath="$MAVEN_SIGNING_KEY" clean deploy
```

`MAVEN_SIGNING_KEY` is the path to the exported OpenPGP private key. The Java
signer reads it directly without a GPG executable. On macOS, a key created by
Go+ may already exist at
`~/Library/Application Support/goplus/maven-central-private.asc`; assayxport
uses `~/Library/Application Support/assayxport/maven-central-private.asc`.
A fingerprint alone is not a private key. The corresponding public key must
be available on a Central-supported keyserver.

In the pinned Go+ v0.158.0, `goplus publish` redirects to `ax publish`.
Refine uses the Maven reactor to preserve its parent POM and `maven-plugin`
packaging; its Java runtime is not a translation of the entire Go module.

The profile attaches sources and Javadocs, signs every artifact, and submits the
staging bundle to Central. `clean verify` without the profile performs a local
unsigned packaging check. Publishing `0.4.0` is immutable; do not retry it after
partial publication without first checking the Central Portal state.

The checked-in GitHub Actions workflow (`maven-publish.yml`) performs the same
release with Java 25. Configure the `maven-central` environment with
`MAVEN_USERNAME`, `MAVEN_PASSWORD`, `MAVEN_GPG_PRIVATE_KEY`, and
`MAVEN_GPG_KEY_ID` secrets before dispatching it for `v0.4.0`.

## Maven use

Generated contracts can depend on the shared runtime directly:

```xml
<dependency>
  <groupId>dev.goforge</groupId><artifactId>refine</artifactId><version>0.4.0</version>
</dependency>
```

```xml
<plugin>
  <groupId>dev.goforge</groupId><artifactId>refine-maven-plugin</artifactId>
  <version>0.4.0</version>
  <executions><execution><goals><goal>generate</goal></goals></execution></executions>
</plugin>
```

The plugin runs the transitive `refine-engine` JAR in Maven's JVM by default.
No executable discovery, Go installation, or native library is involved in
generation. Google formatting launches a Java subprocess using Maven's own JDK and a formatter JAR resolved from Maven Central. A few functions that exceed the JVM method-size limit execute in
Chicory's pure-Java interpreter. This is the existing engine compiled for the
JVM, not an independent Java-source rewrite.

Set `-Drefine.executable=/absolute/path/to/refine` only to explicitly opt back
into the external CLI for compatibility. `-Drefine.root=...` selects a schema project other than the Maven base
directory, and `-Drefine.skip=true` disables the execution.

For Gradle, invoke the same CLI in a task and keep the generated source/resource
directories on the corresponding source sets:

```groovy
tasks.register('refineGenerate', Exec) {
    commandLine 'refine', 'project', 'generate', '--root', project.projectDir
}
compileJava.dependsOn refineGenerate
```

## JVM schema imports

The `ingest` goal imports a checked-in native spec with the same JVM engine:

```sh
mvn dev.goforge:refine-maven-plugin:0.4.0:ingest \
  -Drefine.input=specs/api.json -Drefine.output=schemata/person/v1.0.0.refined.json \
  -Drefine.format=openapi -Drefine.type=Person \
  -Drefine.pointer=/components/schemas/Person
```

Input/output paths are confined to the Maven project. Optional `refine.resource`
specifies the native document URI; it does not trigger a network fetch. Import
failures do not overwrite the destination. The generator's exclusive lock,
owned-file checks, staging, and rollback still run inside the JVM engine.

The engine artifact retains build digests and third-party licenses under
`META-INF/refine-engine`. Its sources JAR includes the compiler's Go/Go+ inputs
and the generated Java wrapper. The producer uses
`maven/scripts/prepare-engine.py`; consumer builds never run this script.

Chicory 1.7.5 passes an unsupported `COPY_ATTRIBUTES` option to `Files.move` on
host filesystems. The engine's narrowly scoped WASI adapter retries that operation
without the invalid option, preserving atomic replacement and project confinement.
It does not fall back to non-atomic copy/delete.

## Generated Java formatting

Google Java Format **1.36.0** formats all generated production and test Java
sources by default. Maven resolves the formatter automatically; no Go executable,
formatter installation, or manual JVM module-export flags are needed. The formatter
runs as a separate Java process using `${java.home}/bin/java` so its compiler-module
access does not require changing Maven's JVM arguments. Java 25 remains required.

```xml
<configuration>
  <javaFormat>google</javaFormat>
</configuration>
```

Use `-Drefine.javaFormat=none` (or `<javaFormat>none</javaFormat>`) for the previous
unformatted output. Unknown values fail the build. This named option leaves room
for additional formatter backends; this release supports only `google` and `none`.
Formatting is a Maven build setting, not a `refine.project.json` schema setting.

The plugin first requests the Java output plan without writing generated files,
formats private staged copies, then regenerates and requires an exact match with
the original source set before applying the formatted bytes. Ownership hashes,
publication checks, and atomic installation use the final formatted bytes.
Formatting errors leave existing generated outputs unchanged. Repeated generation
is deterministic; switching between `google` and `none` does not require deleting
the ownership manifest. Hand-edited owned files still cause generation to fail.
Only generated Java is formatted; handwritten application sources and generated
schema resources retain their original bytes.

The internal CLI bridge is `project generate --java-format-plan` followed by
`project generate --java-format-input <project-relative-plan.json>`. The latter
accepts a map from generated Java path to exact `source` and prepared `formatted`
text. It supports `--check` with the same prepared plan. Plans are trusted build
inputs and bounded to 16 MiB. The CLI by itself retains its unformatted default;
Maven supplies the formatter. An external `refine.executable` must support this
bridge, or be used with `refine.javaFormat=none`.

When upgrading from 0.2.0, update the plugin version and run the ordinary build.
When Maven clean deletes generated files, it must also delete the ownership
manifest, as shown in Offscript's `maven-clean-plugin` configuration.

## Mutation verification (0.4.0)

The plugin includes `refine:mutate`, a Java-only consumer mutation harness with
separate generated-property and application-test results and a Rice's Tax export.
See [mutation verification](MUTATION-TESTING.md) for its supported project layout,
required catalog, evidence, and failure policy.
