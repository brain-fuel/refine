package native

import (
    "strings"
    "testing"

    "goforge.dev/refine/schemajson"
)

func directionalLimitArray(values int)string{if values==0{return `[]`};return `[`+strings.Repeat(`0,`,values-1)+`0]`}

func TestOpenAPI30DirectionalMaterializationPreflightsAggregateNodes(t *testing.T){
    cases:=[]struct{name string;resources []Resource}{
        {"one resource",[]Resource{{URI:"https://example.test/one.json",Source:`{"unused":`+directionalLimitArray(openAPIDirectionWorkLimit)+`,"selected":{"type":"object"}}`}}},
        {"aggregate resources",[]Resource{{URI:"https://example.test/first.json",Source:`{"unused":`+directionalLimitArray(openAPIDirectionWorkLimit/2)+`,"selected":{"type":"object"}}`},{URI:"https://example.test/second.json",Source:`{"unused":`+directionalLimitArray(openAPIDirectionWorkLimit/2)+`}`}}},
    }
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){_,err:=openAPI30DirectionalResources(tc.resources,[]ResourceSelector{{Resource:tc.resources[0].URI,Pointer:"/selected"}},OpenAPIRequest);if problemCode(err)!="native.limit"||!strings.Contains(err.Error(),"aggregate JSON-node limit"){t.Fatalf("directional mutable-tree allocation was not preflighted: %v",err)}})}

    exact,err:=schemajson.Parse([]byte(directionalLimitArray(openAPIDirectionWorkLimit-1)),schemajson.Limits{});if err!=nil{t.Fatal(err)};total:=0;if err=openAPIDirectionMaterializationPreflight(exact.Root(),"exact",&total);err!=nil||total!=openAPIDirectionWorkLimit{t.Fatalf("exact node boundary rejected: total=%d err=%v",total,err)}
    one,err:=schemajson.Parse([]byte(`0`),schemajson.Limits{});if err!=nil{t.Fatal(err)};if err=openAPIDirectionMaterializationPreflight(one.Root(),"one-over",&total);problemCode(err)!="native.limit"{t.Fatalf("one-over node boundary accepted: %v",err)}
}
