package analysis

import (
    "encoding/json"
    "strings"
    "testing"

    "goforge.dev/refine/language"
)

func syntaxProgram(t *testing.T,source string)*language.Program{t.Helper();program,err:=language.Compile(source);if err!=nil{t.Fatal(err)};return program}

func TestContractSyntaxIgnoresOnlyLayoutCommentsAndEquivalentTextEscapes(t *testing.T){
    old:=syntaxProgram(t,"-- before\ntype T = String where it == \"hello\"\n")
    next:=syntaxProgram(t,"-- revised docs\n\n type T=String where (it == \"\\u0068ello\") -- after\n")
    evidence,err:=CompareContractSyntax(old,"T",next,"T");if err!=nil||!evidence.Equal||len(evidence.Differences)!=0||evidence.BaselineFingerprint!=evidence.CandidateFingerprint||evidence.Version!=ContractSyntaxVersion{t.Fatalf("canonical equality: %+v %v",evidence,err)}
    again,err:=CompareContractSyntax(old,"T",next,"T");if err!=nil{t.Fatal(err)};first,_:=json.Marshal(evidence);second,_:=json.Marshal(again);if string(first)!=string(second){t.Fatal("syntax evidence is nondeterministic")}
}

func TestContractSyntaxRetainsExecutableAndPublicChanges(t *testing.T){
    base:="package example.one\ntype T = Int where it > 0 @code \"positive\" @message \"private-message\" @steps 100\ntype Other = Int\npositive :: Int -> Bool\npositive x = x > 0\n"
    old:=syntaxProgram(t,base)
    cases:=[]struct{name,source,root,kind string}{
        {"predicate",strings.Replace(base,"it > 0","it >= 0",1),"T","type-changed"},
        {"message",strings.Replace(base,"private-message","new-private-message",1),"T","type-changed"},
        {"code",strings.Replace(base,`@code "positive"`,`@code "nonnegative"`,1),"T","type-changed"},
        {"budget",strings.Replace(base,"@steps 100","@steps 101",1),"T","type-changed"},
        {"package",strings.Replace(base,"example.one","example.two",1),"T","package"},
        {"root",base,"Other","root"},
        {"function",strings.Replace(base,"positive x = x > 0","positive x = x >= 0",1),"T","function-changed"},
        {"new public type",base+"type Added = Bool\n","T","type-added"},
        {"new function",base+"negative :: Int -> Bool\nnegative x = x < 0\n","T","function-added"},
    }
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){evidence,err:=CompareContractSyntax(old,"T",syntaxProgram(t,tc.source),tc.root);if err!=nil||evidence.Equal||evidence.BaselineFingerprint==evidence.CandidateFingerprint{t.Fatalf("changed syntax accepted: %+v %v",evidence,err)};found:=false;for _,difference:=range evidence.Differences{if difference.Kind==tc.kind{found=true}};if !found{t.Fatalf("missing %s: %+v",tc.kind,evidence)};encoded,_:=json.Marshal(evidence);if strings.Contains(string(encoded),"private-message")||strings.Contains(string(encoded),"it >="){t.Fatal("evidence leaked rule contents")}})}
}

func TestContractSyntaxOrderAndDirectionRemainExplicit(t *testing.T){
    old:=syntaxProgram(t,"type T = {a :: Int, b :: Bool}\ntype U = Bool\nf :: Int -> Int\nf x = x + 1\ng :: Int -> Int\ng x = x + 2\n")
    next:=syntaxProgram(t,"type U = Bool\ntype T = {a :: Int, b :: Bool}\ng :: Int -> Int\ng x = x + 2\nf :: Int -> Int\nf x = x + 1\n")
    evidence,err:=CompareContractSyntax(old,"T",next,"T");if err!=nil||evidence.Equal||len(evidence.Differences)!=2||evidence.Differences[0].Kind!="type-order"||evidence.Differences[1].Kind!="function-order"{t.Fatalf("order: %+v %v",evidence,err)}
    backwards,err:=CompareContractSyntax(next,"T",old,"T");if err!=nil||backwards.BaselineFingerprint!=evidence.CandidateFingerprint||backwards.CandidateFingerprint!=evidence.BaselineFingerprint{t.Fatal("direction not retained",err)}
    reordered:=syntaxProgram(t,"type T = {b :: Bool, a :: Int}\ntype U = Bool\nf :: Int -> Int\nf x = x + 1\ng :: Int -> Int\ng x = x + 2\n");fields,err:=CompareContractSyntax(old,"T",reordered,"T");if err!=nil||fields.Equal||len(fields.Differences)!=1||fields.Differences[0].Kind!="type-changed"{t.Fatalf("record constructor order ignored: %+v %v",fields,err)}
    if _,err=CompareContractSyntax(nil,"T",next,"T");err==nil{t.Fatal("nil program accepted")};if _,err=CompareContractSyntax(old,"Missing",next,"T");err==nil{t.Fatal("unknown root accepted")}
}
