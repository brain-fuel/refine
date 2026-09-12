package native

import (
    "fmt"
    "unicode/utf8"

    "goforge.dev/refine/language"
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

const ExampleCatalogVersion="refine.examples/v1"
const MaxEmbeddedExamples=64
const MaxEmbeddedExampleBytes=64<<10
const MaxEmbeddedExamplesBytes=1<<20
const embeddedExampleSteps uint64=100000
const embeddedExampleNameBytes=128
const embeddedExampleCodeBytes=1024

type ExampleExpectation string
const (ExpectedValid ExampleExpectation="valid";ExpectedInvalid ExampleExpectation="invalid")
type NativeExampleExpectation string
const (NativeExpectedValid NativeExampleExpectation="valid";NativeExpectedInvalid NativeExampleExpectation="invalid")

// ExampleCatalog contains canonical Refine values, never untyped native JSON.
// Omitted expectations normalize to valid. Case order is stable metadata and
// therefore participates in bundle and release identity.
type ExampleCatalog struct {Version string `json:"version"`;Cases []ExampleCase `json:"cases"`}
type ExampleCase struct {
    Name string `json:"name"`
    Target string `json:"target"`
    Value string `json:"value"`
    Expected ExampleExpectation `json:"expected,omitempty"`
    DiagnosticCodes []string `json:"diagnosticCodes,omitempty"`
    NativeExpected NativeExampleExpectation `json:"nativeExpected,omitempty"`
}

// CheckedExample is the structure-checked, immutable adapter-neutral form.
// NativeExpected remains an authored assertion: only a configured generated
// native wire adapter can execute it.
type CheckedExample struct {Name string;Target string;Value value.Data;Expected ExampleExpectation;DiagnosticCodes []string;NativeExpected NativeExampleExpectation}

func normalizedExpected(value ExampleExpectation)(ExampleExpectation,bool){if value==""{return ExpectedValid,true};return value,value==ExpectedValid||value==ExpectedInvalid}
func normalizedNativeExpected(value NativeExampleExpectation)(NativeExampleExpectation,bool){if value==""{return NativeExpectedValid,true};return value,value==NativeExpectedValid||value==NativeExpectedInvalid}
func stableExampleName(name string)bool{if name==""||len(name)>embeddedExampleNameBytes||!utf8.ValidString(name){return false};for i,r:=range name{if !(r>='A'&&r<='Z'||r>='a'&&r<='z'||i>0&&(r>='0'&&r<='9'||r=='.'||r=='_'||r=='-')){return false}};return true}
func reportContainsCode(report validation.Report,code string)bool{for _,detail:=range report.Diagnostics(){if detail.Code==code{return true}};return false}

func copyExampleCatalog(input *ExampleCatalog)*ExampleCatalog{if input==nil{return nil};out:=&ExampleCatalog{Version:input.Version,Cases:make([]ExampleCase,len(input.Cases))};for i,item:=range input.Cases{out.Cases[i]=item;out.Cases[i].DiagnosticCodes=append([]string(nil),item.DiagnosticCodes...)};return out}
func exampleCatalogEqual(left,right *ExampleCatalog)bool{if left==nil||right==nil{return left==right};if left.Version!=right.Version||len(left.Cases)!=len(right.Cases){return false};for i,item:=range left.Cases{other:=right.Cases[i];if item.Name!=other.Name||item.Target!=other.Target||item.Value!=other.Value||item.Expected!=other.Expected||item.NativeExpected!=other.NativeExpected||len(item.DiagnosticCodes)!=len(other.DiagnosticCodes){return false};for j,code:=range item.DiagnosticCodes{if code!=other.DiagnosticCodes[j]{return false}}};return true}

// CheckExamples validates bounded canonical typed values and their Refine
// outcomes. It deliberately does not claim native validity: NativeExpected is
// retained for a generated JSON/Avro adapter to execute later.
func CheckExamples(program *language.Program,catalog *ExampleCatalog)([]CheckedExample,error){
    if catalog==nil{return nil,nil};if program==nil{return nil,fmt.Errorf("examples require a checked program")};if _,err:=program.PayloadType("Int");err!=nil{return nil,fmt.Errorf("examples require a checked program")};if catalog.Version!=ExampleCatalogVersion{return nil,fmt.Errorf("examples version must be %q",ExampleCatalogVersion)};if len(catalog.Cases)==0{return nil,fmt.Errorf("examples catalog must contain at least one case")};if len(catalog.Cases)>MaxEmbeddedExamples{return nil,fmt.Errorf("examples catalog exceeds %d cases",MaxEmbeddedExamples)}
    declarations:=map[string]language.TypeDecl{};for _,decl:=range program.Syntax().Types{declarations[decl.Name]=decl};names:=map[string]bool{};total:=0;result:=make([]CheckedExample,0,len(catalog.Cases))
    for i,item:=range catalog.Cases{
        label:=fmt.Sprintf("example %d",i);if !stableExampleName(item.Name){return nil,fmt.Errorf("%s name must be a stable ASCII identifier of at most %d bytes",label,embeddedExampleNameBytes)};if names[item.Name]{return nil,fmt.Errorf("duplicate example name %s",item.Name)};names[item.Name]=true
        decl,ok:=declarations[item.Target];if !ok||len(decl.Parameters)>0{return nil,fmt.Errorf("%s target %s must be a closed declared type",item.Name,item.Target)}
        if !utf8.ValidString(item.Value){return nil,fmt.Errorf("%s value is not UTF-8",item.Name)};if len(item.Value)>MaxEmbeddedExampleBytes{return nil,fmt.Errorf("%s value exceeds %d bytes",item.Name,MaxEmbeddedExampleBytes)};if len(item.Value)>MaxEmbeddedExamplesBytes-total{return nil,fmt.Errorf("examples values exceed %d aggregate bytes",MaxEmbeddedExamplesBytes)};total+=len(item.Value)
        expected,ok:=normalizedExpected(item.Expected);if !ok{return nil,fmt.Errorf("%s has invalid expected outcome %q",item.Name,item.Expected)};nativeExpected,ok:=normalizedNativeExpected(item.NativeExpected);if !ok{return nil,fmt.Errorf("%s has invalid native expected outcome %q",item.Name,item.NativeExpected)}
        if expected==ExpectedValid&&len(item.DiagnosticCodes)!=0{return nil,fmt.Errorf("valid %s cannot require diagnostics",item.Name)};if expected==ExpectedInvalid&&len(item.DiagnosticCodes)!=1{return nil,fmt.Errorf("invalid %s must require exactly one diagnostic code",item.Name)};for _,code:=range item.DiagnosticCodes{if code==""||len(code)>embeddedExampleCodeBytes||!utf8.ValidString(code){return nil,fmt.Errorf("%s has an invalid diagnostic code",item.Name)}};if nativeExpected==NativeExpectedInvalid&&(expected!=ExpectedValid||len(item.DiagnosticCodes)!=0){return nil,fmt.Errorf("native-invalid %s must be Refine-valid and cannot claim refinement diagnostics",item.Name)}
        text,err:=value.TextFromUTF8(item.Value);if err!=nil{return nil,fmt.Errorf("%s value is not canonical text: %w",item.Name,err)};data,structural:=program.ReadDataWithoutRefinements(item.Target,text,validation.Limits{Total:embeddedExampleSteps,Clause:embeddedExampleSteps});if validation.StateName(structural.State())!="valid"||structural.Incomplete(){return nil,fmt.Errorf("%s value is not conclusively structure-valid: %s",item.Name,validation.StateName(structural.State()))};shown,err:=language.ShowDataWithoutValidation(data,validation.Limits{Total:embeddedExampleSteps,Clause:embeddedExampleSteps});if err!=nil{return nil,fmt.Errorf("%s value cannot be shown canonically: %w",item.Name,err)};canonical,err:=shown.UTF8();if err!=nil||canonical!=item.Value{return nil,fmt.Errorf("%s value must use exact canonical Refine text",item.Name)}
        checked:=program.ValidateData(item.Target,data,validation.Limits{Total:embeddedExampleSteps,Clause:embeddedExampleSteps});state:=validation.StateName(checked.State());if checked.Incomplete(){return nil,fmt.Errorf("%s Refine expectation is incomplete",item.Name)};if expected==ExpectedValid&&state!="valid"{return nil,fmt.Errorf("%s expected valid but was %s",item.Name,state)};if expected==ExpectedInvalid&&(state!="invalid"||!reportContainsCode(checked,item.DiagnosticCodes[0])){return nil,fmt.Errorf("%s expected complete invalid containing diagnostic %s",item.Name,item.DiagnosticCodes[0])}
        result=append(result,CheckedExample{Name:item.Name,Target:item.Target,Value:data,Expected:expected,DiagnosticCodes:append([]string(nil),item.DiagnosticCodes...),NativeExpected:nativeExpected})
    }
    return result,nil
}
