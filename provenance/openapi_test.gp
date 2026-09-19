package provenance

import (
    "fmt"
    "reflect"
    "sort"
    "strings"
    "testing"

    "goforge.dev/refine/language"
    "goforge.dev/refine/schemajson"
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

const openAPIEntry="https://example.test/openapi.yaml"
func openAPIJSONResource(source string)OpenAPIResource{return OpenAPIResource{URI:openAPIEntry,Source:[]byte(source),Syntax:OpenAPIJSON,Role:OpenAPIDocument}}
func discoverOpenAPI(t *testing.T,resources []OpenAPIResource)*OpenAPI{t.Helper();found,err:=DiscoverOpenAPI(resources,OpenAPIOptions{EntryResource:openAPIEntry});if err!=nil{t.Fatal(err)};return found}
func openAPIConstraintAt(t *testing.T,projection *OpenAPI,pointer string)Constraint{t.Helper();for _,constraint:=range projection.Constraints(){if constraint.Pointer==pointer{return constraint}};t.Fatalf("missing %s in %+v",pointer,projection.Constraints());return Constraint{}}

func TestOpenAPIConstraintPositionsExcludeAnnotations(t *testing.T){
    cases:=[]struct{name string;member string;pointer string}{
        {"component-schema",`"components":{"schemas":{"X":{"type":"integer","minimum":1}}}`,`/components/schemas/X/minimum`},
        {"component-parameter",`"components":{"parameters":{"X":{"schema":{"type":"integer","minimum":1}}}}`, `/components/parameters/X/schema/minimum`},
        {"component-header",`"components":{"headers":{"X":{"schema":{"type":"integer","minimum":1}}}}`, `/components/headers/X/schema/minimum`},
        {"component-request-body",`"components":{"requestBodies":{"X":{"content":{"application/json":{"schema":{"type":"integer","minimum":1}}}}}}`, `/components/requestBodies/X/content/application~1json/schema/minimum`},
        {"component-response",`"components":{"responses":{"X":{"headers":{"Rate":{"schema":{"type":"integer","minimum":1}}}}}}`, `/components/responses/X/headers/Rate/schema/minimum`},
        {"component-path-item",`"components":{"pathItems":{"X":{"get":{"responses":{"200":{"content":{"application/json":{"schema":{"type":"integer","minimum":1}}}}}}}}}`, `/components/pathItems/X/get/responses/200/content/application~1json/schema/minimum`},
        {"path-parameter",`"paths":{"/x":{"parameters":[{"schema":{"type":"integer","minimum":1}}]}}`, `/paths/~1x/parameters/0/schema/minimum`},
        {"operation-parameter",`"paths":{"/x":{"get":{"parameters":[{"schema":{"type":"integer","minimum":1}}]}}}`, `/paths/~1x/get/parameters/0/schema/minimum`},
        {"request-media",`"paths":{"/x":{"post":{"requestBody":{"content":{"application/json":{"schema":{"type":"integer","minimum":1}}}}}}}`, `/paths/~1x/post/requestBody/content/application~1json/schema/minimum`},
        {"response-header",`"paths":{"/x":{"get":{"responses":{"200":{"headers":{"Rate":{"schema":{"type":"integer","minimum":1}}}}}}}}`, `/paths/~1x/get/responses/200/headers/Rate/schema/minimum`},
        {"response-media",`"paths":{"/x":{"get":{"responses":{"200":{"content":{"application/json":{"schema":{"type":"integer","minimum":1}}}}}}}}`, `/paths/~1x/get/responses/200/content/application~1json/schema/minimum`},
        {"callback",`"paths":{"/x":{"post":{"callbacks":{"done":{"{$request.body#/url}":{"post":{"requestBody":{"content":{"application/json":{"schema":{"type":"integer","minimum":1}}}}}}}}}}}`, `/paths/~1x/post/callbacks/done/{$request.body#~1url}/post/requestBody/content/application~1json/schema/minimum`},
        {"webhook",`"webhooks":{"changed":{"post":{"requestBody":{"content":{"application/json":{"schema":{"type":"integer","minimum":1}}}}}}}`, `/webhooks/changed/post/requestBody/content/application~1json/schema/minimum`},
    }
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){source:=`{"openapi":"3.1.2","info":{"title":"x","version":"1"},`+tc.member+`,"x-ignore":{"type":"integer","minimum":900},"examples":[{"type":"integer","minimum":901}],"default":{"type":"integer","minimum":902}}`;projection:=discoverOpenAPI(t,[]OpenAPIResource{openAPIJSONResource(source)});constraints:=projection.Constraints();if len(constraints)!=1||constraints[0].Pointer!=tc.pointer||constraints[0].Resource!=openAPIEntry{t.Fatalf("%+v",constraints)}})}
}

func TestOpenAPI32MediaAndEncodingSchemaPositions(t *testing.T){
    cases:=[]struct{name string;member string;pointer string}{
        {"component-media-type",`"components":{"mediaTypes":{"X":{"schema":{"type":"integer","minimum":1}}}}`,`/components/mediaTypes/X/schema/minimum`},
        {"item-schema",`"paths":{"/x":{"post":{"requestBody":{"content":{"multipart/mixed":{"itemSchema":{"type":"integer","minimum":1}}}}}}}`,`/paths/~1x/post/requestBody/content/multipart~1mixed/itemSchema/minimum`},
        {"encoding-header",`"paths":{"/x":{"post":{"requestBody":{"content":{"multipart/form-data":{"encoding":{"part":{"headers":{"X":{"schema":{"type":"integer","minimum":1}}}}}}}}}}}`,`/paths/~1x/post/requestBody/content/multipart~1form-data/encoding/part/headers/X/schema/minimum`},
        {"prefix-encoding-header",`"paths":{"/x":{"post":{"requestBody":{"content":{"multipart/mixed":{"prefixEncoding":[{"headers":{"X":{"schema":{"type":"integer","minimum":1}}}}]}}}}}}`, `/paths/~1x/post/requestBody/content/multipart~1mixed/prefixEncoding/0/headers/X/schema/minimum`},
        {"nested-encoding-header",`"paths":{"/x":{"post":{"requestBody":{"content":{"multipart/form-data":{"encoding":{"part":{"encoding":{"nested":{"headers":{"X":{"schema":{"type":"integer","minimum":1}}}}}}}}}}}}}`,`/paths/~1x/post/requestBody/content/multipart~1form-data/encoding/part/encoding/nested/headers/X/schema/minimum`},
        {"additional-operation",`"paths":{"/x":{"additionalOperations":{"COPY":{"responses":{"200":{"content":{"application/json":{"schema":{"type":"integer","minimum":1}}}}}}}}}`,`/paths/~1x/additionalOperations/COPY/responses/200/content/application~1json/schema/minimum`},
    }
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){source:=`{"openapi":"3.2.1","info":{"title":"x","version":"1"},`+tc.member+`}`;projection:=discoverOpenAPI(t,[]OpenAPIResource{openAPIJSONResource(source)});constraints:=projection.Constraints();if len(constraints)!=1||constraints[0].Pointer!=tc.pointer{t.Fatalf("%+v",constraints)}})}
}

func TestOpenAPIYAMLNumericLexemesAreExact(t *testing.T){
    source:="openapi: 3.2.1\ninfo: {title: x, version: '1'}\ncomponents: {x-é: ignored, schemas: {Hex: {type: integer, minimum: 0x10, maximum: 1_000}, Decimal: {type: number, exclusiveMinimum: .5, maximum: +1.5e+2}}}\n"
    projection:=discoverOpenAPI(t,[]OpenAPIResource{{URI:openAPIEntry,Source:[]byte(source),Syntax:OpenAPIYAML,Role:OpenAPIDocument}})
    expected:=map[string]struct{native string;predicate string}{
        "/components/schemas/Hex/minimum":{"0x10","(it >= 16)"},
        "/components/schemas/Hex/maximum":{"1_000","(it <= 1000)"},
        "/components/schemas/Decimal/exclusiveMinimum":{".5","(it > 0.5)"},
        "/components/schemas/Decimal/maximum":{"+1.5e+2","(it <= 1.5e2)"},
    }
    if len(projection.Constraints())!=len(expected){t.Fatalf("%+v",projection.Constraints())};for path,want:=range expected{constraint:=openAPIConstraintAt(t,projection,path);if constraint.Native!=want.native||constraint.Predicate!=want.predicate{t.Fatalf("%s: %+v",path,constraint)};got,err:=projection.RecoverNative(constraint.Name,projection.ConstraintSource());if err!=nil||got!=want.native{t.Fatalf("%s recovery %q: %v",path,got,err)}}
    resources:=projection.Resources();resources[0].Source[0]='X';if string(projection.Resources()[0].Source)!=source{t.Fatal("resource bytes alias caller-visible storage")}
}

func TestOpenAPIExplicitResourcesReferencesAndIDs(t *testing.T){
    entry:=openAPIJSONResource(`{"openapi":"3.1.2","info":{"title":"x","version":"1"},"paths":{"/x":{"get":{"responses":{"200":{"$ref":"parts.json#/response"}}}}},"components":{"schemas":{"Local":{"$id":"https://schema.test/local","$defs":{"N":{"type":"integer","minimum":3}},"$ref":"#/$defs/N"},"External":{"$ref":"schema.json"}}}}`)
    fragment:=OpenAPIResource{URI:"https://example.test/parts.json",Source:[]byte(`{"response":{"content":{"application/json":{"schema":{"type":"integer","maximum":9}}}},"unreferenced":{"type":"integer","minimum":800}}`),Syntax:OpenAPIJSON,Role:OpenAPIFragment}
    schema:=OpenAPIResource{URI:"https://example.test/schema.json",Source:[]byte(`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"integer","exclusiveMinimum":1}`),Syntax:OpenAPIJSON,Role:OpenAPISchema,Dialect:jsonSchema202012}
    projection:=discoverOpenAPI(t,[]OpenAPIResource{fragment,schema,entry});paths:=[]string{};for _,constraint:=range projection.Constraints(){paths=append(paths,constraint.Resource+"#"+constraint.Pointer)};sort.Strings(paths);want:=[]string{"https://example.test/openapi.yaml#/components/schemas/Local/$defs/N/minimum","https://example.test/parts.json#/response/content/application~1json/schema/maximum","https://example.test/schema.json#/exclusiveMinimum"};if !reflect.DeepEqual(paths,want){t.Fatalf("%v",paths)}
    reversed:=discoverOpenAPI(t,[]OpenAPIResource{entry,schema,fragment});if !reflect.DeepEqual(projection.Constraints(),reversed.Constraints()){t.Fatal("resource input order changed identities or findings")}
    chainedEntry:=openAPIJSONResource(`{"openapi":"3.1.2","info":{"title":"x","version":"1"},"components":{"schemas":{"External":{"$ref":"first.json#/root"}}}}`);first:=OpenAPIResource{URI:"https://example.test/first.json",Source:[]byte(`{"root":{"$ref":"nested.json#/schema"}}`),Syntax:OpenAPIJSON,Role:OpenAPIFragment};nested:=OpenAPIResource{URI:"https://example.test/nested.json",Source:[]byte(`{"schema":{"type":"integer","minimum":7}}`),Syntax:OpenAPIJSON,Role:OpenAPIFragment};chained:=discoverOpenAPI(t,[]OpenAPIResource{chainedEntry,first,nested});constraint:=openAPIConstraintAt(t,chained,"/schema/minimum");if constraint.Resource!=nested.URI{t.Fatalf("nested relative ref retained caller base: %+v",constraint)}
}

func TestOpenAPIWrapperReferencesAreChainedWithoutDroppingSiblings(t *testing.T){
    entry:=openAPIJSONResource(`{"openapi":"3.1.2","info":{"title":"x","version":"1"},"paths":{"/x":{"get":{"responses":{"200":{"$ref":"parts.json#/first"}}}}}}`)
    fragment:=OpenAPIResource{URI:"https://example.test/parts.json",Source:[]byte(`{"first":{"$ref":"#/second","summary":"allowed annotation"},"second":{"content":{"application/json":{"schema":{"type":"integer","minimum":4}}}}}`),Syntax:OpenAPIJSON,Role:OpenAPIFragment}
    projection:=discoverOpenAPI(t,[]OpenAPIResource{entry,fragment});constraint:=openAPIConstraintAt(t,projection,"/second/content/application~1json/schema/minimum");if constraint.Resource!=fragment.URI{t.Fatalf("%+v",constraint)}
    bad:=openAPIJSONResource(`{"openapi":"3.1.2","info":{"title":"x","version":"1"},"paths":{"/x":{"$ref":"#/components/pathItems/X","get":{"responses":{}}}},"components":{"pathItems":{"X":{}}}}`);if _,err:=DiscoverOpenAPI([]OpenAPIResource{bad},OpenAPIOptions{EntryResource:openAPIEntry});err==nil||!strings.Contains(err.Error(),"structural siblings"){t.Fatalf("meaningful wrapper sibling was silently discarded: %v",err)}
    cycleFragment:=OpenAPIResource{URI:"https://example.test/cycle.json",Source:[]byte(`{"a":{"$ref":"#/b"},"b":{"$ref":"#/a"}}`),Syntax:OpenAPIJSON,Role:OpenAPIFragment};cycleEntry:=openAPIJSONResource(`{"openapi":"3.1.2","info":{"title":"x","version":"1"},"paths":{"/x":{"get":{"responses":{"200":{"$ref":"cycle.json#/a"}}}}}}`);if _,err:=DiscoverOpenAPI([]OpenAPIResource{cycleEntry,cycleFragment},OpenAPIOptions{EntryResource:openAPIEntry});err==nil||!strings.Contains(err.Error(),"cyclic wrapper"){t.Fatalf("wrapper reference cycle was not bounded: %v",err)}
}

func TestOpenAPIJSONConstEnumAndAudit(t *testing.T){
    source:=`{"openapi":"3.1.2","info":{"title":"x","version":"1"},"components":{"schemas":{"Exact":{"const":{"b":[1],"a":"e\u0301"},"enum":[]}}}}`
    projection:=discoverOpenAPI(t,[]OpenAPIResource{openAPIJSONResource(source)});if len(projection.Constraints())!=2{t.Fatalf("%+v",projection.Constraints())};constant:=openAPIConstraintAt(t,projection,"/components/schemas/Exact/const");enumeration:=openAPIConstraintAt(t,projection,"/components/schemas/Exact/enum");if constant.Scope!="JSON"||enumeration.Predicate!="((oneOf it) [])"||enumeration.Native!="[]"{t.Fatalf("%+v %+v",constant,enumeration)};program,err:=language.Compile(projection.ConstraintSource());if err!=nil{t.Fatal(err)};number,_:=value.ParseNumber("1");list,err:=value.Variant("JSONArray",[]value.Data{value.List([]value.Data{func()value.Data{v,_:=value.Variant("JSONNumber",[]value.Data{value.OfNumber(number)});return v}()})});if err!=nil{t.Fatal(err)};mapping,err:=value.Map([]value.MapEntry{jsonEntry(t,"a",jsonStringData(t,"é")),jsonEntry(t,"b",list)});if err!=nil{t.Fatal(err)};candidate,err:=value.Variant("JSONObject",[]value.Data{mapping});if err!=nil{t.Fatal(err)};if validation.StateName(program.ValidateData(constant.Name,candidate,validation.Limits{}).State())!="valid"{t.Fatal("JSON const canonical predicate changed semantics")}
    shadowed:=projection.ConstraintSource()+"\noneOf :: JSON -> [JSON] -> Bool\noneOf _ _ = True\n";findings,err:=projection.AuditSource(shadowed);if err!=nil{t.Fatal(err)};states:=map[string]string{};for _,finding:=range findings{states[finding.Constraint.Keyword]=StatusName(finding.Status)};if states["const"]!="unchanged"||states["enum"]!="changed"{t.Fatalf("%v",states)}
}

func TestOpenAPIProvenanceRejectsAmbiguousAuthorityAndBounds(t *testing.T){
    base:=`{"openapi":"3.1.2","info":{"title":"x","version":"1"},"components":{"schemas":{"X":{"type":"integer","minimum":1}}}}`
    cases:=[]struct{name string;resources []OpenAPIResource;options OpenAPIOptions;code string}{
        {"oas2",[]OpenAPIResource{{URI:openAPIEntry,Source:[]byte(strings.Replace(base,"3.1.2","2.0.0",1)),Syntax:OpenAPIJSON,Role:OpenAPIDocument}},OpenAPIOptions{EntryResource:openAPIEntry},"openapi.version"},
        {"dialect",[]OpenAPIResource{{URI:openAPIEntry,Source:[]byte(strings.Replace(base,`"info"`,`"jsonSchemaDialect":"https://example.test/custom","info"`,1)),Syntax:OpenAPIJSON,Role:OpenAPIDocument}},OpenAPIOptions{EntryResource:openAPIEntry},"openapi.dialect"},
        {"anchor",[]OpenAPIResource{{URI:openAPIEntry,Source:[]byte(strings.Replace(base,`"type":"integer"`,`"$anchor":"x","type":"integer"`,1)),Syntax:OpenAPIJSON,Role:OpenAPIDocument}},OpenAPIOptions{EntryResource:openAPIEntry},"openapi.reference"},
        {"dynamic-ref",[]OpenAPIResource{{URI:openAPIEntry,Source:[]byte(strings.Replace(base,`"type":"integer"`,`"$dynamicRef":"#x","type":"integer"`,1)),Syntax:OpenAPIJSON,Role:OpenAPIDocument}},OpenAPIOptions{EntryResource:openAPIEntry},"openapi.reference"},
        {"missing-ref",[]OpenAPIResource{{URI:openAPIEntry,Source:[]byte(strings.Replace(base,`"type":"integer","minimum":1`,`"$ref":"missing.json"`,1)),Syntax:OpenAPIJSON,Role:OpenAPIDocument}},OpenAPIOptions{EntryResource:openAPIEntry},"openapi.reference"},
        {"node-limit",[]OpenAPIResource{{URI:openAPIEntry,Source:[]byte(base),Syntax:OpenAPIJSON,Role:OpenAPIDocument}},OpenAPIOptions{EntryResource:openAPIEntry,Limits:schemajson.Limits{Nodes:3}},"json.limit"},
        {"aggregate-bytes",[]OpenAPIResource{{URI:openAPIEntry,Source:[]byte(`{}`),Syntax:OpenAPIJSON,Role:OpenAPIDocument},{URI:"https://example.test/part.json",Source:[]byte(`{}`),Syntax:OpenAPIJSON,Role:OpenAPIFragment}},OpenAPIOptions{EntryResource:openAPIEntry,Limits:schemajson.Limits{Bytes:3}},"openapi.limit"},
        {"fragment-entry",[]OpenAPIResource{{URI:openAPIEntry,Source:[]byte(`{}`),Syntax:OpenAPIJSON,Role:OpenAPIFragment}},OpenAPIOptions{EntryResource:openAPIEntry},"openapi.resources"},
    }
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){_,err:=DiscoverOpenAPI(tc.resources,tc.options);if err==nil||!strings.Contains(err.Error(),tc.code){t.Fatalf("%v",err)}})}
    forwardID:=strings.Replace(base,`"components":{"schemas":{`,`"components":{"schemas":{"A":{"$ref":"https://schema.test/b"},"B":{"$id":"https://schema.test/b","type":"integer","minimum":2},`,1);if _,err:=DiscoverOpenAPI([]OpenAPIResource{openAPIJSONResource(forwardID)},OpenAPIOptions{EntryResource:openAPIEntry});err==nil||!strings.Contains(err.Error(),"logical $id"){t.Fatalf("forward logical ID was traversal-order dependent: %v",err)}
}

func TestOpenAPIProvenanceIdentityFramesResourceAndPointer(t *testing.T){
    schema:=func(uri string)OpenAPIResource{return OpenAPIResource{URI:uri,Source:[]byte(`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"integer","minimum":1}`),Syntax:OpenAPIJSON,Role:OpenAPISchema,Dialect:jsonSchema202012}}
    projection:=discoverOpenAPI(t,[]OpenAPIResource{openAPIJSONResource(`{"openapi":"3.2.1","info":{"title":"x","version":"1"}}`),schema("https://example.test/a"),schema("https://example.test/aa")});constraints:=projection.Constraints();if len(constraints)!=2||constraints[0].Name==constraints[1].Name{t.Fatalf("ambiguous resource identity: %+v",constraints)};for _,constraint:=range constraints{if !strings.HasPrefix(constraint.Name,"Native_")||len(constraint.Fingerprint)!=64{t.Fatalf("%+v",constraint)}}
}
