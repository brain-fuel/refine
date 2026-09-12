package language

import (
    "testing"

    "goforge.dev/refine/validation"
)

func TestLocallyAnnotatedEnclosingTypeVariables(t *testing.T){
    source:=`copy :: a -> a
copy x = let y :: a = x in y
roundTrip :: a -> Result String a
roundTrip x = let restored :: Result String a = read (show x) in restored
checked :: a -> a
checked x = let y :: (a where True) = x in y
type Box a = { value :: a } where (let same :: a = it.value in length (show same) > 0)
entry :: [Result String Int]
entry = [roundTrip (copy 4), roundTrip (checked 7)]
`
    evaluator,result,failure:=execution(t,source,validation.Limits{});if failure!=nil{t.Fatal(failure)};if actual:=evaluator.show(result,Span{});actual!="[(Ok 4), (Ok 7)]"{t.Fatal(actual)}
    bad:=[]string{"copy :: a -> a\ncopy x = let y :: b = x in y","copy :: a -> a\ncopy x = let y :: a = 1 in y","first :: a -> a\nfirst x = x\nsecond :: Int -> Int\nsecond x = let y :: a = x in y"}
    for _,text:=range bad{if _,err:=Compile(text);err==nil{t.Fatal("undeclared, mismatched, or leaked generic annotation accepted")}}
}
