package language

import (
    "strings"
    "testing"

    "goforge.dev/refine/validation"
)

func TestNumericAndOrderingCapabilitiesInferAndPropagate(t *testing.T) {
    source:=`twice :: a -> a
twice x = x + x
negative :: a -> a
negative x = -x
ratio :: a -> a -> Real
ratio x y = x / y
remainder :: a -> a -> a
remainder x y = x % y
less :: a -> a -> Bool
less x y = x < y
calculate :: a -> a
calculate x = twice x
orderedCalculation :: a -> a -> Bool
orderedCalculation x y = twice x < twice y
entry :: Bool
entry = orderedCalculation 2 3 && less "a" "b" && ratio 1.0 2.0 == 0.5 && remainder 5 2 == 1
`
    program,err:=Compile(source);if err!=nil{t.Fatal(err)}
    capabilities:=program.CheckedSyntax().FunctionCapabilities
    for name,want:=range map[string]string{
        "twice":"Num a","negative":"Num a","ratio":"Num a","remainder":"Integral a","less":"Ord a",
        "calculate":"Num a","orderedCalculation":"Ord a,Num a","entry":"",
    }{if got:=capabilityNames(capabilities[name]);got!=want{t.Fatalf("%s capabilities = %q, want %q",name,got,want)}}
    e,result,failure:=execution(t,source,validation.Limits{});if failure!=nil{t.Fatal(failure)}
    if got:=e.show(result,Span{});got!="True"{t.Fatalf("entry = %s",got)}
}

func TestNumericCapabilitiesRejectUnsupportedOrImplicitConversions(t *testing.T) {
    cases:=[]struct{source,contains string}{
        {"twice :: Num a => a -> a\ntwice x = x + x\nentry :: Bool\nentry = twice True","numeric operations require a numeric type"},
        {"less :: Ord a => a -> a -> Bool\nless x y = x < y\nentry :: Bool\nentry = less True False","ordering requires a numeric, String, or Timestamp"},
        {"less :: Ord a => a -> a -> Bool\nless x y = x < y\nentry :: Bool\nentry = less [1] [2]","ordering requires a numeric, String, or Timestamp"},
        {"increment :: a -> a\nincrement x = x + 1","expected type variable, got Int"},
        {"remainder :: Integral a => a -> a -> a\nremainder x y = x % y\nentry :: Real\nentry = remainder 1.0 2.0","remainder requires an integer type"},
        {"entry :: Int\nentry = 1 + 2.0","expected Int"},
        {"type Bad a = {value :: a} where it.value + it.value == it.value","numeric type cannot be inferred"},
    }
    for _,tc:=range cases{_,err:=Compile(tc.source);if err==nil||!strings.Contains(err.Error(),tc.contains){t.Fatalf("Compile(%q) error = %v, want %q",tc.source,err,tc.contains)}}
}
