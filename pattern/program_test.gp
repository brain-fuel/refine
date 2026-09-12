package pattern

import (
    "reflect"
    "testing"
    "testing/quick"
    "unicode"
)

func TestProgramSnapshotIsolation(t *testing.T) {
    if _,err:=(Regex{}).Program();err==nil||err.(*Error).Code!="regex.uncompiled"{t.Fatal("missing program accepted")}
    property:=func(choice uint8)bool{
        sources:=[]string{"(?i)[kσ]+","a|ab","(?m)^x$","[a-z]","\\bcat\\b","(?:x?)*"}
        re,err:=Compile(text(sources[int(choice)%len(sources)]),meter(1000000));if err!=nil{t.Fatal(err)}
        expected,err:=re.Program();if err!=nil{t.Fatal(err)}
        if expected.Profile!=InstructionProfile||expected.UnicodeVersion!=unicode.Version||expected.Start<0||expected.Start>=len(expected.Instructions){t.Fatal("invalid program metadata")}
        changed,err:=re.Program();if err!=nil{t.Fatal(err)}
        for i:=range changed.Instructions{
            if OpcodeName(changed.Instructions[i].Opcode)==""{t.Fatal("missing opcode name")}
            for j:=range changed.Instructions[i].Runes{changed.Instructions[i].Runes[j]=0}
            changed.Instructions[i].Out=999999;changed.Instructions[i].Arg=999999;changed.Instructions[i].Opcode=Fail()
        }
        changed.Start=-1;changed.Profile="changed";changed.UnicodeVersion="changed";changed.Instructions=nil
        actual,err:=re.Program();return err==nil&&reflect.DeepEqual(actual,expected)
    }
    if err:=quick.Check(property,&quick.Config{MaxCount:1000});err!=nil{t.Fatal(err)}
}

func TestLegacyModeFold(t *testing.T) {
    cases:=ModeCases[string]{Full:func()string{return "full"},Search:func()string{return "search"}}
    if Fold(Full(),cases)!="full"||Fold(Search(),cases)!="search"{t.Fatal("legacy Mode fold changed")}
}
