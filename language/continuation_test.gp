package language

import (
    "testing"

    "goforge.dev/refine/validation"
)

func TestLeadingInfixContinuation(t *testing.T){
    for _,expression:=range []string{"1 + 2\n * 3", "1\n + 2 * 3", "(1\n + 2) * 3"}{
        _,_,failure:=execution(t,"entry :: Int\nentry = "+expression,validation.Limits{});if failure!=nil{t.Fatal(failure)}
    }
    program,err:=Compile("type T = Int where it > 0\n && it < 10\ntype U = Bool\n");if err!=nil||len(program.Syntax().Types)!=2{t.Fatal("continuation consumed declaration",err)}
    flat,err:=Compile("type T = Int where it > 0 && it < 10\ntype U = Bool\n");if err!=nil||program.Formatted()!=flat.Formatted(){t.Fatal("continuation changed precedence",err)}
}
