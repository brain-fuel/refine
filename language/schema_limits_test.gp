package language

import (
    "errors"
    "strings"
    "testing"

    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

func TestSchemaLimitsParseFormatAndRejectMalformedDeclarations(t *testing.T){
    module,err:=Parse("package example.limits\n@limits clause 17 total 101\ntype T = Int\n");if err!=nil{t.Fatal(err)};if module.Limits.Total!=101||module.Limits.Clause!=17{t.Fatalf("limits lost: %+v",module.Limits)};formatted:=Format(module);if !strings.Contains(formatted,"@limits total 101 clause 17\n") {t.Fatalf("limits not canonical:\n%s",formatted)};again,err:=Parse(formatted);if err!=nil||again.Limits.Total!=101||again.Limits.Clause!=17{t.Fatal("formatted limits do not parse",err)}
    invalid:=[]string{"@limits\ntype T = Int","@limits total 0\ntype T = Int","@limits total 1.0\ntype T = Int","@limits total 18446744073709551616\ntype T = Int","@limits other 1\ntype T = Int","@limits total 1 total 2\ntype T = Int","@limits total 1\n@limits clause 2\ntype T = Int","@unknown total 1\ntype T = Int"};for _,source:=range invalid{if _,err:=Parse(source);err==nil{t.Fatalf("invalid limits accepted: %q",source)}else{var problem *Error;if !errors.As(err,&problem)||problem.Code!="language.syntax"{t.Fatalf("wrong error for %q: %v",source,err)}}}
}

func TestImportedSchemaLimitsUseExplicitComponentMinimum(t *testing.T){
    sources:=map[string]string{"app/main.refine":"package example.app\n@limits total 500\nimport \"../lib/a.refine\"\nimport \"../lib/b.refine\"\ntype Root = A\n","lib/a.refine":"@limits total 700 clause 40\ntype A = B\n","lib/b.refine":"@limits clause 90\ntype B = Int\n"};bundle,err:=CompileSources("app/main.refine",sources);if err!=nil{t.Fatal(err)};limits:=bundle.Program().SchemaLimits();if limits.Total!=500||limits.Clause!=40{t.Fatalf("wrong effective limits: %+v",limits)};if strings.Count(bundle.Program().Source(),"@limits")!=1||!strings.Contains(bundle.Program().Source(),"@limits total 500 clause 40"){t.Fatalf("flattened limits are not singular/effective:\n%s",bundle.Program().Source())};files:=bundle.Files();found:=false;for _,file:=range files{if file.ID=="lib/a.refine"&&strings.Contains(file.Source,"@limits total 700 clause 40"){found=true}};if !found{t.Fatal("original imported limit source was not retained")}
}

func TestSchemaAndCallerBudgetsApplyToValidatePayloadAndRead(t *testing.T){
    source:="@limits total 1000 clause 1\ntype Default = Int where it == it\ntype Override = Int where it == it @steps 100\n";program,err:=Compile(source);if err!=nil{t.Fatal(err)};limits:=program.SchemaLimits();limits.Total=1;if program.SchemaLimits().Total!=1000{t.Fatal("schema limits accessor aliases compiler state")};one:=value.OfNumber(value.Integer(1));if state:=validation.StateName(program.ValidateData("Default",one,validation.Limits{}).State());state!="indeterminate"{t.Fatalf("schema default clause limit not applied: %s",state)};if state:=validation.StateName(program.ValidateData("Override",one,validation.Limits{}).State());state!="valid"{t.Fatalf("@steps did not override schema clause default: %s",state)};if state:=validation.StateName(program.ValidateData("Override",one,validation.Limits{Clause:1}).State());state!="indeterminate"{t.Fatalf("caller clause limit relaxed: %s",state)};target,err:=program.PayloadType("Override");if err!=nil{t.Fatal(err)};if state:=validation.StateName(target.ValidateData(one,validation.Limits{Clause:1}).State());state!="indeterminate"{t.Fatalf("payload handle ignored caller/schema limits: %s",state)};text,_:=value.TextFromUTF8("1");if _,report:=program.ReadData("Override",text,validation.Limits{Total:1});validation.StateName(report.State())!="indeterminate"{t.Fatalf("read ignored total limit: %+v",report)}
}
