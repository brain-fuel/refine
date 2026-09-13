package project

import (
    "strings"
    "testing"

    "goforge.dev/refine/native"
)

func TestGenerateNativeJSONCarriersComposeModelsOraclePropertiesAndExports(t *testing.T){
    cases:=[]struct{name,schema string}{
        {"unconstrained","true"},
        {"mixed",`{"oneOf":[{"type":"integer"},{"type":"string"}]}`},
        {"heterogeneous map",`{"type":"object","properties":{"label":{"type":"string"}},"additionalProperties":{"type":"integer"}}`},
        {"tuple",`{"type":"array","prefixItems":[{"type":"integer"},{"type":"string"}],"items":false}`},
    }
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){imported,err:=native.IngestProject(native.JSONSchema,[]byte(tc.schema),native.ProjectOptions{Root:native.ResourceSelector{TypeName:"Value"}});if err!=nil{t.Fatal(err)};bundle,err:=Generate(GenerateInput{Contracts:[]Contract{{Family:"jsonvalue",NativeProject:imported,Formats:[]native.Format{native.JSONSchema}}}});if err!=nil{t.Fatal(err)};found:=map[string]bool{};for _,file:=range bundle.Files{source:=string(file.Content);switch{
        case strings.HasSuffix(file.Path,"/JSONValue.java"):found["semantic JSON model"]=strings.Contains(source,"sealed interface JSONValue")
        case strings.HasSuffix(file.Path,"/Value.java"):found["nominal root"]=strings.Contains(source,"JSONValue")
        case strings.HasSuffix(file.Path,"/RefineJSONModule.java"):found["checked Jackson adapter"]=strings.Contains(source,`new S("json"`)&&strings.Contains(source,"nativeGate.validate")
        case strings.HasSuffix(file.Path,"/RefineJSONModuleNativeSidecar.java"):found["native oracle"]=true
        case strings.HasSuffix(file.Path,"/ContractGeneratedProperties.java"):found["native-filtered properties"]=strings.Contains(source,"acceptsNativeCandidate(data)")&&strings.Contains(source,"JSONObject")
        case strings.HasSuffix(file.Path,"/contract.refined.json"):found["original bundle"]=true;restored,err:=native.ParseBundle(file.Content);if err!=nil{t.Fatal(err)};if restored.NativeDocument().Original()!=tc.schema{t.Fatal("project generation changed original native schema")}
        case strings.HasSuffix(file.Path,"/ordinary-json-schema-resources.json"):found["ordinary resource manifest"]=true
        }};for _,name:=range []string{"semantic JSON model","nominal root","checked Jackson adapter","native oracle","native-filtered properties","original bundle","ordinary resource manifest"}{if !found[name]{t.Fatalf("missing %s",name)}}})}
}
