package provenance

import (
    "strings"
    "testing"

    "goforge.dev/refine/schemajson"
)

func openAPI30Document(source string,syntax OpenAPISyntax)OpenAPIResource{return OpenAPIResource{URI:"https://example.test/api",Source:[]byte(source),Syntax:syntax,Role:OpenAPIDocument}}

func TestOpenAPI30PairedBoundsPreserveExactTokensAndAuditAtomically(t *testing.T){
    source:="openapi: 3.0.4\ninfo: {title: Bounds, version: '1'}\ncomponents:\n  schemas:\n    Value:\n      type: number\n      minimum: +1.50e+2\n      exclusiveMinimum: TRUE\n      maximum: 0x100\n      exclusiveMaximum: false\n"
    projection,err:=DiscoverOpenAPI([]OpenAPIResource{openAPI30Document(source,OpenAPIYAML)},OpenAPIOptions{EntryResource:"https://example.test/api"});if err!=nil{t.Fatal(err)};constraints:=projection.Constraints();if len(constraints)!=2{t.Fatalf("%+v",constraints)}
    minimum:=openAPIConstraintAt(t,projection,"/components/schemas/Value/minimum");maximum:=openAPIConstraintAt(t,projection,"/components/schemas/Value/maximum")
    if minimum.Native!="+1.50e+2"||minimum.PairedKeyword!="exclusiveMinimum"||minimum.PairedNative!="TRUE"||minimum.Predicate!="(it > 1.50e2)"{t.Fatalf("minimum token pair changed: %+v",minimum)}
    if maximum.Native!="0x100"||maximum.PairedKeyword!="exclusiveMaximum"||maximum.PairedNative!="false"||maximum.Predicate!="(it <= (256 / 1))"{t.Fatalf("maximum token pair changed: %+v",maximum)}
    if got,err:=projection.RecoverNative(minimum.Name,projection.ConstraintSource());err!=nil||got!=minimum.Native{t.Fatalf("unchanged primary token recovery %q: %v",got,err)}
    edited:=strings.Replace(projection.ConstraintSource(),minimum.Predicate,"(it >= (151 / 1))",1);findings,err:=projection.AuditSource(edited);if err!=nil{t.Fatal(err)};states:=map[string]string{};for _,finding:=range findings{states[finding.Constraint.Keyword]=StatusName(finding.Status)};if states["minimum"]!="changed"||states["maximum"]!="unchanged"{t.Fatalf("paired edit disturbed the opposite bound: %v",states)}
}

func TestOpenAPI30PairedBoundsRejectInvalidMembersAndScopeExternalResources(t *testing.T){
    invalid:=[]string{
        `{"openapi":"3.0.4","info":{"title":"x","version":"1"},"components":{"schemas":{"X":{"type":"number","minimum":"1"}}}}`,
        `{"openapi":"3.0.4","info":{"title":"x","version":"1"},"components":{"schemas":{"X":{"type":"number","minimum":1,"exclusiveMinimum":1}}}}`,
    }
    for _,source:=range invalid{if _,err:=DiscoverOpenAPI([]OpenAPIResource{openAPI30Document(source,OpenAPIJSON)},OpenAPIOptions{EntryResource:"https://example.test/api"});err==nil||!strings.Contains(err.Error(),"openapi.assertion"){t.Fatalf("invalid pair accepted: %v",err)}}
    entry:=openAPI30Document(`{"openapi":"3.0.4","info":{"title":"x","version":"1"},"components":{"schemas":{"External":{"$ref":"part.yaml#/schema"}}}}`,OpenAPIJSON)
    external:=OpenAPIResource{URI:"https://example.test/part.yaml",Source:[]byte("schema: {type: integer, minimum: 0x10, exclusiveMinimum: true}\n"),Syntax:OpenAPIYAML,Role:OpenAPIFragment}
    projection,err:=DiscoverOpenAPI([]OpenAPIResource{entry,external},OpenAPIOptions{EntryResource:entry.URI});if err!=nil{t.Fatal(err)};constraints:=projection.Constraints();if len(constraints)!=1||constraints[0].Resource!=external.URI||constraints[0].SchemaPointer!="/schema"||constraints[0].Native!="0x10"||constraints[0].PairedNative!="true"{t.Fatalf("external pair lost resource authority: %+v",constraints)}
}

func TestOpenAPI30PairingDoesNotChangeJSONSchemaOrOpenAPI31Units(t *testing.T){
    api,err:=DiscoverOpenAPI([]OpenAPIResource{openAPIJSONResource(`{"openapi":"3.1.2","info":{"title":"x","version":"1"},"components":{"schemas":{"X":{"type":"number","exclusiveMinimum":1}}}}`)},OpenAPIOptions{EntryResource:openAPIEntry});if err!=nil{t.Fatal(err)};constraint:=api.Constraints()[0];if constraint.Keyword!="exclusiveMinimum"||constraint.PairedKeyword!=""||constraint.Native!="1"{t.Fatalf("OpenAPI 3.1 unit changed: %+v",constraint)}
    schema,err:=DiscoverJSONSchema([]byte(`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"number","exclusiveMinimum":1}`),schemajson.Limits{});if err!=nil{t.Fatal(err)};constraint=schema.Constraints()[0];if constraint.Keyword!="exclusiveMinimum"||constraint.PairedKeyword!=""||constraint.Native!="1"{t.Fatalf("JSON Schema unit changed: %+v",constraint)}
}

func TestOpenAPI30ReferenceObjectSiblingsDoNotAcquireConstraintAuthority(t *testing.T){
    source:=`{"openapi":"3.0.4","info":{"title":"x","version":"1"},"components":{"schemas":{"Base":{"type":"integer","minimum":1,"exclusiveMinimum":false},"Alias":{"$ref":"#/components/schemas/Base","minimum":9,"exclusiveMinimum":true}}}}`
    projection,err:=DiscoverOpenAPI([]OpenAPIResource{openAPI30Document(source,OpenAPIJSON)},OpenAPIOptions{EntryResource:"https://example.test/api"});if err!=nil{t.Fatal(err)};constraints:=projection.Constraints();if len(constraints)!=1||constraints[0].SchemaPointer!="/components/schemas/Base"||constraints[0].Native!="1"{t.Fatalf("ignored Reference Object sibling became editable: %+v",constraints)}
}
