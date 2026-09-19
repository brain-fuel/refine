package native

import (
    "strings"
    "testing"

    "goforge.dev/refine/validation"
)

func TestOpenAPICatalogOperationAnnotationKeepsIntentionalEditsAcrossBundleAndExport(t *testing.T){
    base:=catalogAnnotationProject(t);project,err:=base.WithDerivedOpenAPIOperations(OpenAPIDerivationOptions{});if err!=nil{t.Fatal(err)};source:=project.EditableSource();editedSource:=strings.Replace(source,"it > 0","it > 2",1);if source==editedSource{t.Fatal("operation annotation predicate was not found")};edited,err:=project.WithEditedSource(editedSource);if err!=nil{t.Fatal(err)}
    bundle,err:=edited.Bundle();if err!=nil{t.Fatal(err)};reloaded,err:=ParseBundle(bundle);if err!=nil{t.Fatal(err)};exported,err:=edited.Export(LowerOptions{Mode:Refined});if err!=nil{t.Fatal(err)};reingested,err:=IngestProjectResources(OpenAPI,exported.Resources(),ProjectOptions{Root:exported.Root(),Metadata:exported.Metadata()});if err!=nil{t.Fatal(err)}
    for _,candidate:=range []*Project{edited,reloaded,reingested}{for _,test:=range []struct{payload string;state string}{{"1","invalid"},{"3","valid"}}{request:=OpenAPIRequestJSON{Body:&OpenAPIMediaJSON{MediaType:"application/json",Value:[]byte(test.payload)}};_,report,err:=candidate.DecodeAndValidateOpenAPIRequest("putValue",request,OpenAPILimits{},validation.Limits{});if err!=nil||validation.StateName(report.State())!=test.state{t.Fatalf("edited operation predicate lost after reconstruction for %s: %v %+v",test.payload,err,report)}}}
    request:=OpenAPIRequestJSON{Body:&OpenAPIMediaJSON{MediaType:"application/json",Value:[]byte(`1`)}};if _,report,err:=project.DecodeAndValidateOpenAPIRequest("putValue",request,OpenAPILimits{},validation.Limits{});err!=nil||validation.StateName(report.State())!="valid"{t.Fatalf("edit mutated prior annotation authority: %v %+v",err,report)}
}
