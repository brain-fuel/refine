package cli

import (
    "os"
    "path/filepath"
    "strings"
    "testing"

    "goforge.dev/refine/native"
    refineopenapi "goforge.dev/refine/openapi"
)

const cliOperationSource=`
type Root = { value :: Int }
type Params = { id :: Int }
type Headers = {}
type Body = {}
type Request = { parameters :: Params, headers :: Headers, body :: Body }
type ResponseBody = { id :: Int }
type Response = { headers :: Headers, body :: ResponseBody }
type Context = { request :: Request, response :: Response }
  where it.request.parameters.id == it.response.body.id @code "same.id"
`

func cliOperationSchema(method string)*refineopenapi.Schema{
    response:=refineopenapi.ResponseBinding{Status:"200",ResponseType:"Response",ContextType:"Context"};operation:=refineopenapi.OperationBinding{OperationID:"get",Method:method,Path:"/items/{id}",RequestType:"Request",Responses:[]refineopenapi.ResponseBinding{response}};return &refineopenapi.Schema{Version:refineopenapi.SchemaVersion,Operations:[]refineopenapi.OperationBinding{operation}}
}

func cliOperationBundle(t *testing.T,method string)string{
    t.Helper();project,err:=native.IngestProject(native.JSONSchema,[]byte(`{"type":"object","required":["value"],"properties":{"value":{"type":"integer"}}}`),native.ProjectOptions{Root:native.ResourceSelector{TypeName:"Root"}});if err!=nil{t.Fatal(err)};project,err=project.WithEditedSource(cliOperationSource);if err!=nil{t.Fatal(err)};project,err=project.WithMetadata(native.WireMetadata{OpenAPI:cliOperationSchema(method)});if err!=nil{t.Fatal(err)};bundle,err:=project.Bundle();if err!=nil{t.Fatal(err)};return string(bundle)
}

func TestNativeOperationMetadataIsAuthoritativeAndReleaseIdentified(t *testing.T){
    config:=`{"families":{"foo":{"formats":["json-schema"]}}}`;contents:=[]string{cliOperationBundle(t,"GET"),cliOperationBundle(t,"POST")};identities:=[]string{}
    for _,content:=range contents{root:=releaseFixture(t,map[string]string{"schemata/foo/SNAPSHOT.refined.json":content},config);workflow,err:=buildReleaseWorkflow(root,"refine.project.json",nil);if err!=nil{t.Fatal(err)};identities=append(identities,string(workflow.snapshots["foo"].content))}
    if identities[0]==identities[1]{t.Fatal("operation method was omitted from native release identity")}
    external:=`{"families":{"foo":{"formats":["json-schema"],"wire":{"openapi":{"version":"refine.openapi.operations/v1","operations":[]}}}}}`;root:=releaseFixture(t,map[string]string{"schemata/foo/SNAPSHOT.refined.json":contents[0]},external);if _,err:=loadProject(root,"refine.project.json","");err==nil||!strings.Contains(err.Error(),"native bundle owns wire metadata"){t.Fatalf("external-only operation metadata was silently ignored: %v",err)};if _,err:=buildReleaseWorkflow(root,"refine.project.json",nil);err==nil||!strings.Contains(err.Error(),"native bundle owns wire metadata"){t.Fatalf("release silently ignored external operation metadata: %v",err)}
    if _,err:=os.Stat(filepath.Join(root,".refine-generated.json"));!os.IsNotExist(err){t.Fatal("rejected operation metadata wrote outputs")}
}
