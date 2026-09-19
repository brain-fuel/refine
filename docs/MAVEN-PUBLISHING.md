# Maven Central publication

The Maven distribution is a small reactor under `maven/` with two artifacts:

- `dev.goforge:refine:0.1.0`, the Java 25 runtime primitives used by generated
  validators; and
- `dev.goforge:refine-maven-plugin:0.1.0`, which runs `refine project generate`
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
<server>
  <id>central</id>
  <username>...</username>
  <password>...</password>
</server>
```

With Java 25, Maven, and GnuPG configured, run from this directory:

```sh
mvn -s /Users/mattlaine/para/projects/goforge/maven_settings.xml \
  -f maven/pom.xml -Pcentral-release -DperformCentralRelease \
  -Dgpg.keyname="$GPG_KEY_ID" clean deploy
```

The profile attaches sources and Javadocs, signs every artifact, and submits the
staging bundle to Central. `clean verify` without the profile performs a local
unsigned packaging check. Publishing `0.1.0` is immutable; do not retry it after
partial publication without first checking the Central Portal state.

The checked-in GitHub Actions workflow (`maven-publish.yml`) performs the same
release with Java 25. Configure the `maven-central` environment with
`MAVEN_USERNAME`, `MAVEN_PASSWORD`, `MAVEN_GPG_PRIVATE_KEY`, and
`MAVEN_GPG_KEY_ID` secrets before dispatching it for `v0.1.0`.

## Maven use

Generated contracts can depend on the shared runtime directly:

```xml
<dependency>
  <groupId>dev.goforge</groupId><artifactId>refine</artifactId><version>0.1.0</version>
</dependency>
```

```xml
<plugin>
  <groupId>dev.goforge</groupId><artifactId>refine-maven-plugin</artifactId>
  <version>0.1.0</version>
  <executions><execution><goals><goal>generate</goal></goals></execution></executions>
</plugin>
```

Set `-Drefine.executable=/absolute/path/to/refine` when the executable is not on
`PATH`. `-Drefine.root=...` selects a schema project other than the Maven base
directory, and `-Drefine.skip=true` disables the execution.

For Gradle, invoke the same CLI in a task and keep the generated source/resource
directories on the corresponding source sets:

```groovy
tasks.register('refineGenerate', Exec) {
    commandLine 'refine', 'project', 'generate', '--root', project.projectDir
}
compileJava.dependsOn refineGenerate
```
