package language

import "testing"

func TestSubstituteTypeIsSimultaneousAndBounded(t *testing.T){
    program,err:=Compile("type Pair a b = { left :: a, right :: [b where show it /= \"\"] }\n");if err!=nil{t.Fatal(err)};body:=program.Syntax().Types[0].Body
    a:=&Type{Form:NamedType{Name:"b"}};b:=&Type{Form:NamedType{Name:"Int"}};result,err:=SubstituteType(body,map[string]*Type{"a":a,"b":b});if err!=nil{t.Fatal(err)}
    match result.Form{case RecordType(fields):match fields[0].Type.Form{case NamedType(name):if name!="b"{t.Fatalf("replacement was rebound: %s",name)};if fields[0].Type!=a{t.Fatal("replacement tree was copied")};case _:t.Fatal("wrong left type")};match fields[1].Type.Form{case ListType(element):match element.Form{case RefinedType(base,rules):if base!=b||len(rules)!=1{t.Fatal("refinement was not preserved")};case _:t.Fatal("refinement lost")};case _:t.Fatal("list lost")};case _:t.Fatal("record lost")}
    if _,err:=SubstituteTypeBounded(body,map[string]*Type{},1);err==nil{t.Fatal("node bound was not enforced")};if _,err:=SubstituteTypeBounded(body,map[string]*Type{"a":nil},100);err==nil{t.Fatal("nil replacement accepted")}
    deep:=&Type{Form:NamedType{Name:"Int"}};for i:=0;i<514;i++{deep=&Type{Form:ListType{Element:deep}}};if _,err:=SubstituteTypeBounded(deep,map[string]*Type{},1000);err==nil{t.Fatal("depth bound was not enforced")}
}
