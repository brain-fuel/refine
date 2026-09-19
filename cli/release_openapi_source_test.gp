package cli

import (
    "os"
    "path/filepath"
    "strings"
    "testing"

    "goforge.dev/refine/analysis"
    "goforge.dev/refine/native"
)

func authoredOperationSource(extra bool)string{
    block:=cliAuthoredOpenAPI;if extra{block=strings.TrimSuffix(block,"}\n") + `  operation pong "POST" "/pong/{id}" {
    request Request {
      parameter path "id" at parameters.id required
      body "application/json" at body optional
    }
    response "200" Response "done" {
      body "application/json" at body optional
    }
  }
}
`};return cliAuthoredOpenAPITypes+block
}

func TestReleasePlansAuthoredOpenAPIOperationsFromExactSource(t *testing.T){
    files:=map[string]string{"schemata/api/v1.0.0.refine":authoredOperationSource(false),"schemata/api/SNAPSHOT.refine":authoredOperationSource(true)};implicit:=`{"families":{"api":{"release":{"change":"feature","intended":"1.1.0"}}}}`;root:=releaseFixture(t,files,implicit);workflow,err:=buildReleaseWorkflow(root,"refine.project.json",[]string{"api"});if err!=nil{t.Fatal(err)};entry:=workflow.snapshots["api"];report:=workflow.reports[0];if entry.kind!=refineSchema||!releaseOperationsEntry(entry)||entry.nativeProject.Root()!=(native.ResourceSelector{})||len(report.Comparisons)!=2{t.Fatalf("authored operation release used a payload or native-bundle identity: %+v %+v",entry,report)};if report.Comparisons[1].Logical.Outcome!=analysis.No||report.Comparisons[1].Logical.Code!="analysis.operation_removed"{t.Fatalf("authored operation inventory was not compared: %+v",report.Comparisons[1])};identity:=report.Comparisons[0].SnapshotSHA256
    explicit:=`{"families":{"api":{"formats":["openapi"],"release":{"change":"feature","intended":"1.1.0"}}}}`;if err=os.WriteFile(filepath.Join(root,"refine.project.json"),[]byte(explicit),0600);err!=nil{t.Fatal(err)};again,err:=buildReleaseWorkflow(root,"refine.project.json",[]string{"api"});if err!=nil{t.Fatal(err)};if again.reports[0].Comparisons[0].SnapshotSHA256!=identity{t.Fatal("implicit and explicit authored OpenAPI formats produced different effective identities")}
}

func TestReleasePromotesAuthoredOpenAPIRefineImportsExactly(t *testing.T){
    api:="import \"../types/SNAPSHOT.refine\"\n"+strings.Replace(cliAuthoredOpenAPITypes,"Int}","Shared}",1)+cliAuthoredOpenAPI;files:=map[string]string{"schemata/types/SNAPSHOT.refine":"type Shared = Int\n","schemata/api/SNAPSHOT.refine":api};config:=`{"families":{"api":{"noCodegen":["SNAPSHOT","v0.1.0"],"release":{"change":"feature","intended":"0.1.0"}},"types":{"root":"Shared","formats":["json-schema"],"noCodegen":["SNAPSHOT","v0.1.0"],"release":{"change":"feature","intended":"0.1.0"}}}}`;root:=releaseFixture(t,files,config);workflow,err:=buildReleaseWorkflow(root,"refine.project.json",nil);if err!=nil{t.Fatal(err)};if len(workflow.reports)!=2||!workflow.plans["api"].Ready||!workflow.plans["types"].Ready{t.Fatalf("initial authored API batch not ready: %+v",workflow.reports)};if len(workflow.reports[0].Comparisons)!=0||len(workflow.reports[1].Comparisons)!=0{t.Fatal("initial release unexpectedly fabricated comparisons")};if _,err=promoteReleaseWorkflow(workflow);err!=nil{t.Fatal(err)};released,err:=os.ReadFile(filepath.Join(root,"schemata","api","v0.1.0.refine"));if err!=nil{t.Fatal(err)};text:=string(released);if !strings.Contains(text,`import "../types/v0.1.0.refine"`)||!strings.Contains(text,`openapi "3.2.1"`){t.Fatalf("authored API release lost exact pin or declaration:\n%s",text)};if _,err=os.Stat(filepath.Join(root,"schemata","api","v0.1.0.refined.json"));!os.IsNotExist(err){t.Fatalf("authored source was promoted as a native bundle: %v",err)}
}
