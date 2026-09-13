package project

import (
    "strings"
    "testing"

    "goforge.dev/refine/native"
)

func TestGenerateOperationsOnlyOpenAPIRejectsMissingPropertyAssembly(t *testing.T){
    source:=[]byte(`{"openapi":"3.1.2","info":{"title":"Rootless","version":"1"},"paths":{"/ping":{"post":{"operationId":"ping","requestBody":{"required":true,"content":{"application/json":{"schema":{"type":"integer"}}}},"responses":{"204":{"description":"accepted"}}}}}}`)
    imported,err:=native.IngestOpenAPIOperations(source,native.OpenAPIOperationIngestOptions{});if err!=nil{t.Fatal(err)}
    for _,disabled:=range []bool{false,true}{
        output,err:=Generate(GenerateInput{Contracts:[]Contract{{Family:"ping",NativeProject:imported,Formats:[]native.Format{native.OpenAPI},NoCodegen:disabled}}})
        if err==nil||!strings.Contains(err.Error(),"operation-aware generated property tests")||len(output.Files)!=0{t.Fatalf("rootless project assembly silently skipped its missing boundary: no-codegen=%v err=%v files=%d",disabled,err,len(output.Files))}
    }
}
