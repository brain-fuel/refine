package value

import (
    "fmt"
    "testing"
    "testing/quick"
)

func TestExplicitRounding(t *testing.T){
    for _,test:=range []struct{raw string;trunc string;floor string;ceil string;even string}{
        {"1/3","0","0","1","0"},{"-1/3","0","-1","0","0"},
        {"3/2","1","1","2","2"},{"5/2","2","2","3","2"},
        {"-3/2","-1","-2","-1","-2"},{"-5/2","-2","-3","-2","-2"},
        {"7/2","3","3","4","4"},{"-7/2","-3","-4","-3","-4"},
        {"2","2","2","2","2"},{"0","0","0","0","0"},
        {"9007199254740993/2","4503599627370496","4503599627370496","4503599627370497","4503599627370496"},
    }{n,err:=ParseNumber(test.raw);if err!=nil{t.Fatal(err)};actual:=[]string{n.Truncate().Show(),n.Floor().Show(),n.Ceiling().Show(),n.RoundHalfEven().Show()};expected:=[]string{test.trunc,test.floor,test.ceil,test.even};for i:=range actual{if actual[i]!=expected[i]{t.Errorf("%s mode%d got %s want%s",test.raw,i,actual[i],expected[i])}};if n.Show()!=test.raw{t.Fatal("rounding mutated raw value")}}
}
func TestRoundingLaws(t *testing.T){
    property:=func(n int32,divisor uint16)bool{
        denominator:=int64(divisor)+1;x,_:=ParseNumber(fmt.Sprintf("%d/%d",n,denominator));lo,hi,nearest:=x.Floor(),x.Ceiling(),x.RoundHalfEven()
        distance:=nearest.Subtract(x);if distance.Sign()<0{distance=distance.Negate()};half,_:=ParseNumber("1/2")
        return lo.IsInteger()&&hi.IsInteger()&&nearest.IsInteger()&&lo.Compare(x)<=0&&hi.Compare(x)>=0&&hi.Subtract(lo).Compare(Integer(1))<=0&&distance.Compare(half)<=0&&x.Negate().RoundHalfEven().Compare(nearest.Negate())==0
    };if err:=quick.Check(property,&quick.Config{MaxCount:10000});err!=nil{t.Fatal(err)}
}
