package project

import (
    "errors"
    "strings"
    "testing"
    "goforge.dev/refine/analysis"
    "goforge.dev/refine/language"
    "goforge.dev/refine/native"
)

func TestProjectSchemaProofGateIsAtomicAndUnknownIsExplicit(t *testing.T){
    for _,noCodegen:=range []bool{false,true}{p,err:=language.Compile("type Impossible = Int where it > 0 where it < 1\n");if err!=nil{t.Fatal(err)};result,err:=Generate(GenerateInput{Contracts:[]Contract{{Family:"empty",Program:p,RootType:"Impossible",Formats:[]native.Format{native.JSONSchema},NoCodegen:noCodegen}}});var proof *analysis.SchemaError;if !errors.As(err,&proof)||len(result.Files)!=0{t.Fatal("known empty declaration emitted project files",err)}}
    p,err:=language.Compile("type Empty = Int where it > 0 && it < 1\ntype Optional = { value :: Maybe Empty }\ntype Text = String\n");if err!=nil{t.Fatal(err)};result,err:=Generate(GenerateInput{Contracts:[]Contract{{Family:"text",Program:p,RootType:"Text",Formats:[]native.Format{native.JSONSchema}}}});if err!=nil{t.Fatalf("unused or optional impossible declaration rejected inhabitable root: %v",err)};found:=false;for _,file:=range result.Files{if strings.HasSuffix(file.Path,"schema-analysis.json"){found=true;content:=string(file.Content);if !strings.Contains(content,`"roots": [`)||!strings.Contains(content,`"Text"`)||!strings.Contains(content,`"outcome": "no"`)||!strings.Contains(content,`"outcome": "unknown"`)||!strings.Contains(content,"explicit payload and OpenAPI operation entrypoints"){t.Fatal("scoped or unknown result hidden",content)}}};if !found{t.Fatal("schema proof resource absent")}
}

func TestProjectSchemaProofGateIncludesOpenAPIEntrypoints(t *testing.T){
    source:="type Root = Int\ntype Params = { id :: Int }\ntype Headers = {}\ntype Body = {}\ntype Request = { parameters :: Params, headers :: Headers, body :: Body } where False\ntype Response = { headers :: Headers, body :: Body }\ntype Context = { request :: Request, response :: Response }\n";program,err:=language.Compile(source);if err!=nil{t.Fatal(err)};result,err:=Generate(GenerateInput{Contracts:[]Contract{{Family:"operation",Program:program,RootType:"Root",Formats:[]native.Format{native.JSONSchema},Wire:projectOperationWire(),NoCodegen:true}}});var proof *analysis.SchemaError;if !errors.As(err,&proof)||proof.Type!="Request"||len(result.Files)!=0{t.Fatalf("proven-empty OpenAPI entrypoint emitted project files: %+v %v",result,err)}
}
