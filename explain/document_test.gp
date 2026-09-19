package explain

import (
    "fmt"
    "os"
    "reflect"
    "strings"
    "sync"
    "testing"
    "testing/quick"

    "goforge.dev/refine/language"
)

func documentation(t *testing.T,source string)Document{t.Helper();program,err:=language.Compile(source);if err!=nil{t.Fatal(err)};doc,err:=Generate(program);if err!=nil{t.Fatal(err)};return doc}

func TestSeparateClausesAndCustomMessages(t *testing.T){
    doc:=documentation(t,`type Person = { age :: Int where it >= 0 }
type Child = Person where it.age >= 0 && it.age < 18
  @code "child.range" @message "Expected 0 <= age < 18; got " ++ show it.age @steps 123
type Percentage = Int where it >= 0 where it <= 100
`)
    rules:=doc.Rules();if len(rules)!=4{t.Fatalf("one entry per where, got %d",len(rules))}
    child:=rules[1];if child.Code!="child.range"||child.Steps!=123||child.MessageEntry==""||!strings.Contains(child.Predicate,"&&"){t.Fatalf("lost clause metadata: %+v",child)}
    if rules[0].Location!="value / field age"{t.Fatal(rules[0])}
    markdown:=doc.Markdown()
    for _,want:=range []string{"Expected 0 <= age < 18; got", "Declared clause limit: 123", "without evaluating", "custom", "Custom-message failure", "does not claim", "one diagnostic unit"}{if !strings.Contains(strings.ToLower(markdown),strings.ToLower(want)){t.Errorf("missing %q",want)}}
    // Returned metadata must not permit a caller to alter later exports.
    rules[0].Predicate="False";defs:=doc.Definitions();defs[0].Name="Changed";steps:=doc.Instructions();steps[0].English="Changed"
    if doc.Markdown()!=markdown{t.Fatal("mutable exported document")}
}

func TestAllSyntaxAndRecursion(t *testing.T){
    input,err:=os.ReadFile("../language/testdata/contracts.refine");if err!=nil{t.Fatal(err)}
    doc:=documentation(t,string(input));text:=doc.Markdown()
    for _,want:=range []string{"isAdult", "sum", "nonEmpty", "nonempty list", "Recursive calls", "partial applications", "first match", "Bind that value", "alternative", "UTF-16", "absence is not null", "null is not absence"}{if !strings.Contains(text,want){t.Errorf("missing %q",want)}}
    equations:=doc.Equations();before:=doc.Markdown();equations[0].Patterns[0]="mutated";if doc.Markdown()!=before{t.Fatal("equation pattern mutation escaped")}
    // Documentation must not attempt to run recursive predicates or messages.
    forever:=documentation(t,`loop :: Int -> Bool
loop x = loop x
type Infinite = Int where loop it @message show (1 / 0)
`)
    if len(forever.Instructions())>30{t.Fatal("recursive function expanded instead of referenced")}
}

func TestBuiltinAndLexicalShadowing(t *testing.T){
    cases:=[]struct{source string; wanted string; forbidden string}{
        {`type T = String where length it > 0`,"number of list elements or UTF-16", ""},
        {`type T = String where codePointLength it > 0`,"number of Unicode code points", ""},
        {`length :: Int -> Bool
length x = x > 0
type T = Int where length it`,"Refer to named function length", "number of list elements or UTF-16"},
        {`f :: Int -> Int
f length = length
type T = Int where f it > 0`,"lexically bound value length", "number of list elements or UTF-16"},
        {`type T = Int where (let length = it in length) > 0`,"lexically bound value length", "number of list elements or UTF-16"},
        {`type T = Maybe Int where case it of { Nothing -> True; Just length -> length > 0 }`,"lexically bound value length", "number of list elements or UTF-16"},
    }
    for _,test:=range cases{doc:=documentation(t,test.source);text:=doc.Markdown();if !strings.Contains(text,test.wanted){t.Fatalf("missing %q in %s",test.wanted,text)};if test.forbidden!=""&&strings.Contains(text,test.forbidden){t.Fatalf("shadowed name misdescribed: %s",text)}}
    for _,name:=range []string{"not","isInteger","show","read","length","codePointLength","reverse","map","filter","foldl","oneOf","elem","unique","matches","search","all","any","satisfiesAll","satisfiesOnlyOneOf","satisfiesOneOf","satisfiesAtLeastOneOf"}{if words,ok:=builtinMeaning(name);!ok||words==""{t.Errorf("missing builtin %s",name)}}
}

func TestOperatorsAndDemandDrivenDescriptions(t *testing.T){
    doc:=documentation(t,`type T = Int where it /= 0 && (1 / it) > 0.0
type U = Bool where it || False
type V = Int where (if it > 0 then it else -it) >= 0
type W = [Int] where (1 : reverse it) == ([1] ++ reverse it)
type R = Int where { x = it }.x == it
`)
    text:=doc.Markdown()
    for _,want:=range []string{"without evaluating", "otherwise evaluate and return only", "division by zero", "prepend", "concatenate", "construct a new record", "select its field", "do not execute the numbered list eagerly"}{if !strings.Contains(text,want){t.Errorf("missing %q",want)}}
    for _,op:=range []string{"==","/=","<","<=",">",">=","+","-","*","/","%","++",":"}{if binaryMeaning(op)==""{t.Fatal(op)}}
}

func TestDeterministicAndConcurrent(t *testing.T){
    property:=func(low int16,width uint8)bool{
        source:=fmt.Sprintf("type T = Int where it >= %d where it <= %d\n",low,int(low)+int(width))
        p,err:=language.Compile(source);if err!=nil{return false};first,err:=Generate(p);if err!=nil{return false};second,err:=Generate(p);if err!=nil{return false}
        return reflect.DeepEqual(first,second)&&first.Markdown()==second.Markdown()&&len(first.Rules())==2
    }
    if err:=quick.Check(property,&quick.Config{MaxCount:3000});err!=nil{t.Fatal(err)}
    p,err:=language.Compile("type T = Int where it > 0");if err!=nil{t.Fatal(err)}
    base,err:=Generate(p);if err!=nil{t.Fatal(err)};want:=base.Markdown()
    var wg sync.WaitGroup;for range 16{wg.Add(1);go func(){defer wg.Done();doc,err:=Generate(p);if err!=nil||doc.Markdown()!=want{t.Error("non-deterministic concurrent generation")}}()};wg.Wait()
}

func TestMarkdownLiteralSafety(t *testing.T){
    doc:=documentation(t,"type T = Int where it > 0 @message \"```\\n<script>alert(1)</script> [click](https://example.com)\"\n")
    text:=doc.Markdown();if !strings.Contains(text,"````text\n"){t.Fatal("author backticks broke fence")}
    if !strings.Contains(text,"&lt;script&gt;"){t.Fatal("instruction prose did not escape HTML")}
    if strings.Contains(prose("[x](u) <tag>\n# title"),"<tag>"){t.Fatal("unsafe HTML")}
}

func TestGenerationLimitsAndNil(t *testing.T){
    if _,err:=Generate(nil);err==nil{t.Fatal("nil accepted")}
    b:=builder{bytes:16<<20};func(){defer func(){if _,ok:=recover().(limitError);!ok{t.Error("missing output limit")}}();b.charge(1)}()
    b=builder{next:100000};func(){defer func(){if _,ok:=recover().(limitError);!ok{t.Error("missing instruction limit")}}();b.expr("",&language.Expr{Form:language.BoolLiteral(true)})}()
}

func TestSelectedPayloadDocumentation(t *testing.T){
    p,err:=language.Compile("type Box a = {value :: a}\n");if err!=nil{t.Fatal(err)}
    target,err:=p.PayloadType(`Box (Int where it > 0 @message "Root argument must be positive")`);if err!=nil{t.Fatal(err)}
    doc,err:=GeneratePayload(target);if err!=nil{t.Fatal(err)}
    if len(doc.Rules())!=1||doc.Rules()[0].Owner!="$payload"||!strings.Contains(doc.Markdown(),"Root argument must be positive"){t.Fatal("inline selected target lost")}
    if _,err:=GeneratePayload(nil);err==nil{t.Fatal("nil payload accepted")}
}

func FuzzExplain(f *testing.F){
    for _,source:=range []string{"type T = Int where it >= 0", "type T = String where length it > 1", "f :: Int -> Bool\nf x = f x\ntype T = Int where f it"}{f.Add(source)}
    f.Fuzz(func(t *testing.T,source string){if len(source)>65536{t.Skip()};program,err:=language.Compile(source);if err!=nil{return};doc,err:=Generate(program);if err!=nil{return};other,err:=Generate(program);if err!=nil||doc.Markdown()!=other.Markdown(){t.Fatal("nondeterministic explanation")};ids:=map[string]bool{};for _,step:=range doc.Instructions(){if ids[step.ID]||step.English==""{t.Fatal("invalid instruction")};ids[step.ID]=true};for _,rule:=range doc.Rules(){if !ids[rule.Entry]||(rule.MessageEntry!=""&&!ids[rule.MessageEntry]){t.Fatal("dangling entry")}}})
}
