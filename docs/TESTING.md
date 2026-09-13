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
   one named target and an explicit iteration budget (or deliberate duration).
   Fuzz campaigns are not deterministic
   enumerations; their selected target, seed corpus and replayed failures are.
   Ordinary test runs already replay checked-in fuzz seeds.
8. The coordinating agent owns whole-repository integration runs. Subagents
   hand off their exact commands, results, and covered source state. Do not
   repeat their checks on unchanged inputs merely to obtain a second report.

At an integration checkpoint, freeze source generation, then run generation
consistency, `go test -race -timeout=20m ./...`, and `go vet ./...` once with required Java and
Maven dependencies provisioned. A failed check is rerun for its affected scope
after the fix; expand that scope only if the fix changes other contracts. CI
provides the separate Linux/macOS environment coverage. Module/toolchain pins,
shared runtime contracts, or broad AST changes warrant this full gate, but not
after each intermediate edit.

CI uses an explicit `-timeout=20m` package ceiling. The hosted macOS Java
package reached Go's default ten-minute alarm while compiling its final worked
example, although that individual test had run only four seconds. Raising this
ceiling does not add tests or repeat successes; it bounds the existing distinct
Java harnesses on slower runners. Individual harness process limits still apply.

If the real Maven lifecycle test already passed on the checkpoint's unchanged
generator/dependency inputs, the local integration command may use
`go test -race -timeout=20m ./... -skip '^TestMavenRegenerationAndReproducibleArtifact$'`.
Record the reused Maven command/result alongside it. That test launches Maven
and a separately built CLI, so enabling Go race instrumentation in its harness
does not add race coverage to those processes. CI still runs the Maven check in
each platform environment. This exception does not permit skipping other tests
or reusing Maven evidence after a relevant generator/fixture/dependency edit.

## Reproducible CI fuzz selection

CI runs the full integration gate once per platform, then selects additional
fuzz campaigns from the commit diff. Inspect the same selection without running
tests:

```sh
go run ./cmd/refine-testplan --base <baseline-commit-sha> --head HEAD
```

The versioned JSON report lists changed paths, sorted package/target names,
test input files, selection reasons, and an `execution` policy. Add `--run` to
execute that plan with anchored fuzz names, no ordinary tests, a requested
10,000-iteration budget per campaign, a 1,000-iteration minimization budget, and
an explicit two-minute Go test timeout. `--iterations` accepts 1 through 100,000.
`--duration` deliberately selects wall-clock mode (1s through 1m) and conflicts
with an explicitly supplied `--iterations`; `--full` selects every target.
Campaign timing and generated inputs are stochastic. Parallel workers may
finish in-flight work beyond the requested iteration count. Selection and
requested budgets are deterministic for the same commits, tree, and build
environment; retained failing inputs support deterministic replay.

Counted mode avoids the Go 1.26 fuzz deadline race tracked in
[golang/go#75804](https://github.com/golang/go/issues/75804). It does not suppress
errors: any fuzz failure or test timeout aborts nonzero. Explicit duration mode
can still encounter that upstream race on affected toolchains. There is no
automatic retry of a failed target or rerun of successful campaigns.

Targets are discovered from the build-selected Go test files, including newly
added fuzzers. Production changes follow reverse `Imports`, `TestImports`, and
`XTestImports` edges. Test-only edits select fuzz declarations and their
transitive test helper/type/method files. `TestMain`, package initializers, and
blank-import initialization affect every target in their package. Changed
ordinary test imports are compared against the baseline too: importing a new
package can change initialization even if no fuzz target references that test.
Unchanged import lists do not broaden the helper-based selection. Named corpus
edits select that target. Fixtures use the explicit consumer inventory in
`internal/testplan/plan.gp`, then follow reverse imports. Unregistered fixture
roots select all targets, including Markdown fixtures. Toolchain,
workflow, or selector changes, unknown input ownership, and unavailable
baselines select all targets. Documentation-only changes need no extra fuzzing.
The integration gate still replays all seed corpora regardless of this plan.
This is a repository-specific impact policy, not a proof of whole-program Go
behavior. Register new filesystem fixture consumers in the reviewed inventory;
do not assume a missing Go import proves a fixture cannot affect a package.
With `--run`, stdout remains the JSON report; progress and test output go to
stderr so the plan can be retained as machine-readable evidence.

On pull requests the baseline is the event's base commit; on pushes it is the
previous commit supplied by GitHub. Checkout retains commit history. The tool
does not fetch history, clear caches, rerun successes, or silently treat missing
history as no changes. Run it against the checked-out `--head`; it discovers
targets from the working tree, not by compiling an arbitrary historical tree.

## Current work selections

These are development selections, not substitutes for the integration gate.
Extend a selection when a change adds a new test or affects another behavior.

The schema-limit, diagnostic-path, and operations-only OpenAPI batch uses the
following focused checks. Commands already run by the owning agent are reused;
review fixes rerun only the affected anchors, not this whole list. Java commands
use required Java 25 and the pinned dependency directories described below.

```sh
go test ./cmd/refine-testplan -run '^TestFuzzExecutionPolicyIsExplicitBoundedAndDeterministic$'
go test ./language -run '^(TestSchemaLimitsParseFormatAndRejectMalformedDeclarations|TestImportedSchemaLimitsUseExplicitComponentMinimum|TestSchemaAndCallerBudgetsApplyToValidatePayloadAndRead)$'
go test ./language -run '^(TestAffectedDiagnosticPaths|TestValidateDataEachWhereInheritanceAndMessages|TestValidateDataFieldAndWholeRecordEquivalence)$'
go test ./analysis -run '^TestAnalysisAndSyntaxEvidenceRetainSchemaLimits$'
go test ./explain -run '^TestExplanationIncludesEffectiveSchemaLimits$'
go test ./native -run '^(TestRootlessOpenAPIOperationsIngestAndBoundary|TestRootlessOpenAPIOperationsBundleRestoresEditedAuthority|TestRootlessOpenAPIOperationsExportDoesNotInventSchemaRoot|TestRootlessOpenAPIOperationsRejectBadInputsAndKeepRootedV1|TestWithDerivedOpenAPIOperationsBuildsAuthoritativeCheckedBoundary|TestOpenAPIOperationIndexAndSemanticBoundary|TestOpenAPI30DirectionalRequirednessUsesFixedNativeViews|TestNativeBundleRetainsSchemaValidationLimits)$'
REFINE_REQUIRE_JAVA=1 go test ./java -run '^(TestGeneratedContractValidation|TestInlineRefinementModels)$'
REFINE_REQUIRE_JAVA=1 go test ./java -run '^TestGeneratedSchemaLimitsApplyToValidationAndRead$'
go test ./project -run '^(TestGenerateOperationsOnlyOpenAPIContextPropertiesAndResources|TestGenerateOperationsOnlyOpenAPIRejectsRootAndTargetNarrowingAtomically)$'
go test ./cli -run '^(TestProjectCLIGeneratesRootlessOpenAPIOperationBundle|TestProjectCLIRootlessTargetConfigurationAndReleaseComparisonFailClosed)$'
```

The planner change also used exactly one local campaign: the previously failing
`FuzzRuntimePackageNames`, with `-run '^$' -fuzz '^FuzzRuntimePackageNames$'
-fuzztime=10000x -fuzzminimizetime=1000x -timeout=2m` in `./java`. No unchanged
campaign or full suite was repeated to investigate the upstream deadline race.
The shared AST/runtime changes require one frozen integration gate, including
the existing Maven lifecycle: earlier Maven evidence predates these inputs.

The following native selection covers the subsequent extra-field policy change:
per-occurrence alias policies, ordinary-schema acceptance, metadata/bundle
authority, and affected JSON/OpenAPI decoder callers. It does not rerun Java or
Maven; their owners have separate exact generated-code selections.

```sh
go test ./native -run '^(TestExtraFieldPoliciesArePerNominalOccurrence|TestExtraFieldMetadataResolvesAliasesBoundedlyAndRejectsConflicts|TestExtraFieldLoweringKeepsDiscardOpenAndRejectAliasesLocal|TestJSONWireMetadataLowersRecordsAndTaggedUnions|TestLowerOpenAPIAndRecursiveReferences|TestWireMetadataCheckedAndImmutable|TestDecodeAndValidateJSONComposesNativeExactAndRefined|TestDecodeAndValidateJSONUsesExplicitScalarAndUnionWireMetadata|TestDecodeAndValidateJSONClosesNestedGenericArgumentsSimultaneously|TestOpenAPIOperationIndexAndSemanticBoundary)$'
```

That selection exposed the incorrect integer-prefix classification of `IntBox`.
The implementation fix selected the three new failed anchors plus
`TestNativeIntegerPrimitiveNamesDoNotCaptureRecordAliases`,
`TestFixedIntegerGenerationLimit`,
`TestDecodeAndValidateAvroComposesNativeAndRefinements`, and
`TestDecodeAndValidateAvroExactScalarMetadata` in one anchored alternation in
`./native`. The subsequent test-only numeric-conversion correction reran only
`^TestNativeIntegerPrimitiveNamesDoNotCaptureRecordAliases$`.

The generated-code owners use these separate required-Java selections (with the
pinned Jackson, JetCheck, NetworkNT and Graal directories as applicable):

```sh
REFINE_REQUIRE_JAVA=1 go test ./java -run '^TestGeneratedJSONExtraFieldPoliciesArePerOccurrence$'
REFINE_REQUIRE_JAVA=1 go test ./java -run '^(TestJacksonNestedRecursiveAndGenericRecords|TestJSONSerdeOptionsFromMetadataIsCopiedAndFailClosed)$'
REFINE_REQUIRE_JAVA=1 go test ./java -run '^TestGeneratedProjectOpenAPIPropertiesExerciseEveryBinding$'
```

Neither owner runs Maven. After all review fixes have an explicit green/frozen
handoff, the coordinator runs the affected project/Maven integration selection
once. Unchanged native and Java focused evidence is reused; CI provides the
full Linux/macOS gate. A changed generated-property template invalidates its
rootless caller checks, but not unrelated rooted resource/loader checks.

For the operations/extra-field batch the final local runtime selection is exactly
`go test -race -timeout=20m ./project -run '^TestMavenRegenerationAndReproducibleArtifact$'`,
with both Java and Maven required and the pinned dependency directories. Its
fixture now includes a rootless OpenAPI family beside the existing family in
one artifact, while retaining the same four lifecycle invocations. The focused
native, Java, rootless caller and rooted regression results above are reused;
this is not another local full Java or repository run.

The following follow-up selection isolates generic JSON descriptor identity and
its aggregate work bound. It executes one Java harness and one pure-Go test,
not the full Java package:

```sh
REFINE_REQUIRE_JAVA=1 go test ./java -run '^(TestJacksonGenericAnonymousRecordDescriptorsAreSpecializationSensitive|TestJSONDescriptorTypeKeysHaveAggregateStructuralBounds)$'
```

For rootless release integration, the initial reviewed selection was:

```sh
go test ./analysis ./cli -run '^(TestCompareOperationsUsesAsymmetricRequestAndResponseDirections|TestCompareOperationsClassifiesOperationAndStatusSurfaceDirection|TestCompareOperationsKeepsChangedRelationalContextUnknown|TestReleaseOperationsPlansAsymmetricEntrypointsAndExactOverrides|TestReleaseOperationsRemovalRequiresCompatibilityBoundary|TestReleaseOperationsInitialPromotionAndUnchangedSnapshot|TestReleaseOperationsDocumentationClaimRetainsAllEntrypointsAndResources|TestReleasePlanAllBaselinesExactOverrideAndDocumentationIdentity|TestReleaseOverrideIdentityIncludesRootPackageAndWirePolicy|TestReleasePromotePinsBatchAndLeavesSnapshotWithoutPendingVersion|TestReleaseNativeBundlePlanningUsesExactBundleIdentity|TestProjectCLIRootlessTargetConfiguration)$'
```

An alias-fixture correction reran only the failed context anchor. Subsequent
inventory-copy and initial-root validation corrections selected the three
analysis anchors plus `TestReleaseOperationsInitialPromotionAndUnchangedSnapshot`
and `TestReleaseInitialPayloadValidatesSelectedRoot`. Successful unrelated CLI
approval, removal and documentation results were reused. Final review of generic
context traversal has its own bounded-DAG/context selection, recorded with its
result in IMPLEMENTATION.md.

```sh
go test ./analysis -run '^(TestCompareOperationsKeepsChangedRelationalContextUnknown|TestOperationContextResolutionBoundsGenericDAGWork)$'
```

The operation example/replay generator uses the existing
`^TestGeneratedProjectOpenAPIPropertiesExerciseEveryBinding$` harness with pinned
Java dependencies. Its owner waits for coherent shared Java generation; the
coordinator does not repeat the successful descriptor harness. Changed property
output requires the two rootless project generation anchors above. This follow-up
does not alter Maven lifecycle/dependency integration, so no additional local
Maven lifecycle is scheduled; CI still covers it on both platforms.

| Change | Selected checks | Why |
| --- | --- | --- |
| Map allocation/order preflights | `go test ./language -run '^TestMapLiteralAllocationPreflight$'`; `go test ./native -run '^(TestNativeMapOrderingAndJSONAllocationPreflights|TestJSONMapRefinementsAndUnicodeBoundary|TestAvroMapProjectionDecodeAndLowering)$'`; `REFINE_REQUIRE_JAVA=1 go test ./java -run '^TestGeneratedJavaMapParity$'` with pinned dependencies | Preallocation charging, nonallocating JSON cardinality, aggregate native ordering cap and unchanged exact Go/Java budget reports; no unrelated function/serde harness reruns |
| String-keyed maps | `go test ./value -run '^TestMapDataIsImmutableExactAndOrderIndependent$'`; `go test ./language -run '^(TestMapLiteralOperationsAndCanonicalReadShow|TestMapKeysAndPredicateFailuresAreExact|FuzzMapReadShow|FuzzPayloadType)$'`; `go test ./native -run '^(TestJSONTypedMapProjectionAndCheckedDecodePreserveNativeSchema|TestJSONMapProjectionUsesCarrierForHeterogeneousOrOpenValueDomains|TestJSONMapRefinementsAndUnicodeBoundary|TestAvroMapProjectionDecodeAndLowering|TestAvroMapValueRecordDefaultsRemainRefinementChecked|TestJSONMapLoweringUsesSchemaValuedAdditionalProperties)$'`; `REFINE_REQUIRE_JAVA=1 go test ./java -run '^TestGeneratedJavaMapParity$'` with pinned Jackson/Avro/JetCheck directories | Exact immutable key identity, native projection/constraints/defaults, canonical text, generic typed Java maps, all map operations, serde, generated properties, zero-output failures and 198 Go/Java budget reports. Tests run by each owner are reused until their relevant inputs change |
| Documentation classification | `go test ./cli -run '^(TestReleaseDocumentationClaimRetainsContractChanges|TestReleaseDocumentationClaimIncludesReachableDependencyBodies|TestReleaseDocumentationClaimBoundsNativeMetadataAndOpaqueResources|TestReleaseDocumentationClaimRetainsNativeSourceGraphWithOverrides|TestReleasePlanAllBaselinesExactOverrideAndDocumentationIdentity|TestReleaseNativeBundlePlanningUsesExactBundleIdentity|TestReleaseOverrideIdentityIncludesRootPackageAndWirePolicy|TestReleasePromotePinsBatchAndLeavesSnapshotWithoutPendingVersion)$'` | Functional changes cannot be mislabeled documentation using a compatibility override; source graph, native metadata, comments-only acceptance, opaque unknown and promotion identity remain explicit |
| Raw JSON refinement bypass | `REFINE_REQUIRE_JAVA=1 REFINE_NETWORKNT_DIR=… go test ./java -run '^(TestGeneratedJSONRawBypassKeepsNativeAndStructuralValidation|TestGeneratedJackson3JSONSerde)$'` | Explicit bypass still enforces native, structural, exact wire and resource gates; one ordinary Jackson regression covers unchanged validating defaults. A subsequent fixture-only correction reruns only the new test |
| Native Avro JSON decoding | `go test ./native -run '^(TestAvroJSONNativeEncodingAndExactTranscode|TestAvroJSONRejectsMalformedLossyAndDefaultedWriterInputs|TestAvroJSONBudgetsAndRefinementBoundary|TestAvroJSONSeededLongAgreementWithBinary|FuzzAvroJSONBoundary)$'`; `REFINE_REQUIRE_JAVA=1 REFINE_AVRO_DIR=… go test ./java -run '^TestNativeAvroJSONAgreesWithApacheEncoding$'` | Strict framing, native union/bytes/fixed semantics, required writer fields, limits, exact checked decoding, 1,000 deterministic Hamba integer comparisons, fixed fuzz corpus and one Apache Java oracle JVM. No campaign is implied by seed replay |
| CLI Avro JSON input flag | `go test ./cli -run '^(TestNativeAvroJSONInputEncodingIsExplicitAndValidated|TestNativeRefinedAvroValidationBoundary|TestNativeRefinedJSONValidationBoundary|TestNativeWorkflowUsageAndPrivacy|TestFormatterAndHelp)$'` | Explicit encoding, native/refined/unknown outcomes, no payload leakage, unchanged default binary and JSON paths, usage/help |
| Embedded examples and portable Java lookup | `go test ./native -run '^(TestEmbeddedExamplesAreCanonicalBoundedAndConclusive|TestEmbeddedExamplesDeepCopyBundleAndRefinedAnnotationRoundTrip)$'`; `REFINE_REQUIRE_JAVA=1 go test ./project -run '^(TestProjectGenerationExecutesEmbeddedExamplesWithoutMutatingOptions|TestProjectExamplesRejectUnsupportedTargetsAndRequireNativeAdapter|TestProjectJavaToolsUseConfiguredHomesAndRequireJava25|TestGenerateIncludesCheckedOpenAPIContextFacade)$'`; `go test ./cli -run '^(TestProjectCLIParsesAndGeneratesStrictEmbeddedExamples|TestEmbeddedExamplesAreReleaseIdentityAndNativeBundleAuthority)$'` | Metadata bounds/canonical evidence, immutable transport, generation and release identity; Java lookup precedence and CI-shaped facade execution |
| Native OpenAPI operation index and Go boundary | `go test ./native -run '^(TestOpenAPIOperationIndexAndSemanticBoundary|TestOpenAPIOperationNativeFailuresStatusAndTokens|TestOpenAPIOperationMetadataAndAggregateLimitsFailClosed|TestOpenAPIOperation30SchemaSeedsAreAdapted)$'`; `go test ./openapi -run '^TestNativeBindingsAreImmutableInRefineOnlyContract$'` | Schema-object scope, canonical adapted resources, semantic part native gates, status/context/token behavior, aggregate limits and defensive copies |
| Published-version identity immutability | `go test ./release -run '^(TestPromotionRejectsAlreadyPublishedVersionIdentityBeforeWrites|TestPromotionValidationLeavesEverythingUnpromoted|TestPromotionRejectsSymlinkAndImmutableCollision|TestPromoteMultiFamilyExactPinsAndRetainsSnapshots)$'` | Same/conflicting-content republish and duplicate published catalogs reject before writes; existing transaction and multi-family behavior |
| No-codegen publication ledger | `go test ./release -run '^(TestPublicationGateDistinguishesPublishedAndUnpublishedInventory|TestPublicationGateFailsClosedOnUnknownOrStaleEvidence|TestPublicationGateDoesNotRequireLedgerForFreshGeneration)$'`; `go test ./project -run '^(TestWriteOwnedCheckedRejectsChangedPublicationInputBeforeDeletion|TestMavenSnippetAndNoCodegenPlan)$'`; `go test ./cli -run '^(TestProjectPublicationGateRequiresEffectiveMavenAndExactLedger|TestProjectPublicationLedgerStrictAndUnpublished|TestProjectCLIConfigNoCodegenAndOverrides|TestReleaseProspectiveNoCodegenVersionIsAllowedAndRemovesNoCurrentOutput|TestReleaseNoCodegenRemovalRequiresAndAppliesMavenArtifactPlan|TestMavenCLIIsOptInOutputOnly)$'` | Strict digest-bound published/unpublished inventories, Maven effective-model evidence, fresh/prospective behavior, under-lock preconditions, ordinary deletion and recoverable promotion |
| Explicit JSON annotation before automatic projection | `go test ./native -run '^(TestJSONTypedMapProjectionAndCheckedDecodePreserveNativeSchema|TestJSONMapProjectionUsesCarrierForHeterogeneousOrOpenValueDomains|TestJSONOrdinaryExtraFieldPoliciesRemainProjectable|TestSelectedJSONAnnotationIntentionallyBypassesOnlyAutoProjection|TestInvalidSelectedJSONAnnotationsFailAtomically)$'`; `go test -race ./native -run '^(TestRootAnnotationSeedsEditableSourceWithoutChangingSelector|TestNativeConstraintCommentLookalikeDoesNotGrantEditAuthority|TestVersionOneBundleWithoutConstraintSourceFieldRestoresCanonicalUnits|TestExplicitJSONSchemaResourceResolutionAndBundle|TestResourceAndBundleFailuresAreExplicit|TestProjectExportComposesEffectiveNativeAndEditableJSONSchema|TestRefinedLoweringCarriesCheckedWireMetadataAcrossFormats)$'`; `REFINE_REQUIRE_JAVA=1 REFINE_NETWORKNT_DIR=… REFINE_GRAALJS_DIR=… go test -race ./java -run '^TestGeneratedNativeRegexECMA262AndBudgets$'` | Homogeneous typed maps remain precise; heterogeneous domains use the JSON carrier. Both preserve native constraints. Deliberately authored views still preserve native enforcement, selected roots, annotations, resource scope, and generated pattern-properties coverage |
| Explicit structural-only canonical reader | `go test ./language -run '^(TestStructuralReadBypassRetainsRepresentationAndResourceChecks|TestStructuralReadBypassClosedTargetsAndIsolation|TestTypedReadExecution|TestReadNeverExecutesExpressions|TestReadValueRevalidatesAndProtectsBudgets|TestReadTargetInsideGenericDeclaration|TestReadShowProperties|TestCanonicalValueConformanceFixtures|TestFiniteFloatPayloadReadShowAndArithmetic)$'` | Bypass skips only refinements, preserves exact representation and budgets, cannot execute expressions or mutate later validating reads; seeded integer properties and existing typed-read regressions cover the shared dispatch |
| Shared project/promotion lock and recovery path safety | Commands below | Lock exclusion, reserved paths, inode-owned recovery, CLI promotion callers |
| Native JSON composition | `go test ./java -run '^(TestGeneratedProjectJSONSerdeComposesNativeAndRefinements|TestGeneratedNativeJSONValidatorExactOfflineAndBounded|TestProjectJSONSerdeIncludesNativeRegexComposition|TestNativeJSONGeneratorHandlesPatternsAndGatesUnsupportedFormats)$'` | Native plus refined validation and fail-closed generation |
| Bounded generated ECMA-262 regex | `REFINE_REQUIRE_JAVA=1 REFINE_NETWORKNT_DIR=… REFINE_GRAALJS_DIR=… go test ./java -run '^(TestNativeRegexEmissionIsConditional|TestGeneratedNativeRegexECMA262AndBudgets|TestGeneratedProjectJSONSerdeExposesRegexLimits)$'` | Conditional Graal linkage, lookaround/backreferences/Unicode, pattern properties, aggregate caps, cancellation, combinator propagation and composed read/write limit plumbing on stock Java 25 |
| CLI native JSON validation bridge | `go test ./cli -run '^(TestNativeArtifactWorkflow|TestNativeRefinedJSONValidationBoundary|TestNativeOfflineDependencyWorkflow|TestNativeWorkflowUsageAndPrivacy)$'` | Default native plus refined checks, native-only override, budgets, exit status and redaction |
| Avro serde feature addition | Exact new/affected `TestGeneratedAvro…` names, recorded by its owner | Avoid rebuilding unrelated Java fixtures per feature |
| Closed generic/native numeric lowering | `go test ./native -run '^(TestLowerClosedGenericAliasesAndTransformedParents|TestLowerRecursiveGenericAvroDefinesBeforeReference|TestLowerGenericTaggedUnionUsesOneClosedDefinition|TestLowerGenericNamesAvoidDeclarationsAndExpansionIsBounded|TestLowerRepeatedAvroScalarAliasStaysStructural|TestLowerNumericKeywordExpansionIsBoundedBeforeExactParse|TestLowerOpenAPIAndRecursiveReferences|TestAvroRepeatedNamedRecordUsesReference)$'` | Simultaneous substitution, transformed aliases, deterministic collision-safe names, recursive Avro order, structural scalar aliases, native payload validation, generic and exact-number expansion bounds, and existing nominal recursion |
| Qualified polymorphism | Exact capability/parser/type-check/runtime tests recorded by its owner | Static behavior plus Go/Java agreement |
| Maven lifecycle wiring | `go test ./project -run '^TestMavenRegenerationAndReproducibleArtifact$'` | Real Maven execution; do not rerun for unrelated parser or docs edits |
| Conditional Maven native-regex dependencies | `go test ./project -run '^(TestMavenInfersOnlyRequiredNativeRegexDependency|TestMavenSnippetAndNoCodegenPlan)$'`, then the lifecycle check | Schema-aware selection, no-codegen and example exclusions, explicit bootstrap, compile-time API plus runtime engine |
| Imported JSON/OpenAPI number defaults | `go test ./java -run '^(TestGeneratedNativeNumberWireDefaultsRemainExact|TestJSONSerdeRequiresExplicitWirePolicies)$'` | One JVM covers exact native scalar/nested numeric reads and writes, native constraints, no rounding or partial output, and unchanged standalone explicit-policy requirement |
| Native numeric/OpenAPI project export | `go test ./native -run '^(TestNativeNumberProjectExportsExactWireWithoutStandaloneOptOut|TestOpenAPIProjectAdditionKeepsNativeReferencesAndLiteralValues|TestOpenAPIProjectExportRecursiveCompositionRetainsNativeOracle|TestProjectExportComposesEffectiveNativeAndEditableJSONSchema|TestProjectOrdinaryExportRequiresAndReportsDocumentedLoss|TestProjectRefinedExportSupportsOpenAPI30AndAvroWithoutReplacingNative|TestUncomposedOrdinaryProjectExportNeverClaimsExactEditedStructure|TestWireUnrepresentableTypesAlwaysError)$'` | Exact native decimal wire context, collision-free OpenAPI component references, recursive native constraints, literal isolation, and unchanged standalone/loss opt-ins |
| Schema proof compilation gate | `go test ./analysis -run '^(TestCheckSchemaRejectsProofAndRetainsUnknownInOrder|TestCheckSchemaUnknownDoesNotRejectOrLeakWitness|TestCheckSchemaRootsRejectsOnlySelectedClosedEntrypoints|TestSatisfiability|TestUnknownIsNotProof)$'`; `go test ./native -run '^(TestProjectSchemaChecksRejectOnlySelectedEntrypoints|TestProjectSchemaChecksIncludeOpenAPIEntrypoints|TestProjectSchemaChecksRetainUnknownAndRecomputeOnBundle|TestProjectSchemaProofPrecedesAvroDefaultRefinement)$'`; `go test ./project -run '^(TestProjectSchemaProofGateIsAtomicAndUnknownIsExplicit|TestProjectSchemaProofGateIncludesOpenAPIEntrypoints)$'`; `go test ./cli -run '^(TestSchemaCheckCLIRejectsOnlyProvenEmptyAndReportsUnknown|TestCommandPhases|TestFormatterAndHelp|TestUsageAndIOFailures|TestAnalysisCLI|TestWorkflowErrors)$'` | Declaration-order evidence, explicit selected-root rejection scope, unused and optional impossible declaration acceptance, OpenAPI entrypoint gates, bounded unknown acceptance, CLI reporting and unchanged phase/usage semantics |
| Generated valid JSON property wiring | `go test ./java -run '^TestGeneratedJSONPropertiesExerciseWire$'` | Real round trips plus a test-only deliberate failure proving the wire property executes |
| Generated typed-example and native-invalid evidence | `REFINE_REQUIRE_JAVA=1 REFINE_JETCHECK_DIR=… REFINE_NETWORKNT_DIR=… go test ./java -run '^(TestGeneratedPropertiesUseModelBoundariesAndTypedReplay|TestGeneratedPropertiesExecuteResultExamplesAndNativeInvalidFiltering|TestGeneratedSchemaPropertiesExecuteJetCheck)$'` | `Result` rule traversal, target-scoped valid example seeds, direct model/read/wire example boundaries, explicit native/structural rejection, invalid-candidate native filtering, and unchanged existing typed examples |
| Project wire metadata plumbing | `go test ./project -run '^(TestGenerateAppliesExplicitWireMetadata|TestGenerateVersionedAndSnapshotDeterministic)$'`; `go test ./cli -run '^(TestProjectCLIConfiguredWireMetadata|TestReleaseOverrideIdentityIncludesRootPackageAndWirePolicy|TestReleasePromotePinsBatchAndLeavesSnapshotWithoutPendingVersion)$'` | Metadata reaches serde/native lowering and invalidates stale release approvals |
| Automatic Avro project adapter and properties | `go test ./project -run '^TestGenerateDefaultAndAvroOnlyAdapters$'`, followed by the Maven lifecycle check above | Default and Avro-only selection, merged models, actual binary/JSON round trips in generated Maven tests |
| Avro-native property candidate filtering | `go test ./java -run '^(TestGeneratedAvroFloatDoubleOnlyAcceptExactFiniteReals|TestGeneratedPropertiesUseModelBoundariesAndTypedReplay)$'`; `go test ./project -run '^TestGenerateDefaultAndAvroOnlyAdapters$'` | Structural native rejection returns false before positive refinement selection; codec limits propagate; accepted cases still execute binary and Avro JSON round trips |
| Native bundle project assembly | `go test ./project -run '^(TestGenerateNativeBundlePreservesOracleResourcesAndMetadata|TestGenerateNativeBundleRejectsConflictingOrLossyConfiguration|TestGenerateAppliesExplicitWireMetadata|TestGenerateVersionedAndSnapshotDeterministic|TestGenerateDefaultAndAvroOnlyAdapters|TestGeneratedTestsAndNoCodegen)$'` | Bundle-owned root/wire, independent native validator and candidate filter, retained external-resource URI manifest, ordinary/refined exports, no-codegen, atomic rejection and existing generation modes |
| Exact native Avro default audit | `go test ./native -run '^(TestAvroDefaultsRejectNumericTruncationAndOverflow|TestAvroDefaultsAuditNamedReferencesAndDependencyResources|TestAvroDefaultsUseFirstMatchingUnionBranchWithoutChangingOriginal|TestAvroUnionDefaultNamedReferencesAndNestedOmissions|TestAvroDefaultMatcherUsesAggregateTriStateBudget|TestAvroDefaultRefinementUsesFirstMatchingUnionBranch|TestAvroRationalCarrierDefaultsAreNeverSilentlySkipped|TestAvroDefaultTraversalFailuresAreExplicit|TestValidatedLosslessIngestion|TestStrictStructureVersionsAndOfflineRefs)$'` | Fractional/overflowing and lexically floating integer defaults, nested collections/records, ordered union selection, named references/dependencies, aggregate tri-state work/depth/scalar bounds, explicit deep/substitution unknowns, scalar-carrier defaults, and original ingestion regressions |
| Named JSON scalar wire policies | `go test ./java -run '^(TestGeneratedJSONNamedScalarPolicies|TestJSONScalarMetadataRejectsWrongBaseTypes|TestJSONSerdeOptionsFromMetadataIsCopiedAndFailClosed|TestGeneratedJackson3JSONSerde)$'` | Local metadata through aliases/lists/generics, rational-record exactness, preserved primitive defaults, malformed wire and original default-adapter regression |
| Jackson JSON codec resource bounds | `go test -race ./java -run '^(TestGeneratedJSONCodecResourceLimits|TestJSONCodecGenerationLimitsFailClosed|TestGeneratedJackson3JSONSerde|TestJacksonExactRealPolicies|TestJacksonNestedRecursiveAndGenericRecords|TestJacksonExplicitTaggedUnionsAndResult|TestGeneratedJSONNamedScalarPolicies)$'` | Strict root factory, composable nested module reads, iterative traversal, staged output, exact numeric work, and deterministic depth/node/byte/string/name/number failures under the test harness's `-Xss256k -Xmx32m` JVM |
| OpenAPI request/response refinement context | `go test -race ./validation -run '^TestMergeReportsPreservesInvalidAndIncomplete$'`; `go test -race ./openapi -run '^(TestOperationContextValidation|TestOperationMetadataRejectsAmbiguousOrIncompatibleBindings)$'`; `go test -race ./native -run '^(TestOpenAPIOperationMetadataBundleAnnotationAndCopy|TestOpenAPIOperationMetadataRejectsStaleTypeReferences|TestOpenAPIOperationExplanationIncludesUnreachableContextAndRequiresLossOptIn|TestOpenAPI30DirectionalRequirednessUsesFixedNativeViews|TestOpenAPI30DirectionalTypedMapAuditRequiresOptionalNestedFields|TestOpenAPI30DirectionalApplicatorAmbiguityFailsClosed|TestOpenAPI31DirectionalViewsRemainCanonical|TestWithDerivedOpenAPIOperationsDoesNotScanDirectionalExampleLookalikes|TestWithDerivedOpenAPIOperationsBuildsAuthoritativeCheckedBoundary|TestWithDerivedOpenAPIOperationsVersionMatrix)$'`; `go test -race ./java -run '^(TestGeneratedOpenAPIContextMatchesGo|TestOpenAPIContextGenerationRejectsPartialOutput|TestGeneratedNativeOpenAPIContextComposesAllBoundaries|TestGeneratedOpenAPI30DirectionAwareNativeValidation)$'`; `go test -race ./project -run '^(TestGenerateIncludesCheckedOpenAPIContextFacade|TestGenerateIncludesComposedNativeOpenAPIOperationFacade|TestGenerateRejectsInvalidOrExternalNativeOpenAPIMetadata)$'`; `go test -race ./cli -run '^TestNativeOperationMetadataIsAuthoritativeAndReleaseIdentified$'` | Versioned method/path/type bindings, OAS 3.0 direction-aware requiredness and checked optional carriers, exact/class/default response selection, cross-request predicates, missing-context aggregation, immutable bundle/annotation metadata, complete operation English and ordinary-loss opt-in, release identity, project facade merging, native metadata authority, aggregate native part validation and regex budgets, strict per-part framing, immutable valid-request tokens, and Go/Java outcome parity |
| Generated timestamp/float/generic-recursive strategies | `go test ./java -run '^(TestGeneratedTimestampFloatAndClosedGenericRecursiveProperties|TestGeneratedSchemaPropertiesExecuteJetCheck|TestGeneratedPropertyExhaustionFailsHard|TestPropertyGenerationRejectsUnsupportedAtomically|TestGeneratedPropertiesUseModelBoundariesAndTypedReplay)$'` | Timestamp and exact finite-float boundaries, closed generic unions/records, finite-base recursion, target invocation, hard exhaustion, atomic rejection, factories and replay |

Transaction batch:

```sh
go tool goplus gen ./release ./project
go test -race ./release -run '^(TestPromoteMultiFamilyExactPinsAndRetainsSnapshots|TestPromotion.*|TestRecover.*|TestRollbackRejectsSymlinkedDestinationParent|TestReservedTransactionPaths)$'
go test -race ./project -run '^(TestProjectAndPromotionShareMutationLock|TestWriteOwned.*|TestPlanOwnedAddition.*)$'
go test -race ./cli -run '^TestReleasePromot.*$'
go vet ./release ./project
```

## Evidence record

The offline JAR inventory boundary has one independent race/seed selection:

```sh
go test -race ./release -run '^(TestInspectJavaArtifactAndVerifyPublishedLedger|TestVerifyPublishedArtifactRejectsByteClaimMismatchesWithoutABIClaim|TestInspectJavaArtifactRejectsUnsafeArchivesAndLimits|TestJavaArtifactInventoryDeterministicProperties|FuzzInspectJavaArtifact)$'
```

This covers immutable artifact/class evidence, mismatched claims, pre-allocation
ZIP directory checks, bounded streaming CRC validation, unsafe paths and modes,
64 deterministic property cases, and the checked-in fuzz seeds. It launches no
JVM, Maven build, network fetch or fuzz campaign. Reuse its evidence after
unrelated OpenAPI/Java edits; they do not affect this API's inputs.

The intrinsic-JSON/automatic-operation batch uses these focused selections:

```sh
go test ./native -run '^(TestJSONCarrierProjectionRetainsNativeApplicatorAndTupleAuthority|TestJSONCarrierReferenceSiblingsPreserveDeclaredMembers|TestJSONCarrierRefinementsAndOrdinaryLowering|TestJSONMapProjectionUsesCarrierForHeterogeneousOrOpenValueDomains|TestJSONTypedMapProjectionAndCheckedDecodePreserveNativeSchema|TestJSONOrdinaryExtraFieldPoliciesRemainProjectable|TestApplicatorConstraintIsNotHoisted|TestLocalReferencesBecomeNamedRecursiveDeclarations)$'
go test ./native -run '^TestJSONCarrierDecoderPreservesNativeKindsAndPreflights$'
go test ./native -run '^TestWithDerivedOpenAPIOperations(BuildsAuthoritativeCheckedBoundary|RemainsEditableAndHasNoInferredContext|FailsClosedAtomically|VersionMatrix|DoesNotScanDirectionalExampleLookalikes)$'
go test ./java -run '^(TestGeneratedIntrinsicJSONValueModelsSerdeAndProperties|TestIntrinsicJSONModelEmissionIsLazyAndCollisionSafe|TestIntrinsicJSONModelObjectPreflightBeforeCopy)$'
go test ./project -run '^TestGenerateNativeJSONCarriersComposeModelsOraclePropertiesAndExports$'
go test ./release -run '^TestDependencyEvidenceFlagDoesNotChangePinIdentity$'
go test ./cli -run '^(TestDocumentationOnlyDependencyCommentChangeIsNonAffectingButStillPending|TestDependencyDocumentationEvidenceIncludesEntryPolicyAndNativeResources|TestReleaseDocumentationClaimIncludesReachableDependencyBodies)$'
```

The native matrix covers native applicator/tuple authority and retained precise
projections; the separate decoder test covers allocation/depth/ordering limits.
Selected Boolean export changes additionally use
`go test ./native -run '^(TestProjectExportRetainsSelectedBooleanTrueSchemaAtRootAndPointer|TestProjectRejectsSelectedBooleanFalseSchemaAsProvenEmpty|TestProjectExportComposesEffectiveNativeAndEditableJSONSchema|TestProjectOrdinaryExportRequiresAndReportsDocumentedLoss|TestProjectRefinedExportSupportsOpenAPI30AndAvroWithoutReplacingNative|TestUncomposedOrdinaryProjectExportNeverClaimsExactEditedStructure)$'`.
The grouped Java harness exercises model, Jackson and JetCheck boundaries in
one JVM. Run it with the pinned required-Java/Jackson/JetCheck environment, not
with missing-dependency skips. These are development selections, not substitutes
for the once-per-stable-batch integration gate for shared language/runtime edits.

The OpenAPI 3.0 direction/resource-helper batch, including the reviewed generic
record-path and aggregate-materialization fixes, uses this native selection:

```sh
go test -race ./openapi ./native -run '^(TestOperationContextValidation|TestOperationMetadataRejectsAmbiguousOrIncompatibleBindings|TestNativeBindingsAreImmutableInRefineOnlyContract|TestOpenAPIOperationFieldPathsSpecializeGenericOptionalRecords|TestOpenAPIDirectionalAuditTraversesNullableGenericLists|TestOpenAPI30DirectionalMaterializationPreflightsAggregateNodes|TestOpenAPI30DirectionalRequirednessUsesFixedNativeViews|TestOpenAPI30DirectionalTypedMapAuditRequiresOptionalNestedFields|TestOpenAPI30DirectionalApplicatorAmbiguityFailsClosed|TestOpenAPI31DirectionalViewsRemainCanonical|TestWithDerivedOpenAPIOperationsDoesNotScanDirectionalExampleLookalikes|TestWithDerivedOpenAPIOperationsBuildsAuthoritativeCheckedBoundary|TestWithDerivedOpenAPIOperationsVersionMatrix|TestOpenAPIOperationIndexAndSemanticBoundary|TestOpenAPIOperationMetadataAndAggregateLimitsFailClosed|TestOpenAPIOperation30SchemaSeedsAreAdapted|TestWithDerivedOpenAPIOperationsRemainsEditableAndHasNoInferredContext|TestWithDerivedOpenAPIOperationsFailsClosedAtomically)$'
go test ./java -run '^(TestGeneratedOpenAPI30DirectionAwareNativeValidation|TestGeneratedNativeOpenAPIContextComposesAllBoundaries|TestGeneratedNativeJSONValidatorExactOfflineAndBounded|TestGeneratedProjectJSONSerdeComposesNativeAndRefinements|TestProjectJSONSerdeIncludesNativeRegexComposition|TestNativeJSONGeneratorHandlesPatternsAndGatesUnsupportedFormats|TestNativeRegexEmissionIsConditional|TestGeneratedNativeRegexECMA262AndBudgets|TestNativeJSONGeneratorUsesOpenAPI30ExactAdapter)$'
```

After native and Java sources are coherent, run the affected assembly callers
once, with the pinned required-Java/Maven/JAR environment:

```sh
go test -race ./project -run '^(TestMavenRegenerationAndReproducibleArtifact|TestGenerateIncludesCheckedOpenAPIContextFacade|TestGenerateIncludesComposedNativeOpenAPIOperationFacade|TestGenerateRejectsInvalidOrExternalNativeOpenAPIMetadata|TestProjectSchemaProofGateIncludesOpenAPIEntrypoints|TestGenerateNativeBundlePreservesOracleResourcesAndMetadata|TestGenerateNativeBundleRejectsConflictingOrLossyConfiguration)$'
go test -race ./cli -run '^(TestNativeOperationMetadataIsAuthoritativeAndReleaseIdentified|TestProjectCLIGeneratesNativeBundleWithoutDiscardingIt)$'
```

Maven is necessary here because its fixture consumes the changed native Java
resource helper. Its existing four distinct lifecycle builds cover unchanged
reproducibility, schema regeneration and expected generated-property failure;
the first build also supplies the actual JAR to the offline inventory verifier.
No fifth build is added. Unchanged model/evaluator/Avro harnesses and the
independent artifact unit selection retain their prior evidence.

For each completed batch record: source revision (or exact dirty-file scope),
command, result, environment, and any skipped coverage. A later relevant edit
invalidates that evidence; an unrelated edit does not. Keep checkpoint results
in [IMPLEMENTATION.md](IMPLEMENTATION.md). A command that reports “no tests to
run” is a selection failure, never a passing check.
