package native

import (
    "strings"
    "testing"

    "goforge.dev/refine/validation"
)

const catalogAnnotationEntry=`{
  "openapi":"3.1.2","info":{"title":"Catalog annotations","version":"1"},
  "paths":{"/values":{"post":{"operationId":"putValue","requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"https://schemas.test/body#payload"}}}},"responses":{"204":{"description":"ok"}}}}},
  "components":{"schemas":{"Root":{"$id":"https://schemas.test/root","type":"object","required":["value"],"properties":{"value":{"$ref":"#/$defs/Value"}},"$defs":{"Value":{"type":"integer"}},"x-refine":{"source":"type Root = {value :: Int} where it.value > 0 @code \"root.positive\"","root":"Root"}}}}
}`

const catalogAnnotationBody=`{
  "$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://schemas.test/body","$anchor":"payload","type":"integer",
  "x-refine":{"source":"type BodyPositive = Int where it > 0 @code \"body.positive\"","root":"BodyPositive"}
}`

func catalogAnnotationProject(t *testing.T)*Project{t.Helper();resources:=[]Resource{{URI:"https://physical.test/api.json",Source:catalogAnnotationEntry},{URI:"https://physical.test/body.json",Source:catalogAnnotationBody}};project,err:=IngestProjectResources(OpenAPI,resources,ProjectOptions{ResourceID:"https://physical.test/api.json",Root:ResourceSelector{Resource:"https://physical.test/api.json",Pointer:"/components/schemas/Root",TypeName:"Root"}});if err!=nil{t.Fatal(err)};return project}

func TestOpenAPICatalogAnnotationsComposeRootAndDerivedLogicalOperationAcrossExportBundle(t *testing.T){
    base:=catalogAnnotationProject(t);if _,report,err:=base.DecodeAndValidateJSON([]byte(`{"value":1}`),validation.Limits{});err!=nil||validation.StateName(report.State())!="valid"{t.Fatalf("logical-ID rooted annotation failed: %v %+v",err,report)};if _,report,err:=base.DecodeAndValidateJSON([]byte(`{"value":0}`),validation.Limits{});err!=nil||validation.StateName(report.State())!="invalid"{t.Fatalf("root refinement was not enforced: %v %+v",err,report)}
    project,err:=base.WithDerivedOpenAPIOperations(OpenAPIDerivationOptions{});if err!=nil{t.Fatal(err)};if !strings.Contains(project.EditableSource(),"type BodyPositive =")||!strings.Contains(project.EditableSource(),`@code "body.positive"`){t.Fatalf("operation annotation source was not composed:\n%s",project.EditableSource())};catalog,err:=project.OpenAPIOperationIndex();if err!=nil{t.Fatal(err)};part:=catalog.Operations[0].RequestParts[0];if part.Resource!="https://physical.test/api.json"||!strings.Contains(part.Pointer,"/requestBody/content/application~1json/schema"){t.Fatalf("published operation selector stopped being physical: %+v",part)}
    request:=OpenAPIRequestJSON{Body:&OpenAPIMediaJSON{MediaType:"application/json",Value:[]byte(`1`)}};token,report,err:=project.DecodeAndValidateOpenAPIRequest("putValue",request,OpenAPILimits{},validation.Limits{});if err!=nil||token==nil||validation.StateName(report.State())!="valid"{t.Fatalf("logical operation annotation valid value failed: %v %+v",err,report)};request.Body.Value=[]byte(`0`);if token,report,err=project.DecodeAndValidateOpenAPIRequest("putValue",request,OpenAPILimits{},validation.Limits{});err!=nil||token!=nil||validation.StateName(report.State())!="invalid"{t.Fatalf("logical operation refinement was not enforced: %v %+v",err,report)}
    bundle,err:=project.Bundle();if err!=nil{t.Fatal(err)};again,err:=ParseBundle(bundle);if err!=nil||!again.HasOpenAPINativeBindings(){t.Fatalf("bundle lost catalog annotation composition: %v",err)};exported,err:=project.Export(LowerOptions{Mode:Refined});if err!=nil{t.Fatal(err)};reingested,err:=IngestProjectResources(OpenAPI,exported.Resources(),ProjectOptions{ResourceID:exported.Root().Resource,Root:exported.Root(),Metadata:exported.Metadata()});if err!=nil||!reingested.HasOpenAPINativeBindings(){t.Fatalf("refined export lost catalog annotation composition: %v",err)}
}

func TestOpenAPICatalogOperationDerivationRejectsDynamicAnnotationTargets(t *testing.T){
    annotation:=`{"source":"type Hidden = Int where it > 0","root":"Hidden"}`;source:=`{"openapi":"3.1.2","info":{"title":"Dynamic","version":"1"},"paths":{"/x":{"post":{"operationId":"dynamic","requestBody":{"required":true,"content":{"application/json":{"schema":{"$dynamicRef":"#node"}}}},"responses":{"204":{"description":"ok"}}}}},"components":{"schemas":{"Root":{"type":"object"},"Initial":{"$dynamicAnchor":"node","type":"integer"},"Override":{"$id":"https://override.test/value","$dynamicAnchor":"node","type":"integer","x-refine":`+annotation+`}}}}`;base,err:=IngestProject(OpenAPI,[]byte(source),ProjectOptions{ResourceID:"https://example.test/dynamic.json",Root:ResourceSelector{Pointer:"/components/schemas/Root",TypeName:"Root"}});if err!=nil{t.Fatal(err)};if _,err:=base.WithDerivedOpenAPIOperations(OpenAPIDerivationOptions{});problemCode(err)!="native.refinement"||!strings.Contains(err.Error(),"Override"){t.Fatalf("dynamic target annotation was silently ignored or consumed: %v",err)}
}

func TestOpenAPICatalogOperationIndexAuditsUnconsumedAnnotations(t *testing.T){
    plain:=`{"openapi":"3.1.2","info":{"title":"Index","version":"1"},"paths":{"/x":{"post":{"operationId":"indexed","requestBody":{"required":true,"content":{"application/json":{"schema":{"type":"integer"}}}},"responses":{"204":{"description":"ok"}}}}},"components":{"schemas":{"Root":{"type":"object"}}}}`;base,err:=IngestProject(OpenAPI,[]byte(plain),ProjectOptions{ResourceID:"https://example.test/index.json",Root:ResourceSelector{Pointer:"/components/schemas/Root",TypeName:"Root"}});if err!=nil{t.Fatal(err)};derived,err:=base.WithDerivedOpenAPIOperations(OpenAPIDerivationOptions{});if err!=nil{t.Fatal(err)}
    nested:=strings.Replace(plain,`{"type":"integer"}`,`{"type":"object","properties":{"value":{"type":"integer","x-refine":{"source":"type Hidden = Int","root":"Hidden"}}}}`,1);candidate,err:=IngestProject(OpenAPI,[]byte(nested),ProjectOptions{ResourceID:"https://example.test/index.json",Root:ResourceSelector{Pointer:"/components/schemas/Root",TypeName:"Root"}});if err!=nil{t.Fatal(err)};candidate,err=candidate.WithEditedSource(derived.EditableSource());if err!=nil{t.Fatal(err)};if _,err=candidate.WithMetadata(derived.Metadata());problemCode(err)!="native.refinement"||!strings.Contains(err.Error(),"/properties/value/x-refine"){t.Fatalf("operation index ignored an unconsumed nested annotation: %v",err)}
    direct:=strings.Replace(plain,`{"type":"integer"}`,`{"type":"integer","x-refine":{"source":"type Hidden = String","root":"Hidden"}}`,1);candidate,err=IngestProject(OpenAPI,[]byte(direct),ProjectOptions{ResourceID:"https://example.test/index.json",Root:ResourceSelector{Pointer:"/components/schemas/Root",TypeName:"Root"}});if err!=nil{t.Fatal(err)};candidate,err=candidate.WithEditedSource(derived.EditableSource()+"\ntype Hidden = String\n");if err!=nil{t.Fatal(err)};if _,err=candidate.WithMetadata(derived.Metadata());problemCode(err)!="native.refinement"||!strings.Contains(err.Error(),"does not bind"){t.Fatalf("unrelated checked type claimed a direct operation annotation: %v",err)}
}
