package provenance

import (
    "reflect"
    "strings"
    "testing"

    "goforge.dev/refine/schemajson"
)

func indexOpenAPIRoots(t *testing.T,resources []OpenAPIResource)[]OpenAPISchemaRoot{t.Helper();roots,err:=IndexOpenAPISchemaRoots(resources,OpenAPIOptions{EntryResource:openAPIEntry});if err!=nil{t.Fatal(err)};return roots}

func TestOpenAPISchemaRootIndexCoversWrapperRoles(t *testing.T){
    cases:=[]struct{name,member,pointer string}{
        {"component",`"components":{"schemas":{"X":{"type":"integer"}}}`,`/components/schemas/X`},
        {"parameter",`"paths":{"/x":{"get":{"parameters":[{"name":"q","in":"query","schema":{"type":"integer"}}]}}}`,`/paths/~1x/get/parameters/0/schema`},
        {"response-header",`"paths":{"/x":{"get":{"responses":{"200":{"headers":{"Rate":{"schema":{"type":"integer"}}}}}}}}`,`/paths/~1x/get/responses/200/headers/Rate/schema`},
        {"media",`"paths":{"/x":{"post":{"requestBody":{"content":{"application/json":{"schema":{"type":"integer"}}}}}}}`,`/paths/~1x/post/requestBody/content/application~1json/schema`},
        {"callback",`"paths":{"/x":{"post":{"callbacks":{"done":{"{$request.body#/url}":{"post":{"requestBody":{"content":{"application/json":{"schema":{"type":"integer"}}}}}}}}}}}`,`/paths/~1x/post/callbacks/done/{$request.body#~1url}/post/requestBody/content/application~1json/schema`},
        {"webhook",`"webhooks":{"changed":{"post":{"requestBody":{"content":{"application/json":{"schema":{"type":"integer"}}}}}}}`,`/webhooks/changed/post/requestBody/content/application~1json/schema`},
        {"item-schema",`"paths":{"/x":{"post":{"requestBody":{"content":{"multipart/mixed":{"itemSchema":{"type":"integer"}}}}}}}`,`/paths/~1x/post/requestBody/content/multipart~1mixed/itemSchema`},
    }
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){source:=`{"openapi":"3.2.1","info":{"title":"x","version":"1"},`+tc.member+`,"examples":[{"schema":{"type":"string"}}],"default":{"schema":{"type":"string"}},"x-lookalike":{"schema":{"type":"string"}}}`;roots:=indexOpenAPIRoots(t,[]OpenAPIResource{openAPIJSONResource(source)});want:=[]OpenAPISchemaRoot{{Resource:openAPIEntry,Pointer:tc.pointer,Dialect:openAPIBase}};if !reflect.DeepEqual(roots,want){t.Fatalf("%+v",roots)}})}
}

func TestOpenAPISchemaRootIndexResolvesOnlyWrapperReferences(t *testing.T){
    entry:=openAPIJSONResource(`{"openapi":"3.1.2","info":{"title":"x","version":"1"},"paths":{"/a":{"get":{"responses":{"200":{"$ref":"#/components/responses/R"},"201":{"$ref":"#/components/responses/R"}}}}},"components":{"responses":{"R":{"$ref":"parts.json#/response"}}}}`)
    fragment:=OpenAPIResource{URI:"https://example.test/parts.json",Source:[]byte(`{"response":{"content":{"application/json":{"schema":{"type":"integer"}}}},"unreferenced":{"schema":{"type":"string"}}}`),Syntax:OpenAPIJSON,Role:OpenAPIFragment}
    schema:=OpenAPIResource{URI:"https://example.test/schema.json",Source:[]byte(`{"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"nested","$dynamicAnchor":"node","$dynamicRef":"#node","$ref":"missing.json"}`),Syntax:OpenAPIJSON,Role:OpenAPISchema,Dialect:jsonSchema202012}
    roots:=indexOpenAPIRoots(t,[]OpenAPIResource{schema,entry,fragment});want:=[]OpenAPISchemaRoot{{Resource:fragment.URI,Pointer:"/response/content/application~1json/schema",Dialect:openAPIBase},{Resource:schema.URI,Pointer:"",Dialect:jsonSchema202012}};if !reflect.DeepEqual(roots,want){t.Fatalf("sorted/deduplicated roots changed: %+v",roots)}
}

func TestOpenAPISchemaRootIndexLeavesSchemaReferencesOpaque(t *testing.T){
    source:=`{"openapi":"3.2.1","info":{"title":"x","version":"1"},"components":{"schemas":{"Opaque":{"$id":"https://schemas.test/opaque","$anchor":"static","$dynamicAnchor":"dynamic","$dynamicRef":"#dynamic","$ref":"absent.json","properties":{"ignored":{"$ref":"also-absent.json"}}}}}}`
    roots:=indexOpenAPIRoots(t,[]OpenAPIResource{openAPIJSONResource(source)});want:=[]OpenAPISchemaRoot{{Resource:openAPIEntry,Pointer:"/components/schemas/Opaque",Dialect:openAPIBase}};if !reflect.DeepEqual(roots,want){t.Fatalf("Schema Object internals were traversed: %+v",roots)}
}

func TestOpenAPISchemaRootIndexKeepsWrapperFailuresAndBounds(t *testing.T){
    bad:=openAPIJSONResource(`{"openapi":"3.1.2","info":{"title":"x","version":"1"},"paths":{"/x":{"$ref":"#/components/pathItems/X","get":{"responses":{}}}},"components":{"pathItems":{"X":{}}}}`);if _,err:=IndexOpenAPISchemaRoots([]OpenAPIResource{bad},OpenAPIOptions{EntryResource:openAPIEntry});err==nil||!strings.Contains(err.Error(),"structural siblings"){t.Fatalf("wrapper sibling semantics changed: %v",err)}
    fragment:=OpenAPIResource{URI:"https://example.test/cycle.json",Source:[]byte(`{"a":{"$ref":"#/b"},"b":{"$ref":"#/a"}}`),Syntax:OpenAPIJSON,Role:OpenAPIFragment};cycle:=openAPIJSONResource(`{"openapi":"3.1.2","info":{"title":"x","version":"1"},"paths":{"/x":{"get":{"responses":{"200":{"$ref":"cycle.json#/a"}}}}}}`);if _,err:=IndexOpenAPISchemaRoots([]OpenAPIResource{cycle,fragment},OpenAPIOptions{EntryResource:openAPIEntry});err==nil||!strings.Contains(err.Error(),"cyclic wrapper"){t.Fatalf("wrapper cycle semantics changed: %v",err)}
    bounded:=openAPIJSONResource(`{"openapi":"3.1.2","info":{"title":"x","version":"1"},"components":{"schemas":{"A":{"type":"integer"},"B":{"type":"string"}}}}`);if _,err:=indexOpenAPISchemaRootsWithPathLimit([]OpenAPIResource{bounded},OpenAPIOptions{EntryResource:openAPIEntry},64);err==nil||!strings.Contains(err.Error(),"retained paths"){t.Fatalf("retained wrapper paths were not bounded: %v",err)}
}

func TestOpenAPISchemaRootIndexUsesEveryDocumentContext(t *testing.T){
    shared:=OpenAPIResource{URI:"https://example.test/shared.json",Source:[]byte(`{"response":{"content":{"multipart/mixed":{"itemSchema":{"type":"integer"}}}}}`),Syntax:OpenAPIJSON,Role:OpenAPIFragment}
    entry:=openAPIJSONResource(`{"openapi":"3.1.2","paths":{"/entry":{"get":{"responses":{"200":{"$ref":"shared.json#/response"}}}}}}`)
    secondary32:=OpenAPIResource{URI:"https://example.test/secondary-32.json",Source:[]byte(`{"openapi":"3.2.0","paths":{"/secondary":{"get":{"responses":{"200":{"$ref":"shared.json#/response"}}}}}}`),Syntax:OpenAPIJSON,Role:OpenAPIDocument}
    secondary31:=OpenAPIResource{URI:"https://example.test/secondary-31.json",Source:[]byte(`{"openapi":"3.1.2","jsonSchemaDialect":"https://json-schema.org/draft/2020-12/schema","components":{"schemas":{"Own":{"type":"string"}}}}`),Syntax:OpenAPIJSON,Role:OpenAPIDocument}
    roots:=indexOpenAPIRoots(t,[]OpenAPIResource{entry,shared,secondary32,secondary31});want:=[]OpenAPISchemaRoot{{Resource:secondary31.URI,Pointer:"/components/schemas/Own",Dialect:jsonSchema202012},{Resource:shared.URI,Pointer:"/response/content/multipart~1mixed/itemSchema",Dialect:openAPIBase}};if !reflect.DeepEqual(roots,want){t.Fatalf("document-local version/dialect indexing changed: %+v",roots)}
}

func TestOpenAPISchemaRootIndexWrapperDocumentAndFragmentContexts(t *testing.T){
    target:=OpenAPIResource{URI:"https://example.test/target.json",Source:[]byte(`{"openapi":"3.1.2","components":{"responses":{"R":{"content":{"multipart/mixed":{"schema":{"type":"string"},"itemSchema":{"type":"integer"}}}}}}}`),Syntax:OpenAPIJSON,Role:OpenAPIDocument}
    entry:=openAPIJSONResource(`{"openapi":"3.2.0","paths":{"/x":{"get":{"responses":{"200":{"$ref":"target.json#/components/responses/R"}}}}}}`)
    roots:=indexOpenAPIRoots(t,[]OpenAPIResource{entry,target});want:=[]OpenAPISchemaRoot{{Resource:target.URI,Pointer:"/components/responses/R/content/multipart~1mixed/schema",Dialect:openAPIBase}};if !reflect.DeepEqual(roots,want){t.Fatalf("wrapper target did not use its document context: %+v",roots)}

    shared:=OpenAPIResource{URI:"https://example.test/shared-context.json",Source:[]byte(`{"response":{"content":{"application/json":{"schema":{"type":"integer"}}}}}`),Syntax:OpenAPIJSON,Role:OpenAPIFragment}
    draft:=OpenAPIResource{URI:"https://example.test/draft-document.json",Source:[]byte(`{"openapi":"3.1.2","jsonSchemaDialect":"https://json-schema.org/draft/2020-12/schema","paths":{"/x":{"get":{"responses":{"200":{"$ref":"shared-context.json#/response"}}}}}}`),Syntax:OpenAPIJSON,Role:OpenAPIDocument}
    base:=openAPIJSONResource(`{"openapi":"3.1.2","paths":{"/x":{"get":{"responses":{"200":{"$ref":"shared-context.json#/response"}}}}}}`)
    roots=indexOpenAPIRoots(t,[]OpenAPIResource{base,draft,shared});want=[]OpenAPISchemaRoot{{Resource:shared.URI,Pointer:"/response/content/application~1json/schema",Dialect:jsonSchema202012},{Resource:shared.URI,Pointer:"/response/content/application~1json/schema",Dialect:openAPIBase}};if !reflect.DeepEqual(roots,want){t.Fatalf("untyped fragment contexts were collapsed: %+v",roots)}
}

func TestOpenAPISchemaRootIndexDocumentContextWorkIsAggregate(t *testing.T){
    first:=OpenAPIResource{URI:openAPIEntry,Source:[]byte(`{"openapi":"3.1.2"}`),Syntax:OpenAPIJSON,Role:OpenAPIDocument};second:=OpenAPIResource{URI:"https://example.test/second.json",Source:[]byte(`{"openapi":"3.1.2"}`),Syntax:OpenAPIJSON,Role:OpenAPIDocument}
    if _,err:=IndexOpenAPISchemaRoots([]OpenAPIResource{first,second},OpenAPIOptions{EntryResource:openAPIEntry,Limits:schemajson.Limits{Nodes:6}});err==nil||!strings.Contains(err.Error(),"document-context work limit"){t.Fatalf("document context work budget reset per resource: %v",err)}
}
