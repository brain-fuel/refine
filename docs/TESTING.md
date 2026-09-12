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
| Explicit JSON annotation before automatic projection | `go test ./native -run '^(TestJSONTypedMapProjectionFailsWithoutWeakeningNativeSchema|TestJSONOrdinaryExtraFieldPoliciesRemainProjectable|TestSelectedJSONAnnotationIntentionallyBypassesOnlyAutoProjection|TestInvalidSelectedJSONAnnotationsFailAtomically)$'`; `go test -race ./native -run '^(TestRootAnnotationSeedsEditableSourceWithoutChangingSelector|TestNativeConstraintCommentLookalikeDoesNotGrantEditAuthority|TestVersionOneBundleWithoutConstraintSourceFieldRestoresCanonicalUnits|TestExplicitJSONSchemaResourceResolutionAndBundle|TestResourceAndBundleFailuresAreExplicit|TestProjectExportComposesEffectiveNativeAndEditableJSONSchema|TestRefinedLoweringCarriesCheckedWireMetadataAcrossFormats)$'`; `REFINE_REQUIRE_JAVA=1 REFINE_NETWORKNT_DIR=… REFINE_GRAALJS_DIR=… go test -race ./java -run '^TestGeneratedNativeRegexECMA262AndBudgets$'` | Unannotated typed maps fail explicitly; deliberately authored views still preserve native enforcement, selected roots, annotations, resource scope, and full generated pattern-properties coverage |
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
| OpenAPI request/response refinement context | `go test -race ./validation -run '^TestMergeReportsPreservesInvalidAndIncomplete$'`; `go test -race ./openapi -run '^(TestOperationContextValidation|TestOperationMetadataRejectsAmbiguousOrIncompatibleBindings)$'`; `go test -race ./native -run '^(TestOpenAPIOperationMetadataBundleAnnotationAndCopy|TestOpenAPIOperationMetadataRejectsStaleTypeReferences|TestOpenAPIOperationExplanationIncludesUnreachableContextAndRequiresLossOptIn)$'`; `go test -race ./java -run '^(TestGeneratedOpenAPIContextMatchesGo|TestOpenAPIContextGenerationRejectsPartialOutput)$'`; `go test -race ./project -run '^(TestGenerateIncludesCheckedOpenAPIContextFacade|TestGenerateRejectsInvalidOrExternalNativeOpenAPIMetadata)$'`; `go test -race ./cli -run '^TestNativeOperationMetadataIsAuthoritativeAndReleaseIdentified$'` | Versioned method/path/type bindings, exact/class/default response selection, cross-request predicates, missing-context aggregation, immutable bundle/annotation metadata, complete operation English and ordinary-loss opt-in, release identity, project facade merging, native metadata authority, and Go/Java outcome parity |
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
