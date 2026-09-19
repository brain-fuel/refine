package provenance

import (
    "strings"
    "testing"

    "goforge.dev/refine/language"
    "goforge.dev/refine/validation"
)

func TestOpenAPI30JSONEnumPreservesOrderedTokenAndNullableSemantics(t *testing.T){
    source:=`{"openapi":"3.0.4","info":{"title":"Enum","version":"1"},"paths":{},"components":{"schemas":{"Value":{"type":"string","nullable":true,"enum":["x",null],"const":"unsupported"}}}}`;origin,err:=DiscoverOpenAPI([]OpenAPIResource{{URI:"https://example.test/enum",Syntax:OpenAPIJSON,Role:OpenAPIDocument,Source:[]byte(source)}},OpenAPIOptions{EntryResource:"https://example.test/enum"});if err!=nil{t.Fatal(err)};constraints:=origin.Constraints();if len(constraints)!=1{t.Fatalf("constraints: %+v",constraints)};constraint:=constraints[0];if constraint.Keyword!="enum"||constraint.Scope!="JSON"||constraint.Native!=`["x",null]`||!strings.Contains(constraint.Predicate,"oneOf"){t.Fatalf("enum constraint: %+v",constraint)};if strings.Contains(origin.ConstraintSource(),"const"){t.Fatal("OpenAPI 3.0 const acquired unsupported authority")};if recovered,err:=origin.RecoverNative(constraint.Name,origin.ConstraintSource());err!=nil||recovered!=`["x",null]`{t.Fatalf("ordered token recovery: %q %v",recovered,err)}
    program,err:=language.Compile(origin.ConstraintSource());if err!=nil{t.Fatal(err)}
    for _,candidate:=range []struct{valid bool;useNull bool;text string}{{true,false,"x"},{true,true,""},{false,false,"y"}}{data:=jsonStringData(t,candidate.text);if candidate.useNull{data=jsonNullData(t)};report:=program.ValidateData(constraint.Name,data,validation.Limits{});if (validation.StateName(report.State())=="valid")!=candidate.valid{t.Fatalf("candidate null=%t text=%q: %+v",candidate.useNull,candidate.text,report.Diagnostics())}}
}

func TestOpenAPI30EnumIgnoresReferenceSiblingsAndYAML(t *testing.T){
    source:=`{"openapi":"3.0.4","info":{"title":"Enum","version":"1"},"paths":{},"components":{"schemas":{"Base":{"type":"string","enum":["base"]},"Alias":{"$ref":"#/components/schemas/Base","enum":["ignored"]}}}}`;origin,err:=DiscoverOpenAPI([]OpenAPIResource{{URI:"https://example.test/ref-enum",Syntax:OpenAPIJSON,Role:OpenAPIDocument,Source:[]byte(source)}},OpenAPIOptions{EntryResource:"https://example.test/ref-enum"});if err!=nil{t.Fatal(err)};constraints:=origin.Constraints();if len(constraints)!=1||constraints[0].SchemaPointer!="/components/schemas/Base"||constraints[0].Native!=`["base"]`{t.Fatalf("ignored Reference Object sibling acquired authority: %+v",constraints)}
    yamlSource:="openapi: 3.0.4\ninfo: {title: Enum, version: '1'}\npaths: {}\ncomponents:\n  schemas:\n    Value: {type: string, enum: [x, y]}\n";yamlOrigin,err:=DiscoverOpenAPI([]OpenAPIResource{{URI:"https://example.test/yaml-enum",Syntax:OpenAPIYAML,Role:OpenAPIDocument,Source:[]byte(yamlSource)}},OpenAPIOptions{EntryResource:"https://example.test/yaml-enum"});if err!=nil{t.Fatal(err)};if len(yamlOrigin.Constraints())!=0{t.Fatalf("YAML enum acquired JSON-only authority: %+v",yamlOrigin.Constraints())}
}
