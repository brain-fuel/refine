# Consumer mutation verification

Refine owns the Java mutation runner and Rice's Tax evidence export in
`refine-maven-plugin`. Offscript is a consumer demonstration, not the implementation
of the harness. The generator's fault-injection regression tests remain in
`java/property_evidence_test.gp`; they test Refine's emitted assertions independently
of any Spring application.

With Refine 0.4.0 available from Maven Central,
configure the plugin in a consumer POM and run:

```sh
./mvnw refine:mutate
```

This goal must be invoked separately, not bound to a lifecycle: it launches a clean
`verify` control itself. It currently supports a single-module Maven project using
Java 25, standard `target/classes` and `target/test-classes` directories, generated
Refine property suites executed by `verify`, and application tests run by Surefire.
It uses Maven's own installation and JDK; consumers do not need Go or a copied script.

Parameters:

| Property | Default | Purpose |
|---|---|---|
| `refine.mutationCatalog` | `refine.mutations.tsv` | Exact source replacements |
| `refine.mutationSuites` | `1` | Required generated suite summaries per healthy run |
| `refine.mutationMain` | `refine.generated.RefineGeneratedTests` | Generated test entry point |
| `refine.mutationTimeout` | `180` | Timeout in seconds for each subprocess |

The tab-separated catalog has five columns: unique id, project-relative production
Java file, binding label, original single-line source fragment, replacement fragment.
Each original must occur exactly once and differ from its replacement. Targets must
be under `target/generated-sources/` or `src/main/java/`. The catalog is an explicit,
bounded selection of faults; this is not exhaustive operator discovery or coverage.
Offscript's catalog supplies eight faults across its two generated schema families.

The runner compiles each replacement into an isolated copy of the healthy build and
runs generated properties and application JUnit tests independently. It never invokes
generation after mutation. Each mutation starts with fresh baseline classes. A zero
exit without expected test evidence is an infrastructure failure; a nonzero process
exit alone is not a kill. Compilation failures, timeouts, infrastructure failures and
survivors all fail the Maven goal. The goal does not call `System.exit` in Maven.

`.mut/runs/` retains source snapshots, hashes, catalog, baseline, compiler logs, property
logs and Surefire XML. A completed control-green run atomically updates `.mut/current`
on systems supporting symbolic links. Rice's Tax can read its report and augmented
manifest with this configuration:

```yaml
runtime:
  name: refine-source-mutation
  artefacts: .mut/current
  package: .
  tests: src/test/java
  command: ./mvnw refine:mutate
```

The existing adapter maps invalid and infrastructure failures to `skipped`; the exact
status is retained separately in each report entry, and the Maven goal fails on them.
No covering-test probes or observations are fabricated. A Rice's Tax audit supplements
the mutation goal; it cannot replace the goal's failure policy.

Offscript is the end-to-end example: its ordinary build checks native imports, generated
contracts, codecs and properties; its mutation build tests those generated artifacts
and its application assertions. Application tests killing a fault do not imply that
generated properties killed it: the report preserves each layer's result. General
Refine coverage gaps discovered there belong back in Refine's generator and regression
tests. Application-specific fixture assertions belong in Offscript.

The initial demonstration exposed missing getter, native-validator and traversal-budget
checks. Maven 0.4.0 adds generated checks for these boundaries and generator regression
mutations that must be killed. This remains a finite catalog, not full generated-test
coverage. Native probe expectations are established independently during generation;
generic/union accessor coverage and authored native-invalid model examples remain
separate, explicitly reported gaps.
