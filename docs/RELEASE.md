# Release planning and promotion

The `release` package is a policy and filesystem transaction layer. It does not
parse schemas and it never claims that two arbitrary contracts are compatible.
A schema analyzer supplies explicit `ComparisonValid`, `ComparisonInvalid`, or
`ComparisonUnknown` evidence for each direction. The planner checks that
evidence against exact SHA-256 identities.

## Schema-family planning

`Plan(PlanningInput)` returns a `PlanResult` containing all policy issues and the
minimum suggested version. A pending release is ready only after the snapshot's
declared intended version exactly accepts that suggestion.

The caller supplies:

- the family and exact snapshot content digest;
- every immutable released baseline and its exact dependency pins;
- an explicit change classification;
- backward and forward comparison evidence against every earlier release in
  the suggested version's major;
- whether forward compatibility is a family guarantee; and
- any reviewed overrides or breaking-fix records.

Backward compatibility is always enforced within a compatibility boundary.
Forward compatibility is still reported in both directions but is enforced only
when `EnforceForward` is true. Before 1.0, each minor is a compatibility
boundary: comparison evidence is still required against every `0.x` baseline,
but a `0.1` to `0.2` break does not need an exception. From 1.0 onward, the major
is the boundary.

An override contains a `ComparisonRef` and a nonempty reason. Its content IDs
are SHA-256 hashes of the exact canonical comparison representations supplied to
the analyzer (including resolved contract inputs, excluding release-only
metadata such as an intended version). That reference binds the family,
baseline version, baseline comparison content, snapshot comparison content, and
direction.
Changing either input invalidates it. An invalid comparison released inside a
boundary also needs a separate `BreakingFix` with a distinct justification.
Merely acknowledging a break never classifies it as a fix.

Documentation-only changes, compatible fixes, compatible features, and breaking
changes suggest patch, patch, minor, and compatibility-boundary versions
respectively. A fully justified breaking fix may remain a patch. Dependency pin
content changes and removals participate in snapshot change detection; a pin
marked `AffectsContract` prevents a changed effective contract from being
classified as documentation-only. Existing releases retain their recorded pins.

If the latest release comparison content and dependency pins equal the snapshot, the result
has `NoPendingVersion` and no suggestion. A stale intended version is rejected;
promotion never manufactures the next patch number.

Example outline:

```go
candidate := release.Digest(snapshotBytes)
ref := release.ComparisonRef{
    Family: "booking", Baseline: oldVersion,
    BaselineContent: oldDigest, CandidateContent: candidate,
    Direction: release.Backward,
}
plan := release.Plan(release.PlanningInput{
    Family: "booking", SnapshotContent: candidate,
    Intended: &intended, Change: release.CompatibleFix,
    Releases: baselines,
    Comparisons: []release.CompatibilityEvidence{
        {Comparison: ref, Result: release.ComparisonUnknown,
            Detail: "recursive implication exceeded the analyzer's proof boundary"},
        // Supply the forward result and both directions for every other baseline.
    },
    Overrides: []release.CompatibilityOverride{
        {Comparison: ref, Reason: "reviewed by the contract owners"},
    },
})
```

## Filesystem promotion

`Promote(PromotionInput)` promotes one or more families in one validated batch.
Each family supplies the snapshot path and digest, immutable versioned schema
destination, exact release bytes, exact imports, and generated artifacts. The
engine verifies all of the following before installing an output:

- the snapshot is a regular path under the root and still has the planned bytes;
- caller-supplied release bytes are staged independently, allowing exact
  released import pins and release-only metadata to be materialized without
  modifying the editable snapshot;
- every import is an exact release, resolving either to the same batch or an
  explicitly supplied published identity;
- the supplied published-release catalog has unique family/version identities,
  and no batch member attempts to republish one of those immutable versions;
- all destinations are relative, distinct, and do not traverse a known symbolic
  link; immutable outputs must be absent, while an explicitly typed mutable
  replacement must be an existing regular file with the exact expected digest;
  and
- every family and version is unique and canonical as a typed value.

The engine stages and fsyncs all bytes and a transaction journal under the
promotion root. Immutable installs use hard links, an atomic no-overwrite
operation. A mutable replacement first receives a same-inode transaction backup,
is rechecked by inode and digest, and is then installed with a no-overwrite hard
link; recovery can restore the backup even after a crash between unlink and
install. Rollback removes a destination only if it is the same inode as that
transaction's staged file; equal bytes are not treated as ownership. Existing
releases and unrelated files are never overwritten. `SNAPSHOT` files remain in
place. Successful results report no pending version for the promoted contract;
the next planning pass must compare canonical contract content so release-only
pin/version metadata does not create a false change.

On a returned error, promotion attempts complete rollback and removes its own
staging directory. If the process or machine crashes, call `Recover(root)` before
another promotion. Recovery validates the complete journal, staged file hashes,
and directory contents, then rolls an incomplete install back by inode identity;
a committed transaction only loses its private staging metadata. An unexpected
file or malformed journal stops recovery instead of deleting it.

Filesystem caveats are explicit:

- Multi-file installation is crash-recoverable, not instantaneously isolated.
  Another process reading destinations during promotion can observe a prefix of
  the batch until promotion completes or recovery runs.
- The root must be used under exclusive operator control. The lock detects other
  cooperating promotions and project generators through `.refine-release.lock`,
  but portable Go path APIs cannot eliminate a malicious
  directory-swap symlink race. The final path component is still protected by
  no-overwrite hard-link creation.
- Staging and destinations must be on the same filesystem. A mount boundary
  makes hard-link installation fail and triggers rollback.
- Recovery is an explicit assertion that no promotion or generation process owns the
  crash-stale lock.

## Maven `no-codegen` version policy

`PlanMavenVersion` is independent of schema-family `Plan`. Its input lists every
previously published and next schema version and whether its Java classes are
generated. It implements the project-specific policy without substituting
generic Java API semver rules:

- removing generated classes from a previous schema-family major requires a
  major Maven artifact bump; and
- removing a generated version in the current schema-family major requires a
  minor Maven artifact bump.

The current family major includes `no-codegen` schema versions: publishing a new
family major while removing old-major classes still requires a major artifact
bump. Other caller-classified artifact changes combine by taking the stronger
requirement. With no changes there is no pending artifact version and no blind
patch increment.

This planner does not inspect Java bytecode, generate Maven files, or publish an
artifact. `PlanPublication` supplies the bounded integration for `noCodegen`
and owned generated-source removals. It validates a strict version-1 checked-in
publication ledger, exact schema/source/class/artifact digests, explicit
published versus unpublished attestations, and Maven effective coordinates.
It does not treat generated output as published and does not claim general Java
ABI compatibility.

## Project release workflow

The CLI reads release policy from the checked-in `refine.project.json` used by
project generation:

```json
{
  "release": {
    "enforceForward": false,
    "maven": {
      "current": "3.2.0",
      "intended": "3.3.0",
      "previouslyGenerated": [
        { "family": "booking", "version": "1.4.2" }
      ]
    }
  },
  "families": {
    "booking": {
      "root": "Booking",
      "release": {
        "change": "fix",
        "intended": "1.4.3",
        "overrides": [{
          "baseline": "1.4.2",
          "baselineSha256": "<lowercase SHA-256 from release plan>",
          "snapshotSha256": "<lowercase SHA-256 from release plan>",
          "direction": "backward",
          "reason": "reviewed against the deployed wire and Java consumers"
        }],
        "breakingFixes": [{
          "baseline": "1.4.2",
          "baselineSha256": "<same exact baseline identity>",
          "snapshotSha256": "<same exact snapshot identity>",
          "direction": "backward",
          "justification": "repairs values accepted contrary to the contract"
        }]
      }
    }
  }
}
```

`change` is one of `none`, `documentation`, `fix`, `feature`, or `breaking`.
Versions in policy use canonical `x.y.z` text without a `v` prefix. Unknown
fields, duplicate JSON keys, noncanonical versions, loose comparison identities,
and empty or reused reasons are rejected.

For `documentation`, the CLI additionally compares the latest baseline's
canonical checked language declarations, reachable dependency bodies and source
packages. Comments, layout, and equivalent string escapes do not count as
contract changes; predicates, functions, field/order changes, diagnostic
messages, and budgets do. Native metadata and constraint units are checked too.
Compatibility overrides do not authorize a false documentation classification.
An unproven classification rejects without a version suggestion until the author
chooses `fix`, `feature`, or `breaking`; the normal compatibility/version policy
then applies. This does not infer whether a functional change is a bug fix.

Native-resource changes currently remain unknown for documentation-only
classification, even if they appear confined to descriptions. Native annotation
equivalence needs a schema-position-aware proof, not removal of every JSON key
named `description`. Historical Java/project-policy compatibility still has its
separate unknown/override gate; canonical language equality does not prove it.

`refine release plan [family...]` discovers every `vX.Y.Z.refine` or
`vX.Y.Z.refined.json` baseline and both comparison directions automatically;
snapshots use the matching extension. Defining one family/version with both
extensions is rejected. A native bundle is treated as one exact self-contained
release input: its original native documents, URI-addressed resources, sidecar
metadata, editable/imported source graph, and native constraint units all bind
the comparison SHA. Even whitespace changes to the checked-in bundle invalidate
an earlier override. The comparison SHA for Refine sources binds the exact
original reachable sources—including comments and documentation—while
normalizing family entry names and import spellings. Consequently changing
documentation invalidates an override, while promotion's mechanical
`SNAPSHOT.refine` to `vX.Y.Z.refine` pin rewrite does not manufacture a later
pending release.

The identity also binds compatibility-relevant project policy for every
reachable schema family: selected root, logical/base/Java packages, native wire
formats, `noCodegen`, and the forward-guarantee setting. The plan reports the
source-plus-policy identity used by overrides and a separate deterministic
policy digest. Changing any of these settings invalidates an earlier override.
Historical per-version ABI metadata is not inferred when it is absent.

The built-in analyzer supplies only conservative logical payload evidence. A
logical counterexample is invalid evidence. Otherwise the combined release
comparison remains unknown because general native-wire and generated-Java ABI
proofs do not yet exist. Those dimensions are displayed separately and are
never presented as proven by `compare-payload`; an enforced unknown needs the
exact content-bound override shown above.

Native bundles may contain a complete private Refine import graph. If an
embedded source resolves to another versioned family file in the release
catalog, however, the workflow currently cannot prove that relationship as an
exact semantic dependency pin and fails closed. It never silently drops that
dependency from release planning. Cross-format generation of opaque native
constraints is likewise unsupported unless the requested output can be proven;
configure the bundle's origin format for the exact supported path.

`refine release promote [family...]` repeats planning against current bytes,
requires every changed family in the batch to have explicitly accepted its
suggested version, rewrites schema-family imports to exact releases, and calls
the recoverable promotion engine once. Snapshot dependencies must be included
in the same batch. Existing exact releases may be used from disk. The operation
does not deploy or publish anything.

A native snapshot is copied byte-for-byte to
`vX.Y.Z.refined.json`; its contents are not flattened or regenerated. The
snapshot remains unchanged. The immutable version path and every bundle/config/
dependency input used by planning and generation are rechecked while holding
the promotion lock before any output is installed.

Version-qualified generated Java sources, property tests, resources, and the
owned-output manifest participate in the same journal as schema files. New
paths use atomic no-overwrite hard links. An existing owned shared output (for
example the generated test launcher) and `.refine-generated.json` may be
replaced only when their bytes match the planned digest; the transaction keeps
same-inode backups until commit. Recovery restores those backups on an
incomplete install. This remains crash-recoverable rather than instantaneously
isolated to concurrent readers. Run `refine release recover --root DIR` only
after establishing that no promotion process is still active.

Generation is planned for the complete project—every existing release and
snapshot plus each new release—so replacement of the shared test launcher never
drops prior suites. All source files reachable during planning or code
generation, together with `refine.project.json`, become content preconditions
that are rechecked after the promotion lock is acquired. A dependency or config
edit in the plan/apply window therefore fails before any output is installed.

The optional Maven policy records current/intended artifact versions and may
select `release.maven.publicationLedger` (default
`refine.publications.json`). `otherChange` may explicitly be `none`, `patch`,
`feature`, or `breaking`. The legacy `previouslyGenerated` list is not
publication authority: publication-sensitive removals require digest-bound
ledger records. Both ordinary generation and promotion run the same gate before
owned deletion. Promotion also adds the ledger and every consulted immutable
schema to its under-lock content preconditions. An intended new schema version
may appear in `noCodegen` before its immutable schema file exists; because it
has no historical generated class removal, resources can still be generated
and promoted without manufacturing publication history.

For a relevant published removal, standalone `release plan`/`promote` accepts
`--maven-group-id`, `--maven-artifact-id`, and `--maven-version`; all must be
values from Maven's effective model, must match the ledger coordinates, and the
version must equal the explicitly accepted artifact suggestion. Missing values
fail as unknown. Raw POM text is never used as proof of effective coordinates.

The version-1 ledger describes one exact prior artifact baseline; every
`published` record therefore uses the same artifact version and SHA-256. Its
shape is:

```json
{
  "version": 1,
  "groupId": "com.example",
  "artifactId": "models",
  "records": [{
    "state": "published",
    "family": "orders",
    "schemaVersion": "1.2.0",
    "schemaSha256": "<SHA-256 of schemata/orders/v1.2.0.refine>",
    "generatedSources": [{"path": "target/generated-sources/refine/orders/v1_2_0/Order.java", "sha256": "<SHA-256>"}],
    "artifactVersion": "2.0.0",
    "artifactSha256": "<SHA-256 of the published JAR>",
    "classes": [{"path": "com/example/orders/Order.class", "sha256": "<SHA-256 of that JAR entry>"}],
    "inventorySha256": "<release.PublicationInventoryDigest(record)>",
    "reason": "verified against repository artifact com.example:models:2.0.0"
  }]
}
```

Records are sorted by family/version; inventory arrays use unique, sorted
portable paths. An `unpublished` record retains
the schema/generated-source inventory and reason, but omits artifact version,
artifact digest, and classes. Unknown/duplicate JSON fields, unsafe paths,
noncanonical versions, stale schema/source bytes, case-fold collisions, and a
mismatched inventory digest reject the entire gate.
