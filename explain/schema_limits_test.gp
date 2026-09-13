package explain

import (
    "encoding/json"
    "strings"
    "testing"

    "goforge.dev/refine/language"
)

func TestExplanationIncludesEffectiveSchemaLimits(t *testing.T){
    program,err:=language.Compile("@limits total 321 clause 17\ntype T = Int where it == it\n");if err!=nil{t.Fatal(err)};document,err:=Generate(program);if err!=nil{t.Fatal(err)};limits:=document.Limits();if limits.Total!=321||limits.Clause!=17||limits.TotalDefault||limits.ClauseDefault{t.Fatalf("wrong explanation limits: %+v",limits)};markdown:=document.Markdown();if !strings.Contains(markdown,"total validation limit is 321")||!strings.Contains(markdown,"default limit for each where clause is 17")||!strings.Contains(markdown,"schema's default clause limit of 17"){t.Fatalf("limit policy absent from explanation:\n%s",markdown)};encoded,err:=json.Marshal(document);if err!=nil||!strings.Contains(string(encoded),`"limits":{"total":321,"clause":17,"totalDefault":false,"clauseDefault":false}`){t.Fatalf("JSON limits absent: %s %v",encoded,err)}
    defaults,err:=language.Compile("type U = Int\n");if err!=nil{t.Fatal(err)};defaultDocument,err:=Generate(defaults);if err!=nil{t.Fatal(err)};if !defaultDocument.Limits().TotalDefault||!defaultDocument.Limits().ClauseDefault{t.Fatal("documented defaults were not identified")}
}
