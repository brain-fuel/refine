package cli

import (
    "bytes"
    "os"
    "path/filepath"
    "strings"
    "testing"

    "goforge.dev/refine/analysis"
    "goforge.dev/refine/native"
)

func operationReleaseBundle(t *testing.T,extra bool,description string)[]byte{
    t.Helper();paths:=`"/ping":{"post":{"operationId":"ping","requestBody":{"required":true,"content":{"application/json":{"schema":{"type":"integer"}}}},"responses":{"200":{"description":"ok","content":{"application/json":{"schema":{"type":"integer"}}}}}}}`;if extra{paths+=`,"/pong":{"post":{"operationId":"pong","requestBody":{"required":true,"content":{"application/json":{"schema":{"type":"boolean"}}}},"responses":{"204":{"description":"done"}}}}`};source:=`{"openapi":"3.1.2","info":{"title":"Operations","version":"1","description":"`+description+`"},"paths":{`+paths+`}}`;project,err:=native.IngestOpenAPIOperations([]byte(source),native.OpenAPIOperationIngestOptions{EntryResource:"https://example.test/api.json"});if err!=nil{t.Fatal(err)};bundle,err:=project.Bundle();if err!=nil{t.Fatal(err)};return bundle
}

func operationReleaseFixture(t *testing.T,config string,versions map[string][]byte)string{
    t.Helper();root:=t.TempDir();if err:=os.WriteFile(filepath.Join(root,"pom.xml"),[]byte("<project/>"),0600);err!=nil{t.Fatal(err)};if err:=os.WriteFile(filepath.Join(root,"refine.project.json"),[]byte(config),0600);err!=nil{t.Fatal(err)};directory:=filepath.Join(root,"schemata","api");if err:=os.MkdirAll(directory,0755);err!=nil{t.Fatal(err)};for version,bundle:=range versions{if err:=os.WriteFile(filepath.Join(directory,version+".refined.json"),bundle,0600);err!=nil{t.Fatal(err)}};return root
}

func operationReleaseConfig(change,intended,extra string)string{version:="";if intended!=""{version=`,"intended":"`+intended+`"`};return `{"families":{"api":{"formats":["openapi"],"release":{"change":"`+change+`"`+version+extra+`}}}}`}

func TestReleaseOperationsPlansAsymmetricEntrypointsAndExactOverrides(t *testing.T){
    baseline:=operationReleaseBundle(t,false,"baseline");candidate:=operationReleaseBundle(t,true,"candidate");root:=operationReleaseFixture(t,operationReleaseConfig("feature","1.1.0",""),map[string][]byte{"v1.0.0":baseline,"v1.0.1":baseline,"SNAPSHOT":candidate});workflow,err:=buildReleaseWorkflow(root,"refine.project.json",[]string{"api"});if err!=nil{t.Fatal(err)};report:=workflow.reports[0];if len(report.Comparisons)!=4||report.Plan.Ready||report.Plan.Suggested==nil||report.Plan.Suggested.String()!="1.1.0"{t.Fatalf("operation all-baseline plan: %+v",report)};for index:=1;index<len(report.Comparisons);index+=2{if report.Comparisons[index].Logical.Outcome!=analysis.No||report.Comparisons[index].Logical.Code!="analysis.operation_removed"{t.Fatalf("operation addition did not break forward entrypoints: %+v",report.Comparisons[index])}}
    overrides:=``;for index:=0;index<len(report.Comparisons);index+=2{comparison:=report.Comparisons[index];if overrides!=""{overrides+=","};overrides+=`{"baseline":"`+comparison.Baseline+`","baselineSha256":"`+comparison.BaselineSHA256+`","snapshotSha256":"`+comparison.SnapshotSHA256+`","direction":"backward","reason":"reviewed exact native operation and Java surfaces"}`};config:=operationReleaseConfig("feature","1.1.0",`,"overrides":[`+overrides+`]`);writeReleaseConfigWithSchemaAuthority(t,root,config);approved,err:=buildReleaseWorkflow(root,"refine.project.json",[]string{"api"});if err!=nil{t.Fatal(err)};if !approved.reports[0].Plan.Ready{t.Fatalf("exact operation overrides rejected: %+v",approved.reports[0].Plan)}
    snapshot:=filepath.Join(root,"schemata","api","SNAPSHOT.refined.json");authorized,err:=os.ReadFile(snapshot);if err!=nil{t.Fatal(err)};_,policy,err:=native.ReleaseComparisonBundle(authorized);if err!=nil||policy==nil{t.Fatalf("schema policy missing after migration: %v",err)};changed,err:=native.AppendBundleReleasePolicy(append(candidate,'\n'),policy);if err!=nil{t.Fatal(err)};if err=os.WriteFile(snapshot,changed,0600);err!=nil{t.Fatal(err)};stale,err:=buildReleaseWorkflow(root,"refine.project.json",[]string{"api"});if err!=nil{t.Fatal(err)};if stale.reports[0].Plan.Ready||stale.reports[0].Comparisons[0].SnapshotSHA256==report.Comparisons[0].SnapshotSHA256{t.Fatal("changed operation bundle reused a content-bound override")}
}

func TestReleaseOperationsRemovalRequiresCompatibilityBoundary(t *testing.T){
    baseline:=operationReleaseBundle(t,true,"same");candidate:=operationReleaseBundle(t,false,"same");root:=operationReleaseFixture(t,operationReleaseConfig("breaking","2.0.0",""),map[string][]byte{"v1.0.0":baseline,"SNAPSHOT":candidate});workflow,err:=buildReleaseWorkflow(root,"refine.project.json",[]string{"api"});if err!=nil{t.Fatal(err)};report:=workflow.reports[0];if !report.Plan.Ready||report.Plan.Suggested==nil||report.Plan.Suggested.String()!="2.0.0"||report.Comparisons[0].Logical.Outcome!=analysis.No||report.Comparisons[0].Logical.Code!="analysis.operation_removed"{t.Fatalf("operation removal boundary: %+v",report)}
}

func TestReleaseOperationsInitialPromotionAndUnchangedSnapshot(t *testing.T){
    snapshot:=operationReleaseBundle(t,false,"initial");root:=operationReleaseFixture(t,operationReleaseConfig("feature","0.1.0",""),map[string][]byte{"SNAPSHOT":snapshot});var output,errors bytes.Buffer;if status:=releaseCommand([]string{"promote","--root",root,"--json"},&output,&errors);status!=0{t.Fatalf("rootless promotion %d: %s %s",status,&output,&errors)};released,err:=os.ReadFile(filepath.Join(root,"schemata","api","v0.1.0.refined.json"));if err!=nil||!bytes.Equal(released,snapshot){t.Fatal("rootless operation bundle was not promoted verbatim",err)};current,err:=os.ReadFile(filepath.Join(root,"schemata","api","SNAPSHOT.refined.json"));if err!=nil||!bytes.Equal(current,snapshot){t.Fatal("rootless snapshot changed",err)};if err:=os.WriteFile(filepath.Join(root,"refine.project.json"),[]byte(operationReleaseConfig("none","","")),0600);err!=nil{t.Fatal(err)};workflow,err:=buildReleaseWorkflow(root,"refine.project.json",[]string{"api"});if err!=nil||!workflow.reports[0].Plan.NoPendingVersion||!workflow.reports[0].Plan.Ready{t.Fatalf("unchanged operation snapshot remained pending: %v %+v",err,workflow.reports[0].Plan)}
}

func TestReleaseOperationsDocumentationClaimRetainsAllEntrypointsAndResources(t *testing.T){
    baseline:=operationReleaseBundle(t,false,"old documentation");candidate:=operationReleaseBundle(t,false,"new documentation");root:=operationReleaseFixture(t,operationReleaseConfig("documentation","1.0.1",""),map[string][]byte{"v1.0.0":baseline,"SNAPSHOT":candidate});workflow,err:=buildReleaseWorkflow(root,"refine.project.json",[]string{"api"});if err!=nil{t.Fatal(err)};report:=workflow.reports[0];if report.Documentation==nil||report.Documentation.Outcome!=analysis.Unknown||report.Plan.Ready||report.Plan.Suggested!=nil{t.Fatalf("native operation resource documentation was overclassified: %+v",report)};if !strings.Contains(strings.Join(report.Documentation.Reasons," "),"native resource changes"){t.Fatalf("resource uncertainty absent: %+v",report.Documentation)}
}

func TestReleaseInitialPayloadValidatesSelectedRoot(t *testing.T){
    files:=map[string]string{"schemata/foo/SNAPSHOT.refine":"type First = Int\ntype Second = Int\n"};for _,config:=range []string{`{"families":{"foo":{"release":{"change":"feature","intended":"0.1.0"}}}}`,`{"families":{"foo":{"root":"Missing","release":{"change":"feature","intended":"0.1.0"}}}}`}{root:=releaseFixture(t,files,config);if _,err:=buildReleaseWorkflow(root,"refine.project.json",[]string{"foo"});err==nil{t.Fatalf("initial payload without one valid selected root was accepted: %s",config)}}
}
