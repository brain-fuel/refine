package language

import (
    "strings"
    "testing"

    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

func TestMapLiteralOperationsAndCanonicalReadShow(t *testing.T){
    cases:=[]struct{name,declarations,typ,expression,want string}{
        {"canonical literal","","Map String Int",`map {"b" = 2, "a" = 1}`,`map {"a" = 1, "b" = 2}`},
        {"order independent equality","","Bool",`map {"b" = 2, "a" = 1} == map {"a" = 1, "b" = 2}`,"True"},
        {"list map remains higher order","double :: Int -> Int\ndouble n = n + n\n","[Int]","map double [2, 3]","[4, 6]"},
        {"lookup","","Maybe Int",`lookup "a" (map {"a" = 2})`,"(Just 2)"},
        {"missing","","Maybe Int",`lookup "z" (map {"a" = 2})`,"Nothing"},
        {"insert replaces","","Map String Int",`insert "a" 3 (map {"b" = 2, "a" = 1})`,`map {"a" = 3, "b" = 2}`},
        {"delete","","Map String Int",`delete "a" (map {"b" = 2, "a" = 1})`,`map {"b" = 2}`},
        {"key identity","","Bool",`member "\u00e9" (map {"e\u0301" = 1})`,"False"},
        {"keys","","[String]",`keys (map {"b" = 2, "a" = 1})`,`["a", "b"]`},
        {"values","","[Int]",`values (map {"b" = 2, "a" = 1})`,`[1, 2]`},
        {"map values","double :: Int -> Int\ndouble n = n + n\n","Map String Int",`mapValues double (map {"b" = 2, "a" = 1})`,`map {"a" = 2, "b" = 4}`},
        {"filter values","positive :: Int -> Bool\npositive n = n > 0\n","Map String Int",`filterValues positive (map {"b" = -1, "a" = 1})`,`map {"a" = 1}`},
        {"quantifiers","positive :: Int -> Bool\npositive n = n > 0\n","Bool",`allValues positive (map {"b" = 2, "a" = 1})`,"True"},
    }
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){e,result,failure:=execution(t,tc.declarations+"entry :: "+tc.typ+"\nentry = "+tc.expression+"\n",validation.Limits{});if failure!=nil{t.Fatal(failure)};if got:=e.show(result,Span{});got!=tc.want{t.Fatalf("got %s, want %s",got,tc.want)}})}
    program,err:=Compile("type M = Map String Int\n");if err!=nil{t.Fatal(err)};input,_:=value.TextFromUTF8(`map {"b" = 2, "a" = 1}`);data,report:=program.ReadData("M",input,validation.Limits{});if validation.StateName(report.State())!="valid"{t.Fatalf("map read failed: %+v",report.Diagnostics())};shown,err:=ShowDataWithoutValidation(data,validation.Limits{});if err!=nil||shown.Show()!=`"map {\"a\" = 1, \"b\" = 2}"`{t.Fatalf("map canonical show failed: %s %v",shown.Show(),err)}
}

func TestMapKeysAndPredicateFailuresAreExact(t *testing.T){
    for _,source:=range []string{"type Bad = Map Int Bool\n","type Bad = Map (String where length it > 0) Bool\n","type Map a b = a\n"}{if _,err:=Compile(source);err==nil{t.Fatalf("unsupported map key/declaration accepted: %s",source)}}
    if _,err:=Compile(`entry :: Map String Int
entry = map {"a" = 1, "\u0061" = 2}
`);err==nil||!strings.Contains(err.Error(),"duplicate map key"){t.Fatalf("decoded duplicate was not rejected: %v",err)}
    _,_,failure:=execution(t,"unknown :: Int -> Bool\nunknown _ = 1 / 0 > 0.0\nentry :: Bool\nentry = allValues unknown (map {\"b\" = 2, \"a\" = 1})\n",validation.Limits{});if failure==nil||failure.code!="evaluation.divide"{t.Fatalf("map predicate error became false: %v",failure)}
    _,_,failure=execution(t,"entry :: Map String Int\nentry = insert \"zzzzzzzzzz\" 4 (map {\"aaaaaaaaaa\" = 1, \"bbbbbbbbbb\" = 2, \"cccccccccc\" = 3})\n",validation.Limits{Total:20,Clause:20});if failure==nil||failure.code!="evaluation.budget"{t.Fatalf("map copy/sort work bypassed the resource budget: %v",failure)}
}

func TestMapLiteralAllocationPreflight(t *testing.T){_,_,failure:=execution(t,"entry :: Map String Int\nentry = map {\"a\" = 1, \"b\" = 2, \"c\" = 3}\n",validation.Limits{Total:4,Clause:4});if failure==nil||failure.code!="evaluation.budget"{t.Fatalf("map literal allocation bypassed its entry-count preflight: %v",failure)}}

func FuzzMapReadShow(f *testing.F){
    for _,seed:=range []string{`map {}`,`map {"b" = [1, -2], "a" = []}`,`map {"\ud800" = [1], "\ud83d\ude00" = []}`,`map {"a" = [], "\u0061" = [1]}`,`map {"x" = [1,]}`,`{"a" = [1]}`}{f.Add(seed)}
    program,err:=Compile("type T = Map String [Int]\n");if err!=nil{f.Fatal(err)};limits:=validation.Limits{Total:20000,Clause:2000}
    f.Fuzz(func(t *testing.T,input string){if len(input)>4096{t.Skip()};text,err:=value.TextFromUTF8(input);if err!=nil{return};data,report:=program.ReadData("T",text,limits);if validation.StateName(report.State())!="valid"{return};shown,err:=ShowDataWithoutValidation(data,limits);if err!=nil{t.Fatal(err)};reread,again:=program.ReadData("T",shown,limits);equal,err:=data.EqualWith(reread,func(uint64)error{return nil});if err!=nil||!equal||validation.StateName(again.State())!="valid"{t.Fatal("valid map read/show round trip failed")};second,err:=ShowDataWithoutValidation(reread,limits);if err!=nil||!shown.Equal(second){firstText,_:=shown.UTF8();secondText,_:=second.UTF8();t.Fatalf("map canonical display is not idempotent: %q %q",firstText,secondText)}})
}
