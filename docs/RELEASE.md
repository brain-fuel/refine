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
- all destinations are relative, distinct, absent, and do not traverse a known
  symbolic link; and
- every family and version is unique and canonical as a typed value.

The engine stages and fsyncs all bytes and a transaction journal under the
promotion root. It then installs with hard links. A hard link is an atomic
no-overwrite operation, so a destination appearing after validation causes the
whole in-process operation to roll back. Rollback removes a destination only if
it is the same inode as that transaction's staged file; equal bytes are not
treated as ownership. Existing releases and unrelated files are never
overwritten. `SNAPSHOT` files remain in place. Successful results report no
pending version for the promoted contract; the next planning pass must compare
canonical contract content so release-only pin/version metadata does not create
a false change.

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
  cooperating promotions, but portable Go path APIs cannot eliminate a malicious
  directory-swap symlink race. The final path component is still protected by
  no-overwrite hard-link creation.
- Staging and destinations must be on the same filesystem. A mount boundary
  makes hard-link installation fail and triggers rollback.
- Recovery is an explicit assertion that no promotion process still owns the
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

This planner does not inspect Java bytecode, generate Maven files, publish an
artifact, or decide Maven coordinates. Those remain integration responsibilities.
