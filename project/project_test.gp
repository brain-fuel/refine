// GoPlus-authored project generation tests.
package project

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"goforge.dev/refine/language"
	"goforge.dev/refine/native"
	"goforge.dev/refine/release"
)

func program(t *testing.T) *language.Program {
	t.Helper()
	p, err := language.Compile("type Name = String where length it > 0\n")
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func TestGenerateVersionedAndSnapshotDeterministic(t *testing.T) {
	p := program(t)
	v := release.Version{Major: 1, Minor: 2, Patch: 3}
	input := GenerateInput{BaseJavaPackage: "com.example", Contracts: []Contract{{Family: "people", Version: &v, Program: p, RootType: "Name", Formats: []native.Format{native.JSONSchema}}, {Family: "draft", Program: p, RootType: "Name", NoCodegen: true, Formats: []native.Format{native.JSONSchema}}}}
	a, err := Generate(input)
	if err != nil {
		t.Fatal(err)
	}
	b, err := Generate(input)
	if err != nil {
		t.Fatal(err)
	}
	if len(a.Files) == 0 || len(a.Files) != len(b.Files) {
		t.Fatal("missing output")
	}
	for i := range a.Files {
		if a.Files[i].Path != b.Files[i].Path || !bytes.Equal(a.Files[i].Content, b.Files[i].Content) {
			t.Fatalf("nondeterministic %d", i)
		}
	}
	seenVersion, seenSnapshotResource, snapshotJava := false, false, false
	for _, f := range a.Files {
		seenVersion = seenVersion || strings.Contains(f.Path, "com/example/people/v1_2_3/")
		seenSnapshotResource = seenSnapshotResource || strings.Contains(f.Path, "refine/draft/snapshot/contract.refine")
		snapshotJava = snapshotJava || (strings.HasSuffix(f.Path, ".java") && strings.Contains(f.Path, "/draft/"))
	}
	if !seenVersion || !seenSnapshotResource || snapshotJava {
		t.Fatalf("layout flags version=%t snapshot=%t noCodegenJava=%t", seenVersion, seenSnapshotResource, snapshotJava)
	}
}

func TestGenerateFlatDetectsClassCollisions(t *testing.T) {
	p := program(t)
	_, err := Generate(GenerateInput{Layout: Layout{Flat: true}, Contracts: []Contract{{Family: "a", Program: p, RootType: "Name", Formats: []native.Format{native.JSONSchema}}, {Family: "b", Program: p, RootType: "Name", Formats: []native.Format{native.JSONSchema}}}})
	if err == nil {
		t.Fatal("flat class collision accepted")
	}
}

func TestDetectRoot(t *testing.T) {
	root := t.TempDir()
	nested := filepath.Join(root, "a", "b")
	if err := os.MkdirAll(nested, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "pom.xml"), []byte("<project/>"), 0644); err != nil {
		t.Fatal(err)
	}
	got, err := DetectRoot(nested)
	if err != nil || got != root {
		t.Fatalf("%q %v", got, err)
	}
}

func TestWriteOwnedRetryStaleAndPreservation(t *testing.T) {
	root := t.TempDir()
	first := Bundle{Files: []File{{Path: "target/generated/A.java", Content: []byte("A1")}, {Path: "target/generated/stale.java", Content: []byte("old")}}}
	if err := WriteOwned(root, first, ""); err != nil {
		t.Fatal(err)
	}
	if err := WriteOwned(root, first, ""); err != nil {
		t.Fatalf("deterministic retry: %v", err)
	}
	second := Bundle{Files: []File{{Path: "target/generated/A.java", Content: []byte("A2")}}}
	if err := WriteOwned(root, second, ""); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, "target/generated/stale.java")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("stale output remains: %v", err)
	}
	data, _ := os.ReadFile(filepath.Join(root, "target/generated/A.java"))
	if string(data) != "A2" {
		t.Fatal("replacement failed")
	}
	if err := os.WriteFile(filepath.Join(root, "target/generated/A.java"), []byte("user edit"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := WriteOwned(root, first, ""); err == nil {
		t.Fatal("edited generated output overwritten")
	}
	data, _ = os.ReadFile(filepath.Join(root, "target/generated/A.java"))
	if string(data) != "user edit" {
		t.Fatal("user edit lost")
	}
}

func TestWriteOwnedRejectsUnownedAndSymlink(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "collision"), []byte("mine"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := WriteOwned(root, Bundle{Files: []File{{Path: "collision", Content: []byte("new")}}}, ""); err == nil {
		t.Fatal("unowned collision overwritten")
	}
	outside := t.TempDir()
	if err := os.Symlink(outside, filepath.Join(root, "linked")); err != nil {
		t.Skip(err)
	}
	if err := WriteOwned(root, Bundle{Files: []File{{Path: "linked/X.java", Content: []byte("x")}}}, ""); err == nil {
		t.Fatal("symlink traversal accepted")
	}
	if _, err := os.Stat(filepath.Join(outside, "X.java")); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("wrote outside root")
	}
}

func TestMavenSnippetAndNoCodegenPlan(t *testing.T) {
	snippet := MavenSnippet(MavenOptions{CLIExecutable: "refine&generate", CLIArguments: []string{"project", "a<b"}})
	for _, want := range []string{"maven.compiler.release>25", "generate-sources", "generated-test-sources", "refine&amp;generate", "a&lt;b"} {
		if !strings.Contains(snippet, want) {
			t.Fatalf("missing %q", want)
		}
	}
	current := release.Version{Major: 1}
	want := release.Version{Major: 2}
	plan := PlanNoCodegen(release.MavenPlanningInput{Current: current, Intended: &want, PreviouslyPublished: []release.GeneratedVersion{{Family: "foo", SchemaVersion: release.Version{Major: 1}, Generated: true}}, Next: []release.GeneratedVersion{{Family: "foo", SchemaVersion: release.Version{Major: 2}, Generated: false}}})
	if !plan.Ready || plan.RequiredChange != release.ArtifactBreakingChange {
		t.Fatalf("plan %+v", plan)
	}
}

func TestWriteOwnedRollsBackInstallFailure(t *testing.T) {
    root := t.TempDir()
    original := linkOwned
    calls := 0
    linkOwned = func(old, new string) error {
        calls++
        if calls == 2 { return errors.New("injected link failure") }
        return os.Link(old, new)
    }
    defer func() { linkOwned = original }()
    bundle := Bundle{Files: []File{{Path: "a.java", Content: []byte("a")}, {Path: "b.java", Content: []byte("b")}}}
    if err := WriteOwned(root, bundle, ""); err == nil { t.Fatal("expected failure") }
    for _, name := range []string{"a.java", "b.java", ".refine-generated.json"} {
        if _, err := os.Stat(filepath.Join(root, name)); !errors.Is(err, os.ErrNotExist) { t.Fatalf("partial output %s: %v", name, err) }
    }
}

func TestWriteOwnedManifestAndPortablePathHardening(t *testing.T) {
    root:=t.TempDir();duplicate:=[]byte(`{"version":1,"version":1,"files":{}}`);if err:=os.WriteFile(filepath.Join(root,".refine-generated.json"),duplicate,0644);err!=nil{t.Fatal(err)};if err:=WriteOwned(root,Bundle{},"");err==nil{t.Fatal("duplicate manifest key accepted")}
    if err:=os.Remove(filepath.Join(root,".refine-generated.json"));err!=nil{t.Fatal(err)};if err:=WriteOwned(root,Bundle{Files:[]File{{Path:"A.java",Content:[]byte("a")},{Path:"a.java",Content:[]byte("b")}}},"");err==nil{t.Fatal("case-fold collision accepted")}
}

func TestWriteOwnedRejectsStaleSymlinkSwap(t *testing.T) {
    root:=t.TempDir();first:=Bundle{Files:[]File{{Path:"stale/X.java",Content:[]byte("owned")}}};if err:=WriteOwned(root,first,"");err!=nil{t.Fatal(err)};if err:=os.Remove(filepath.Join(root,"stale/X.java"));err!=nil{t.Fatal(err)};if err:=os.Remove(filepath.Join(root,"stale"));err!=nil{t.Fatal(err)};outside:=t.TempDir();if err:=os.Symlink(outside,filepath.Join(root,"stale"));err!=nil{t.Skip(err)};if err:=WriteOwned(root,Bundle{},"");err==nil{t.Fatal("stale symlink accepted")};if _,err:=os.Stat(filepath.Join(outside,"X.java"));!errors.Is(err,os.ErrNotExist){t.Fatal("outside file touched")}
}
