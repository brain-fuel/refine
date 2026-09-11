package language

import (
    "testing"
    "goforge.dev/refine/validation"
)

func TestAnonymousFunctionAndLocalContracts(t *testing.T) {
    cases:=[]struct{name string;source string;want string;failure string}{
        {"local valid","entry :: Int\nentry = let n :: (Int where it > 0) = 2 in n","2",""},
        {"local invalid","entry :: Int\nentry = let n :: (Int where it > 0) = -2 in n","","evaluation.refinement"},
        {"local unknown","entry :: Int\nentry = let n :: (Int where 1 / 0 > 0.0) = 2 in n","","evaluation.refinement_unknown"},
        {"parameter valid","f :: (Int where it > 0) -> Int\nf n = n + 1\nentry :: Int\nentry = f 2","3",""},
        {"parameter invalid","f :: (Int where it > 0) -> Bool\nf _ = True\nentry :: Bool\nentry = f (-2)","","evaluation.refinement"},
        {"result valid","f :: Int -> (Int where it > 0)\nf n = n + 1\nentry :: Int\nentry = f 2","3",""},
        {"result invalid","f :: Int -> (Int where it > 0)\nf n = n - 1\nentry :: Int\nentry = f 0","","evaluation.refinement"},
        {"partial eager precondition","f :: (Int where it > 0) -> Int -> Int\nf a b = a + b\nentry :: Bool\nentry = let partial = f (-1) in True","","evaluation.refinement"},
        {"higher order preserved","apply :: ((Int where it > 0) -> Int) -> Int\napply f = f (-1)\nid :: Int -> Int\nid n = n\nentry :: Int\nentry = apply id","","evaluation.refinement"},
        {"higher order postcondition","apply :: (Int -> (Int where it > 0)) -> Int\napply f = f 0\nid :: Int -> Int\nid n = n\nentry :: Int\nentry = apply id","","evaluation.refinement"},
        {"returned function contract","make :: Int -> ((Int where it > 0) -> Int)\nmake n = add n\nadd :: Int -> Int -> Int\nadd a b = a + b\nentry :: Int\nentry = make 2 (-1)","","evaluation.refinement"},
        {"inline list","f :: [Int where it > 0] -> Bool\nf _ = True\nentry :: Bool\nentry = f [1, -1]","","evaluation.refinement"},
        {"inline record","f :: {x :: Int where it > 0} -> Bool\nf _ = True\nentry :: Bool\nentry = f {x = -1}","","evaluation.refinement"},
        {"inline optional","f :: Maybe (Int where it > 0) -> Bool\nf _ = True\nentry :: Bool\nentry = f (Just (-1))","","evaluation.refinement"},
        {"inline absent","f :: Maybe (Int where it > 0) -> Bool\nf _ = True\nentry :: Bool\nentry = f Nothing","True",""},
        {"generic data argument","data Box a = Box a\nf :: Box (Int where it > 0) -> Bool\nf _ = True\nentry :: Bool\nentry = f (Box (-1))","","evaluation.refinement"},
        {"anonymous read","entry :: Bool\nentry = let parsed :: Result String (Int where it > 0) = read \"-1\" in case parsed of { Err _ -> False; Ok _ -> True }","False",""},
        {"generic anonymous read","parse :: String -> Result String a\nparse s = read s\nentry :: Bool\nentry = let parsed :: Result String (Int where it > 0) = parse \"-1\" in case parsed of { Err _ -> False; Ok _ -> True }","False",""},
        {"late read inference past annotation","entry :: Result String Int\nentry = let parse = read in let n :: (Int where it > 0) = 1 in parse (show n)","(Ok 1)",""},
    }
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){
        e,result,failure:=execution(t,tc.source,validation.Limits{})
        if tc.failure!=""{if failure==nil || failure.code!=tc.failure{t.Fatalf("got %v, want %s",failure,tc.failure)};return}
        if failure!=nil{t.Fatal(failure)}
        if shown:=e.show(result,Span{});shown!=tc.want{t.Fatalf("got %s, want %s",shown,tc.want)}
    })}
}

func TestNamedParentSubstitutionDoesNotRerunRules(t *testing.T) {
    // Validation still checks the derived clause after finding a base violation.
    // Reasserting the named Parent at the function boundary would add an unknown
    // child diagnostic, rather than the single conclusive parent violation.
    p:=validationProgram(t,"type Parent = Int where False @steps 1\ntype Child = Parent where accepts it\naccepts :: Parent -> Bool\naccepts _ = True")
    report:=p.ValidateData("Child",integerPayload(1),validation.Limits{})
    if validation.StateName(report.State())!="invalid" || report.Incomplete() || len(report.Diagnostics())!=1{t.Fatalf("%+v",report.Diagnostics())}
}
