# Deterministic development test selection

Development checks are selected from the changed behavior, not repeatedly run
across the whole repository. CI remains the integration gate. A green focused
selection is evidence only for that selection, not a release-readiness claim.

## Selection rules

1. Before running tests, record the changed source/fixtures, the behavior they
   affect, and the exact package and anchored `-run` expression. Select existing
   regressions for that behavior as well as its new tests. Do not select by an
   unanchored substring or rely on a test-name match without checking its names.
2. Generate only edited GoPlus packages before testing. A generation operation
   must finish before its tests start. Generated Go and its `.gp` source are one
   change, not reasons for two test runs.
3. For an implementation change, include affected callers and contract tests.
   Use `go list -json ./...` and its `Imports`, `TestImports`, and `XTestImports`
   to identify reverse dependencies. Add explicit fixture/template consumers:
   these are not necessarily represented by Go imports. If impact cannot be
   bounded confidently, run the affected package closure instead of inventing a
   narrower selection.
4. Test-only changes need the changed tests. Documentation-only edits need no
   runtime tests unless they alter executable examples, inputs, or dependencies.
   Formatting/generated-only changes need generation consistency, not a repeat
   of unchanged expensive Java or Maven tests.
5. Preserve Go's test cache. Do not routinely use `-count=1` or clean the cache.
   Use an uncached run only for a stated reason such as a changed external JAR,
   toolchain, environment, or reproducibility/concurrency experiment. Record
   toolchain versions and dependency digests for external-runtime evidence.
6. Run race detection once for the affected integration selection after a
   coherent feature batch; use it immediately for concurrency/transaction
   changes. Do not repeat the same selection after unrelated edits.
7. Fuzz during development only for an affected parser/codec/evaluator, using
   one named target and a stated duration. Fuzz campaigns are not deterministic
   enumerations; their selected target, seed corpus and replayed failures are.
   Ordinary test runs already replay checked-in fuzz seeds.
8. The coordinating agent owns whole-repository integration runs. Subagents
   hand off their exact commands, results, and covered source state. Do not
   repeat their checks on unchanged inputs merely to obtain a second report.

At an integration checkpoint, freeze source generation, then run generation
consistency, `go test -race ./...`, and `go vet ./...` once with required Java and
Maven dependencies provisioned. A failed check is rerun for its affected scope
after the fix; expand that scope only if the fix changes other contracts. CI
provides the separate Linux/macOS environment coverage. Module/toolchain pins,
shared runtime contracts, or broad AST changes warrant this full gate, but not
after each intermediate edit.

If the real Maven lifecycle test already passed on the checkpoint's unchanged
generator/dependency inputs, the local integration command may use
`go test -race ./... -skip '^TestMavenRegenerationAndReproducibleArtifact$'`.
Record the reused Maven command/result alongside it. That test launches Maven
and a separately built CLI, so enabling Go race instrumentation in its harness
does not add race coverage to those processes. CI still runs the Maven check in
each platform environment. This exception does not permit skipping other tests
or reusing Maven evidence after a relevant generator/fixture/dependency edit.

## Current work selections

These are development selections, not substitutes for the integration gate.
Extend a selection when a change adds a new test or affects another behavior.

| Change | Selected checks | Why |
| --- | --- | --- |
| Shared project/promotion lock and recovery path safety | Commands below | Lock exclusion, reserved paths, inode-owned recovery, CLI promotion callers |
| Native JSON composition | `go test ./java -run '^(TestGeneratedProjectJSONSerdeComposesNativeAndRefinements|TestGeneratedNativeJSONValidatorExactOfflineAndBounded|TestProjectJSONSerdeGatesUnsupportedNativeComposition|TestNativeJSONGeneratorGatesPatternsAndUnsupportedFormats)$'` | Native plus refined validation and fail-closed generation |
| CLI native JSON validation bridge | `go test ./cli -run '^(TestNativeArtifactWorkflow|TestNativeRefinedJSONValidationBoundary|TestNativeOfflineDependencyWorkflow|TestNativeWorkflowUsageAndPrivacy)$'` | Default native plus refined checks, native-only override, budgets, exit status and redaction |
| Avro serde feature addition | Exact new/affected `TestGeneratedAvro…` names, recorded by its owner | Avoid rebuilding unrelated Java fixtures per feature |
| Closed generic/native numeric lowering | `go test ./native -run '^(TestLowerClosedGenericAliasesAndTransformedParents|TestLowerRecursiveGenericAvroDefinesBeforeReference|TestLowerGenericTaggedUnionUsesOneClosedDefinition|TestLowerGenericNamesAvoidDeclarationsAndExpansionIsBounded|TestLowerRepeatedAvroScalarAliasStaysStructural|TestLowerNumericKeywordExpansionIsBoundedBeforeExactParse|TestLowerOpenAPIAndRecursiveReferences|TestAvroRepeatedNamedRecordUsesReference)$'` | Simultaneous substitution, transformed aliases, deterministic collision-safe names, recursive Avro order, structural scalar aliases, native payload validation, generic and exact-number expansion bounds, and existing nominal recursion |
| Qualified polymorphism | Exact capability/parser/type-check/runtime tests recorded by its owner | Static behavior plus Go/Java agreement |
| Maven lifecycle wiring | `go test ./project -run '^TestMavenRegenerationAndReproducibleArtifact$'` | Real Maven execution; do not rerun for unrelated parser or docs edits |
| Generated valid JSON property wiring | `go test ./java -run '^TestGeneratedJSONPropertiesExerciseWire$'` | Real round trips plus a test-only deliberate failure proving the wire property executes |
| Project wire metadata plumbing | `go test ./project -run '^(TestGenerateAppliesExplicitWireMetadata|TestGenerateVersionedAndSnapshotDeterministic)$'`; `go test ./cli -run '^(TestProjectCLIConfiguredWireMetadata|TestReleaseOverrideIdentityIncludesRootPackageAndWirePolicy|TestReleasePromotePinsBatchAndLeavesSnapshotWithoutPendingVersion)$'` | Metadata reaches serde/native lowering and invalidates stale release approvals |
| Automatic Avro project adapter and properties | `go test ./project -run '^TestGenerateDefaultAndAvroOnlyAdapters$'`, followed by the Maven lifecycle check above | Default and Avro-only selection, merged models, actual binary/JSON round trips in generated Maven tests |
| Avro-native property candidate filtering | `go test ./java -run '^(TestGeneratedAvroFloatDoubleOnlyAcceptExactFiniteReals|TestGeneratedPropertiesUseModelBoundariesAndTypedReplay)$'`; `go test ./project -run '^TestGenerateDefaultAndAvroOnlyAdapters$'` | Structural native rejection returns false before positive refinement selection; codec limits propagate; accepted cases still execute binary and Avro JSON round trips |
| Native bundle project assembly | `go test ./project -run '^(TestGenerateNativeBundlePreservesOracleResourcesAndMetadata|TestGenerateNativeBundleRejectsConflictingOrLossyConfiguration|TestGenerateAppliesExplicitWireMetadata|TestGenerateVersionedAndSnapshotDeterministic|TestGenerateDefaultAndAvroOnlyAdapters|TestGeneratedTestsAndNoCodegen)$'` | Bundle-owned root/wire, independent native validator and candidate filter, retained external-resource URI manifest, ordinary/refined exports, no-codegen, atomic rejection and existing generation modes |
| Named JSON scalar wire policies | `go test ./java -run '^(TestGeneratedJSONNamedScalarPolicies|TestJSONScalarMetadataRejectsWrongBaseTypes|TestJSONSerdeOptionsFromMetadataIsCopiedAndFailClosed|TestGeneratedJackson3JSONSerde)$'` | Local metadata through aliases/lists/generics, rational-record exactness, preserved primitive defaults, malformed wire and original default-adapter regression |
| Generated timestamp/float/generic-recursive strategies | `go test ./java -run '^(TestGeneratedTimestampFloatAndClosedGenericRecursiveProperties|TestGeneratedSchemaProperties|TestGeneratedPropertyExhaustionFailsHard|TestPropertyGenerationRejectsUnsupportedAtomically|TestGeneratedPropertiesUseModelBoundariesAndTypedReplay)$'` | Timestamp and exact finite-float boundaries, closed generic unions/records, finite-base recursion, target invocation, hard exhaustion, atomic rejection, factories and replay |

Transaction batch:

```sh
go tool goplus gen ./release ./project
go test -race ./release -run '^(TestPromoteMultiFamilyExactPinsAndRetainsSnapshots|TestPromotion.*|TestRecover.*|TestRollbackRejectsSymlinkedDestinationParent|TestReservedTransactionPaths)$'
go test -race ./project -run '^(TestProjectAndPromotionShareMutationLock|TestWriteOwned.*|TestPlanOwnedAddition.*)$'
go test -race ./cli -run '^TestReleasePromot.*$'
go vet ./release ./project
```

## Evidence record

For each completed batch record: source revision (or exact dirty-file scope),
command, result, environment, and any skipped coverage. A later relevant edit
invalidates that evidence; an unrelated edit does not. Keep checkpoint results
in [IMPLEMENTATION.md](IMPLEMENTATION.md). A command that reports “no tests to
run” is a selection failure, never a passing check.
