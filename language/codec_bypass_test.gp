package language

import (
    "math/rand"
    "testing"
    "testing/quick"

    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

func TestStructuralReadBypassRetainsRepresentationAndResourceChecks(t *testing.T){
    program:=validationProgram(t,`type Positive = Int where it > 0
type Byte = UInt8 where False
type Fraction = Float32 where fromFloat32 it > 0.0
type Time = Timestamp where False
type Unknown = Int where 1 / 0 > 0.0
type Box a = {value :: a}
type Nested = Box [Positive]
data Tree a = Leaf a | Branch (Tree a) (Tree a)
type Recursive = Tree Positive
`)
    cases:=[]struct{name,root,input,state,normal,canonical string;limits validation.Limits}{
        {"predicate","Positive","-1","valid","invalid","-1",validation.Limits{}},
        {"fixed width refinement","Byte","0","valid","invalid","0",validation.Limits{}},
        {"fixed width overflow","Byte","256","invalid","invalid","",validation.Limits{}},
        {"negative unsigned","Byte","-1","invalid","invalid","",validation.Limits{}},
        {"fractional integer","Positive","1/2","invalid","invalid","",validation.Limits{}},
        {"finite float","Fraction","-1/2","valid","invalid","-1/2",validation.Limits{}},
        {"inexact float","Fraction","1/3","invalid","invalid","",validation.Limits{}},
        {"timestamp","Time",`"2020-01-01T00:00:00Z"`,"valid","invalid",`"2020-01-01T00:00:00Z"`,validation.Limits{}},
        {"bad timestamp","Time",`"2020-13-01T00:00:00Z"`,"invalid","invalid","",validation.Limits{}},
        {"unknown refinement","Unknown","1","valid","indeterminate","1",validation.Limits{}},
        {"nested generic","Nested","{value = [-1, 2]}","valid","invalid","{value = [-1, 2]}",validation.Limits{}},
        {"recursive","Recursive","(Branch (Leaf (-1)) (Leaf 2))","valid","invalid","(Branch (Leaf (-1)) (Leaf 2))",validation.Limits{}},
        {"bad shape","Nested","{value = False}","invalid","invalid","",validation.Limits{}},
        {"missing field","Nested","{}","invalid","invalid","",validation.Limits{}},
        {"expression is not data","Positive","1 + 2","invalid","invalid","",validation.Limits{}},
        {"numeric expansion","Positive","1e999999999999999999999","indeterminate","indeterminate","",validation.Limits{}},
        {"caller budget","Nested","{value = [-1, 2]}","indeterminate","indeterminate","",validation.Limits{Total:1,Clause:1}},
    }
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){
        text,_:=value.TextFromUTF8(tc.input);data,report:=program.ReadDataWithoutRefinements(tc.root,text,tc.limits)
        if got:=validation.StateName(report.State());got!=tc.state{t.Fatalf("bypass %s, want %s: %+v",got,tc.state,report.Diagnostics())}
        _,normal:=program.ReadData(tc.root,text,tc.limits);if got:=validation.StateName(normal.State());got!=tc.normal{t.Fatalf("normal %s, want %s: %+v",got,tc.normal,normal.Diagnostics())}
        if tc.state!="valid"{if tag,ok:=data.Constructor();!ok||tag!="Null"{t.Fatal("failed read exposed candidate")};return}
        shown,err:=ShowDataWithoutValidation(data,validation.Limits{});if err!=nil{t.Fatal(err)};raw,err:=shown.UTF8();if err!=nil||raw!=tc.canonical{t.Fatalf("canonical = %q (%v), want %q",raw,err,tc.canonical)}
        if structural:=program.ValidateDataWithoutRefinements(tc.root,data,validation.Limits{});validation.StateName(structural.State())!="valid"{t.Fatal(structural.Diagnostics())}
        if checked:=program.ValidateData(tc.root,data,validation.Limits{});validation.StateName(checked.State())!=tc.normal{t.Fatalf("revalidation lost predicates: %+v",checked.Diagnostics())}
    })}
}

func TestStructuralReadBypassClosedTargetsAndIsolation(t *testing.T){
    program:=validationProgram(t,"type Positive = Int where it > 0\ntype Box a = {value :: a}\n")
    target,err:=program.PayloadType("Box (Int where it > 0)");if err!=nil{t.Fatal(err)}
    text,_:=value.TextFromUTF8("{value = -3}");data,report:=target.ReadDataWithoutRefinements(text,validation.Limits{});if validation.StateName(report.State())!="valid"{t.Fatal(report.Diagnostics())}
    _,checked:=target.ReadData(text,validation.Limits{});if validation.StateName(checked.State())!="invalid"{t.Fatal("bypass mutated checked target")}
    if checked:=target.ValidateData(data,validation.Limits{});validation.StateName(checked.State())!="invalid"{t.Fatal("bypass erased inline rule")}
    var missingProgram *Program;var missingTarget *PayloadType;zeroProgram:=&Program{};zeroTarget:=&PayloadType{}
    for _,read:=range []func(value.Text,validation.Limits)(value.Data,validation.Report){missingTarget.ReadDataWithoutRefinements,zeroTarget.ReadDataWithoutRefinements,func(text value.Text,limits validation.Limits)(value.Data,validation.Report){return missingProgram.ReadDataWithoutRefinements("Positive",text,limits)},func(text value.Text,limits validation.Limits)(value.Data,validation.Report){return zeroProgram.ReadDataWithoutRefinements("Positive",text,limits)},func(text value.Text,limits validation.Limits)(value.Data,validation.Report){return program.ReadDataWithoutRefinements("Box",text,limits)},func(text value.Text,limits validation.Limits)(value.Data,validation.Report){return program.ReadDataWithoutRefinements("Missing",text,limits)}}{_,report:=read(text,validation.Limits{});if validation.StateName(report.State())!="invalid"||report.Diagnostics()[0].Code!="validation.root"{t.Fatal("unusable root accepted",report.Diagnostics())}}
    property:=func(n int64)bool{original:=value.OfNumber(value.Integer(n));shown,err:=ShowDataWithoutValidation(original,validation.Limits{});if err!=nil{return false};decoded,report:=program.ReadDataWithoutRefinements("Positive",shown,validation.Limits{});same,err:=original.EqualWith(decoded,func(uint64)error{return nil});return err==nil&&same&&validation.StateName(report.State())=="valid"}
    if err:=quick.Check(property,&quick.Config{MaxCount:1000,Rand:rand.New(rand.NewSource(419))});err!=nil{t.Fatal(err)}
}
