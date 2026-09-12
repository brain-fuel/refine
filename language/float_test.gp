package language

import (
    "strings"
    "testing"

    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

func TestExplicitFiniteFloatConversions(t *testing.T){
    for _,tc:=range []struct{name,mode,typ string}{{"toFloat32","exact","Float32"},{"toFloat64","exact","Float64"},{"roundToFloat32","round","Float32"},{"roundToFloat64","round","Float64"},{"fromFloat32","from","Float32"},{"fromFloat64","from","Float64"}}{conversion,ok:=FixedFloatConversion(tc.name);if !ok||conversion.Mode!=tc.mode||conversion.Type!=tc.typ{t.Fatalf("conversion %s = %+v, %v",tc.name,conversion,ok)}}
    for _,name:=range []string{"toFloat16","toFloat032","toFloat32x","roundFloat32","wrapFloat32","fromFloat128","Float32"}{if _,ok:=FixedFloatConversion(name);ok{t.Fatalf("invalid conversion name accepted: %s",name)}}
    cases:=[]struct{typ,expression,want string}{
        {"Result String Float32","toFloat32 0.5","(Ok (1/2))"},
        {"Result String Float32","toFloat32 (1 / 3)",`(Err "conversion.precision: value is not exactly representable as finite Float32")`},
        {"Result String Float32","roundToFloat32 16777217.0","(Ok 16777216)"},
        {"Result String Float32","roundToFloat32 16777219.0","(Ok 16777220)"},
        {"Result String Float32","roundToFloat32 340282356779733661637539395458142568448.0",`(Err "conversion.overflow: rounded value is outside finite Float32 range")`},
        {"Result String Float64","toFloat64 9007199254740992.0","(Ok 9007199254740992)"},
        {"Result String Float64","toFloat64 9007199254740993.0",`(Err "conversion.precision: value is not exactly representable as finite Float64")`},
        {"Result String Float32",`read "1/2"`,"(Ok (1/2))"},
        {"Result String Float32",`read "1/3"`,"(Err \"read value does not satisfy the target type\")"},
        {"Result String Real","case toFloat32 0.5 of { Ok n -> Ok (fromFloat32 n); Err e -> Err e }","(Ok (1/2))"},
        {"Result String Real","case roundToFloat64 9007199254740993.0 of { Ok n -> Ok (fromFloat64 n); Err e -> Err e }","(Ok 9007199254740992)"},
        {"Result String String",`case toFloat32 0.5 of { Ok n -> Ok (show n); Err e -> Err e }`,`(Ok "1/2")`},
    }
    for _,tc:=range cases{t.Run(tc.expression,func(t *testing.T){
        e,result,failure:=execution(t,"entry :: "+tc.typ+"\nentry = "+tc.expression,validation.Limits{});if failure!=nil{t.Fatal(failure)}
        if shown:=e.show(result,Span{});shown!=tc.want{t.Fatalf("got %s, want %s",shown,tc.want)}
    })}
    for _,source:=range []string{
        "entry :: Float32\nentry = 1.0",
        "entry :: Result String Float32\nentry = toFloat32 1",
        "entry :: Real\nentry = fromFloat32 1.0",
        "entry :: Float32\nentry = roundToFloat32 1.0",
    }{if _,err:=Compile(source);err==nil{t.Fatalf("implicit or unchecked conversion accepted: %s",source)}}
    e,result,failure:=execution(t,"toFloat32 :: Int -> Int\ntoFloat32 n = n + 1\nentry :: Int\nentry = toFloat32 2",validation.Limits{});if failure!=nil||e.show(result,Span{})!="3"{t.Fatal("user conversion name did not shadow built-in",failure)}
}

func TestFiniteFloatPayloadReadShowAndArithmetic(t *testing.T){
    program:=validationProgram(t,"type F32 = Float32 where fromFloat32 it >= 0.0\ntype F64 = Float64\ntype Sum = Float32 where fromFloat32 (it + it) >= 0.0\ntype Product = Float32 where fromFloat32 (it * it) >= 0.0\n")
    for _,tc:=range []struct{root,text,state string}{
        {"F32","1/2","valid"},{"F32","1/3","invalid"},{"F32","-1/2","invalid"},
        {"F64","9007199254740992","valid"},{"F64","9007199254740993","invalid"},
        {"Sum","1/2","valid"},{"Sum","340282346638528859811704183484516925440","indeterminate"},
        {"Product","1/2","valid"},{"Product","1/713623846352979940529142984724747568191373312","indeterminate"},
    }{t.Run(tc.root+"/"+tc.text,func(t *testing.T){
        input,_:=value.TextFromUTF8(tc.text);data,report:=program.ReadData(tc.root,input,validation.Limits{})
        if got:=validation.StateName(report.State());got!=tc.state{t.Fatalf("got %s: %+v",got,report.Diagnostics())}
        if tc.state=="valid"{shown,err:=ShowDataWithoutValidation(data,validation.Limits{});if err!=nil{t.Fatal(err)};raw,err:=shown.UTF8();if err!=nil||raw!=tc.text{t.Fatalf("show = %q, %v",raw,err)}}
        if tc.state=="indeterminate"{found:=false;for _,diagnostic:=range report.Diagnostics(){if strings.Contains(diagnostic.Message,"evaluation.precision"){found=true}};if !found{t.Fatal("missing exact arithmetic precision diagnostic")}}
    })}
    source:="add :: Num a => a -> a -> a\nadd a b = a + b\nentry :: Result String Float32\nentry = case toFloat32 0.5 of { Ok n -> Ok (add n n); Err e -> Err e }"
    e,result,failure:=execution(t,source,validation.Limits{});if failure!=nil{t.Fatal(failure)};if e.show(result,Span{})!="(Ok 1)"{t.Fatal("Float32 did not satisfy Num")}
    if _,err:=Compile("bad :: Integral a => a -> a\nbad n = n % n\nentry :: Result String Float32\nentry = case toFloat32 1.0 of { Ok n -> Ok (bad n); Err e -> Err e }");err==nil||!strings.Contains(err.Error(),"integer type"){t.Fatalf("Float32 Integral accepted: %v",err)}
}
