package cli

import (
    "bytes"
    "os"
    "path/filepath"
    "strings"
    "testing"

    "goforge.dev/refine/native"
)

func rootlessBundleBytes(t *testing.T)[]byte{
    t.Helper();source:=[]byte(`{"openapi":"3.1.2","info":{"title":"Rootless","version":"1"},"paths":{"/ping":{"post":{"operationId":"ping","requestBody":{"required":true,"content":{"application/json":{"schema":{"type":"integer"}}}},"responses":{"200":{"description":"ok","content":{"application/json":{"schema":{"type":"string"}}}}}}}}}`);project,err:=native.IngestOpenAPIOperations(source,native.OpenAPIOperationIngestOptions{EntryResource:"https://example.test/api.json"});if err!=nil{t.Fatal(err)};bundle,err:=project.Bundle();if err!=nil{t.Fatal(err)};return bundle
}

func rootlessProjectFixture(t *testing.T,config string,versions ...string)string{
    t.Helper();root:=t.TempDir();if err:=os.WriteFile(filepath.Join(root,"pom.xml"),[]byte("<project/>"),0600);err!=nil{t.Fatal(err)};if err:=os.WriteFile(filepath.Join(root,"refine.project.json"),[]byte(config),0600);err!=nil{t.Fatal(err)};for _,version:=range versions{name:=filepath.Join(root,"schemata","api",version+".refined.json");if err:=os.MkdirAll(filepath.Dir(name),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(name,rootlessBundleBytes(t),0600);err!=nil{t.Fatal(err)}};return root
}

func TestProjectCLIGeneratesRootlessOpenAPIOperationBundle(t *testing.T){
    config:=`{"families":{"api":{"formats":["openapi"]}}}`;root:=rootlessProjectFixture(t,config,"SNAPSHOT");input,err:=loadProject(root,"refine.project.json","");if err!=nil||len(input.Contracts)!=1{t.Fatalf("rootless bundle discovery: %+v %v",input,err)};contract:=input.Contracts[0];if contract.NativeProject==nil||contract.NativeProject.Target().Kind!=native.OpenAPIOperationsProject||contract.RootType!=""{t.Fatalf("rootless target changed: %+v",contract)}
    var output,errors bytes.Buffer;if status:=Run([]string{"project","generate","--root",root},nil,&output,&errors);status!=0{t.Fatalf("rootless generation %d: %s %s",status,&output,&errors)};base:=filepath.Join(root,"target","generated-resources","refine","refine","api","snapshot");for _,name:=range []string{"contract.refined.json","contract.refine","explanation.md","ordinary-openapi.json","refined-openapi.json","ordinary-openapi-resources.json"}{if _,err:=os.Stat(filepath.Join(base,name));err!=nil{t.Fatalf("missing %s: %v",name,err)}};if _,err:=os.Stat(filepath.Join(root,"target","generated-test-sources","refine","api","snapshot","ContractGeneratedProperties.java"));err!=nil{t.Fatal("rootless property suite missing",err)}
}

func TestProjectCLIRootlessTargetConfigurationAndReleaseComparisonFailClosed(t *testing.T){
    for _,config:=range []string{`{"families":{"api":{"root":"Fake","formats":["openapi"]}}}`,`{"families":{"api":{}}}`,`{"families":{"api":{"formats":["json-schema"]}}}`}{root:=rootlessProjectFixture(t,config,"SNAPSHOT");if _,err:=loadProject(root,"refine.project.json","");err==nil{t.Fatalf("invalid rootless configuration accepted: %s",config)}}
    root:=rootlessProjectFixture(t,`{"families":{"api":{"formats":["openapi"],"release":{"change":"none"}}}}`,"v1.0.0","SNAPSHOT");_,err:=buildReleaseWorkflow(root,"refine.project.json",[]string{"api"});if err==nil||!strings.Contains(err.Error(),"multi-entrypoint release compatibility is unknown"){t.Fatalf("rootless release invented a payload comparison: %v",err)}
}
