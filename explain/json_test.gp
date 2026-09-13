package explain

import (
    "strings"
    "testing"
)

func TestIntrinsicJSONDocumentationIsSemantic(t *testing.T){
    doc:=documentation(t,"type Root = JSON where it == it @code \"json.reflexive\"\n")
    text:=doc.Markdown();for _,want:=range []string{"immutable JSON value","JSONNull","JSONNumber","JSON object keys are never normalized"}{if !strings.Contains(text,want){t.Fatalf("intrinsic JSON documentation omits %q",want)}}
}
