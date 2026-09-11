package pattern

import (
    "regexp"
    "strings"
    "testing"
    "testing/quick"
    "unicode/utf8"

    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

func meter(limit uint64)*validation.Meter{return validation.NewBudget(validation.Limits{Total:limit,Clause:limit},validation.Limits{}).BeginClause(0)}
func text(raw string)value.Text{v,err:=value.TextFromUTF8(raw);if err!=nil{panic(err)};return v}

func TestRegexSemantics(t *testing.T){
    cases:=[]struct{pattern string;subject string;full bool;search bool}{
        {"a","cat",false,true},{"a|ab","ab",true,true},{"a*","",true,true},
        {"","x",false,true},{"^a$","a\n",false,false},{"(?m)^a$","b\na\nb",false,true},
        {".","\n",false,false},{"(?s).","\n",true,true},{".","😀",true,true},
        {"..","😀",false,false},{"(?i)k","K",true,true},{"(?i)σ","ς",true,true},
        {"\\w+","é",false,false},{"\\p{Greek}+","αβ",true,true},
        {"\\bcat\\b","a cat!",false,true},{"a{2,4}","aaa",true,true},
        {"a{2,4}","aaaaa",false,true},{"(?:a?)*b","aaa",false,false},
        {"[a-zA-Z0-9]+","aZ09",true,true},{"[^a]","b",true,true},
        {"a+?","aaa",true,true},{"\\Acat\\z","cat",true,true},
        {"a$|ab","ab",true,true},{"a^","a",false,false},
    }
    for _,tc:=range cases{t.Run(tc.pattern+"/"+tc.subject,func(t *testing.T){
        r,err:=Compile(text(tc.pattern),meter(1000000));if err!=nil{t.Fatal(err)}
        for _,mode:=range []Mode{Full(),Search()}{
            got,err:=r.Match(text(tc.subject),mode,meter(1000000));want:=tc.full;match mode{case Search():want=tc.search;case Full():}
            if err!=nil||got!=want{t.Fatalf("got %v (%v), want %v",got,err,want)}
        }
    })}
}

func TestRegexSurrogateIdentity(t *testing.T){
    lone,err:=value.ReadText(`"\ud800"`);if err!=nil{t.Fatal(err)}
    for _,tc:=range []struct{pattern string;want bool}{{".",true},{`\x{d800}`,true},{`\x{fffd}`,false},{`\p{Cs}`,true}}{
        r,err:=Compile(text(tc.pattern),meter(1000000));if err!=nil{t.Fatal(err)}
        got,err:=r.Match(lone,Full(),meter(1000000));if err!=nil||got!=tc.want{t.Fatalf("%s: %v %v",tc.pattern,got,err)}
    }
    if _,err:=Compile(lone,meter(1000000));err==nil{t.Fatal("literal lone surrogate pattern must require an explicit escape")}
}

func TestRegexLimitsAndPrivacy(t *testing.T){
    simple:=meter(1000);literal,err:=Compile(text("a"),simple);if err!=nil{t.Fatal(err)}
    if simple.Used()!=8{t.Fatalf("literal compilation cost changed: %d",simple.Used())}
    matched,err:=literal.Match(text("a"),Full(),simple)
    if err!=nil||!matched||simple.Used()!=17{t.Fatalf("literal match cost changed: %d, %v",simple.Used(),err)}
    for _,source:=range []string{"(?=private-value)",`(private-value)\1`,"[private-value"}{
        _,err:=Compile(text(source),meter(1000000));if err==nil||err.(*Error).Code!="regex.syntax"||strings.Contains(err.Error(),"private-value"){t.Fatalf("unsanitized error: %v",err)}
    }
    if _,err:=Compile(text(strings.Repeat("x",10000)),meter(20));err==nil||err.(*Error).Code!="regex.budget"{t.Fatal("compilation not budgeted")}
    if _,err:=Compile(text(`(?:a{1000}){1000}`),meter(1000));err==nil{t.Fatal("expansion limit bypassed")}
    if _,err:=(Regex{}).Match(text("x"),Full(),meter(1000));err==nil{t.Fatal("uncompiled regex accepted")}
    source,subject:=text("(a|aa)*b"),text(strings.Repeat("a",30)+"b")
    cost:=meter(1000000);r,err:=Compile(source,cost);if err!=nil{t.Fatal(err)}
    ok,err:=r.Match(subject,Full(),cost);if err!=nil||!ok{t.Fatal(err)}
    used:=cost.Used()
    for _,limit:=range []uint64{used-1,used,used+1}{
        m:=meter(limit);r,err:=Compile(source,m);if err==nil{_,err=r.Match(subject,Full(),m)}
        if (err==nil)!=(limit>=used){t.Fatalf("threshold %d, required %d: %v",limit,used,err)}
    }
}

func differential(t *testing.T,source,subject string){
    t.Helper()
    if !utf8.ValidString(source)||!utf8.ValidString(subject){return}
    reference,err:=regexp.Compile(source);if err!=nil{return}
    m:=meter(1000000);r,err:=Compile(text(source),m)
    if err!=nil{if err.(*Error).Code=="regex.budget"||err.(*Error).Code=="regex.limit"{return};t.Fatal(err)}
    for _,mode:=range []Mode{Full(),Search()}{
        got,err:=r.Match(text(subject),mode,meter(1000000));if err!=nil{if err.(*Error).Code=="regex.budget"{continue};t.Fatal(err)}
        want:=reference.MatchString(subject)
        match mode{case Full():full,err:=regexp.Compile(`\A(?:`+source+`)\z`);if err!=nil{return};want=full.MatchString(subject);case Search():}
        if got!=want{t.Fatalf("pattern %q subject %q mode %v: got %v want %v",source,subject,mode,got,want)}
    }
}

func TestRegexDifferentialProperties(t *testing.T){
    atoms:=[]string{"a","b",".","[a-z]","[^x]","\\w","\\p{Greek}","(?i:k)","(?:a|ab)","(?:a?)"}
    quantifiers:=[]string{"","?","*","+","{0,3}","{2}","+?"}
    property:=func(a,b uint8,raw []byte)bool{
        if len(raw)>100{raw=raw[:100]};subject:=strings.ToValidUTF8(string(raw),"�")
        source:=atoms[int(a)%len(atoms)]+quantifiers[int(b)%len(quantifiers)]
        differential(t,source,subject);differential(t,source,"abkkα😀\n"+subject);return true
    }
    if err:=quick.Check(property,&quick.Config{MaxCount:2000});err!=nil{t.Fatal(err)}
}

func FuzzRegexDifferential(f *testing.F){
    for _,seed:=range []string{"a|ab","(?m)^a$","(?:a?)*b","(?i)k","\\p{Greek}+","."}{f.Add(seed,"ab\naK😀")}
    f.Fuzz(func(t *testing.T,source,subject string){if len(source)>200||len(subject)>1000{t.Skip()};differential(t,source,subject)})
}
