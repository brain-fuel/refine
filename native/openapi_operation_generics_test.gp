package native

import (
    "strings"
    "testing"

    refineopenapi "goforge.dev/refine/openapi"
    "goforge.dev/refine/validation"
)

const genericOperationDocument=`{
  "openapi":"3.0.4","info":{"title":"Generic paths","version":"1"},
  "paths":{"/values":{"post":{"operationId":"putValue",
    "parameters":[{"in":"query","name":"payload","required":true,"schema":{"type":"integer"}}],
    "requestBody":{"required":true,"content":{"application/json":{"schema":{"type":"array","items":{"$ref":"#/components/schemas/Directional"}}}}},
    "responses":{"200":{"description":"ok","headers":{"payload":{"schema":{"type":"integer"}}},"content":{"application/json":{"schema":{"type":"array","items":{"$ref":"#/components/schemas/Directional"}}}}}}
  }}},
  "components":{"schemas":{
    "Root":{"type":"object"},
    "Directional":{"type":"object","required":["server","client"],"properties":{"server":{"type":"integer","readOnly":true},"client":{"type":"integer","writeOnly":true}}}
  }}
}`

const genericOperationSource=`
type Holder a = { value :: a }
type Envelope a = { server :: Maybe a, client :: Maybe a }
type Request a = { parameters :: { payload :: Holder a }, headers :: {}, body :: Nullable [Envelope a] }
type Response a = { headers :: { payload :: Maybe (Holder a) }, body :: Maybe (Nullable [Envelope a]) }
type RequestInt = Request Int
type ResponseInt = Response Int
type Root = {}
`

func genericOperationProject(t *testing.T)*Project{t.Helper();project,err:=IngestProject(OpenAPI,[]byte(genericOperationDocument),ProjectOptions{ResourceID:"https://example.test/generic-operation.json",Root:ResourceSelector{Pointer:"/components/schemas/Root",TypeName:"Root"}});if err!=nil{t.Fatal(err)};project,err=project.WithEditedSource(genericOperationSource);if err!=nil{t.Fatal(err)};operation:=refineopenapi.OperationBinding{OperationID:"putValue",Method:"POST",Path:"/values",RequestType:"RequestInt",Responses:[]refineopenapi.ResponseBinding{{Status:"200",ResponseType:"ResponseInt"}}};nativeBinding:=refineopenapi.NativeOperationBinding{OperationID:"putValue",Parameters:[]refineopenapi.NativeParameterBinding{{In:"query",Name:"payload",FieldPath:[]string{"payload","value"}}},RequestBody:&refineopenapi.NativeMediaBinding{MediaType:"application/json"},Responses:[]refineopenapi.NativeResponseBinding{{Status:"200",Headers:[]refineopenapi.NativeHeaderBinding{{Name:"payload",FieldPath:[]string{"payload","value"}}},Body:&refineopenapi.NativeMediaBinding{MediaType:"application/json"}}}};metadata:=WireMetadata{OpenAPI:&refineopenapi.Schema{Version:refineopenapi.SchemaVersion,Operations:[]refineopenapi.OperationBinding{operation},Native:&refineopenapi.NativeBindings{Version:refineopenapi.NativeBindingsVersion,Operations:[]refineopenapi.NativeOperationBinding{nativeBinding}}}};project,err=project.WithMetadata(metadata);if err!=nil{t.Fatal(err)};return project}

func TestOpenAPIOperationFieldPathsSpecializeGenericOptionalRecords(t *testing.T){project:=genericOperationProject(t);catalog,err:=project.OpenAPIOperationIndex();if err!=nil{t.Fatal(err)};if len(catalog.Operations)!=1{t.Fatal("operation index missing")};operation:=catalog.Operations[0];parameterType:="";for _,part:=range operation.RequestParts{if part.In=="query"{parameterType=part.TypeExpression}};headerType:="";for _,response:=range operation.Responses{for _,part:=range response.Parts{if part.In=="header"{headerType=part.TypeExpression}}};if parameterType!="Int"||headerType!="Int"{t.Fatalf("generic field paths did not specialize to Int: parameter=%s header=%s",parameterType,headerType)}
    request:=OpenAPIRequestJSON{Parameters:[]OpenAPIParameterJSON{{In:"query",Name:"payload",Value:[]byte(`3`)}},Body:&OpenAPIMediaJSON{MediaType:"application/json",Value:[]byte(`[{"client":1}]`)}};token,report,err:=project.DecodeAndValidateOpenAPIRequest("putValue",request,OpenAPILimits{},validation.Limits{});if err!=nil||token==nil||validation.StateName(report.State())!="valid"{t.Fatalf("generic nested request mapping failed: %v %+v",err,report)}
    response:=OpenAPIResponseJSON{Status:"200",Body:&OpenAPIMediaJSON{MediaType:"application/json",Value:[]byte(`[{"server":2}]`)}};_,report,err=project.DecodeAndValidateOpenAPIResponse("putValue",response,nil,OpenAPILimits{},validation.Limits{});if err!=nil||validation.StateName(report.State())!="valid"{t.Fatalf("absent optional generic response header failed: %v %+v",err,report)};response.Headers=[]OpenAPIHeaderJSON{{Name:"PAYLOAD",Value:[]byte(`4`)}};if _,report,err=project.DecodeAndValidateOpenAPIResponse("putValue",response,nil,OpenAPILimits{},validation.Limits{});err!=nil||validation.StateName(report.State())!="valid"{t.Fatalf("present nested generic response header failed: %v %+v",err,report)}}

func TestOpenAPIDirectionalAuditTraversesNullableGenericLists(t *testing.T){project:=genericOperationProject(t);cases:=[]struct{name,old,new string}{{"request read-only","server :: Maybe a","server :: a"},{"response write-only","client :: Maybe a","client :: a"}};for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){edited:=strings.Replace(genericOperationSource,tc.old,tc.new,1);changed,err:=project.WithEditedSource(edited);if changed!=nil||problemCode(err)!="native.enforcement"||!strings.Contains(err.Error(),"must be Maybe"){t.Fatalf("mandatory directional field under Nullable/list/generic wrappers was accepted: %v",err)}})}}
