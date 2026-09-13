package cli

import (
    "bytes"
    "encoding/json"
    "os"
    "path/filepath"
    "strings"
    "testing"

    "goforge.dev/refine/language"
    "goforge.dev/refine/native"
)

// writeReleaseConfigWithSchemaAuthority is test migration plumbing: legacy
// config records remain present, but identical authority is written into each
// SNAPSHOT schema before the workflow is rebuilt.
func writeReleaseConfigWithSchemaAuthority(t *testing.T,root,text string){
    t.Helper();if err:=os.WriteFile(filepath.Join(root,"refine.project.json"),[]byte(text),0600);err!=nil{t.Fatal(err)};var config projectConfig;if err:=json.Unmarshal([]byte(text),&config);err!=nil{t.Fatal(err)}
    for family,settings:=range config.Families{if len(settings.Release.Overrides)==0&&len(settings.Release.BreakingFixes)==0{continue};policy:=&language.ReleasePolicy{Version:1};for _,item:=range settings.Release.Overrides{policy.Overrides=append(policy.Overrides,language.CompatibilityApproval{ReleaseComparison:language.ReleaseComparison{Baseline:item.Baseline,BaselineSHA256:item.BaselineSHA256,SnapshotSHA256:item.SnapshotSHA256,Direction:item.Direction},Reason:item.Reason})};for _,item:=range settings.Release.BreakingFixes{policy.BreakingFixes=append(policy.BreakingFixes,language.BreakingFixApproval{ReleaseComparison:language.ReleaseComparison{Baseline:item.Baseline,BaselineSHA256:item.BaselineSHA256,SnapshotSHA256:item.SnapshotSHA256,Direction:item.Direction},Justification:item.Justification})}
        refinePath:=filepath.Join(root,"schemata",family,"SNAPSHOT.refine");if raw,err:=os.ReadFile(refinePath);err==nil{base,_,_,err:=language.SplitReleasePolicyFooter(string(raw));if err!=nil{t.Fatal(err)};updated,err:=language.AppendReleasePolicyFooter(base,policy);if err!=nil{t.Fatal(err)};if err=os.WriteFile(refinePath,[]byte(updated),0600);err!=nil{t.Fatal(err)};continue}
        nativePath:=filepath.Join(root,"schemata",family,"SNAPSHOT.refined.json");raw,err:=os.ReadFile(nativePath);if err!=nil{t.Fatal(err)};base,_,err:=native.ReleaseComparisonBundle(raw);if err!=nil{t.Fatal(err)};updated,err:=native.AppendBundleReleasePolicy(base,policy);if err!=nil{t.Fatal(err)};_,checked,err:=native.ReleaseComparisonBundle(updated);if err!=nil||checked==nil||len(checked.Overrides)!=len(policy.Overrides)||len(checked.BreakingFixes)!=len(policy.BreakingFixes){t.Fatalf("native schema policy write mismatch: %v %+v",err,checked)};if err=os.WriteFile(nativePath,updated,0600);err!=nil{t.Fatal(err)}
    }
}

func TestReleasePolicyRequiresSchemaAuthorityAndExcludesOnlyCarrier(t *testing.T){
    root:=releaseFixture(t,map[string]string{"schemata/foo/v1.0.0.refine":"type Thing = Int\n","schemata/foo/SNAPSHOT.refine":"-- next\ntype Thing = Int\n"},releaseConfig("documentation","1.0.1",""));workflow,err:=buildReleaseWorkflow(root,"refine.project.json",nil);if err!=nil{t.Fatal(err)};comparison:=workflow.reports[0].Comparisons[0];record:=`,"overrides":[{"baseline":"1.0.0","baselineSha256":"`+comparison.BaselineSHA256+`","snapshotSha256":"`+comparison.SnapshotSHA256+`","direction":"backward","reason":"reviewed exact native and Java surfaces"}]`;legacy:=releaseConfig("documentation","1.0.1",record)
    if err=os.WriteFile(filepath.Join(root,"refine.project.json"),[]byte(legacy),0600);err!=nil{t.Fatal(err)};if _,err=buildReleaseWorkflow(root,"refine.project.json",nil);err==nil||!strings.Contains(err.Error(),"release.policy_migration"){t.Fatalf("config-only approval remained authority: %v",err)}
    before,err:=os.ReadFile(filepath.Join(root,"schemata/foo/SNAPSHOT.refine"));if err!=nil{t.Fatal(err)};writeReleaseConfigWithSchemaAuthority(t,root,legacy);approved,err:=buildReleaseWorkflow(root,"refine.project.json",nil);if err!=nil||!approved.reports[0].Plan.Ready{t.Fatalf("schema authority rejected: %v %+v",err,approved.reports[0].Plan)};after,err:=os.ReadFile(filepath.Join(root,"schemata/foo/SNAPSHOT.refine"));if err!=nil{t.Fatal(err)};base,_,present,err:=language.SplitReleasePolicyFooter(string(after));if err!=nil||!present||!bytes.Equal([]byte(base),before){t.Fatalf("release carrier masked non-policy bytes: %v",err)};if approved.reports[0].Comparisons[0].SnapshotSHA256!=comparison.SnapshotSHA256{t.Fatal("schema-carried policy changed its own comparison identity")}
    if err=os.WriteFile(filepath.Join(root,"refine.project.json"),[]byte(releaseConfig("documentation","1.0.1","")),0600);err!=nil{t.Fatal(err)};schemaOnly,err:=buildReleaseWorkflow(root,"refine.project.json",nil);if err!=nil||!schemaOnly.reports[0].Plan.Ready{t.Fatalf("schema-only authority rejected: %v %+v",err,schemaOnly.reports[0].Plan)}
    conflict:=strings.Replace(legacy,"reviewed exact native and Java surfaces","different config reason",1);if err=os.WriteFile(filepath.Join(root,"refine.project.json"),[]byte(conflict),0600);err!=nil{t.Fatal(err)};if _,err=buildReleaseWorkflow(root,"refine.project.json",nil);err==nil||!strings.Contains(err.Error(),"conflicts between SNAPSHOT schema"){t.Fatalf("conflicting duplicate policy accepted: %v",err)}
}
