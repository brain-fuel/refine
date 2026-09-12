package native

import (
    "strings"
    "testing"
    "time"
)

func TestRegexpTimeoutNeverBecomesBooleanResult(t *testing.T){
    old:=ecmaMatchTimeout;ecmaMatchTimeout=time.Nanosecond;defer func(){ecmaMatchTimeout=old}()
    subject:=`"`+strings.Repeat("a",20000)+`!"`
    schemas:=[]string{
        `{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"string","not":{"type":"string","pattern":"^(a+)+$"}}`,
        `{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"string","anyOf":[{"type":"string","pattern":"^(a+)+$"},{"type":"integer"}]}`,
    }
    for _,schemaSource:=range schemas{project,err:=IngestProject(JSONSchema,[]byte(schemaSource),ProjectOptions{});if err!=nil{t.Fatal(err)};for attempt:=0;attempt<3;attempt++{err=project.ValidateJSON([]byte(subject));if problemCode(err)!="native.enforcement"{t.Fatalf("regexp failure became a schema truth value: %v",err)}}}
}
