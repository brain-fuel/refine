package provenance

import (
    "fmt"
    "strings"
    "testing"
    "goforge.dev/refine/language"
    "goforge.dev/refine/schemajson"
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

func TestCollectionCardinalityCanonicalRoundTripAndOracle(t *testing.T){
    for _,kind:=range []string{"array","object"}{for _,edge:=range []string{"min","max"}{keyword:=edge+"Items";if kind=="object"{keyword=edge+"Properties"};for _,token:=range []string{"0","2","2.00","2e0","9007199254740993"}{
        t.Run(kind+"/"+keyword+"/"+token,func(t *testing.T){raw:=fmt.Sprintf(`{"type":%q,%q:%s}`,kind,keyword,token);origin:=discover(t,raw);constraints:=origin.Constraints();if len(constraints)!=1{t.Fatalf("constraints: %+v",constraints)};constraint:=constraints[0];source:=origin.ConstraintSource();program,err:=language.Compile(source);if err!=nil{t.Fatal(err)};if recovered,err:=origin.RecoverNative(constraint.Name,source);err!=nil||recovered!=token{t.Fatalf("exact original recovery: %q %v",recovered,err)};oracle:=nativeOracle(t,raw)
            for count:=0;count<5;count++{var data value.Data;var native any;if kind=="array"{items:=make([]value.Data,count);values:=make([]any,count);for i:=range items{items[i]=jsonNullData(t)};data=value.List(items);native=values}else{entries:=make([]value.MapEntry,count);object:=map[string]any{};for i:=range entries{name:=fmt.Sprintf("key%d",i);entries[i]=jsonEntry(t,name,jsonNullData(t));object[name]=nil};data,err=value.Map(entries);if err!=nil{t.Fatal(err)};native=object};actual:=validation.StateName(program.ValidateData(constraint.Name,data,validation.Limits{}).State())=="valid";expected:=oracle.Validate(native)==nil;if actual!=expected{t.Fatalf("count %d: language=%v native=%v",count,actual,expected)}}
        })
    }}}
}

func TestCollectionCardinalityIsolationShadowingAndBounds(t *testing.T){
    origin:=discover(t,`{"type":"array","minItems":1.0,"maxItems":4,"examples":[{"type":"array","minItems":9}],"properties":{"nested":{"type":"object","minProperties":2}}}`);if len(origin.Constraints())!=3{t.Fatalf("schema positions: %+v",origin.Constraints())};minimum,maximum:=find(t,origin,"/minItems"),find(t,origin,"/maxItems");source:=strings.Replace(origin.ConstraintSource(),minimum.Predicate,"length it >= 2",1);if _,err:=origin.RecoverNative(minimum.Name,source);err==nil{t.Fatal("edited count retained original guarantee")};if got,err:=origin.RecoverNative(maximum.Name,source);err!=nil||got!="4"{t.Fatalf("untouched count lost guarantee: %q %v",got,err)}
    shadowed:=origin.ConstraintSource()+"\nlength :: [JSON] -> Int\nlength _ = 0\n";findings,err:=origin.AuditSource(shadowed);if err!=nil{t.Fatal(err)};for _,finding:=range findings{expected:="changed";if finding.Constraint.Keyword=="minProperties"{expected="unchanged"};if StatusName(finding.Status)!=expected{t.Fatalf("builtin authority: %+v",finding)}}
    for _,raw:=range []string{`{"minItems":2}`,`{"type":["array","null"],"minItems":2}`,`{"type":"string","minLength":2}`,`{"type":"array","minItems":1e1000000000}`}{origin:=discover(t,raw);if len(origin.Constraints())!=0||origin.Original()!=raw{t.Fatalf("nonprojectable count not retained: %s",raw)}}
    for _,bound:=range []string{`-1`,`1.5`,`"2"`,`true`}{_,err:=DiscoverJSONSchema([]byte(`{"type":"array","minItems":`+bound+`}`),schemajson.Limits{});if err==nil||!strings.Contains(err.Error(),"native.cardinality"){t.Fatalf("invalid count %s: %v",bound,err)}}
}

func TestOpenAPICollectionCardinalityPreservesJSONAndYAMLTokens(t *testing.T){
    for _,fixture:=range []struct{syntax OpenAPISyntax;source string;token string}{
        {OpenAPIJSON,`{"openapi":"3.1.2","info":{"title":"Counts","version":"1"},"paths":{},"components":{"schemas":{"Items":{"type":"array","minItems":2.00,"maxItems":4}}}}`,"2.00"},
        {OpenAPIYAML,"openapi: 3.2.1\ninfo: {title: Counts, version: '1'}\npaths: {}\ncomponents:\n  schemas:\n    Items: {type: array, minItems: 0x02, maxItems: 4}\n","0x02"},
    }{origin,err:=DiscoverOpenAPI([]OpenAPIResource{{URI:"https://example.test/counts",Syntax:fixture.syntax,Role:OpenAPIDocument,Source:[]byte(fixture.source)}},OpenAPIOptions{EntryResource:"https://example.test/counts"});if err!=nil{t.Fatal(err)};if len(origin.Constraints())!=2{t.Fatalf("OpenAPI counts: %+v",origin.Constraints())};for _,constraint:=range origin.Constraints(){want:="4";if constraint.Keyword=="minItems"{want=fixture.token};if got,err:=origin.RecoverNative(constraint.Name,origin.ConstraintSource());err!=nil||got!=want{t.Fatalf("%s exact token %q: %v",constraint.Keyword,got,err)}}}
}

func TestOpenAPI30CollectionCardinalityRequiresNonnullableExplicitCollections(t *testing.T){
    fixtures:=[]struct{name string;syntax OpenAPISyntax;source string;want map[string]string}{
        {"json-array",OpenAPIJSON,`{"openapi":"3.0.4","info":{"title":"Counts","version":"1"},"paths":{},"components":{"schemas":{"Items":{"type":"array","nullable":false,"minItems":2.00,"maxItems":4}}}}`,map[string]string{"minItems":"2.00","maxItems":"4"}},
        {"yaml-object",OpenAPIYAML,"openapi: 3.0.4\ninfo: {title: Counts, version: '1'}\npaths: {}\ncomponents:\n  schemas:\n    Values: {type: object, minProperties: 0x02, maxProperties: 4}\n",map[string]string{"minProperties":"0x02","maxProperties":"4"}},
    }
    for _,fixture:=range fixtures{t.Run(fixture.name,func(t *testing.T){origin,err:=DiscoverOpenAPI([]OpenAPIResource{{URI:"https://example.test/oas30-counts",Syntax:fixture.syntax,Role:OpenAPIDocument,Source:[]byte(fixture.source)}},OpenAPIOptions{EntryResource:"https://example.test/oas30-counts"});if err!=nil{t.Fatal(err)};constraints:=origin.Constraints();if len(constraints)!=len(fixture.want){t.Fatalf("constraints: %+v",constraints)};for _,constraint:=range constraints{want,ok:=fixture.want[constraint.Keyword];if !ok{t.Fatalf("unexpected constraint: %+v",constraint)};if got,err:=origin.RecoverNative(constraint.Name,origin.ConstraintSource());err!=nil||got!=want{t.Fatalf("%s exact token %q: %v",constraint.Keyword,got,err)}}})}
    for _,schema:=range []string{`{"type":"array","nullable":true,"minItems":1}`,`{"type":"object","nullable":true,"minProperties":1}`,`{"type":"array","nullable":"false","minItems":1}`,`{"nullable":false,"minItems":1}`}{source:=`{"openapi":"3.0.4","info":{"title":"Counts","version":"1"},"paths":{},"components":{"schemas":{"Value":`+schema+`}}}`;origin,err:=DiscoverOpenAPI([]OpenAPIResource{{URI:"https://example.test/oas30-opaque",Syntax:OpenAPIJSON,Role:OpenAPIDocument,Source:[]byte(source)}},OpenAPIOptions{EntryResource:"https://example.test/oas30-opaque"});if err!=nil{t.Fatal(err)};if len(origin.Constraints())!=0{t.Fatalf("nullable/untyped count acquired a correspondence: %s %+v",schema,origin.Constraints())}}
}

func TestCollectionCardinalityChargesAggregateAttemptedExpansion(t *testing.T){
    large:=strings.Repeat("9",40000)
    // Both clauses are native-valid. The first has no useful projected scope,
    // but its attempted bigint work must still consume the aggregate budget.
    raw:=`{"$defs":{"ignored":{"type":"string","minItems":`+large+`},"limited":{"type":"array","minItems":`+large+`},"small":{"type":"array","maxItems":2}}}`
    origin:=discover(t,raw);if origin.numericExpansion!=40001||len(origin.Constraints())!=1||origin.Constraints()[0].Keyword!="maxItems"{t.Fatalf("attempted expansion was not bounded: work=%d count=%d",origin.numericExpansion,len(origin.Constraints()))};if origin.Original()!=raw{t.Fatal("bounded projection changed original")}
    api:=`{"openapi":"3.1.2","info":{"title":"Counts","version":"1"},"paths":{},"components":{"schemas":{"First":{"type":"array","minItems":`+large+`},"Second":{"type":"array","minItems":`+large+`},"Small":{"type":"object","maxProperties":2}}}}`
    projection,err:=DiscoverOpenAPI([]OpenAPIResource{{URI:"https://example.test/counts",Syntax:OpenAPIJSON,Role:OpenAPIDocument,Source:[]byte(api)}},OpenAPIOptions{EntryResource:"https://example.test/counts"});if err!=nil{t.Fatal(err)};if len(projection.Constraints())!=2{t.Fatalf("OpenAPI expansion reset per schema: %d constraints",len(projection.Constraints()))};for _,constraint:=range projection.Constraints(){if strings.Contains(constraint.Pointer,"/Second/"){t.Fatal("exhausted OpenAPI count acquired a projection")}}
}
