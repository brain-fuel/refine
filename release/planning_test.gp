// GoPlus-authored release planner tests.
package release

import (
	"math/rand"
	"strings"
	"testing"
)

func vp(v Version) *Version { return &v }
func baseline(v Version, text string) ReleaseBaseline {
	return ReleaseBaseline{Version: v, Content: Digest([]byte(text))}
}
func comparisons(family string, candidate ContentID, releases []ReleaseBaseline, backward, forward ComparisonResult) []CompatibilityEvidence {
	var out []CompatibilityEvidence
	for _, b := range releases {
		for _, item := range []struct {
			d Direction
			r ComparisonResult
		}{{Backward, backward}, {Forward, forward}} {
			out = append(out, CompatibilityEvidence{Comparison: ComparisonRef{Family: family, Baseline: b.Version, BaselineContent: b.Content, CandidateContent: candidate, Direction: item.d}, Result: item.r})
		}
	}
	return out
}
func hasIssue(result PlanResult, code string) bool {
	for _, i := range result.Issues {
		if i.Code == code {
			return true
		}
	}
	return false
}

func TestParseVersionCanonical(t *testing.T) {
	for _, text := range []string{"0.0.0", "v1.2.3", "25.10.9"} {
		if _, err := ParseVersion(text); err != nil {
			t.Fatalf("%s: %v", text, err)
		}
	}
	for _, text := range []string{"", "1.2", "1.2.3-beta", "01.2.3", "-1.2.3"} {
		if _, err := ParseVersion(text); err == nil {
			t.Fatalf("accepted %q", text)
		}
	}
}

func TestPlanVersionTable(t *testing.T) {
	base := baseline(Version{Major: 1}, "old")
	newID := Digest([]byte("new"))
	tests := []struct {
		name     string
		change   ChangeKind
		evidence []CompatibilityEvidence
		want     Version
	}{
		{"docs", DocumentationOnly, comparisons("foo", newID, []ReleaseBaseline{base}, ComparisonValid, ComparisonValid), Version{Major: 1, Patch: 1}},
		{"compatible fix", CompatibleFix, comparisons("foo", newID, []ReleaseBaseline{base}, ComparisonValid, ComparisonUnknown), Version{Major: 1, Patch: 1}},
		{"feature", CompatibleFeature, comparisons("foo", newID, []ReleaseBaseline{base}, ComparisonValid, ComparisonValid), Version{Major: 1, Minor: 1}},
		{"breaking", BreakingChange, comparisons("foo", newID, []ReleaseBaseline{base}, ComparisonInvalid, ComparisonValid), Version{Major: 2}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			in := PlanningInput{Family: "foo", SnapshotContent: newID, Change: tc.change, Releases: []ReleaseBaseline{base}, Comparisons: tc.evidence, Intended: vp(tc.want)}
			got := Plan(in)
			if got.Suggested == nil || *got.Suggested != tc.want {
				t.Fatalf("suggested=%v issues=%v", got.Suggested, got.Issues)
			}
			if !got.Ready {
				t.Fatalf("not ready: %+v", got.Issues)
			}
		})
	}
}

func TestBreakingFixRequiresTwoDistinctJustifications(t *testing.T) {
	b := baseline(Version{Major: 1}, "old")
	candidate := Digest([]byte("fix"))
	ev := comparisons("foo", candidate, []ReleaseBaseline{b}, ComparisonInvalid, ComparisonValid)
	ref := ev[0].Comparison
	intended := Version{Major: 1, Patch: 1}
	in := PlanningInput{Family: "foo", SnapshotContent: candidate, Change: BreakingChange, Releases: []ReleaseBaseline{b}, Comparisons: ev, Intended: &intended,
		Overrides: []CompatibilityOverride{{Comparison: ref, Reason: "acknowledge incompatibility"}}, BreakingFixes: []BreakingFix{{Comparison: ref, Justification: "repairs incorrectly accepted data"}}}
	if got := Plan(in); !got.Ready || got.Suggested == nil || *got.Suggested != intended {
		t.Fatalf("breaking fix rejected: %+v", got)
	}
	in.BreakingFixes[0].Justification = in.Overrides[0].Reason
	if got := Plan(in); !hasIssue(got, "release.fix_reason_distinct") {
		t.Fatalf("same reason accepted: %+v", got)
	}
	in.BreakingFixes = nil
	if got := Plan(in); got.Suggested == nil || *got.Suggested != (Version{Major: 2}) {
		t.Fatalf("override silently became fix: %+v", got)
	}
}

func TestUnknownDirectionGuaranteesAndContentBoundOverride(t *testing.T) {
	b := baseline(Version{Major: 1}, "old")
	candidate := Digest([]byte("new"))
	ev := comparisons("foo", candidate, []ReleaseBaseline{b}, ComparisonValid, ComparisonUnknown)
	intended := Version{Major: 1, Patch: 1}
	in := PlanningInput{Family: "foo", SnapshotContent: candidate, Change: CompatibleFix, Releases: []ReleaseBaseline{b}, Comparisons: ev, Intended: &intended}
	if got := Plan(in); !got.Ready {
		t.Fatalf("unenforced forward unknown failed: %+v", got)
	}
	in.EnforceForward = true
	if got := Plan(in); !hasIssue(got, "release.unknown") {
		t.Fatalf("enforced forward unknown passed: %+v", got)
	}
	wrong := ev[1].Comparison
	wrong.CandidateContent = Digest([]byte("changed"))
	in.Overrides = []CompatibilityOverride{{Comparison: wrong, Reason: "reviewed"}}
	if got := Plan(in); !hasIssue(got, "release.unknown") {
		t.Fatalf("non-content-bound override passed: %+v", got)
	}
	in.Overrides = []CompatibilityOverride{{Comparison: ev[1].Comparison, Reason: "solver could not decide recursive rule"}}
	if got := Plan(in); !got.Ready {
		t.Fatalf("exact override rejected: %+v", got)
	}
}

func TestAllInMajorBaselinesAndZeroMinorBoundary(t *testing.T) {
	releases := []ReleaseBaseline{baseline(Version{Minor: 1}, "a"), baseline(Version{Minor: 1, Patch: 1}, "b")}
	candidate := Digest([]byte("break"))
	intended := Version{Minor: 2}
	in := PlanningInput{Family: "foo", SnapshotContent: candidate, Change: BreakingChange, Releases: releases, Comparisons: comparisons("foo", candidate, releases, ComparisonInvalid, ComparisonUnknown), Intended: &intended, EnforceForward: true}
	if got := Plan(in); !got.Ready {
		t.Fatalf("0.x minor boundary did not permit break/unknown: %+v", got)
	}
	in.Comparisons = in.Comparisons[:len(in.Comparisons)-1]
	if got := Plan(in); !hasIssue(got, "release.missing_comparison") {
		t.Fatalf("prior baseline direction was not required: %+v", got)
	}
}

func TestUnchangedSnapshotHasNoPendingVersion(t *testing.T) {
	id := Digest([]byte("same"))
	pin := ImportPin{Family: "dep", Version: Version{Major: 1}, Content: Digest([]byte("dep")), AffectsContract: true}
	b := ReleaseBaseline{Version: Version{Major: 1}, Content: id, Imports: []ImportPin{pin}}
	got := Plan(PlanningInput{Family: "foo", SnapshotContent: id, SnapshotImports: []ImportPin{pin}, Change: NoChange, Releases: []ReleaseBaseline{b}})
	if !got.Ready || !got.NoPendingVersion || got.Suggested != nil {
		t.Fatalf("unchanged plan: %+v", got)
	}
	stale := Version{Major: 1, Patch: 1}
	got = Plan(PlanningInput{Family: "foo", SnapshotContent: id, SnapshotImports: []ImportPin{pin}, Change: NoChange, Releases: []ReleaseBaseline{b}, Intended: &stale})
	if !got.NoPendingVersion || !hasIssue(got, "release.unneeded_intended") {
		t.Fatalf("stale intended survived: %+v", got)
	}
}

func TestDependencyContentAffectsPlan(t *testing.T) {
	same := Digest([]byte("schema"))
	oldPin := ImportPin{Family: "dep", Version: Version{Major: 1}, Content: Digest([]byte("dep1")), AffectsContract: true}
	newPin := oldPin
	newPin.Version.Patch = 1
	newPin.Content = Digest([]byte("dep2"))
	b := ReleaseBaseline{Version: Version{Major: 1}, Content: same, Imports: []ImportPin{oldPin}}
	want := Version{Major: 1, Patch: 1}
	in := PlanningInput{Family: "foo", SnapshotContent: same, SnapshotImports: []ImportPin{newPin}, Change: DocumentationOnly, Releases: []ReleaseBaseline{b}, Comparisons: comparisons("foo", same, []ReleaseBaseline{b}, ComparisonValid, ComparisonValid), Intended: &want}
	if got := Plan(in); !hasIssue(got, "release.dependency_contract") {
		t.Fatalf("contract-changing dependency treated as docs: %+v", got)
	}
	in.Change = CompatibleFix
	if got := Plan(in); !got.Ready {
		t.Fatalf("dependency contract fix rejected: %+v", got)
	}
	in.SnapshotImports = nil
	if got := Plan(in); !got.Ready {
		t.Fatalf("removed contract dependency was not treated as effective change: %+v", got)
	}
}

func TestDependencyEvidenceFlagDoesNotChangePinIdentity(t *testing.T) {
	pin := ImportPin{Family: "dep", Version: Version{Major: 1}, Content: Digest([]byte("dep")), AffectsContract: true}
	other := pin
	other.AffectsContract = false
	if !samePins([]ImportPin{pin}, []ImportPin{other}) {
		t.Fatal("dependency evidence-only flag changed exact pin identity")
	}
	baseline := ReleaseBaseline{Version: Version{Major: 1}, Content: Digest([]byte("schema")), Imports: []ImportPin{pin}}
	got := Plan(PlanningInput{Family: "foo", SnapshotContent: baseline.Content, SnapshotImports: []ImportPin{other}, Change: NoChange, Releases: []ReleaseBaseline{baseline}})
	if !got.Ready || !got.NoPendingVersion {
		t.Fatalf("evidence-only flag manufactured a pending release: %+v", got)
	}
}

func TestInvalidEvidenceIdentityCannotControlVersion(t *testing.T) {
	b := baseline(Version{Major: 1}, "old")
	candidate := Digest([]byte("new"))
	fake := CompatibilityEvidence{Comparison: ComparisonRef{Family: "foo", Baseline: b.Version, BaselineContent: Digest([]byte("not-old")), CandidateContent: candidate, Direction: Backward}, Result: ComparisonInvalid}
	want := Version{Major: 1, Patch: 1}
	in := PlanningInput{Family: "foo", SnapshotContent: candidate, Change: CompatibleFix, Releases: []ReleaseBaseline{b}, Comparisons: append([]CompatibilityEvidence{fake}, comparisons("foo", candidate, []ReleaseBaseline{b}, ComparisonValid, ComparisonValid)...), Intended: &want}
	got := Plan(in)
	if got.Suggested == nil || *got.Suggested != want || !hasIssue(got, "release.comparison_identity") {
		t.Fatalf("fake evidence influenced plan: %+v", got)
	}
}

func TestEnforcedForwardBreakRequiresBoundaryOrBreakingFix(t *testing.T) {
	b := baseline(Version{Major: 1}, "old")
	candidate := Digest([]byte("new"))
	ev := comparisons("foo", candidate, []ReleaseBaseline{b}, ComparisonValid, ComparisonInvalid)
	major := Version{Major: 2}
	in := PlanningInput{Family: "foo", SnapshotContent: candidate, Change: CompatibleFix, Releases: []ReleaseBaseline{b}, Comparisons: ev, Intended: &major, EnforceForward: true}
	if got := Plan(in); !got.Ready || got.Suggested == nil || *got.Suggested != major {
		t.Fatalf("forward break did not require boundary: %+v", got)
	}
	patch := Version{Major: 1, Patch: 1}
	ref := ev[1].Comparison
	in.Intended = &patch
	in.Overrides = []CompatibilityOverride{{Comparison: ref, Reason: "acknowledge forward break"}}
	in.BreakingFixes = []BreakingFix{{Comparison: ref, Justification: "restores documented producer behavior"}}
	if got := Plan(in); !got.Ready || got.Suggested == nil || *got.Suggested != patch {
		t.Fatalf("forward breaking fix rejected: %+v", got)
	}
}

func TestVersionOverflowRejected(t *testing.T) {
	b := baseline(Version{Major: 1, Patch: maxInt}, "old")
	candidate := Digest([]byte("new"))
	got := Plan(PlanningInput{Family: "foo", SnapshotContent: candidate, Change: CompatibleFix, Releases: []ReleaseBaseline{b}})
	if !hasIssue(got, "release.version_overflow") || got.Suggested != nil {
		t.Fatalf("overflow accepted: %+v", got)
	}
}

func TestVersionSuccessorProperty(t *testing.T) {
	r := rand.New(rand.NewSource(7))
	for i := 0; i < 1000; i++ {
		v := Version{Major: r.Intn(100), Minor: r.Intn(100), Patch: r.Intn(100)}
		for _, next := range []Version{v.nextPatch(), v.nextMinor(), v.nextMajor()} {
			if next.Compare(v) <= 0 {
				t.Fatalf("%v did not advance %v", next, v)
			}
			parsed, err := ParseVersion(next.String())
			if err != nil || parsed != next {
				t.Fatalf("round trip %v: %v", next, err)
			}
		}
	}
}

func TestIssueMessagesDoNotLeakSchemaBytes(t *testing.T) {
	secret := "secret-payload-value"
	got := Plan(PlanningInput{Family: "bad/name", SnapshotContent: Digest([]byte(secret)), Change: NoChange})
	for _, i := range got.Issues {
		if strings.Contains(i.Message, secret) {
			t.Fatalf("issue leaked content: %+v", i)
		}
	}
}
