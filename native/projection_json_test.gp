package native

import (
    "strings"
    "testing"

    "goforge.dev/refine/validation"
)

func TestJSONCarrierProjectionRetainsNativeApplicatorAndTupleAuthority(t *testing.T){
    cases:=[]struct{name,schema,projected,valid,invalid string}{
        {"true","true","JSON",`{"anything":[null,true,1.5,"text"]}`,""},
        {"empty","{}","JSON",`[1,"text",null]`,""},
        {"exactly one",`{"oneOf":[{"type":"integer"},{"type":"number"}]}`,"JSON","1.5","1"},
        {"mixed kinds",`{"type":["string","integer","null"]}`,"JSON","null","false"},
        {"null only",`{"type":"null"}`,"JSON where it == JSONNull","null","0"},
        {"tuple",`{"type":"array","prefixItems":[{"type":"integer"},{"type":"string"}],"items":false}`,"[JSON]",`[1,"text"]`,`["text",1]`},
        {"unconstrained array",`{"type":"array"}`,"[JSON]",`[1,"text",null]`,"{}"},
        {"closed empty array",`{"type":"array","items":false}`,"[JSON where False]","[]","[null]"},
        {"composed object",`{"type":"object","allOf":[{"properties":{"x":{"type":"integer"}},"required":["x"]}],"unevaluatedProperties":false}`,"JSON",`{"x":1}`,`{"x":"bad"}`},
        {"nonidentifier field",`{"type":"object","properties":{"dash-name":{"type":"integer"}},"required":["dash-name"]}`,"Map String JSON",`{"dash-name":1}`,`{"dash-name":false}`},
        {"undeclared required field",`{"type":"object","properties":{"x":{"type":"integer"}},"required":["y"]}`,"Map String JSON",`{"y":null}`,`{"x":1}`},
        {"open object",`{"type":"object"}`,"Map String JSON",`{"x":null}`,"[]"},
        {"empty patterns",`{"type":"object","patternProperties":{}}`,"Map String JSON",`{"x":null}`,"[]"},
    }
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){project,err:=IngestProject(JSONSchema,[]byte(tc.schema),ProjectOptions{Root:ResourceSelector{TypeName:"Root"}});if err!=nil{t.Fatal(err)};if !strings.Contains(project.EditableSource(),"type Root = "+tc.projected+"\n"){t.Fatalf("wrong projection: %s",project.EditableSource())};_,report,err:=project.DecodeAndValidateJSON([]byte(tc.valid),validation.Limits{});if err!=nil||validation.StateName(report.State())!="valid"{t.Fatalf("native-valid value rejected: %v %+v",err,report)};if tc.invalid!=""{if err:=project.ValidateJSON([]byte(tc.invalid));problemCode(err)!="native.payload"{t.Fatalf("native constraint weakened: %v",err)}};if project.NativeDocument().Original()!=tc.schema{t.Fatal("original native schema mutated")};bundle,err:=project.Bundle();if err!=nil{t.Fatal(err)};restored,err:=ParseBundle(bundle);if err!=nil{t.Fatal(err)};if restored.NativeDocument().Original()!=tc.schema{t.Fatal("bundle round trip changed native source")}})}
    if project,err:=IngestProject(JSONSchema,[]byte("false"),ProjectOptions{Root:ResourceSelector{TypeName:"Root"}});project!=nil||problemCode(err)!="native.schema"{t.Fatalf("proven empty root did not fail schema validation: %v",err)}
}

func TestJSONCarrierReferenceSiblingsPreserveDeclaredMembers(t *testing.T){
    source:=`{"$defs":{"Base":{"type":"object","properties":{"x":{"type":"integer"}},"required":["x"]}},"$ref":"#/$defs/Base","properties":{"y":{"type":"string"}},"required":["y"]}`
    project,err:=IngestProject(JSONSchema,[]byte(source),ProjectOptions{Root:ResourceSelector{TypeName:"Root"}});if err!=nil{t.Fatal(err)};if !strings.Contains(project.EditableSource(),"type Root = JSON\n"){t.Fatal(project.EditableSource())};data,report,err:=project.DecodeAndValidateJSON([]byte(`{"x":1,"y":"kept"}`),validation.Limits{});if err!=nil||validation.StateName(report.State())!="valid"{t.Fatalf("supported ref siblings rejected: %v %+v",err,report)};if len(data.Elements()[0].Entries())!=2{t.Fatal("native-declared sibling property was discarded")};if err:=project.ValidateJSON([]byte(`{"x":1}`));problemCode(err)!="native.payload"{t.Fatalf("sibling required constraint lost: %v",err)}
}

func TestJSONCarrierRefinementsAndOrdinaryLowering(t *testing.T){
    project,err:=IngestProject(JSONSchema,[]byte("{}"),ProjectOptions{Root:ResourceSelector{TypeName:"Root"}});if err!=nil{t.Fatal(err)};project,err=project.WithEditedSource("type Root = JSON where it /= JSONNull @code \"not.null\"\n");if err!=nil{t.Fatal(err)};_,report,err:=project.DecodeAndValidateJSON([]byte("null"),validation.Limits{});if err!=nil||validation.StateName(report.State())!="invalid"{t.Fatalf("refinement bypassed: %v %+v",err,report)}
    typ:=payload(t,"type Root = JSON\n","Root");for _,format:=range []Format{JSONSchema,OpenAPI}{for _,mode:=range []ExportMode{Ordinary,Refined}{exported,err:=LowerPayload(format,typ,LowerOptions{Mode:mode});if err!=nil{t.Fatal(err)};if !strings.Contains(exported.String(),"exact finite decimals"){t.Fatal("wire restrictions not explained")};ingested,err:=IngestProject(format,exported.Bytes(),ProjectOptions{Root:ResourceSelector{TypeName:"Root"}});if err!=nil{t.Fatal(err)};for _,raw:=range []string{"null","true","1.25",`"hello"`,"[]","{}"}{if _,report,err:=ingested.DecodeAndValidateJSON([]byte(raw),validation.Limits{});err!=nil||validation.StateName(report.State())!="valid"{t.Fatalf("%s/%s/%s: %v %+v",format,mode,raw,err,report)}}}}
    if _,err:=LowerPayload(Avro,typ,LowerOptions{});problemCode(err)!="native.unrepresentable"{t.Fatalf("invented implicit Avro JSON encoding: %v",err)}
}
