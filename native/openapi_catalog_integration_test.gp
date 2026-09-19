package native

import (
    "strings"
    "testing"

    "goforge.dev/refine/validation"
)

const catalogIntegratedAPI=`{"openapi":"3.1.2","info":{"title":"Catalog integration","version":"1"},"paths":{},"components":{"schemas":{"Root":{"$ref":"https://schemas.test/model#value"}}}}`
const catalogIntegratedModel=`{"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://schemas.test/model","$anchor":"value","type":"object","properties":{"amount":{"type":"integer","minimum":3}},"required":["amount"],"additionalProperties":false}`

func TestOpenAPICatalogRootedIngestionAndRuntimeUsePhysicalValidationView(t *testing.T){
    entry:="https://example.test/api.json";external:="https://example.test/model.json";resources:=[]Resource{{URI:entry,Source:catalogIntegratedAPI},{URI:external,Source:catalogIntegratedModel}}
    project,err:=IngestProjectResources(OpenAPI,resources,ProjectOptions{Root:ResourceSelector{Resource:entry,Pointer:"/components/schemas/Root",TypeName:"Root"}});if err!=nil{t.Fatal(err)};if !strings.Contains(project.EditableSource(),"amount :: Int"){t.Fatalf("catalog projection lost external structure:\n%s",project.EditableSource())};if project.Resources()[0]!=resources[0]||project.Resources()[1]!=resources[1]{t.Fatal("validation view replaced exact project resources")}
    if err:=project.ValidateJSON([]byte(`{"amount":3}`));err!=nil{t.Fatal(err)};if err:=project.ValidateJSON([]byte(`{"amount":2}`));problemCode(err)!="native.payload"{t.Fatalf("external canonical minimum was not enforced: %v",err)};bundle,err:=project.Bundle();if err!=nil{t.Fatal(err)};reloaded,err:=ParseBundle(bundle);if err!=nil{t.Fatal(err)};if err:=reloaded.ValidateJSON([]byte(`{"amount":2}`));problemCode(err)!="native.payload"{t.Fatalf("bundle reload did not rebuild canonical validation authority: %v",err)}
    again,err:=IngestProject(OpenAPI,[]byte(`{"openapi":"3.1.2","info":{"title":"Single","version":"1"},"paths":{},"components":{"schemas":{"Value":{"$id":"https://schemas.test/value","$anchor":"v","type":"string","minLength":2},"Root":{"$ref":"https://schemas.test/value#v"}}}}`),ProjectOptions{ResourceID:entry,Root:ResourceSelector{TypeName:"Root"}});if err!=nil{t.Fatal(err)};if err:=again.ValidateJSON([]byte(`"ok"`));err!=nil{t.Fatal(err)};if err:=again.ValidateJSON([]byte(`"x"`));problemCode(err)!="native.payload"{t.Fatalf("single-resource catalog route lost canonical anchor: %v",err)}
}

func TestOpenAPICatalogStructuralValidationRetainsExternalDefaults(t *testing.T){
    entry:="https://example.test/api.json";external:="https://example.test/model.json";bad:=strings.Replace(catalogIntegratedModel,`"type":"object"`,`"type":"object","default":7`,1)
    if project,err:=IngestProjectResources(OpenAPI,[]Resource{{URI:entry,Source:catalogIntegratedAPI},{URI:external,Source:bad}},ProjectOptions{Root:ResourceSelector{Resource:entry,Pointer:"/components/schemas/Root",TypeName:"Root"}});err==nil||project!=nil||!strings.Contains(strings.ToLower(err.Error()),"default"){t.Fatalf("kin structural validation lost referenced default checking: %v",err)}
}

func TestOpenAPICatalogOperationBoundaryUsesPhysicalValidationView(t *testing.T){
    entry:="https://example.test/operations.json";external:="https://example.test/body.json";api:=`{"openapi":"3.1.2","info":{"title":"Operations","version":"1"},"paths":{"/items":{"post":{"operationId":"createItem","requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"https://schemas.test/body#input"}}}},"responses":{"204":{"description":"done"}}}}}}`;body:=`{"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://schemas.test/body","$anchor":"input","type":"object","properties":{"amount":{"type":"integer","minimum":3}},"required":["amount"],"additionalProperties":false}`
    project,err:=IngestOpenAPIOperationResources([]Resource{{URI:entry,Source:api},{URI:external,Source:body}},OpenAPIOperationIngestOptions{EntryResource:entry});if err!=nil{t.Fatal(err)};request:=OpenAPIRequestJSON{Body:&OpenAPIMediaJSON{MediaType:"application/json",Value:[]byte(`{"amount":3}`)}};token,report,err:=project.DecodeAndValidateOpenAPIRequest("createItem",request,OpenAPILimits{},validation.Limits{});if err!=nil||token==nil||validation.StateName(report.State())!="valid"{t.Fatalf("valid external operation body failed: %v %+v",err,report)};request.Body.Value=[]byte(`{"amount":2}`);if _,_,err:=project.DecodeAndValidateOpenAPIRequest("createItem",request,OpenAPILimits{},validation.Limits{});problemCode(err)!="native.payload"{t.Fatalf("operation compiler lost external minimum: %v",err)}
}

func TestOpenAPIValidationViewRejectsTrustedDialectShadowing(t *testing.T){
    entry:="https://example.test/api.json";document:=Resource{URI:entry,Source:`{"openapi":"3.1.2","info":{"title":"Dialect authority","version":"1"},"paths":{},"components":{"schemas":{"Root":{"type":"string"}}}}`}
    cases:=[]struct{name string;resource Resource}{{"physical",Resource{URI:openAPIBaseDialect,Source:`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"string"}`}},{"logical alias",Resource{URI:"https://example.test/schema.json",Source:`{"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://spec.openapis.org/oas/3.1/dialect/base#","type":"string"}`}}}
    for _,test:=range cases{t.Run(test.name,func(t *testing.T){view,err:=NewOpenAPIValidationView([]Resource{document,test.resource},entry);if err==nil||view!=nil||problemCode(err)!="native.enforcement"||!strings.Contains(err.Error(),"trusted base dialect"){t.Fatalf("reserved dialect identity was accepted: view=%v err=%v",view,err)}})}
}
