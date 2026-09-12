package value

import (
    "math"
    "math/big"
    "testing"
    "testing/quick"
)

func mustNumber(t *testing.T, text string) Number {
    t.Helper()
    n, err := ParseNumber(text)
    if err != nil { t.Fatal(err) }
    return n
}

func TestExactNumberCases(t *testing.T) {
    cases := []struct { input string; show string; decimal string }{
        {"0", "0", "0"}, {"-0", "0", "0"}, {"2/6", "1/3", ""},
        {"1.2500", "5/4", "1.25"}, {"1e-3", "1/1000", "0.001"},
        {"-1.5e2", "-150", "-150"}, {"9007199254740993", "9007199254740993", "9007199254740993"},
    }
    for _, tc := range cases {
        t.Run(tc.input, func(t *testing.T) {
            n := mustNumber(t, tc.input)
            if n.Show() != tc.show { t.Errorf("show = %s; want %s", n.Show(), tc.show) }
            decimal, err := n.Decimal()
            if tc.decimal == "" { if err == nil { t.Fatal("inexact decimal accepted") }; return }
            if err != nil || decimal != tc.decimal { t.Fatalf("decimal = %s, %v; want %s", decimal, err, tc.decimal) }
        })
    }
    for _, input := range []string{"", "NaN", "Infinity", "0x20", "01", "1/0", "1/-3", "+2", "1.", " 1", "1_000", "1e"} {
        if _, err := ParseNumber(input); err == nil { t.Errorf("accepted %q", input) }
    }
}

func TestExactArithmeticLaws(t *testing.T) {
    property := func(a, b, c int64) bool {
        x, y, z := Integer(a), Integer(b), Integer(c)
        original := x.Show()
        sum := x.Add(y)
        if sum.Subtract(y).Compare(x) != 0 || sum.Compare(y.Add(x)) != 0 { return false }
        if x.Multiply(y.Add(z)).Compare(x.Multiply(y).Add(x.Multiply(z))) != 0 { return false }
        if x.Show() != original { return false }
        shown, err := ParseNumber(sum.Show())
        if err != nil || shown.Compare(sum) != 0 { return false }
        if b != 0 {
            q, err := x.Divide(y)
            if err != nil || q.Multiply(y).Compare(x) != 0 { return false }
        }
        return true
    }
    if err := quick.Check(property, &quick.Config{MaxCount: 2000}); err != nil { t.Fatal(err) }
}

func TestFixedWidthAndExplicitWrapping(t *testing.T) {
    cases := []struct { input string; bits uint; signed bool; valid bool; wrapped string }{
        {"127", 8, true, true, "127"}, {"128", 8, true, false, "-128"},
        {"-128", 8, true, true, "-128"}, {"-129", 8, true, false, "127"},
        {"255", 8, false, true, "255"}, {"256", 8, false, false, "0"},
        {"-1", 8, false, false, "255"}, {"0", 1, true, true, "0"},
        {"1", 1, true, false, "-1"},
    }
    for _, tc := range cases {
        n := mustNumber(t, tc.input)
        _, err := n.FixedWidth(tc.bits, tc.signed)
        if (err == nil) != tc.valid { t.Errorf("%s fits %d signed=%v: %v", tc.input, tc.bits, tc.signed, err) }
        w, err := n.Wrap(tc.bits, tc.signed)
        if err != nil || w.Show() != tc.wrapped { t.Errorf("wrap %s: %s, %v", tc.input, w.Show(), err) }
    }
    if _, err := Integer(1).Divide(Integer(0)); err == nil { t.Fatal("division by zero accepted") }
    if _, err := mustNumber(t, "1/2").FixedWidth(8, true); err == nil { t.Fatal("fraction coerced to integer") }
    if _, err := mustNumber(t, "1/2").Wrap(8, true); err == nil { t.Fatal("fraction wrapped") }
    if (Number{}).Show() != "0" { t.Fatal("zero value is not zero") }
}

func TestRationalReadShowLaw(t *testing.T) {
    property := func(a int64, b uint64) bool {
        denominator := Integer(int64(b>>1) + 1)
        // int64 maximum + 1 wraps; any nonzero denominator still exercises the law.
        q, err := Integer(a).Divide(denominator)
        if err != nil { return false }
        read, err := ParseNumber(q.Show())
        return err == nil && read.Compare(q) == 0
    }
    if err := quick.Check(property, &quick.Config{MaxCount: 2000}); err != nil { t.Fatal(err) }
}

func TestIntegerRemainderSemantics(t *testing.T) {
    for _,tc:=range []struct{a,b,want int64}{{13,5,3},{-13,5,-3},{13,-5,3},{-13,-5,-3},{0,5,0}} {
        got,err:=Integer(tc.a).Remainder(Integer(tc.b));if err!=nil || got.Show()!=Integer(tc.want).Show(){t.Fatalf("%d %% %d = %s, %v",tc.a,tc.b,got.Show(),err)}
    }
    if _,err:=Integer(1).Remainder(Integer(0));err==nil{t.Fatal("zero divisor accepted")}
    if _,err:=mustNumber(t,"1/2").Remainder(Integer(1));err==nil{t.Fatal("fractional dividend accepted")}
    if _,err:=Integer(1).Remainder(mustNumber(t,"1/2"));err==nil{t.Fatal("fractional divisor accepted")}
}

func TestFiniteBinaryFloatExactAndExplicitRounding(t *testing.T){
    smallest32:=mustNumber(t,"1/713623846352979940529142984724747568191373312") // 2^-149
    largest32:=mustNumber(t,"340282346638528859811704183484516925440")
    for _,n:=range []Number{Number{},Integer(1),mustNumber(t,"1/2"),smallest32,largest32}{
        exact,err:=n.ExactFloat32();if err!=nil||exact.Compare(n)!=0{t.Fatalf("Float32 exact %s: %s, %v",n.Show(),exact.Show(),err)}
    }
    if _,err:=mustNumber(t,"1/3").ExactFloat32();err==nil{t.Fatal("non-dyadic Float32 accepted")}
    if _,err:=mustNumber(t,"16777217").ExactFloat32();err==nil{t.Fatal("rounded Float32 integer accepted as exact")}
    rounded,err:=mustNumber(t,"16777217").RoundFloat32();if err!=nil||rounded.Show()!="16777216"{t.Fatalf("Float32 tie = %s, %v",rounded.Show(),err)}
    rounded,err=mustNumber(t,"16777219").RoundFloat32();if err!=nil||rounded.Show()!="16777220"{t.Fatalf("Float32 odd tie = %s, %v",rounded.Show(),err)}
    halfSmall,err:=smallest32.Divide(Integer(2));if err!=nil{t.Fatal(err)}
    rounded,err=halfSmall.RoundFloat32();if err!=nil||rounded.Sign()!=0{t.Fatalf("Float32 zero tie = %s, %v",rounded.Show(),err)}
    aboveHalf,err:=smallest32.Multiply(mustNumber(t,"3/4")).RoundFloat32();if err!=nil||aboveHalf.Compare(smallest32)!=0{t.Fatalf("Float32 subnormal rounding = %s, %v",aboveHalf.Show(),err)}
    if _,err:=mustNumber(t,"340282356779733661637539395458142568448").RoundFloat32();err==nil{t.Fatal("Float32 infinity boundary accepted")}

    exact64:=mustNumber(t,"9007199254740992");if _,err:=exact64.ExactFloat64();err!=nil{t.Fatal(err)}
    if _,err:=mustNumber(t,"9007199254740993").ExactFloat64();err==nil{t.Fatal("rounded Float64 integer accepted as exact")}
    rounded,err=mustNumber(t,"9007199254740993").RoundFloat64();if err!=nil||rounded.Show()!="9007199254740992"{t.Fatalf("Float64 tie = %s, %v",rounded.Show(),err)}
    negative,err:=mustNumber(t,"-9007199254740995").RoundFloat64();if err!=nil||negative.Show()!="-9007199254740996"{t.Fatalf("negative Float64 tie = %s, %v",negative.Show(),err)}
}

func TestBinaryFloatQuantizationMatchesIEEEOracle(t *testing.T){
    exact32Bits:=func(bits uint32)bool{
        raw:=math.Float32frombits(bits);if math.IsNaN(float64(raw))||math.IsInf(float64(raw),0){return true}
        rational:=new(big.Rat).SetFloat64(float64(raw));n:=numberFromRat(rational);exact,err:=n.ExactFloat32();return err==nil&&exact.Compare(n)==0
    }
    if err:=quick.Check(exact32Bits,&quick.Config{MaxCount:3000});err!=nil{t.Fatal(err)}
    exactBits:=func(bits uint64)bool{
        raw:=math.Float64frombits(bits);if math.IsNaN(raw)||math.IsInf(raw,0){return true}
        rational:=new(big.Rat).SetFloat64(raw);if rational==nil{return false};n:=numberFromRat(rational);exact,err:=n.ExactFloat64();return err==nil&&exact.Compare(n)==0
    }
    if err:=quick.Check(exactBits,&quick.Config{MaxCount:3000});err!=nil{t.Fatal(err)}
    rounded:=func(numerator int64,rawDenominator uint32)bool{
        denominator:=int64(rawDenominator)+1;r:=new(big.Rat).SetFrac(big.NewInt(numerator),big.NewInt(denominator));n:=numberFromRat(r)
        want32,_:=r.Float32();got32,err32:=n.RoundFloat32()
        if math.IsInf(float64(want32),0){if err32==nil{return false}}else{expected:=numberFromRat(new(big.Rat).SetFloat64(float64(want32)));if err32!=nil||got32.Compare(expected)!=0{return false}}
        want64,_:=r.Float64();got64,err64:=n.RoundFloat64()
        if math.IsInf(want64,0){return err64!=nil};expected:=numberFromRat(new(big.Rat).SetFloat64(want64));return err64==nil&&got64.Compare(expected)==0
    }
    if err:=quick.Check(rounded,&quick.Config{MaxCount:3000});err!=nil{t.Fatal(err)}

    smallest64:=numberFromRat(new(big.Rat).SetFloat64(math.SmallestNonzeroFloat64));if _,err:=smallest64.ExactFloat64();err!=nil{t.Fatal(err)}
    half64,err:=smallest64.Divide(Integer(2));if err!=nil{t.Fatal(err)};zero,err:=half64.RoundFloat64();if err!=nil||zero.Sign()!=0{t.Fatalf("Float64 zero tie = %s, %v",zero.Show(),err)}
    above64,err:=smallest64.Multiply(mustNumber(t,"3/4")).RoundFloat64();if err!=nil||above64.Compare(smallest64)!=0{t.Fatalf("Float64 subnormal rounding = %s, %v",above64.Show(),err)}
    maximum:=numberFromRat(new(big.Rat).SetFloat64(math.MaxFloat64));if _,err:=maximum.ExactFloat64();err!=nil{t.Fatal(err)}
    previous:=numberFromRat(new(big.Rat).SetFloat64(math.Nextafter(math.MaxFloat64,0)));gap:=maximum.Subtract(previous);halfGap,err:=gap.Divide(Integer(2));if err!=nil{t.Fatal(err)}
    if _,err:=maximum.Add(halfGap).RoundFloat64();err==nil{t.Fatal("Float64 infinity tie accepted")}
}
