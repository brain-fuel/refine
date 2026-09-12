package language

import (
    "testing"

    "goforge.dev/refine/validation"
)

func TestEvaluatorTrampolinesDeepNamedRecursion(t *testing.T) {
    source:=`sumDown :: Int -> Int
sumDown 0 = 0
sumDown n = 1 + sumDown (n - 1)
even :: Int -> Bool
even 0 = True
even n = odd (n - 1)
odd :: Int -> Bool
odd 0 = False
odd n = even (n - 1)
entry :: Bool
entry = sumDown 700 == 700 && even 700
`
    e,result,failure:=execution(t,source,validation.Limits{})
    if failure!=nil{t.Fatal(failure)}
    if got:=e.show(result,Span{});got!="True"{t.Fatalf("entry = %s",got)}
    if e.depth!=0{t.Fatalf("logical helper depth leaked: %d",e.depth)}
}

func TestEvaluatorRecursiveLoopFailsByBudgetNotHostDepth(t *testing.T) {
    _,_,failure:=execution(t,"loop :: Int -> Bool\nloop n = loop n\nentry :: Bool\nentry = loop 0",validation.Limits{Clause:2000})
    if failure==nil||failure.code!="evaluation.budget"{t.Fatalf("failure = %v, want evaluation.budget",failure)}
}
