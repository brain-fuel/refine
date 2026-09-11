package language

import (
    "fmt"
    "strings"
    "testing"
    "testing/quick"

    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

func execution(t *testing.T,source string,limits validation.Limits) (*evaluator,evalValue,*evalFailure) {
    t.Helper()
    program,err := Compile(source); if err != nil {t.Fatal(err)}
    e := newEvaluator(program.module,validation.NewBudget(validation.Limits{},limits).BeginClause(0))
    result,failure := e.attempt(&Expr{Form:Variable("entry")},nil)
    return e,result,failure
}

func TestEvaluatorExpressionsAndBuiltins(t *testing.T) {
    cases := []struct{name string; declarations string; typ string; expr string; want string}{
        {"exact thirds","","Real","(1 / 3) * 3.0","1"},
        {"exact whole rational","","Bool","isInteger ((1 / 3) * 3.0)","True"},
        {"exact noninteger","","Bool","isInteger (1 / 3)","False"},
        {"negative whole rational","","Bool","isInteger (-10 / 2)","True"},
        {"large exact integer","","Int","9007199254740993 + 2","9007199254740995"},
        {"signed remainder","","Int","-13 % 5","-3"},
        {"UTF16 length","","Int",`length "\ud83d\ude00"`,"2"},
        {"unpaired surrogate","","String",`"\ud800" ++ "a"`,`"\ud800a"`},
        {"no normalization","","Bool",`"\u00e9" == "e\u0301"`,"False"},
        {"text ordering","","Bool",`"a" < "b"`,"True"},
        {"record projection","","Int","{b = 10, a = 20}.a","20"},
        {"record canonical show","","String",`show {z = True, a = [1, 2]}`,`"{a = [1, 2], z = True}"`},
        {"record equality","","Bool","{a = 1, b = True} == {b = True, a = 1}","True"},
        {"list append","","[Int]","1 : ([2, 3] ++ [4])","[1, 2, 3, 4]"},
        {"reverse","","[Int]","reverse [1, 2, 3]","[3, 2, 1]"},
        {"if lazy branch","","Bool","if True then True else 1 / 0 > 0.0","True"},
        {"and short circuit","","Bool","False && 1 / 0 > 0.0","False"},
        {"or short circuit","","Bool","True || 1 / 0 > 0.0","True"},
        {"let shadow","","Int","let n = 2 in let n = n + 3 in n","5"},
        {"map","double :: Int -> Int\ndouble n = n + n\n","[Int]","map double [1, 2, 3]","[2, 4, 6]"},
        {"filter","positive :: Int -> Bool\npositive n = n > 0\n","[Int]","filter positive [-1, 0, 1, 2]","[1, 2]"},
        {"foldl","sub :: Int -> Int -> Int\nsub a b = a - b\n","Int","foldl sub 20 [1, 2, 3]","14"},
        {"partial application","add :: Int -> Int -> Int\nadd a b = a + b\n","[Int]","map (add 10) [1, 2]","[11, 12]"},
        {"function list","positive :: Int -> Bool\npositive n = n > 0\n","Bool","satisfiesOneOf [positive, positive] 1","True"},
        {"membership","","Bool","oneOf 2 [1, 2, 2]","True"},
        {"elem","","Bool","elem 4 [1, 2, 3]","False"},
        {"unique","","Bool","unique [1, 2, 1]","False"},
        {"constructors","","Maybe (Nullable Int)","Just (NonNull 2)","(Just (NonNull 2))"},
        {"case","","String",`case Just 2 of { Nothing -> "absent"; (Just n) -> show n }`,`"2"`},
        {"nested patterns","f :: Maybe (Nullable Int) -> Int\nf Nothing = 0\nf (Just Null) = 1\nf (Just (NonNull n)) = n\n","Int","f (Just (NonNull 7))","7"},
        {"literal fallthrough","f :: Int -> Bool\nf 1 = True\nf _ = False\n","Bool","f 2","False"},
        {"list patterns","f :: [Int] -> Int\nf [] = 0\nf [a, b] = a + b\nf _ = -1\n","Int","f [2, 3]","5"},
        {"recursive sum","sum :: [Int] -> Int\nsum [] = 0\nsum (x : xs) = x + sum xs\n","Int","sum [1, 2, 3, 4]","10"},
        {"recursive data","data Tree a = Leaf a | Branch (Tree a) (Tree a)\ntotal :: Tree Int -> Int\ntotal (Leaf n) = n\ntotal (Branch a b) = total a + total b\n","Int","total (Branch (Leaf 2) (Leaf 3))","5"},
        {"polymorphic higher order","id :: a -> a\nid a = a\n","[Bool]","map id [True, False]","[True, False]"},
        {"higher order return","id :: a -> a\nid a = a\nadd :: Int -> Int -> Int\nadd a b = a + b\n","Int","(id (add 10)) 2","12"},
    }
    for _,tc := range cases {
        t.Run(tc.name,func(t *testing.T){
            e,result,failure := execution(t,tc.declarations+"entry :: "+tc.typ+"\nentry = "+tc.expr+"\n",validation.Limits{})
            if failure != nil {t.Fatal(failure)}
            if shown := e.show(result,Span{}); shown != tc.want {t.Fatalf("got %s, want %s",shown,tc.want)}
        })
    }
}

func TestEvaluatorExplainedFailures(t *testing.T) {
    cases := []struct{name string; source string; code string; limits validation.Limits}{
        {"zero divisor","entry :: Real\nentry = 1 / 0","evaluation.divide",validation.Limits{}},
        {"zero remainder","entry :: Int\nentry = 1 % 0","evaluation.remainder",validation.Limits{}},
        {"ignored eager argument","ignore :: Real -> Bool\nignore _ = True\nentry :: Bool\nentry = ignore (1 / 0)","evaluation.divide",validation.Limits{}},
        {"eager let","entry :: Bool\nentry = let ignored = 1 / 0 in True","evaluation.divide",validation.Limits{}},
        {"recursion budget","loop :: Int -> Bool\nloop n = loop n\nentry :: Bool\nentry = loop 0","evaluation.budget",validation.Limits{Clause:60}},
        {"recursion nesting","loop :: Int -> Bool\nloop n = loop n\nentry :: Bool\nentry = loop 0","evaluation.depth",validation.Limits{}},
        {"literal expansion","entry :: Real\nentry = 1e9999999999999999999999999","evaluation.budget",validation.Limits{}},
        {"unsupported regex","entry :: Bool\nentry = matches \"(?=secret-payload)\" \"secret-payload\"","regex.syntax",validation.Limits{}},
    }
    for _,tc := range cases {t.Run(tc.name,func(t *testing.T){
        e,_,failure := execution(t,tc.source,tc.limits)
        if failure == nil || failure.code != tc.code {t.Fatalf("got %v, want %s",failure,tc.code)}
        if strings.Contains(failure.Error(),"secret-payload") {t.Fatal("payload leaked into failure")}
        if e.depth != 0 {t.Fatalf("evaluation stack not unwound: %d",e.depth)}
    })}
}

func TestEvaluatorThreeOutcomeCombinations(t *testing.T) {
    declarations := "yes :: Int -> Bool\nyes _ = True\nno :: Int -> Bool\nno _ = False\nunknown :: Int -> Bool\nunknown _ = 1 / 0 > 0.0\n"
    names := []string{"no","yes","unknown"}
    for _,mode := range []string{"satisfiesAll","satisfiesOnlyOneOf","satisfiesOneOf","satisfiesAtLeastOneOf"} {
        for size:=0;size<=4;size++ {
            count:=1; for i:=0;i<size;i++ {count*=3}
            for encoded:=0;encoded<count;encoded++ {
                selected:=[]string{}; yes,no,unknown,n:=0,0,0,encoded
                for i:=0;i<size;i++ {digit:=n%3;n/=3;selected=append(selected,names[digit]);switch digit {case 0:no++;case 1:yes++;case 2:unknown++}}
                want:="unknown"
                switch mode {
                case "satisfiesAll": if no>0 {want="False"} else if unknown==0 {want="True"}
                case "satisfiesOnlyOneOf": if yes>1 {want="False"} else if unknown==0 {if yes==1 {want="True"} else {want="False"}}
                default: if yes>0 {want="True"} else if unknown==0 {want="False"}
                }
                source:=declarations+"entry :: Bool\nentry = "+mode+" ["+strings.Join(selected,", ")+"] 0"
                e,result,failure:=execution(t,source,validation.Limits{})
                if want=="unknown" {if failure==nil || failure.code!="evaluation.divide" {t.Fatalf("%s: %v",source,failure)}} else {
                    if failure!=nil || e.show(result,Span{})!=want {t.Fatalf("%s: %v; want %s",source,failure,want)}
                }
            }
        }
    }
}

func TestEvaluatorCollectionUnknowns(t *testing.T) {
    declarations:="predicate :: Int -> Bool\npredicate n = if n == 0 then 1 / 0 > 0.0 else n > 0\n"
    for _,tc:=range []struct{expr string;want string}{{"any predicate [0, 1]","True"},{"all predicate [0, -1]","False"},{"all predicate []","True"},{"any predicate []","False"}} {
        e,result,failure:=execution(t,declarations+"entry :: Bool\nentry = "+tc.expr,validation.Limits{})
        if failure!=nil || e.show(result,Span{})!=tc.want {t.Fatalf("%s: %v",tc.expr,failure)}
    }
}

func TestEvaluatorDeterministicCostAndThreshold(t *testing.T) {
    source:="entry :: Int\nentry = 12 + 34"
    e,result,failure:=execution(t,source,validation.Limits{})
    if failure!=nil {t.Fatal(failure)}
    // root variable + zero-arg invoke + binary + 2*(literal node + 2 digits)
    // + numeric operation (2*2+1) = 14 logical steps.
    if used:=e.meter.Used();used!=14 {t.Fatalf("step accounting changed: %d",used)}
    n,_:=number(result,Span{});if n.Show()!="46" {t.Fatal("wrong sum")}
    for cap:=uint64(1);cap<=20;cap++ {
        _,_,failure:=execution(t,source,validation.Limits{Clause:cap})
        if (failure==nil)!=(cap>=14) {t.Fatalf("cap %d: %v",cap,failure)}
    }
}

func TestEvaluatorMapFoldLaws(t *testing.T) {
    source:="double :: Int -> Int\ndouble n = n + n\nadd :: Int -> Int -> Int\nadd a b = a + b\nentry :: Int\nentry = 0"
    program,err:=Compile(source);if err!=nil {t.Fatal(err)}
    property:=func(input []int16)bool {
        e:=newEvaluator(program.module,validation.NewBudget(validation.Limits{},validation.Limits{}).BeginClause(0))
        items:=make([]evalValue,len(input)); want:=int64(0)
        for i,n:=range input {items[i]=numberValue(value.Integer(int64(n)),"Int");want+=int64(n)*2}
        original:=evalValue{form:EvalList(items)}
        mapped:=e.builtin("map",[]evalValue{e.resolve("double",Span{}),original},Span{})
        sum:=e.builtin("foldl",[]evalValue{e.resolve("add",Span{}),numberValue(value.Integer(0),"Int"),mapped},Span{})
        n,_:=number(sum,Span{})
        if n.Show()!=fmt.Sprint(want) {return false}
        for i,item:=range items {n,_:=number(item,Span{});if n.Show()!=fmt.Sprint(input[i]) {return false}}
        return true
    }
    if err:=quick.Check(property,&quick.Config{MaxCount:2000});err!=nil {t.Fatal(err)}
}

func TestEvaluatorDataTransferAndFixedWidth(t *testing.T) {
    e:=newEvaluator(&Module{},validation.NewBudget(validation.Limits{},validation.Limits{}).BeginClause(0))
    null:=value.Data{}; optional,_:=value.Variant("Just",[]value.Data{null})
    raw,_:=value.Record([]value.DataField{{Name:"a",Value:optional},{Name:"b",Value:value.List([]value.Data{value.OfNumber(value.Integer(42)),value.OfBool(true)})}})
    converted:=e.toData(e.fromData(raw,Span{}),Span{})
    same,err:=raw.EqualWith(converted,func(uint64)error{return nil});if err!=nil || !same {t.Fatal("payload changed during transfer")}
    expr:=&Expr{Form:Binary("+",&Expr{Form:Variable("a")},&Expr{Form:Variable("b")})}
    env:=map[string]evalValue{"a":numberValue(value.Integer(127),"Int8"),"b":numberValue(value.Integer(1),"Int8")}
    _,failure:=e.attempt(expr,env);if failure==nil || failure.code!="evaluation.overflow" {t.Fatalf("overflow: %v",failure)}
    n,_:=number(env["a"],Span{});if n.Show()!="127" {t.Fatal("overflow modified operand")}
}

func FuzzEvaluatorDeterminism(f *testing.F) {
    for _,seed:=range []string{"1 + 2","False && 1 / 0 > 0.0","length \"x\"","[1, 2]","1e999999999999999999999"} {f.Add(seed)}
    f.Fuzz(func(t *testing.T,expr string){
        if len(expr)>2000 {t.Skip()}
        // Static-check the expression through a String-returning show wrapper.
        p,err:=Compile("entry :: String\nentry = show ("+expr+")");if err!=nil {return}
        evaluate:=func()(string,string,uint64){
            e:=newEvaluator(p.module,validation.NewBudget(validation.Limits{},validation.Limits{Clause:2000}).BeginClause(0))
            result,failure:=e.attempt(&Expr{Form:Variable("entry")},nil)
            if failure!=nil {return "",failure.Error(),e.meter.Used()}
            text:=textOf(result,Span{});return text.Show(),"",e.meter.Used()
        }
        a,ea,ca:=evaluate();b,eb,cb:=evaluate()
        if a!=b || ea!=eb || ca!=cb {t.Fatal("nondeterministic result or cost")}
    })
}
