package native

import (
    "encoding/json"
    "fmt"
    "net/url"
    "reflect"
    "strings"
    "testing"

    jsonoracle "github.com/santhosh-tekuri/jsonschema/v6"
    "goforge.dev/refine/schemajson"
)

type oracleViewLoader struct{values map[string]string}
func (l oracleViewLoader)Load(uri string)(any,error){source,ok:=l.values[uri];if !ok{return nil,fmt.Errorf("unlisted oracle resource %s",uri)};return jsonoracle.UnmarshalJSON(strings.NewReader(source))}
func oracleViewCompiler(t *testing.T,view *openAPIOracleView)*jsonoracle.Compiler{
    t.Helper();compiler:=newOfflineJSONCompiler();compiler.DefaultDraft(jsonoracle.Draft2020);loader:=oracleViewLoader{values:map[string]string{openAPIBaseDialect:openAPIBaseDialectAdapter}}
    for _,alias:=range view.aliases{loader.values[alias.URI]=alias.Source};compiler.UseLoader(loader)
    for _,resource:=range view.resources{parsed,err:=jsonoracle.UnmarshalJSON(strings.NewReader(resource.Source));if err!=nil{t.Fatal(err)};if err:=compiler.AddResource(resource.URI,parsed);err!=nil{t.Fatal(err)}}
    return compiler
}
func assertOracleViewPayload(t *testing.T,compiler *jsonoracle.Compiler,view *openAPIOracleView,selector ResourceSelector,valid,invalid string){
    t.Helper();mapped,err:=view.selector(selector);if err!=nil{t.Fatal(err)};identity,err:=url.Parse(mapped.Resource);if err!=nil{t.Fatal(err)};identity.Fragment=mapped.Pointer;assertOracleLocationPayload(t,compiler,identity.String(),valid,invalid)
}
func assertOracleLocationPayload(t *testing.T,compiler *jsonoracle.Compiler,location,valid,invalid string){
    t.Helper();compiled,err:=compiler.Compile(location);if err!=nil{t.Fatal(err)}
    for _,test:=range []struct{source string;valid bool}{{valid,true},{invalid,false}}{value,err:=jsonoracle.UnmarshalJSON(strings.NewReader(test.source));if err!=nil{t.Fatal(err)};if err:=compiled.Validate(value);(err==nil)!=test.valid{t.Fatalf("validation of %s: %v (want valid=%v)",test.source,err,test.valid)}}
}

func TestOpenAPIOracleViewPreservesPhysicalAndLogicalScope(t *testing.T){
    uri:="https://example.test/api.json";external:="https://example.test/value.json"
    source:=`{"openapi":"3.1.2","info":{"title":"Oracle","version":"1"},"paths":{},"components":{"schemas":{"Root":{"type":"object","required":["value"],"properties":{"value":{"$ref":"value.json#value"}},"examples":[{"$ref":"this is data","$id":"not a schema"}]},"Scoped":{"$id":"https://schemas.test/container","$defs":{"Value":{"$id":"value","$anchor":"n","type":"integer","minimum":2}},"$ref":"value#n"},"Pointer":{"$ref":"#/components/schemas/Scoped/$defs/Value"}}}}`
    resources:=[]Resource{{URI:uri,Source:source},{URI:external,Source:`{"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://schemas.test/text","$anchor":"value","type":"string","minLength":2}`}}
    catalog,err:=newOpenAPIProjectionCatalog(resources,uri);if err!=nil{t.Fatal(err)};view,err:=newOpenAPIOracleView(catalog);if err!=nil{t.Fatal(err)};compiler:=oracleViewCompiler(t,view)
    assertOracleViewPayload(t,compiler,view,ResourceSelector{Resource:uri,Pointer:"/components/schemas/Root"},`{"value":"ok"}`,`{"value":"x"}`)
    for _,name:=range []string{"Scoped","Pointer"}{assertOracleViewPayload(t,compiler,view,ResourceSelector{Resource:uri,Pointer:"/components/schemas/"+name},"2","1")}
    assertOracleLocationPayload(t,oracleViewCompiler(t,view),"https://schemas.test/value#n","2","1")
    if resources[0].Source!=source||catalog.documents[uri].Raw()!=source{t.Fatal("oracle materialization mutated exact source")}
    reversed,err:=newOpenAPIProjectionCatalog([]Resource{resources[1],resources[0]},uri);if err!=nil{t.Fatal(err)};again,err:=newOpenAPIOracleView(reversed);if err!=nil{t.Fatal(err)};if !reflect.DeepEqual(view,again){t.Fatal("input order changed oracle view")}
    root,err:=view.selector(ResourceSelector{Resource:uri,Pointer:"/components/schemas/Root",TypeName:"Root"});if err!=nil||root.TypeName!="Root"{t.Fatal("selector lost its type name")}
    for _,resource:=range view.resources{if resource.URI!=uri{continue};document,err:=schemajson.Parse([]byte(resource.Source),schemajson.Limits{});if err!=nil{t.Fatal(err)};node,err:=document.At(root.Pointer);if err!=nil{t.Fatal(err)};if _,present:=node.Lookup("$id");present{t.Fatal("no-ID root acquired a new resource boundary")};examples,_:=node.Lookup("examples");if examples.Raw()!=`[{"$ref":"this is data","$id":"not a schema"}]`{t.Fatal("example was rewritten as schema")}}
    if _,err:=view.selector(ResourceSelector{Resource:uri,Pointer:"/info"});err==nil{t.Fatal("non-schema selector accepted")}
    if _,err:=compiler.Compile("https://unlisted.test/schema");err==nil{t.Fatal("unlisted offline resource accepted")}
}

func TestOpenAPIOracleViewPreservesDynamicScope(t *testing.T){
    uri:="https://example.test/api.json"
    // Local's anchor belongs to the same physical resource as Array. Moving
    // each component to a separately identified resource would lose it.
    source:=`{"openapi":"3.1.2","info":{"title":"Dynamic","version":"1"},"paths":{},"components":{"schemas":{"Array":{"type":"array","items":{"$dynamicRef":"#item"}},"Local":{"$dynamicAnchor":"item","type":"string","minLength":2},"Scoped":{"$id":"https://schemas.test/root","$dynamicAnchor":"meta","type":"object","properties":{"foo":{"const":"pass"}},"$ref":"extended","$defs":{"Extended":{"$id":"extended","$dynamicAnchor":"meta","type":"object","properties":{"bar":{"$ref":"bar"}}},"Bar":{"$id":"bar","type":"object","properties":{"baz":{"$dynamicRef":"extended#meta"}}}}}}}}`
    catalog,err:=newOpenAPIProjectionCatalog([]Resource{{URI:uri,Source:source}},uri);if err!=nil{t.Fatal(err)};view,err:=newOpenAPIOracleView(catalog);if err!=nil{t.Fatal(err)};compiler:=oracleViewCompiler(t,view)
    assertOracleViewPayload(t,compiler,view,ResourceSelector{Resource:uri,Pointer:"/components/schemas/Array"},`["aa"]`,`["x"]`)
    assertOracleViewPayload(t,compiler,view,ResourceSelector{Resource:uri,Pointer:"/components/schemas/Scoped"},`{"foo":"pass","bar":{"baz":{"foo":"pass"}}}`,`{"foo":"pass","bar":{"baz":{"foo":"fail"}}}`)
    assertOracleLocationPayload(t,oracleViewCompiler(t,view),"https://schemas.test/root",`{"foo":"pass","bar":{"baz":{"foo":"pass"}}}`,`{"foo":"pass","bar":{"baz":{"foo":"fail"}}}`)
}

func TestOpenAPIOracleViewChargesAggregateAliasesAndOutput(t *testing.T){
    uri:="https://example.test/api.json";source:=`{"openapi":"3.1.2","info":{"title":"Bounded","version":"1"},"paths":{},"components":{"schemas":{"Root":{"$id":"https://schemas.test/root","type":"string","description":"`+strings.Repeat("a",1000)+`"}}}}`
    catalog,err:=newOpenAPIProjectionCatalog([]Resource{{URI:uri,Source:source}},uri);if err!=nil{t.Fatal(err)};view,err:=newOpenAPIOracleView(catalog);if err!=nil{t.Fatal(err)};total:=0;for _,resource:=range append(append([]Resource(nil),view.resources...),view.aliases...){total+=len(resource.Source)}
    if _,err:=buildOpenAPIOracleView(catalog,total);err!=nil{t.Fatal(err)};if partial,err:=buildOpenAPIOracleView(catalog,total-1);problemCode(err)!="native.limit"||partial!=nil{t.Fatalf("aggregate bound returned partial output: %v %v",partial,err)}
}

func TestOpenAPIOracleViewRejectsOverlappingDataInterpretations(t *testing.T){
    uri:="https://example.test/api.json";fragment:="https://example.test/parts.json"
    for _,pointer:=range []string{"/Root/foo","/Root/data/Target"}{
        source:=`{"openapi":"3.1.2","info":{"title":"Ambiguous","version":"1"},"paths":{},"components":{"schemas":{"A":{"$ref":"parts.json#/Root"},"B":{"$ref":"parts.json#`+pointer+`"}}}}`
        parts:=`{"Root":{"type":"object","$defs":{"Value":{"type":"integer"}},"foo":{"$ref":"#/Root/$defs/Value"},"data":{"Target":{"$ref":"#/Root/$defs/Value"}}}}`
        catalog,err:=newOpenAPIProjectionCatalog([]Resource{{URI:uri,Source:source},{URI:fragment,Source:parts}},uri);if err!=nil{t.Fatal(err)}
        if view,err:=newOpenAPIOracleView(catalog);err==nil||view!=nil||!strings.Contains(err.Error(),"overlap opaque data"){t.Fatalf("overlapping interpretation %s did not fail closed: %v",pointer,err)}
    }
}

func TestOpenAPIOracleViewQuotesBeforeAllocatingEscapes(t *testing.T){
    for _,text:=range []string{"plain","\"\\\b\f\n\r\t\x00<>&\u2028\u2029é😀",string([]byte{0xff,0x80})}{
        expected,_:=json.Marshal(text);var out strings.Builder;writer:=&openAPIOracleWriter{limit:len(expected)}
        if err:=writer.quote(&out,text);err!=nil||out.String()!=string(expected)||writer.bytes!=len(expected){t.Fatalf("quote size mismatch: %v",err)}
        var blocked strings.Builder;writer=&openAPIOracleWriter{limit:len(expected)-1};if err:=writer.quote(&blocked,text);problemCode(err)!="native.limit"||blocked.Len()!=0||writer.bytes!=0{t.Fatalf("quote allocated output before admitting its escaped size: %v",err)}
    }
}

func TestOpenAPIOracleViewRetainsFragmentDialects(t *testing.T){
    uri:="https://example.test/api.json";fragment:="https://example.test/parts.json";draft:="https://json-schema.org/draft/2020-12/schema"
    source:=`{"openapi":"3.1.2","jsonSchemaDialect":"`+draft+`","info":{"title":"Dialect","version":"1"},"paths":{},"components":{"schemas":{"Root":{"$ref":"parts.json#/Value"}}}}`
    resources:=[]Resource{{URI:uri,Source:source},{URI:fragment,Source:`{"Value":{"type":"integer","minimum":2}}`}}
    catalog,err:=newOpenAPIProjectionCatalog(resources,uri);if err!=nil{t.Fatal(err)};view,err:=newOpenAPIOracleView(catalog);if err!=nil{t.Fatal(err)}
    for _,resource:=range view.resources{if resource.URI!=fragment{continue};document,err:=schemajson.Parse([]byte(resource.Source),schemajson.Limits{});if err!=nil{t.Fatal(err)};node,_:=document.Root().Lookup("$schema");if actual,_:=nodeString(node);actual!=draft{t.Fatalf("fragment lost inherited dialect: %s",actual)}}
    assertOracleViewPayload(t,oracleViewCompiler(t,view),view,ResourceSelector{Resource:uri,Pointer:"/components/schemas/Root"},"2","1")
    mixed:=`{"openapi":"3.1.2","info":{"title":"Mixed","version":"1"},"paths":{},"components":{"schemas":{"A":{"$ref":"parts.json#/A"},"B":{"$ref":"parts.json#/B"}}}}`
    resources=[]Resource{{URI:uri,Source:mixed},{URI:fragment,Source:`{"A":{"$schema":"`+draft+`","type":"string"},"B":{"type":"string"}}`}}
    catalog,err=newOpenAPIProjectionCatalog(resources,uri);if err!=nil{t.Fatal(err)};if view,err:=newOpenAPIOracleView(catalog);view!=nil||err==nil||!strings.Contains(err.Error(),"incompatible inherited schema dialects"){t.Fatalf("mixed scopes were silently collapsed: %v",err)}
}
