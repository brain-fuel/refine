package language

import (
    "encoding/json"
    "strings"
    "sync"
    "testing"
    "testing/quick"

    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

const payloadTypeContract = `
type Age = Int where it >= 0 @code "age.nonnegative"
type Box a = { value :: a, note :: Maybe String }
data Tree a = Leaf a | Branch (Tree a) (Tree a)
data Phantom a = Empty
type FunctionAlias = Int -> Int
type HiddenFunction = { fn :: FunctionAlias }
positive :: Int -> Bool
positive n = n > 0
acceptAge :: Age -> Bool
acceptAge _ = True
parse :: String -> Result String a
parse text = read text
`

func TestCheckedPayloadTypes(t *testing.T){
    program:=validationProgram(t,payloadTypeContract)
    for _,tc:=range []struct{typ,text,state string}{
        {"Box Age","{value = 21}","valid"},
        {"Box Age","{value = -1}","invalid"},
        {"Box Age","{note = Nothing}","invalid"},
        {"Tree Age","Branch (Leaf 1) (Leaf 2)","valid"},
        {"Tree Age","Branch (Leaf -1) (Leaf 2)","invalid"},
        {"Box (Int where positive it)","{value = 1}","valid"},
        {"Box (Int where positive it)","{value = 0}","invalid"},
        {"[Maybe (Nullable Age)]","[Nothing, Just Null, Just (NonNull 1)]","valid"},
        {"[Maybe (Nullable Age)]","[Just (NonNull -1)]","invalid"},
        {"{ age :: Age, labels :: [String] }","{age = 1, labels = [], extra = True}","valid"},
        {"Int where False where 1 / 0 > 0.0","1","invalid"},
        {"Int where 1 / 0 > 0.0","1","indeterminate"},
        {"String where (case parse it of { Ok age -> acceptAge age; Err _ -> False })",`"21"`,"valid"},
        {"String where (case parse it of { Ok age -> acceptAge age; Err _ -> False })",`"-1"`,"invalid"},
        {"Int where (let x :: Int where it > 0 = it in x > 0)","1","valid"},
        {"Int where (let x :: Int where it > 0 = it in x > 0)","-1","indeterminate"},
        {"UInt8","256","invalid"},
        {"Real","1/3","valid"},
        {"Timestamp",`"2026-09-11T12:34:56Z"`,"valid"},
    }{t.Run(tc.typ+"/"+tc.text,func(t *testing.T){
        target,err:=program.PayloadType(tc.typ);if err!=nil{t.Fatal(err)}
        text,_:=value.TextFromUTF8(tc.text);data,report:=target.ReadData(text,validation.Limits{})
        if validation.StateName(report.State())!=tc.state{t.Fatalf("%s: %+v",tc.typ,report.Diagnostics())}
        if tc.state=="valid"{
            if got:=target.ValidateData(data,validation.Limits{});validation.StateName(got.State())!="valid"{t.Fatal(got.Diagnostics())}
            shown,err:=ShowDataWithoutValidation(data,validation.Limits{});if err!=nil{t.Fatal(err)}
            _,again:=target.ReadData(shown,validation.Limits{});if validation.StateName(again.State())!="valid"{t.Fatal(again.Diagnostics())}
        }else if name,ok:=data.Constructor();!ok||name!="Null"{t.Fatal("failed read exposed a candidate")}
        again,err:=program.PayloadType(target.Formatted());if err!=nil||again.Formatted()!=target.Formatted(){t.Fatalf("unstable format: %v",err)}
    })}
}

func TestPayloadTypeRejectionAndIsolation(t *testing.T){
    program:=validationProgram(t,payloadTypeContract)
    for _,source:=range []string{"", "a", "Box", "Box a", "Int Age", "Box Int String", "Unknown", "Int -> Int", "FunctionAlias", "HiddenFunction", "Tree FunctionAlias", "Phantom (Int -> Int)", "Int where it", "Int where missing it", "Int where it > 0 @message 1", "Int\ntype Injected = String", "Int; import \"network\"", "Int where (case Nothing of { Just x -> True })", strings.Repeat("[",520)+"Int"+strings.Repeat("]",520)}{
        if target,err:=program.PayloadType(source);err==nil||target!=nil{t.Fatalf("unchecked target accepted: %q, %v",source,err)}
    }
    if target,err:=(*Program)(nil).PayloadType("Int");err==nil||target!=nil{t.Fatal("nil program accepted")}
    text,_:=value.TextFromUTF8("1")
    for _,target:=range []*PayloadType{nil,{}}{
        if validation.StateName(target.ValidateData(value.OfNumber(value.Integer(1)),validation.Limits{}).State())!="invalid"{t.Fatal("zero target validated")}
        if _,report:=target.ReadData(text,validation.Limits{});validation.StateName(report.State())!="invalid"{t.Fatal("zero target read")}
    }
    target,err:=program.PayloadType("Box Age");if err!=nil{t.Fatal(err)}
    target.Syntax().Form=NamedType("String")
    snapshot:=target.CheckedSyntax();snapshot.Type.Form=NamedType("String");snapshot.Module.Syntax.Types[0].Name="Changed";clear(snapshot.Module.Inferred)
    if target.Source()!="Box Age"||program.Source()!=payloadTypeContract{t.Fatal("snapshot changed source")}
    text,_=value.TextFromUTF8("{value = -1}")
    if _,report:=target.ReadData(text,validation.Limits{});validation.StateName(report.State())!="invalid"{t.Fatal("snapshot changed validation")}
    // A handle retains the originating contract even if an equivalent name is
    // compiled elsewhere with different predicates.
    other:=validationProgram(t,"type Age = Int where it >= -10\ntype Box a = { value :: a }")
    otherTarget,err:=other.PayloadType("Box Age");if err!=nil{t.Fatal(err)}
    if _,report:=otherTarget.ReadData(text,validation.Limits{});validation.StateName(report.State())!="valid"{t.Fatal(report.Diagnostics())}
    var wg sync.WaitGroup
    for i:=0;i<8;i++{wg.Add(1);go func(){defer wg.Done();for j:=0;j<100;j++{if _,report:=target.ReadData(text,validation.Limits{});validation.StateName(report.State())!="invalid"{t.Error("concurrent target changed")}}}()};wg.Wait()
}

func TestPayloadTypeNamedBudgetParity(t *testing.T){
    program:=validationProgram(t,payloadTypeContract);target,err:=program.PayloadType("Age");if err!=nil{t.Fatal(err)}
    same:=func(a,b validation.Report){left,_:=json.Marshal(a);right,_:=json.Marshal(b);if string(left)!=string(right){t.Fatalf("target budget mismatch\n%s\n%s",left,right)}}
    for _,n:=range []int64{-1,0,1}{for steps:=uint64(1);steps<300;steps++{
        limits:=validation.Limits{Total:steps,Clause:steps};data:=value.OfNumber(value.Integer(n));text,_:=value.TextFromUTF8(value.Integer(n).Show())
        same(target.ValidateData(data,limits),program.ValidateData("Age",data,limits))
        same(target.ValidateDataWithoutRefinements(data,limits),program.ValidateDataWithoutRefinements("Age",data,limits))
        _,a:=target.ReadData(text,limits);_,b:=program.ReadData("Age",text,limits);same(a,b)
    }}
    if err:=quick.Check(func(n int64)bool{
        data:=value.OfNumber(value.Integer(n));normal:=target.ValidateData(data,validation.Limits{});bypass:=target.ValidateDataWithoutRefinements(data,validation.Limits{})
        return (validation.StateName(normal.State())=="valid")== (n>=0) && validation.StateName(bypass.State())=="valid"
    },&quick.Config{MaxCount:3000});err!=nil{t.Fatal(err)}
}

func FuzzPayloadType(f *testing.F){
    for _,source:=range []string{"Box Age","Tree (Int where it > 0)","[Maybe Age]","{value :: Int}","Int where positive it","Int -> Int","Box a"}{f.Add(source)}
    program,err:=Compile(payloadTypeContract);if err!=nil{f.Fatal(err)}
    f.Fuzz(func(t *testing.T,source string){
        if len(source)>4096{return}
        target,err:=program.PayloadType(source);if err!=nil{if target!=nil{t.Fatal("partial target escaped")};return}
        formatted:=target.Formatted();again,err:=program.PayloadType(formatted);if err!=nil||again.Formatted()!=formatted{t.Fatalf("target round trip: %v",err)}
        data:=value.OfNumber(value.Integer(1));limit:=validation.Limits{Total:500,Clause:100}
        left,_:=json.Marshal(target.ValidateData(data,limit));right,_:=json.Marshal(target.ValidateData(data,limit));if string(left)!=string(right){t.Fatal("nondeterministic target validation")}
    })
}
