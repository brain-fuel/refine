package native

import (
    "encoding/json"
    "strings"
    "testing"

    "goforge.dev/refine/validation"
)

const genericAnnotationRootSource=`type Box a = {value :: a, allowed :: Bool} where it.allowed @code "box.allowed"`

func requireGenericRootReport(t *testing.T,project *Project,input string,want string){t.Helper();_,report,err:=project.DecodeAndValidateJSON([]byte(input),validation.Limits{});if err!=nil{t.Fatal(err)};if validation.StateName(report.State())!=want{t.Fatalf("generic root state=%s want=%s: %+v",validation.StateName(report.State()),want,report)};if want=="invalid"&&(len(report.Diagnostics())!=1||report.Diagnostics()[0].Code!="box.allowed"){t.Fatalf("generic root refinement was not enforced: %+v",report)}}

func TestGenericAnnotationRootExpressionsComposeAndEnforceAcrossFormats(t *testing.T){
    annotation:=map[string]any{"source":genericAnnotationRootSource,"root":"Box Int32"}
    cases:=[]struct{name string;format Format;schema map[string]any;pointer string}{
        {"jsonschema",JSONSchema,map[string]any{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":map[string]any{"value":map[string]any{"type":"integer"},"allowed":map[string]any{"type":"boolean"}},"required":[]string{"value","allowed"},"additionalProperties":false,"x-refine":annotation},""},
        {"avro",Avro,map[string]any{"type":"record","name":"WireBox","fields":[]any{map[string]any{"name":"value","type":"int"},map[string]any{"name":"allowed","type":"boolean"}},"x-refine":annotation},""},
        {"openapi",OpenAPI,map[string]any{"openapi":"3.1.0","info":map[string]any{"title":"Generic root","version":"1"},"paths":map[string]any{},"components":map[string]any{"schemas":map[string]any{"Payload":map[string]any{"type":"object","properties":map[string]any{"value":map[string]any{"type":"integer"},"allowed":map[string]any{"type":"boolean"}},"required":[]string{"value","allowed"},"additionalProperties":false}}},"x-refine":annotation},"/components/schemas/Payload"},
    }
    for _,tc:=range cases{for _,resources:=range []bool{false,true}{name:=tc.name+"/single";if resources{name=tc.name+"/resources"};t.Run(name,func(t *testing.T){
        input,err:=json.Marshal(tc.schema);if err!=nil{t.Fatal(err)};uri:="https://example.test/"+tc.name+".json";options:=ProjectOptions{ResourceID:uri,Root:ResourceSelector{Resource:uri,Pointer:tc.pointer,TypeName:"Payload"}};var project *Project;if resources{project,err=IngestProjectResources(tc.format,[]Resource{{URI:uri,Source:string(input)}},options)}else{project,err=IngestProject(tc.format,input,options)};if err!=nil{t.Fatal(err)}
        if !strings.Contains(project.EditableSource(),"type Payload = Box Int32"){t.Fatalf("closed generic annotation root was not composed:\n%s",project.EditableSource())}
        if tc.format==Avro{_,report,err:=project.DecodeAndValidateAvro([]byte{2,1},AvroPayloadLimits{},validation.Limits{});if err!=nil||validation.StateName(report.State())!="valid"{t.Fatalf("valid generic Avro root: %v %+v",err,report)};_,report,err=project.DecodeAndValidateAvro([]byte{2,0},AvroPayloadLimits{},validation.Limits{});if err!=nil||validation.StateName(report.State())!="invalid"||len(report.Diagnostics())!=1||report.Diagnostics()[0].Code!="box.allowed"{t.Fatalf("generic Avro refinement was not enforced: %v %+v",err,report)};if _,_,err=project.DecodeAndValidateAvro([]byte{2},AvroPayloadLimits{},validation.Limits{});problemCode(err)!="native.payload"{t.Fatalf("native Avro framing did not remain first: %v",err)};return}
        requireGenericRootReport(t,project,`{"value":1,"allowed":true}`,"valid");requireGenericRootReport(t,project,`{"value":1,"allowed":false}`,"invalid");if _,_,err:=project.DecodeAndValidateJSON([]byte(`{"value":1}`),validation.Limits{});problemCode(err)!="native.payload"{t.Fatalf("native required property did not remain first: %v",err)}
    })}}
}

func TestGenericAnnotationRootExpressionsMustBeClosed(t *testing.T){
    if annotation,err:=checkAnnotation(JSONSchema,"/x-refine",genericAnnotationRootSource,"Box Int32",WireMetadata{},false);err!=nil||annotation.Root!="Box Int32"{t.Fatalf("closed generic root rejected: %v %+v",err,annotation)}
    if _,err:=checkAnnotation(JSONSchema,"/x-refine",genericAnnotationRootSource,"Box a",WireMetadata{},false);problemCode(err)!="native.refinement"{t.Fatalf("open generic root accepted: %v",err)}
}
