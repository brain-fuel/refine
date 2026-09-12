package native

import (
    "strings"
    "testing"

    "goforge.dev/refine/validation"
)

const annotatedJSONMap=`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":{"type":"integer"},"x-refine":{"source":"type MapRoot = {}","root":"MapRoot"}}`

func TestJSONTypedMapProjectionFailsWithoutWeakeningNativeSchema(t *testing.T){
    cases:=[]struct{name,source,valid,invalid,pointer string}{
        {"additional properties map",`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":{"type":"integer"}}`,`{"key":1}`,`{"key":"wrong"}`,"/additionalProperties"},
        {"mixed record and map",`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{"name":{"type":"string"}},"additionalProperties":{"type":"integer"}}`,`{"name":"ok","extra":1}`,`{"name":"ok","extra":"wrong"}`,"/additionalProperties"},
        {"pattern-only map",`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","patternProperties":{"^x":{"type":"integer"}},"additionalProperties":false}`,`{"x":1}`,`{"x":"wrong"}`,"/patternProperties"},
    }
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){uri:="urn:refine:map-test";selector:=ResourceSelector{Resource:uri,TypeName:"MapRoot"};document,err:=validateJSONResources(map[string][]byte{uri:[]byte(tc.source)},selector);if err!=nil{t.Fatalf("native schema oracle rejected fixture: %v",err)};if document.Original()!=tc.source{t.Fatal("native parser changed original map schema bytes")};nativeOnly:=&Project{document:document,root:selector,resources:[]Resource{{URI:uri,Source:tc.source}}};if err=nativeOnly.ValidateJSON([]byte(tc.valid));err!=nil{t.Fatalf("native oracle rejected valid map payload: %v",err)};if err=nativeOnly.ValidateJSON([]byte(tc.invalid));problemCode(err)!="native.payload"{t.Fatalf("native oracle accepted invalid map payload: %v",err)};project,err:=IngestProject(JSONSchema,[]byte(tc.source),ProjectOptions{ResourceID:uri,Root:selector});if project!=nil||problemCode(err)!="native.projection"{t.Fatalf("typed map produced an editable projection: %v",err)};if !strings.Contains(err.Error(),tc.pointer)||!strings.Contains(err.Error(),"language map type"){t.Fatalf("map projection error is not actionable: %v",err)}})}
}

func TestJSONOrdinaryExtraFieldPoliciesRemainProjectable(t *testing.T){
    cases:=[]string{
        `{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":true}`,
        `{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false}`,
        `{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","patternProperties":{}}`,
    }
    for _,source:=range cases{project,err:=IngestProject(JSONSchema,[]byte(source),ProjectOptions{Root:ResourceSelector{TypeName:"RecordRoot"}});if err!=nil{t.Fatalf("ordinary extra-field policy was mistaken for a typed map: %v",err)};if project.NativeDocument().Original()!=source{t.Fatal("project ingestion changed ordinary native source bytes")}}
}

func TestSelectedJSONAnnotationIntentionallyBypassesOnlyAutoProjection(t *testing.T){
    uri:="urn:refine:annotated-map";selector:=ResourceSelector{Resource:uri,TypeName:"MapRoot"};ingesters:=[]struct{name string;ingest func()(*Project,error)}{
        {"single",func()(*Project,error){return IngestProject(JSONSchema,[]byte(annotatedJSONMap),ProjectOptions{ResourceID:uri,Root:selector})}},
        {"resources",func()(*Project,error){return IngestProjectResources(JSONSchema,[]Resource{{URI:uri,Source:annotatedJSONMap}},ProjectOptions{Root:selector})}},
    }
    for _,tc:=range ingesters{t.Run(tc.name,func(t *testing.T){project,err:=tc.ingest();if err!=nil{t.Fatalf("selected checked annotation did not bypass auto-projection: %v",err)};if project.EditableSource()!="type MapRoot = {}"||project.NativeDocument().Original()!=annotatedJSONMap{t.Fatal("annotation or immutable native source changed")};data,_,err:=project.DecodeAndValidateJSON([]byte(`{"key":1}`),validation.Limits{});if err!=nil{t.Fatalf("native-valid annotated map was rejected: %v",err)};if _,present:=data.Lookup("key");present{t.Fatal("raw empty-record view unexpectedly invented a typed map field")};if err=project.ValidateJSON([]byte(`{"key":"wrong"}`));problemCode(err)!="native.payload"{t.Fatalf("annotation bypassed the native map oracle: %v",err)}})}
}

func TestInvalidSelectedJSONAnnotationsFailAtomically(t *testing.T){
    cases:=[]struct{name,annotation,code string}{
        {"syntax",`{"source":"type MapRoot =","root":"MapRoot"}`,"native.refinement"},
        {"root",`{"source":"type MapRoot = {}","root":"Missing"}`,"native.refinement"},
        {"proof",`{"source":"type MapRoot = {} where False","root":"MapRoot"}`,"native.schema"},
    }
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){source:=`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":{"type":"integer"},"x-refine":`+tc.annotation+`}`;project,err:=IngestProject(JSONSchema,[]byte(source),ProjectOptions{Root:ResourceSelector{TypeName:"MapRoot"}});if project!=nil||problemCode(err)!=tc.code{t.Fatalf("invalid annotated project was returned: %v",err)}})}
}
