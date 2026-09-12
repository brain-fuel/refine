package native

import (
    "encoding/json"
    "strings"
    "testing"
)

const unreachableOperationSource=`
type Root = { value :: String }
type Params = { id :: Int }
type Headers = {}
type Body = {}
type Request = { parameters :: Params, headers :: Headers, body :: Body }
type ResponseBody = { id :: Int }
type Response = { headers :: Headers, body :: ResponseBody }
type Context = { request :: Request, response :: Response }
  where it.request.parameters.id == it.response.body.id
    @code "same.id"
    @message "Response id must equal the original request id"
`

func TestOpenAPIOperationExplanationIncludesUnreachableContextAndRequiresLossOptIn(t *testing.T){
    imported,err:=IngestProject(JSONSchema,[]byte(`{"type":"object","required":["value"],"properties":{"value":{"type":"string"}}}`),ProjectOptions{Root:ResourceSelector{TypeName:"Root"}});if err!=nil{t.Fatal(err)};imported,err=imported.WithEditedSource(unreachableOperationSource);if err!=nil{t.Fatal(err)};imported,err=imported.WithMetadata(operationWire());if err!=nil{t.Fatal(err)}
    if _,err=imported.Export(LowerOptions{Mode:Ordinary});problemCode(err)!="native.unrepresentable"{t.Fatalf("ordinary export omitted operation metadata loss gate: %v",err)}
    exported,err:=imported.Export(LowerOptions{Mode:Ordinary,AllowDocumentedLoss:true});if err!=nil{t.Fatal(err)};companion:=exported.CompanionMarkdown();var schema map[string]any;if err=json.Unmarshal([]byte(exported.Resources()[0].Source),&schema);err!=nil{t.Fatal(err)};embedded,_:=schema["description"].(string);for _,want:=range []string{"OpenAPI operation refinement bindings",`"operationId": "get"`,`"method": "GET"`,`"path": "/items/{id}"`,`"status": "200"`,`"requestType": "Request"`,`"responseType": "Response"`,`"contextType": "Context"`,"same.id","Response id must equal the original request id","missing required original-request context as indeterminate"}{if !strings.Contains(companion,want){t.Fatalf("operation explanation omitted %q:\n%s",want,companion)};if !strings.Contains(embedded,want){t.Fatalf("embedded explanation omitted %q",want)}}
    found:=false;for _,loss:=range exported.Losses(){if loss.Owner=="$openapi"&&strings.Contains(loss.Explanation,"does not structurally enforce"){found=true}};if !found{t.Fatalf("operation enforcement loss missing: %+v",exported.Losses())}
    refined,err:=imported.Export(LowerOptions{Mode:Refined});if err!=nil{t.Fatal(err)};if !strings.Contains(refined.Resources()[0].Source,"Response id must equal the original request id"){t.Fatal("refined embedded explanation lost operation context rule")}
}
