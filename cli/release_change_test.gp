package cli

import (
    "encoding/json"
    "os"
    "path/filepath"
    "strings"
    "testing"

    "goforge.dev/refine/analysis"
    "goforge.dev/refine/native"
)

func TestReleaseDocumentationClaimRetainsContractChanges(t *testing.T){
    cases:=[]struct{name,old,next string;want analysis.Outcome}{
        {"comments","type Thing = Int\n","-- clearer documentation\ntype Thing=Int\n",analysis.Yes},
        {"widening","type Thing = Int where it > 0\n","type Thing = Int where it >= 0\n",analysis.No},
        {"message","type Thing = Int where it > 0 @message \"positive\"\n","type Thing = Int where it > 0 @message \"SECRET_NEW_MESSAGE\"\n",analysis.No},
        {"function","allowed :: Int -> Bool\nallowed n = n > 0\ntype Thing = Int where allowed it\n","allowed :: Int -> Bool\nallowed n = n >= 0\ntype Thing = Int where allowed it\n",analysis.No},
        {"package","package first.models\ntype Thing = Int\n","package second.models\ntype Thing = Int\n",analysis.No},
    }
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){root:=releaseFixture(t,map[string]string{"schemata/foo/v1.0.0.refine":tc.old,"schemata/foo/SNAPSHOT.refine":tc.next},releaseConfig("documentation","1.0.1",""));workflow,err:=buildReleaseWorkflow(root,"refine.project.json",nil);if err!=nil{t.Fatal(err)};report:=workflow.reports[0];if report.Documentation==nil||report.Documentation.Outcome!=tc.want{t.Fatalf("wrong classification: %+v",report.Documentation)};encoded,_:=json.Marshal(report.Documentation);if strings.Contains(string(encoded),"SECRET_NEW_MESSAGE"){t.Fatal("classification leaked diagnostic message")};comparison:=report.Comparisons[0];override:=`,"overrides":[{"baseline":"1.0.0","baselineSha256":"`+comparison.BaselineSHA256+`","snapshotSha256":"`+comparison.SnapshotSHA256+`","direction":"backward","reason":"all compatibility dimensions reviewed"}]`;if err=os.WriteFile(filepath.Join(root,"refine.project.json"),[]byte(releaseConfig("documentation","1.0.1",override)),0600);err!=nil{t.Fatal(err)};workflow,err=buildReleaseWorkflow(root,"refine.project.json",nil);if err!=nil{t.Fatal(err)};plan:=workflow.reports[0].Plan;if tc.want==analysis.Yes{if !plan.Ready{t.Fatalf("comment-only classification rejected: %+v",plan)}}else{if plan.Ready||plan.Suggested!=nil||plan.Accepted!=nil{t.Fatalf("compatibility override authorized false documentation claim: %+v",plan)};found:=false;for _,issue:=range plan.Issues{found=found||issue.Code=="release.documentation_unproven"};if !found{t.Fatal("missing explicit classification failure")}}})}
}

func TestReleaseDocumentationClaimIncludesReachableDependencyBodies(t *testing.T){
    files:=map[string]string{"schemata/dep/v1.0.0.refine":"type Dependency = Int where it > 0\n","schemata/dep/v1.1.0.refine":"type Dependency = Int where it >= 0\n","schemata/foo/v1.0.0.refine":"import \"../dep/v1.0.0.refine\"\ntype Thing = Dependency\n","schemata/foo/SNAPSHOT.refine":"import \"../dep/v1.1.0.refine\"\ntype Thing = Dependency\n"};root:=releaseFixture(t,files,releaseConfig("documentation","1.0.1",""));workflow,err:=buildReleaseWorkflow(root,"refine.project.json",[]string{"foo"});if err!=nil{t.Fatal(err)};if workflow.reports[0].Documentation.Outcome!=analysis.No||workflow.reports[0].Plan.Ready{t.Fatal("dependency body hidden by an unchanged local alias")}
}

func TestReleaseDocumentationClaimBoundsNativeMetadataAndOpaqueResources(t *testing.T){
    bundle:=func(schema string)string{project,err:=native.IngestProject(native.JSONSchema,[]byte(schema),native.ProjectOptions{ResourceID:"https://example.test/thing.json",Root:native.ResourceSelector{TypeName:"Thing"}});if err!=nil{t.Fatal(err)};raw,err:=project.Bundle();if err!=nil{t.Fatal(err)};return string(raw)}
    for _,tc:=range []struct{name,old,next string;want analysis.Outcome}{
        {"publication",nativeBundleFixture(t,"published.one"),nativeBundleFixture(t,"published.two"),analysis.No},
        {"opaque-docs",bundle(`{"type":"string","description":"old"}`),bundle(`{"type":"string","description":"new"}`),analysis.Unknown},
    }{t.Run(tc.name,func(t *testing.T){root:=releaseFixture(t,map[string]string{"schemata/foo/v1.0.0.refined.json":tc.old,"schemata/foo/SNAPSHOT.refined.json":tc.next},releaseConfig("documentation","1.0.1",""));workflow,err:=buildReleaseWorkflow(root,"refine.project.json",nil);if err!=nil{t.Fatal(err)};report:=workflow.reports[0];if report.Documentation==nil||report.Documentation.Outcome!=tc.want||report.Plan.Ready{t.Fatalf("native boundary classification: %+v",report)}})}
}

func TestReleaseDocumentationClaimRetainsNativeSourceGraphWithOverrides(t *testing.T){
    base,err:=native.IngestProject(native.JSONSchema,[]byte(`{"type":"string"}`),native.ProjectOptions{Root:native.ResourceSelector{TypeName:"Thing"}});if err!=nil{t.Fatal(err)}
    bundle:=func(dependencyName,source string)string{project,err:=base.WithEditedSources("models/main.refine",map[string]string{"models/main.refine":"import \""+dependencyName+"\"\ntype Thing = Dependency\n","models/"+dependencyName:source});if err!=nil{t.Fatal(err)};encoded,err:=project.Bundle();if err!=nil{t.Fatal(err)};return string(encoded)}
    original:=bundle("common.refine","package original.models\ntype Dependency = String\n")
    for _,tc:=range []struct{name,dependency,source string;want analysis.Outcome}{
        {"package","common.refine","package changed.models\ntype Dependency = String\n",analysis.No},
        {"identity","renamed.refine","package original.models\ntype Dependency = String\n",analysis.No},
        {"comments","common.refine","-- improved docs\npackage original.models\ntype Dependency = String\n",analysis.Yes},
    }{t.Run(tc.name,func(t *testing.T){root:=releaseFixture(t,map[string]string{"schemata/foo/v1.0.0.refined.json":original,"schemata/foo/SNAPSHOT.refined.json":bundle(tc.dependency,tc.source)},releaseConfig("documentation","1.0.1",""));workflow,err:=buildReleaseWorkflow(root,"refine.project.json",nil);if err!=nil{t.Fatal(err)};comparison:=workflow.reports[0].Comparisons[0];override:=`,"overrides":[{"baseline":"1.0.0","baselineSha256":"`+comparison.BaselineSHA256+`","snapshotSha256":"`+comparison.SnapshotSHA256+`","direction":"backward","reason":"compatibility reviewed"}]`;if err=os.WriteFile(filepath.Join(root,"refine.project.json"),[]byte(releaseConfig("documentation","1.0.1",override)),0600);err!=nil{t.Fatal(err)};workflow,err=buildReleaseWorkflow(root,"refine.project.json",nil);if err!=nil{t.Fatal(err)};report:=workflow.reports[0];if report.Documentation.Outcome!=tc.want||report.Plan.Ready!=(tc.want==analysis.Yes){t.Fatalf("native graph lost under flattened syntax: %+v",report)}})}
}
