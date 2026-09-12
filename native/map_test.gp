package native

import (
    "bytes"
    "strings"
    "testing"

    "goforge.dev/refine/language"
    "goforge.dev/refine/schemajson"
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

func TestJSONMapRefinementsAndUnicodeBoundary(t *testing.T){
    schema:=`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":{"type":"integer"}}`;project,err:=IngestProject(JSONSchema,[]byte(schema),ProjectOptions{Root:ResourceSelector{TypeName:"MapRoot"}});if err!=nil{t.Fatal(err)};edited,err:=project.WithEditedSource("type MapRoot = Map String (Int where it > 0)\n");if err!=nil{t.Fatal(err)}
    data,report,err:=edited.DecodeAndValidateJSON([]byte(`{"b":2,"a":1}`),validation.Limits{});if err!=nil||validation.StateName(report.State())!="valid"{t.Fatalf("valid refined map failed: %v %+v",err,report)};entries:=data.Entries();if len(entries)!=2{t.Fatal("map entries missing")};first,_:=entries[0].Key.UTF8();second,_:=entries[1].Key.UTF8();if first!="a"||second!="b"{t.Fatalf("map order is not deterministic: %q %q",first,second)}
    if _,report,err=edited.DecodeAndValidateJSON([]byte(`{"a":-1}`),validation.Limits{});err!=nil||validation.StateName(report.State())!="invalid"{t.Fatalf("map value refinement was not applied: %v %+v",err,report)}
    if _,_,err=edited.DecodeAndValidateJSON([]byte(`{"\ud800":1}`),validation.Limits{});err==nil{t.Fatal("unpaired UTF-16 JSON map key reached checked Data")}
}

func TestAvroMapProjectionDecodeAndLowering(t *testing.T){
    source:=`{"type":"map","values":"long"}`;project,err:=IngestProject(Avro,[]byte(source),ProjectOptions{Root:ResourceSelector{TypeName:"Datum"}});if err!=nil{t.Fatal(err)};if project.NativeDocument().Original()!=source||!strings.Contains(project.EditableSource(),"type Datum = Map String (Int64)"){t.Fatalf("Avro map was not preserved and projected: %s",project.EditableSource())}
    wire:=[]byte{4,2,'b',4,2,'a',2,0};data,report,err:=project.DecodeAndValidateAvro(wire,AvroPayloadLimits{},validation.Limits{});if err!=nil||validation.StateName(report.State())!="valid"||len(data.Entries())!=2{t.Fatalf("Avro map decode failed: %v %+v",err,report)};entries:=data.Entries();first,_:=entries[0].Key.UTF8();if first!="a"{t.Fatal("Avro map entry order became semantic")}
    if _,_,err=project.DecodeAndValidateAvro([]byte{4,2,'a',2,2,'a',4,0},AvroPayloadLimits{},validation.Limits{});problemCode(err)!="native.payload"{t.Fatalf("duplicate Avro map key accepted: %v",err)}
    program,err:=language.Compile("type Datum = Map String Int64\n");if err!=nil{t.Fatal(err)};payload,err:=program.PayloadType("Datum");if err!=nil{t.Fatal(err)};lowered,err:=LowerPayload(Avro,payload,LowerOptions{Mode:Refined});if err!=nil{t.Fatal(err)};if !bytes.Contains(lowered.Bytes(),[]byte(`"type": "map"`))||!bytes.Contains(lowered.Bytes(),[]byte(`"values": "long"`)){t.Fatalf("Avro lowering did not retain map semantics: %s",lowered.Bytes())}
}

func TestAvroMapValueRecordDefaultsRemainRefinementChecked(t *testing.T){
    source:=`{"type":"map","values":{"type":"record","name":"Entry","fields":[{"name":"count","type":"int","default":-1}]}}`;project,err:=IngestProject(Avro,[]byte(source),ProjectOptions{Root:ResourceSelector{TypeName:"Datum"}});if err!=nil{t.Fatal(err)};edited:=strings.Replace(project.EditableSource(),"count :: Int32","count :: Int32 where fromInt32 it > 0",1);if edited==project.EditableSource(){t.Fatalf("unexpected projection: %s",edited)};changed,err:=project.WithEditedSource(edited);if changed!=nil||problemCode(err)!="native.default-refinement"{t.Fatalf("invalid nested map-value default escaped refinement compilation: %v",err)}
}

func TestJSONMapLoweringUsesSchemaValuedAdditionalProperties(t *testing.T){
    program,err:=language.Compile("type Datum = Map String Bool\n");if err!=nil{t.Fatal(err)};payload,err:=program.PayloadType("Datum");if err!=nil{t.Fatal(err)};for _,format:=range []Format{JSONSchema,OpenAPI}{lowered,err:=LowerPayload(format,payload,LowerOptions{Mode:Refined});if err!=nil{t.Fatal(format,err)};if !bytes.Contains(lowered.Bytes(),[]byte(`"additionalProperties": {`))||!bytes.Contains(lowered.Bytes(),[]byte(`"type": "boolean"`)){t.Fatalf("%s map lowering changed value domain: %s",format,lowered.Bytes())}}
}

func TestNativeMapOrderingAndJSONAllocationPreflights(t *testing.T){
    a,_:=value.TextFromUTF8("aa");b,_:=value.TextFromUTF8("ab");entries:=[]value.MapEntry{{Key:a,Value:value.OfBool(true)},{Key:b,Value:value.OfBool(false)}};used:=uint64(0);if problemCode(consumeNativeMapOrdering(JSONSchema,"",entries,&used,21))!="native.limit"{t.Fatal("map ordering work cap was not enforced")};if used!=0{t.Fatal("failed ordering preflight consumed budget")};if err:=consumeNativeMapOrdering(JSONSchema,"",entries,&used,44);err!=nil||used!=22{t.Fatalf("exact map ordering bound rejected: %v %d",err,used)};if err:=consumeNativeMapOrdering(JSONSchema,"",entries,&used,44);err!=nil||used!=44{t.Fatalf("aggregate map ordering budget was not shared: %v %d",err,used)};if problemCode(consumeNativeMapOrdering(JSONSchema,"",entries,&used,44))!="native.limit"{t.Fatal("nested maps received fresh ordering budgets")}
    document,err:=schemajson.Parse([]byte(`{"a":1,"b":2}`),schemajson.Limits{});if err!=nil{t.Fatal(err)};decoder:=jsonValueDecoder{format:JSONSchema,maxDepth:8,maxNodes:2,nodes:1,declarations:map[string]language.TypeDecl{}};element:=&language.Type{Form:language.NamedType("Int")};if _,err=decoder.mapping(element,document.Root(),nil,"",1);problemCode(err)!="native.limit"{t.Fatalf("JSON map allocated beyond remaining node capacity: %v",err)}
}
