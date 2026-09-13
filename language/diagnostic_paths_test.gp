package language

import (
    "reflect"
    "testing"

    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

func diagnosticRule(t *testing.T,source,name string)Where{
    t.Helper();program,err:=Compile(source);if err!=nil{t.Fatal(err)}
    for _,declaration:=range program.Syntax().Types{if declaration.Name==name{match declaration.Body.Form{case RefinedType(_,rules):if len(rules)!=1{t.Fatal("expected one rule")};return rules[0];case _:t.Fatal("expected refined declaration")}}}
    t.Fatal("missing declaration");return Where{}
}

func TestAffectedDiagnosticPaths(t *testing.T){
    source:=`positive :: Int -> Bool
positive value = value > 0
type Shape = { start :: Int, end :: Int, nested :: { left :: Int, right :: Int }, items :: [Int] }
  where it.start <= it.end && it.nested.left < it.nested.right && it.start >= 0
type Collection = { items :: [Int] } where all positive it.items
type Named = { start :: Int, end :: Int } where ordered it
ordered :: { start :: Int, end :: Int } -> Bool
ordered value = value.start <= value.end
type Constant = Int where False
type Shadow = { start :: Int } where it.start > (let it = { end = 9 } in it.end)
`
    cases:=[]struct{name,enclosing string;want []string}{
        {"Shape","",[]string{"/start","/end","/nested/left","/nested/right"}},
        {"Collection","/payload",[]string{"/payload/items"}},
        {"Named","/payload",[]string{"/payload"}},
        {"Constant","/payload",[]string{"/payload"}},
        {"Shadow","",[]string{"/start"}},
    }
    for _,test:=range cases{rule:=diagnosticRule(t,source,test.name);got:=AffectedPaths(rule.Predicate,test.enclosing);if !reflect.DeepEqual(got,test.want){t.Fatalf("%s: got %v want %v",test.name,got,test.want)}}
    unusual:=&Expr{Form:Project(&Expr{Form:Variable("it")},"~/")}
    if got:=AffectedPaths(unusual,"");!reflect.DeepEqual(got,[]string{"/~0~1"}){t.Fatalf("JSON Pointer escaping: %v",got)}
    cycle:=&Expr{};cycle.Form=Project(cycle,"again")
    if got:=AffectedPaths(cycle,"/cycle");!reflect.DeepEqual(got,[]string{"/cycle"}){t.Fatalf("cyclic defensive fallback: %v",got)}
    deep:=&Expr{Form:Variable("it")};for i:=0;i<20;i++{deep=&Expr{Form:Project(deep,"field")}}
    if got:=affectedPathsWithLimits(deep,"/deep",8,1024);!reflect.DeepEqual(got,[]string{"/deep"}){t.Fatalf("deep work fallback: %v",got)}
    aggregate:=&Expr{Form:ListLiteral([]*Expr{{Form:Project(&Expr{Form:Variable("it")},"first")},{Form:Project(&Expr{Form:Variable("it")},"second")}})}
    if got:=affectedPathsWithLimits(aggregate,"/aggregate",100,12);!reflect.DeepEqual(got,[]string{"/aggregate"}){t.Fatalf("aggregate output fallback: %v",got)}
    astral:="/😀";relative:=[]string{"/left","/right"};exact:=len(astral)*len(relative)+len(relative[0])+len(relative[1])
    if got:=prefixAffectedPathsWithLimits(relative,astral,10,exact);!reflect.DeepEqual(got,[]string{"/😀/left","/😀/right"}){t.Fatalf("UTF-8 prefix boundary: %v",got)}
    if got:=prefixAffectedPathsWithLimits(relative,astral,10,exact-1);!reflect.DeepEqual(got,[]string{astral}){t.Fatalf("UTF-8 prefix overflow did not keep enclosing path: %v",got)}
    if got:=prefixAffectedPathsWithLimits([]string{"",""},"",1,100);!reflect.DeepEqual(got,[]string{""}){t.Fatalf("prefix work overflow did not keep enclosing path: %v",got)}

    runtime:=validationProgram(t,`type Pair = { start :: Int, end :: Int } where it.start <= it.end @code "pair.order"
type UnknownPair = { left :: Int, right :: Int } where toReal it.left / 0.0 > toReal it.right @code "pair.unknown"`)
    pair:=func(left,right int64)value.Data{return payloadRecord(t,value.DataField{Name:"left",Value:integerPayload(left)},value.DataField{Name:"right",Value:integerPayload(right)})}
    invalid:=runtime.ValidateData("Pair",payloadRecord(t,value.DataField{Name:"start",Value:integerPayload(2)},value.DataField{Name:"end",Value:integerPayload(1)}),validation.Limits{})
    if validation.StateName(invalid.State())!="invalid"||!reflect.DeepEqual(invalid.Diagnostics()[0].Paths,[]string{"/start","/end"}){t.Fatalf("invalid paths: %+v",invalid.Diagnostics())}
    unknown:=runtime.ValidateData("UnknownPair",pair(1,2),validation.Limits{})
    if validation.StateName(unknown.State())!="indeterminate"||!reflect.DeepEqual(unknown.Diagnostics()[0].Paths,[]string{"/left","/right"}){t.Fatalf("indeterminate paths: %+v",unknown.Diagnostics())}
}
