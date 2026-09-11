package language

import (
    "encoding/json"
    "os"
    "strings"
    "testing"
    "testing/quick"

    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

func TestTypedReadExecution(t *testing.T) {
    cases:=[]struct{name string;declarations string;typ string;expression string;want string}{
        {"integer","","Result String Int",`read "21"`,"(Ok 21)"},
        {"whole real","","Result String Real",`read "21"`,"(Ok 21)"},
        {"exact rational","","Result String Real",`read "-2/6"`,"(Ok (-1/3))"},
        {"huge integer","","Result String Int",`read "9007199254740993"`,"(Ok 9007199254740993)"},
        {"UTF16","","Result String String",`read "\"\\ud800\\ud83d\\ude00\""`,`(Ok "\ud800\ud83d\ude00")`},
        {"optional nullable","","Result String (Maybe (Nullable Int))",`read "(Just (NonNull 3))"`,"(Ok (Just (NonNull 3)))"},
        {"nested lists","","Result String [[Int]]",`read "[[1,2],[]]"`,"(Ok [[1, 2], []])"},
        {"record","type R = {x :: Int, y :: Bool}\n","Result String R",`read "{y = True, x = 2}"`,"(Ok {x = 2, y = True})"},
        {"recursive generic","data Tree a = Leaf a | Branch (Tree a) (Tree a)\n","Result String (Tree Int)",`read "(Branch (Leaf 1) (Leaf 2))"`,"(Ok (Branch (Leaf 1) (Leaf 2)))"},
        {"higher order read","","[Result String Int]",`map read ["1", "2"]`,"[(Ok 1), (Ok 2)]"},
        {"generic parser","parse :: String -> Result String a\nparse text = read text\n","Result String [Int]",`parse "[1,2]"`,"(Ok [1, 2])"},
        {"generic parser higher order","parse :: String -> Result String a\nparse text = read text\n","[Result String Bool]",`map parse ["True", "False"]`,"[(Ok True), (Ok False)]"},
        {"read through identity","id :: a -> a\nid x = x\n","Result String Int",`(id read) "42"`,"(Ok 42)"},
        {"typed local alias","","Result String Int",`let parse = read in parse "42"`,"(Ok 42)"},
        {"fixed-width","","Result String Int8",`read "127"`,"(Ok 127)"},
        {"nominal refined success","type Positive = Int where it > 0\n","Result String Positive",`read "2"`,"(Ok 2)"},
        {"nominal refined failure","type Positive = Int where it > 0\n","Bool",`case read "-2" of { (Ok n) -> accepts n; Err _ -> False }`,"False"},
    }
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){
        declarations:=tc.declarations
        if tc.name=="nominal refined failure"{declarations+="accepts :: Positive -> Bool\naccepts _ = True\n"}
        e,result,failure:=execution(t,declarations+"entry :: "+tc.typ+"\nentry = "+tc.expression,validation.Limits{})
        if failure!=nil{t.Fatal(failure)}
        if shown:=e.show(result,Span{});shown!=tc.want{t.Fatalf("got %s, want %s",shown,tc.want)}
    })}
}

func TestReadNeverExecutesExpressions(t *testing.T) {
    p:=validationProgram(t,"type T = Int\nexplode :: Int\nexplode = 1 + explode")
    for _,input:=range []string{"explode","1 + 2","if True then 1 else explode","let x = 1 in x","{a = 1}.a","1/0","1/-2","-- only a comment","[1,]","{a = 1, a = 1}"}{
        text,_:=value.TextFromUTF8(input)
        _,report:=p.ReadData("T",text,validation.Limits{})
        if validation.StateName(report.State())!="invalid"{t.Fatalf("%q: %+v",input,report.Diagnostics())}
    }
}

func TestReadValueRevalidatesAndProtectsBudgets(t *testing.T) {
    p:=validationProgram(t,`type Secret = String where length it < 2
type Unknown = Int where 1 / 0 > 0.0
type Positive = Int where it > 0
type Both = Int where False where 1 / 0 > 0.0
`)
    for _,tc:=range []struct{root string;input string;state string}{{"Secret",`"private-sensitive-text"`,"invalid"},{"Positive","-1","invalid"},{"Positive","2","valid"},{"Unknown","1","indeterminate"},{"Both","1","invalid"},{"Positive","0.5","invalid"}}{
        text,_:=value.TextFromUTF8(tc.input);candidate,report:=p.ReadData(tc.root,text,validation.Limits{})
        if validation.StateName(report.State())!=tc.state{t.Fatalf("%s: %+v",tc.root,report.Diagnostics())}
        if tc.state!="valid"{name,ok:=candidate.Constructor();if !ok || name!="Null"{t.Fatal("invalid candidate escaped")}}
        for _,detail:=range report.Diagnostics(){if strings.Contains(detail.Message,"private-sensitive"){t.Fatal("read error leaked payload")}}
    }
    e,_,failure:=execution(t,"type T = Int where 1 / 0 > 0.0\nentry :: Result String T\nentry = read \"1\"",validation.Limits{})
    if failure==nil || failure.code!="read.indeterminate" || e.depth!=0{t.Fatalf("unknown was accepted/caught as malformed input: %v",failure)}
    source:="type T = Int where True @steps 1000000\nentry :: Result String T\nentry = read \"1\""
    _,_,failure=execution(t,source,validation.Limits{Clause:10})
    if failure==nil{t.Fatal("nested read reset caller budget")}
    text,_:=value.TextFromUTF8("1e999999999999999999999")
    _,report:=p.ReadData("Positive",text,validation.Limits{})
    if validation.StateName(report.State())!="indeterminate"{t.Fatal("numeric expansion escaped resources")}
}

func TestReadTargetInsideGenericDeclaration(t *testing.T) {
    p:=validationProgram(t,`validRead :: a -> Result String a -> Bool
validRead _ (Ok _) = True
validRead _ (Err _) = False
type Box a = { value :: a } where validRead it.value (read "1")
type IntegerBox = Box Int
type BooleanBox = Box Bool
`)
    integer:=payloadRecord(t,value.DataField{Name:"value",Value:integerPayload(2)})
    boolean:=payloadRecord(t,value.DataField{Name:"value",Value:value.OfBool(true)})
    if report:=p.ValidateData("IntegerBox",integer,validation.Limits{});validation.StateName(report.State())!="valid"{t.Fatalf("%+v",report.Diagnostics())}
    if report:=p.ValidateData("BooleanBox",boolean,validation.Limits{});validation.StateName(report.State())!="invalid"{t.Fatalf("%+v",report.Diagnostics())}
}

func TestReadShowProperties(t *testing.T) {
    p:=validationProgram(t,"type T = {number :: Real, text :: String, items :: [Int], optional :: Maybe (Nullable Real)}")
    property:=func(n int64,den uint16,units []uint16,items []int16,choice uint8)bool{
        rational,err:=value.Integer(n).Divide(value.Integer(int64(den)+1));if err!=nil{return false}
        list:=make([]value.Data,len(items));for i,item:=range items{list[i]=integerPayload(int64(item))}
        var optional value.Data
        switch choice%3 {case 0:optional,_=value.Variant("Nothing",nil);case 1:optional,_=value.Variant("Just",[]value.Data{value.Data{}});case 2:present,_:=value.Variant("NonNull",[]value.Data{value.OfNumber(rational)});optional,_=value.Variant("Just",[]value.Data{present})}
        raw,_:=value.Record([]value.DataField{{Name:"number",Value:value.OfNumber(rational)},{Name:"text",Value:value.OfText(value.TextFromUnits(units))},{Name:"items",Value:value.List(list)},{Name:"optional",Value:optional}})
        shown,err:=ShowDataWithoutValidation(raw,validation.Limits{});if err!=nil{return false}
        read,report:=p.ReadData("T",shown,validation.Limits{})
        equal,err:=raw.EqualWith(read,func(uint64)error{return nil})
        return err==nil && equal && validation.StateName(report.State())=="valid"
    }
    if err:=quick.Check(property,&quick.Config{MaxCount:2000});err!=nil{t.Fatal(err)}
}

func TestReadRejectsUninhabitableCodecsAndChecksAnnotationRules(t *testing.T) {
    for _,source:=range []string{
        "entry :: Result String (Int -> Int)\nentry = read \"x\"",
        "type T = {callback :: Int -> Bool}\nentry :: Result String T\nentry = read \"x\"",
        "entry :: Int\nentry = let n :: (Int where missing it) = 1 in n",
        "entry :: Int\nentry = let n :: (Int where 123) = 1 in n",
    }{if _,err:=Compile(source);err==nil{t.Fatalf("invalid codec/type annotation accepted: %s",source)}}
}

func TestShowRejectsUnrepresentableNamesAndInvalidBypassRead(t *testing.T) {
    for _,name:=range []string{"bad-name","where","a.b"}{
        raw,_:=value.Record([]value.DataField{{Name:name,Value:integerPayload(1)}})
        if _,err:=ShowDataWithoutValidation(raw,validation.Limits{});err==nil{t.Fatalf("unrepresentable field %s shown",name)}
    }
    for _,name:=range []string{"lowercase","True","Bad Name"}{raw,_:=value.Variant(name,nil);if _,err:=ShowDataWithoutValidation(raw,validation.Limits{});err==nil{t.Fatalf("unrepresentable constructor %s shown",name)}}
    p:=validationProgram(t,"type Positive = Int where it > 0")
    shown,err:=ShowDataWithoutValidation(integerPayload(-1),validation.Limits{});if err!=nil{t.Fatal(err)}
    _,report:=p.ReadData("Positive",shown,validation.Limits{})
    if validation.StateName(report.State())!="invalid"{t.Fatal("bypass-created invalid value accepted by validating read")}
}

func TestCanonicalValueConformanceFixtures(t *testing.T) {
    input,err:=os.ReadFile("testdata/canonical-values.json");if err!=nil{t.Fatal(err)}
    var cases []struct{Name string;Schema string;Input string;State string;Canonical string}
    if err:=json.Unmarshal(input,&cases);err!=nil{t.Fatal(err)}
    for _,tc:=range cases{t.Run(tc.Name,func(t *testing.T){
        p:=validationProgram(t,tc.Schema);text,_:=value.TextFromUTF8(tc.Input)
        data,report:=p.ReadData("T",text,validation.Limits{})
        if validation.StateName(report.State())!=tc.State{t.Fatalf("%+v",report.Diagnostics())}
        if tc.State!="valid"{return}
        shown,err:=ShowDataWithoutValidation(data,validation.Limits{});if err!=nil{t.Fatal(err)}
        actual,err:=shown.UTF8();if err!=nil || actual!=tc.Canonical{t.Fatalf("got %q, want %q",actual,tc.Canonical)}
        reread,report:=p.ReadData("T",shown,validation.Limits{})
        equal,err:=data.EqualWith(reread,func(uint64)error{return nil})
        if err!=nil || !equal || validation.StateName(report.State())!="valid"{t.Fatalf("canonical round trip: %+v",report.Diagnostics())}
    })}
}

func FuzzTypedReadShow(f *testing.F) {
    for _,seed:=range []string{"[]","[1,-2,3]","[1/3]","(Just 1)","[1 + 2]","[1e99999999]"}{f.Add(seed)}
    p,err:=Compile("type T = [Real]");if err!=nil{f.Fatal(err)}
    f.Fuzz(func(t *testing.T,input string){
        if len(input)>4000{t.Skip()}
        text,err:=value.TextFromUTF8(input);if err!=nil{return}
        data,report:=p.ReadData("T",text,validation.Limits{Total:10000,Clause:1000})
        if validation.StateName(report.State())!="valid"{return}
        shown,err:=ShowDataWithoutValidation(data,validation.Limits{});if err!=nil{t.Fatal(err)}
        reread,again:=p.ReadData("T",shown,validation.Limits{})
        equal,err:=data.EqualWith(reread,func(uint64)error{return nil})
        if err!=nil || !equal || validation.StateName(again.State())!="valid"{t.Fatal("valid read/show round trip failed")}
    })
}
