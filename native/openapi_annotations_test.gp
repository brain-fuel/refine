package native

import (
    "strings"
    "testing"

    "goforge.dev/refine/validation"
)

func TestOpenAPISchemaObjectAnnotationControlsSelectedPayload(t *testing.T){
    scoped:=`{"openapi":"3.2.1","info":{"title":"Scoped","version":"1"},"paths":{},"components":{"schemas":{"Value":{"type":"integer","minimum":0,"x-refine":{"source":"type Positive = Int where it > 10 @code \"positive\"","root":"Positive","metadata":{"NumericExpansion":123}}}}}}`
    project,err:=IngestProject(OpenAPI,[]byte(scoped),ProjectOptions{ResourceID:"https://example.test/scoped.json",Root:ResourceSelector{Pointer:"/components/schemas/Value",TypeName:"Value"}});if err!=nil{t.Fatal(err)}
    if project.Metadata().NumericExpansion!=123||!strings.Contains(project.EditableSource(),"type Value = Positive"){t.Fatalf("scoped source/metadata was not selected: %s %+v",project.EditableSource(),project.Metadata())}
    if _,report,err:=project.DecodeAndValidateJSON([]byte(`11`),validation.Limits{});err!=nil||validation.StateName(report.State())!="valid"{t.Fatalf("valid scoped value failed: %v %+v",err,report)}
    if _,report,err:=project.DecodeAndValidateJSON([]byte(`5`),validation.Limits{});err!=nil||validation.StateName(report.State())!="invalid"||len(report.Diagnostics())!=1||report.Diagnostics()[0].Code!="positive"{t.Fatalf("Schema Object predicate was inert: %v %+v",err,report)}
    if err:=project.ValidateJSON([]byte(`5`));err!=nil{t.Fatalf("language predicate leaked into the unchanged native oracle: %v",err)}
    resources,err:=IngestProjectResources(OpenAPI,[]Resource{{URI:"https://example.test/scoped.json",Source:scoped}},ProjectOptions{Root:ResourceSelector{Resource:"https://example.test/scoped.json",Pointer:"/components/schemas/Value",TypeName:"Value"}});if err!=nil{t.Fatal(err)};if _,report,err:=resources.DecodeAndValidateJSON([]byte(`5`),validation.Limits{});err!=nil||validation.StateName(report.State())!="invalid"{t.Fatalf("resource ingestion lost scoped predicate: %v %+v",err,report)}

    top:=`{"openapi":"3.2.1","info":{"title":"Top","version":"1"},"paths":{},"x-refine":{"source":"type Value = Int where it > 3 @code \"top\"","root":"Value"},"components":{"schemas":{"Value":{"type":"integer","minimum":0}}}}`
    unchanged,err:=IngestProject(OpenAPI,[]byte(top),ProjectOptions{ResourceID:"https://example.test/top.json",Root:ResourceSelector{Pointer:"/components/schemas/Value",TypeName:"Value"}});if err!=nil{t.Fatal(err)}
    if _,report,err:=unchanged.DecodeAndValidateJSON([]byte(`2`),validation.Limits{});err!=nil||validation.StateName(report.State())!="invalid"||report.Diagnostics()[0].Code!="top"{t.Fatalf("top-level annotation behavior changed: %v %+v",err,report)}
}

func TestOpenAPISchemaObjectAnnotationControlsDerivedOperationPart(t *testing.T){
    source:=`{
      "openapi":"3.2.1","info":{"title":"Operations","version":"1"},
      "paths":{"/values":{"post":{"operationId":"putValue","requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/Positive"}}}},"responses":{"200":{"description":"ok","content":{"application/json":{"schema":{"type":"object","example":{"x-refine":17}}}}}}}}},
      "components":{"schemas":{
        "Root":{"type":"object","additionalProperties":false},
        "Positive":{"type":"integer","minimum":0,"x-refine":{"source":"type Positive = Int where it > 10 @code \"operation.positive\"","root":"Positive"}}
      }}
    }`
    base,err:=IngestProject(OpenAPI,[]byte(source),ProjectOptions{ResourceID:"https://example.test/operations.json",Root:ResourceSelector{Pointer:"/components/schemas/Root",TypeName:"Root"}});if err!=nil{t.Fatal(err)}
    project,err:=base.WithDerivedOpenAPIOperations(OpenAPIDerivationOptions{});if err!=nil{t.Fatal(err)}
    if strings.Count(project.EditableSource(),"type Positive =")!=1{t.Fatalf("scoped module was omitted or duplicated:\n%s",project.EditableSource())}
    request:=OpenAPIRequestJSON{Body:&OpenAPIMediaJSON{MediaType:"application/json",Value:[]byte(`11`)}}
    if token,report,err:=project.DecodeAndValidateOpenAPIRequest("putValue",request,OpenAPILimits{},validation.Limits{});err!=nil||token==nil||validation.StateName(report.State())!="valid"{t.Fatalf("valid annotated operation body failed: %v %+v",err,report)}
    request.Body.Value=[]byte(`5`);if token,report,err:=project.DecodeAndValidateOpenAPIRequest("putValue",request,OpenAPILimits{},validation.Limits{});err!=nil||token!=nil||validation.StateName(report.State())!="invalid"||len(report.Diagnostics())!=1||report.Diagnostics()[0].Code!="operation.positive"{t.Fatalf("operation Schema Object predicate was inert: %v %+v",err,report)}
}

func TestOpenAPISchemaObjectAnnotationAuditFailsClosed(t *testing.T){
    nested:=`{"openapi":"3.2.1","info":{"title":"Nested","version":"1"},"paths":{},"components":{"schemas":{"Root":{"type":"object","properties":{"value":{"type":"integer","x-refine":{"source":"type Positive = Int where it > 0","root":"Positive"}}}}}}}`
    if _,err:=IngestProject(OpenAPI,[]byte(nested),ProjectOptions{ResourceID:"https://example.test/nested.json",Root:ResourceSelector{Pointer:"/components/schemas/Root",TypeName:"Root"}});problemCode(err)!="native.refinement"{t.Fatalf("reachable nested annotation was silently ignored: %v",err)}

    rebased:=`{"openapi":"3.2.1","info":{"title":"Rebased","version":"1"},"paths":{"/values":{"post":{"operationId":"putValue","requestBody":{"required":true,"content":{"application/json":{"schema":{"$id":"https://example.test/scoped/","$ref":"#/components/schemas/Positive"}}}},"responses":{"200":{"description":"ok"}}}}},"components":{"schemas":{"Root":{"type":"object"},"Positive":{"type":"integer","x-refine":{"source":"type Positive = Int where it > 0","root":"Positive"}}}}}`
    base,err:=IngestProject(OpenAPI,[]byte(rebased),ProjectOptions{ResourceID:"https://example.test/rebased.json",Root:ResourceSelector{Pointer:"/components/schemas/Root",TypeName:"Root"}});if err!=nil{t.Fatal(err)};if _,err=base.WithDerivedOpenAPIOperations(OpenAPIDerivationOptions{});problemCode(err)!="native.enforcement"||!strings.Contains(err.Error(),"$id-rebased"){t.Fatalf("$id scope was resolved as a physical URI: %v",err)}
}
