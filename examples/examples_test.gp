package examples

import (
    "os"
    "testing"

    "goforge.dev/refine/analysis"
    "goforge.dev/refine/explain"
    "goforge.dev/refine/language"
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

func TestWorkedExamples(t *testing.T){
    cases:=[]struct{file string;root string;valid string;invalid string}{
        {"booking.refine","Booking",`{checkIn = "2026-01-01T00:00:00Z", checkOut = "2026-01-02T00:00:00Z"}`,`{checkIn = "2026-01-01T00:00:00Z", checkOut = "2026-03-02T00:00:00Z"}`},
        {"invoice.refine","Invoice",`{lines = [{price = 1.005, quantity = 1}, {price = 1.015, quantity = 1}], totalCents = 202}`,`{lines = [{price = 1.005, quantity = 1}], totalCents = 101}`},
        {"batch.refine","Batch",`[{id = "root", parent = Nothing}, {id = "child", parent = Just "root"}]`,`[{id = "child", parent = Just "missing"}]`},
        {"deployment.refine","Deployment",`[{id = "db", dependencies = []}, {id = "api", dependencies = ["db"]}]`,`[{id = "db", dependencies = ["api"]}, {id = "api", dependencies = ["db"]}]`},
        {"payment.refine","Payment",`Card "token" 1.25`,`BankTransfer "x" 0`},
        {"expression.refine","Expression",`IfThenElse (EqualExpr (IntegerLiteral 1) (IntegerLiteral 2)) (Plus (IntegerLiteral 3) (IntegerLiteral 4)) (IntegerLiteral 0)`,`Plus (IntegerLiteral 1) (BooleanLiteral True)`},
        {"polygon.refine","Polygon",`[{x = 0, y = 0}, {x = 2, y = 0}, {x = 2, y = 2}, {x = 0, y = 2}, {x = 0, y = 0}]`,`[{x = 0, y = 0}, {x = 2, y = 2}, {x = 2, y = 0}, {x = 0, y = 2}, {x = 0, y = 0}]`},
    }
    for _,test:=range cases{t.Run(test.root,func(t *testing.T){source,err:=os.ReadFile(test.file);if err!=nil{t.Fatal(err)};program,err:=language.Compile(string(source));if err!=nil{t.Fatal(err)};if _,err:=explain.Generate(program);err!=nil{t.Fatal(err)};for _,sample:=range []struct{raw string;want string}{{test.valid,"valid"},{test.invalid,"invalid"}}{text,err:=value.TextFromUTF8(sample.raw);if err!=nil{t.Fatal(err)};_,report:=program.ReadData(test.root,text,validation.Limits{});if validation.StateName(report.State())!=sample.want{t.Fatalf("want %s got %+v",sample.want,report)}}})}
}

func TestEvolutionExample(t *testing.T){
    oldSource,err:=os.ReadFile("evolution/v1.0.0.refine");if err!=nil{t.Fatal(err)};newSource,err:=os.ReadFile("evolution/SNAPSHOT.refine");if err!=nil{t.Fatal(err)}
    old,err:=language.Compile(string(oldSource));if err!=nil{t.Fatal(err)};next,err:=language.Compile(string(newSource));if err!=nil{t.Fatal(err)}
    result,err:=analysis.Compare(old,"Age",next,"Age",validation.Limits{});if err!=nil||result.Backward.Outcome!=analysis.Yes||result.Forward.Outcome!=analysis.No{t.Fatal(result,err)}
}
