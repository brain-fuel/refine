package native

import (
    "strings"
    "testing"
    "time"

    jsonoracle "github.com/santhosh-tekuri/jsonschema/v6"
    "goforge.dev/refine/internal/ecmaregex"
)

func TestRegexpTimeoutNeverBecomesBooleanResult(t *testing.T){
    subject:=`"`+strings.Repeat("a",20000)+`!"`
    schemas:=[]string{
        `{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"string","not":{"type":"string","pattern":"^(a+)+$"}}`,
        `{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"string","anyOf":[{"type":"string","pattern":"^(a+)+$"},{"type":"integer"}]}`,
    }
    limits:=ecmaregex.DefaultLimits();limits.MaxDuration=time.Nanosecond
    for _,schemaSource:=range schemas{for attempt:=0;attempt<3;attempt++{err:=validateRegexFixture(schemaSource,subject,limits);if problemCode(err)!="native.limit"{t.Fatalf("regexp failure became a schema truth value: %v",err)}}}
}

func validateRegexFixture(schemaSource,subject string,limits ecmaregex.Limits)(failure error){defer recoverRegexEvaluation(JSONSchema,&failure);scope:=newRegexScopeWithLimits(limits);return scope.run(JSONSchema,false,func()error{compiler:=jsonoracle.NewCompiler();compiler.DefaultDraft(jsonoracle.Draft2020);compiler.UseRegexpEngine(scope.jsonRegexp);schemaValue,err:=jsonoracle.UnmarshalJSON(strings.NewReader(schemaSource));if err!=nil{return err};if err=compiler.AddResource("https://refine.invalid/regex.schema.json",schemaValue);err!=nil{return err};schema,err:=compiler.Compile("https://refine.invalid/regex.schema.json");if err!=nil{return err};value,err:=jsonoracle.UnmarshalJSON(strings.NewReader(subject));if err!=nil{return err};return schema.Validate(value)})}
