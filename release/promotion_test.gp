// GoPlus-authored promotion transaction tests.
package release

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func writeSnapshot(t *testing.T, root, path string, content []byte) ContentID {
	t.Helper()
	full := filepath.Join(root, path)
	if err := os.MkdirAll(filepath.Dir(full), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, content, 0644); err != nil {
		t.Fatal(err)
	}
	return Digest(content)
}

func TestPromoteMultiFamilyExactPinsAndRetainsSnapshots(t *testing.T) {
	root := t.TempDir()
	foo := []byte("foo snapshot")
	bar := []byte("bar imports foo SNAPSHOT")
	barRelease := []byte("bar imports foo 1.0.0")
	fooID := writeSnapshot(t, root, "schemata/foo/SNAPSHOT.refine", foo)
	barID := writeSnapshot(t, root, "schemata/bar/SNAPSHOT.refine", bar)
	v := Version{Major: 1}
	in := PromotionInput{Root: root, Families: []PromotionFamily{
		{Family: "foo", Version: v, SnapshotPath: "schemata/foo/SNAPSHOT.refine", SnapshotFileContent: fooID, ReleasePath: "schemata/foo/v1.0.0.refine", ReleaseContent: foo, Generated: []Artifact{{Path: "generated/foo/v1_0_0/Foo.java", Content: []byte("class Foo {}")}}},
		{Family: "bar", Version: v, SnapshotPath: "schemata/bar/SNAPSHOT.refine", SnapshotFileContent: barID, ReleasePath: "schemata/bar/v1.0.0.refine", ReleaseContent: barRelease, Imports: []PromotionImport{{Family: "foo", Kind: ExactRelease, Version: v, Content: fooID}}},
	}}
	got, err := Promote(in)
	if err != nil {
		t.Fatal(err)
	}
	if len(got.Released) != 2 || got.SnapshotPending["foo"] || got.SnapshotPending["bar"] {
		t.Fatalf("got %+v", got)
	}
	for path, want := range map[string]string{"schemata/foo/SNAPSHOT.refine": string(foo), "schemata/foo/v1.0.0.refine": string(foo), "schemata/bar/SNAPSHOT.refine": string(bar), "schemata/bar/v1.0.0.refine": string(barRelease), "generated/foo/v1_0_0/Foo.java": "class Foo {}"} {
		data, e := os.ReadFile(filepath.Join(root, path))
		if e != nil || string(data) != want {
			t.Fatalf("%s=%q %v", path, data, e)
		}
	}
}

func TestPromotionValidationLeavesEverythingUnpromoted(t *testing.T) {
	root := t.TempDir()
	content := []byte("schema")
	id := writeSnapshot(t, root, "SNAPSHOT", content)
	if err := os.WriteFile(filepath.Join(root, "unrelated"), []byte("mine"), 0644); err != nil {
		t.Fatal(err)
	}
	base := PromotionFamily{Family: "foo", Version: Version{Major: 1}, SnapshotPath: "SNAPSHOT", SnapshotFileContent: id, ReleasePath: "release", ReleaseContent: content}
	tests := []struct {
		name   string
		mutate func(*PromotionFamily)
	}{
		{"floating import", func(f *PromotionFamily) { f.Imports = []PromotionImport{{Family: "dep", Kind: VersionRangeImport}} }},
		{"snapshot changed", func(f *PromotionFamily) { f.SnapshotFileContent = Digest([]byte("other")) }},
		{"duplicate destination", func(f *PromotionFamily) { f.Generated = []Artifact{{Path: "release", Content: []byte("code")}} }},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			f := base
			tc.mutate(&f)
			if _, err := Promote(PromotionInput{Root: root, Families: []PromotionFamily{f}}); err == nil {
				t.Fatal("expected failure")
			}
			if _, err := os.Stat(filepath.Join(root, "release")); !errors.Is(err, os.ErrNotExist) {
				t.Fatalf("release changed: %v", err)
			}
			data, _ := os.ReadFile(filepath.Join(root, "unrelated"))
			if string(data) != "mine" {
				t.Fatal("unrelated file changed")
			}
		})
	}
}

func TestPromotionRollbackDoesNotRemoveRacingCollision(t *testing.T) {
	root := t.TempDir()
	content := []byte("schema")
	id := writeSnapshot(t, root, "SNAPSHOT", content)
	if err := os.WriteFile(filepath.Join(root, "unrelated"), []byte("mine"), 0644); err != nil {
		t.Fatal(err)
	}
	original := linkFile
	calls := 0
	linkFile = func(old, new string) error {
		calls++
		if calls == 2 {
			if err := os.WriteFile(new, []byte("racer"), 0644); err != nil {
				return err
			}
			return os.Link(old, new)
		}
		return os.Link(old, new)
	}
	defer func() { linkFile = original }()
	f := PromotionFamily{Family: "foo", Version: Version{Major: 1}, SnapshotPath: "SNAPSHOT", SnapshotFileContent: id, ReleasePath: "a-release", ReleaseContent: content, Generated: []Artifact{{Path: "z-code", Content: []byte("code")}}}
	if _, err := Promote(PromotionInput{Root: root, Families: []PromotionFamily{f}}); err == nil {
		t.Fatal("expected injected collision")
	}
	if _, err := os.Stat(filepath.Join(root, "a-release")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("first output not rolled back: %v", err)
	}
	data, err := os.ReadFile(filepath.Join(root, "z-code"))
	if err != nil || string(data) != "racer" {
		t.Fatalf("racing file touched: %q %v", data, err)
	}
	data, _ = os.ReadFile(filepath.Join(root, "unrelated"))
	if string(data) != "mine" {
		t.Fatal("unrelated changed")
	}
	matches, _ := filepath.Glob(filepath.Join(root, transactionPrefix+"*"))
	if len(matches) != 0 {
		t.Fatalf("transaction debris: %v", matches)
	}
}

func TestRecoverIncompleteTransactionByInodeOwnership(t *testing.T) {
	root := t.TempDir()
	txn, err := os.MkdirTemp(root, transactionPrefix)
	if err != nil {
		t.Fatal(err)
	}
	stage := filepath.Join(txn, "entry-000000")
	if err = os.WriteFile(stage, []byte("owned"), 0644); err != nil {
		t.Fatal(err)
	}
	destination := filepath.Join(root, "release")
	if err = os.Link(stage, destination); err != nil {
		t.Fatal(err)
	}
	entries := []transactionEntry{{Destination: "release", Stage: "entry-000000", Digest: Digest([]byte("owned"))}}
	if err = writeJournal(filepath.Join(txn, "journal.json"), transactionJournal{Version: 1, State: "installing", Entries: entries}); err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(filepath.Join(root, lockName), nil, 0600); err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(filepath.Join(root, "unrelated"), []byte("owned"), 0644); err != nil {
		t.Fatal(err)
	}
	if err = Recover(root); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{destination, txn, filepath.Join(root, lockName)} {
		if _, e := os.Stat(path); !errors.Is(e, os.ErrNotExist) {
			t.Fatalf("%s remains: %v", path, e)
		}
	}
	if data, e := os.ReadFile(filepath.Join(root, "unrelated")); e != nil || string(data) != "owned" {
		t.Fatalf("unrelated touched: %q %v", data, e)
	}
}

func TestPromotionRejectsSymlinkAndImmutableCollision(t *testing.T) {
	root := t.TempDir()
	outside := t.TempDir()
	content := []byte("schema")
	id := writeSnapshot(t, root, "SNAPSHOT", content)
	if err := os.Symlink(outside, filepath.Join(root, "generated")); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	f := PromotionFamily{Family: "foo", Version: Version{Major: 1}, SnapshotPath: "SNAPSHOT", SnapshotFileContent: id, ReleasePath: "release", ReleaseContent: content, Generated: []Artifact{{Path: "generated/Foo.java", Content: []byte("code")}}}
	if _, err := Promote(PromotionInput{Root: root, Families: []PromotionFamily{f}}); err == nil {
		t.Fatal("symlink accepted")
	}
	if _, err := os.Stat(filepath.Join(outside, "Foo.java")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("wrote through symlink: %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "release"), []byte("published"), 0644); err != nil {
		t.Fatal(err)
	}
	f.Generated = nil
	if _, err := Promote(PromotionInput{Root: root, Families: []PromotionFamily{f}}); err == nil {
		t.Fatal("immutable collision accepted")
	}
	data, _ := os.ReadFile(filepath.Join(root, "release"))
	if string(data) != "published" {
		t.Fatal("published release overwritten")
	}
}
