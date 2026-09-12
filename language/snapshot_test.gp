package language

import (
    "testing"
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

func TestCheckedSnapshotIsolation(t *testing.T){
    source:="id :: a -> a\nid x = x\ntype Box a = { value :: a }\ntype T = Int where id it >= 0"
    program,err:=Compile(source);if err!=nil{t.Fatal(err)}
    first,second:=program.CheckedSyntax(),program.CheckedSyntax()
    if len(first.Inferred)==0||len(first.FunctionScopes["id"])==0||len(first.DeclarationScopes["Box"])==0{t.Fatal("checked metadata missing")}
    if _,found:=first.Inferred[first.Syntax.Functions[0].Equations[0].Body];!found{t.Fatal("inferred keys do not refer to the returned syntax")}
    for expr,typ:=range first.Inferred{
        if _,shared:=second.Inferred[expr];shared{t.Fatal("expression identity shared between snapshots")}
        expr.Form=BoolLiteral(false);typ.Form=NamedType("Corrupted")
    }
    first.Syntax.Source="changed";first.Syntax.Functions[0].Signature.Form=NamedType("Changed")
    first.FunctionScopes["id"]["a"]="changed";first.DeclarationScopes["Box"]["a"]="changed"
    if program.Source()!=source||second.FunctionScopes["id"]["a"]=="changed"||second.DeclarationScopes["Box"]["a"]=="changed"{t.Fatal("snapshot mutation escaped")}
    for _,n:=range []int64{-1,0,1}{
        report:=program.ValidateData("T",value.OfNumber(value.Integer(n)),validation.Limits{})
        expected:="valid";if n<0{expected="invalid"}
        if validation.StateName(report.State())!=expected{t.Fatal("snapshot mutated checked execution")}
    }
    third:=program.CheckedSyntax()
    if Format(third.Syntax)!=program.Formatted(){t.Fatal("snapshot changed source structure")}
    for _,typ:=range third.Inferred{match typ.Form{case NamedType(name):if name=="Corrupted"{t.Fatal("inferred type leaked")};case _:}}
}
