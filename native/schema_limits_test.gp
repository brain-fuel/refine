package native

import (
    "testing"

    "goforge.dev/refine/language"
    "goforge.dev/refine/validation"
)

func TestNativeBundleRetainsSchemaValidationLimits(t *testing.T){
    project,err:=IngestProject(JSONSchema,[]byte(`{"type":"integer"}`),ProjectOptions{});if err!=nil{t.Fatal(err)};source:="@limits total 1000 clause 1\ntype ImportedRoot = Int where it == it\n";project,err=project.WithEditedSource(source);if err!=nil{t.Fatal(err)};if _,report,err:=project.DecodeAndValidateJSON([]byte(`1`),validation.Limits{});err!=nil||validation.StateName(report.State())!="indeterminate"{t.Fatalf("native boundary ignored schema limits: %v %+v",err,report)};bundle,err:=project.Bundle();if err!=nil{t.Fatal(err)};again,err:=ParseBundle(bundle);if err!=nil{t.Fatal(err)};program,err:=language.Compile(again.EditableSource());if err!=nil{t.Fatal(err)};if again.EditableSource()!=source||program.SchemaLimits().Clause!=1{t.Fatal("bundle lost schema limits")};if _,report,err:=again.DecodeAndValidateJSON([]byte(`1`),validation.Limits{});err!=nil||validation.StateName(report.State())!="indeterminate"{t.Fatalf("reloaded boundary relaxed schema limits: %v %+v",err,report)}
}
