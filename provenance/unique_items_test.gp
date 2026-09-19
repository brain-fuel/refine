package provenance

import (
    "encoding/json"
    "strings"
    "testing"

    "goforge.dev/refine/language"
    "goforge.dev/refine/schemajson"
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

func TestUniqueItemsIntrinsicJSONMatchesNativeEquality(t *testing.T){
    origin:=discover(t,`{"type":"array","uniqueItems":true}`);constraints:=origin.Constraints();if len(constraints)!=1{t.Fatalf("constraints: %+v",constraints)};constraint:=constraints[0]
    if constraint.Scope!="[JSON]"||constraint.Keyword!="uniqueItems"||constraint.Native!="true"||len(constraint.Builtins)!=1||constraint.Builtins[0]!="unique"{t.Fatalf("constraint: %+v",constraint)}
    source:=origin.ConstraintSource();if recovered,err:=origin.RecoverNative(constraint.Name,source);err!=nil||recovered!="true"{t.Fatalf("exact recovery: %q %v",recovered,err)}
    program,err:=language.Compile(source);if err!=nil{t.Fatal(err)};oracle:=nativeOracle(t,origin.Original())
    cases:=[]struct{name string;items []value.Data;raw string}{
        {"equal-rationals",[]value.Data{jsonNumberData(t,"1"),jsonNumberData(t,"1.0")},`[1,1.0]`},
        {"object-order",[]value.Data{jsonObjectData(t,jsonEntry(t,"a",jsonNumberData(t,"1")),jsonEntry(t,"b",jsonNumberData(t,"2"))),jsonObjectData(t,jsonEntry(t,"b",jsonNumberData(t,"2.0")),jsonEntry(t,"a",jsonNumberData(t,"1.0")))},`[{"a":1,"b":2},{"b":2.0,"a":1.0}]`},
        {"array-order",[]value.Data{jsonArrayData(t,jsonNumberData(t,"1"),jsonNumberData(t,"2")),jsonArrayData(t,jsonNumberData(t,"2"),jsonNumberData(t,"1"))},`[[1,2],[2,1]]`},
        {"unicode-not-normalized",[]value.Data{jsonStringData(t,"é"),jsonStringData(t,"é")},`["é","é"]`},
    }
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){var native any;decoder:=json.NewDecoder(strings.NewReader(tc.raw));decoder.UseNumber();if err:=decoder.Decode(&native);err!=nil{t.Fatal(err)};expected:=oracle.Validate(native)==nil;report:=program.ValidateData(constraint.Name,value.List(tc.items),validation.Limits{});actual:=validation.StateName(report.State())=="valid";if actual!=expected{t.Fatalf("language=%v native=%v diagnostics=%+v",actual,expected,report.Diagnostics())}})}
}

func TestUniqueItemsProjectionIsExplicitDetachedAndShadowAware(t *testing.T){
    for _,raw:=range []string{`{"uniqueItems":true}`,`{"type":["array","null"],"uniqueItems":true}`,`{"type":"object","uniqueItems":true}`,`{"type":"array","uniqueItems":false}`}{origin:=discover(t,raw);if len(origin.Constraints())!=0||origin.Original()!=raw{t.Fatalf("invented uniqueness correspondence: %s %+v",raw,origin.Constraints())}}
    singleton:=discover(t,`{"type":["array"],"uniqueItems":true,"minItems":1}`);if len(singleton.Constraints())!=2{t.Fatalf("singleton array was not projected independently: %+v",singleton.Constraints())}
    unique:=find(t,singleton,"/uniqueItems");minimum:=find(t,singleton,"/minItems");source:=singleton.ConstraintSource()+"\nunique :: [JSON] -> Bool\nunique _ = True\n";findings,err:=singleton.AuditSource(source);if err!=nil{t.Fatal(err)};for _,finding:=range findings{expected:="unchanged";if finding.Constraint.Name==unique.Name{expected="changed"};if StatusName(finding.Status)!=expected{t.Fatalf("shadowing leaked across units: %+v",finding)}}
    if _,err:=singleton.RecoverNative(unique.Name,source);err==nil{t.Fatal("shadowed unique retained native authority")};if got,err:=singleton.RecoverNative(minimum.Name,source);err!=nil||got!="1"{t.Fatalf("unrelated count lost recovery: %q %v",got,err)}
    removed:=strings.Replace(singleton.ConstraintSource(),"type "+unique.Name+" = "+unique.Scope+" where "+unique.Predicate+"\n","",1);findings,err=singleton.AuditSource(removed);if err!=nil{t.Fatal(err)};for _,finding:=range findings{if finding.Constraint.Name==unique.Name&&StatusName(finding.Status)!="removed"{t.Fatalf("removed unique unit: %+v",finding)}}
    if _,err:=DiscoverJSONSchema([]byte(`{"type":"array","uniqueItems":"true"}`),schemajson.Limits{});err==nil||!strings.Contains(err.Error(),"native.unique_items"){t.Fatalf("non-Boolean uniqueItems accepted: %v",err)}
}

func TestOpenAPIUniqueItemsPreservesExactTrueAndNullableBoundary(t *testing.T){
    fixtures:=[]struct{syntax OpenAPISyntax;source string;token string;count int}{
        {OpenAPIJSON,`{"openapi":"3.1.2","info":{"title":"Unique","version":"1"},"paths":{},"components":{"schemas":{"Values":{"type":"array","uniqueItems":true}}}}`,"true",1},
        {OpenAPIYAML,"openapi: 3.2.1\ninfo: {title: Unique, version: '1'}\npaths: {}\ncomponents:\n  schemas:\n    Values: {type: array, uniqueItems: TRUE}\n","TRUE",1},
        {OpenAPIYAML,"openapi: 3.0.4\ninfo: {title: Unique, version: '1'}\npaths: {}\ncomponents:\n  schemas:\n    Values: {type: array, nullable: false, uniqueItems: true}\n","true",1},
        {OpenAPIYAML,"openapi: 3.0.4\ninfo: {title: Unique, version: '1'}\npaths: {}\ncomponents:\n  schemas:\n    Values: {type: array, nullable: true, uniqueItems: true}\n","",0},
    }
    for _,fixture:=range fixtures{origin,err:=DiscoverOpenAPI([]OpenAPIResource{{URI:"https://example.test/unique",Syntax:fixture.syntax,Role:OpenAPIDocument,Source:[]byte(fixture.source)}},OpenAPIOptions{EntryResource:"https://example.test/unique"});if err!=nil{t.Fatal(err)};constraints:=origin.Constraints();if len(constraints)!=fixture.count{t.Fatalf("constraints: %+v",constraints)};if fixture.count==1{constraint:=constraints[0];if constraint.Scope!="[JSON]"||constraint.Keyword!="uniqueItems"{t.Fatalf("constraint: %+v",constraint)};if got,err:=origin.RecoverNative(constraint.Name,origin.ConstraintSource());err!=nil||got!=fixture.token{t.Fatalf("exact token: %q %v",got,err)}}}
}
