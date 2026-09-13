package native

import (
    "encoding/json"
    "strings"
    "testing"

    "goforge.dev/refine/validation"
)

func booleanExportTarget(t *testing.T,source,pointer string)map[string]any{t.Helper();var document any;decoder:=json.NewDecoder(strings.NewReader(source));decoder.UseNumber();if err:=decoder.Decode(&document);err!=nil{t.Fatal(err)};target,err:=effectiveSchemaObject(document,pointer);if err!=nil{t.Fatal(err)};return target}

func TestProjectExportRetainsSelectedBooleanTrueSchemaAtRootAndPointer(t *testing.T){
    cases:=[]struct{name,source,pointer string}{{"root","true",""},{"nested",`{"$schema":"https://json-schema.org/draft/2020-12/schema","$defs":{"Any":true},"$ref":"#/$defs/Any"}`,"/$defs/Any"}}
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){selector:=ResourceSelector{Resource:"https://example.test/any.json",Pointer:tc.pointer,TypeName:"Any"};project,err:=IngestProject(JSONSchema,[]byte(tc.source),ProjectOptions{ResourceID:selector.Resource,Root:selector});if err!=nil{t.Fatal(err)};project,err=project.WithEditedSource("type Any = JSON where it /= JSONNull @code \"not.null\"\n");if err!=nil{t.Fatal(err)};originalResources:=project.Resources();originalDocument:=project.NativeDocument().Original()
        for _,mode:=range []ExportMode{Ordinary,Refined}{t.Run(string(mode),func(t *testing.T){exported,err:=project.Export(LowerOptions{Mode:mode,AllowDocumentedLoss:true});if err!=nil{t.Fatal(err)};if exported.Root()!=selector{t.Fatalf("root selector changed: %+v",exported.Root())};resources:=exported.Resources();if len(resources)!=1{t.Fatalf("wrong exported resource count: %d",len(resources))};target:=booleanExportTarget(t,resources[0].Source,tc.pointer);allOf,ok:=target["allOf"].([]any);if !ok||len(allOf)<2||allOf[0]!=true{t.Fatalf("original Boolean assertion was not retained first: %#v",target)};_,hasRefine:=target["x-refine"];if hasRefine!=(mode==Refined){t.Fatalf("wrong refinement annotation state for %s: %#v",mode,target)}
            again,err:=IngestProjectResources(JSONSchema,resources,ProjectOptions{ResourceID:selector.Resource,Root:selector,Metadata:exported.Metadata()});if err!=nil{t.Fatal(err)};_,validReport,err:=again.DecodeAndValidateJSON([]byte(`{"nested":[true,1.25]}`),validation.Limits{});if err!=nil||validation.StateName(validReport.State())!="valid"{t.Fatalf("retained true schema rejected JSON: %v %+v",err,validReport)};_,nullReport,err:=again.DecodeAndValidateJSON([]byte("null"),validation.Limits{});if err!=nil{t.Fatal(err)};want:="valid";if mode==Refined{want="invalid"};if validation.StateName(nullReport.State())!=want{t.Fatalf("%s re-ingest lost native/refinement authority: %+v",mode,nullReport)}
        })}
        if project.NativeDocument().Original()!=originalDocument||len(project.Resources())!=len(originalResources)||project.Resources()[0]!=originalResources[0]{t.Fatal("export mutated immutable project resources")}
    })}
}

func TestProjectRejectsSelectedBooleanFalseSchemaAsProvenEmpty(t *testing.T){cases:=[]struct{source,pointer string}{{"false",""},{`{"$defs":{"Empty":false},"$ref":"#/$defs/Empty"}`,"/$defs/Empty"}};for _,tc:=range cases{project,err:=IngestProject(JSONSchema,[]byte(tc.source),ProjectOptions{Root:ResourceSelector{Pointer:tc.pointer,TypeName:"Empty"}});if project!=nil||problemCode(err)!="native.schema"{t.Fatalf("selected false schema was not rejected as proven empty: %v",err)}}}
