package explain

import (
    "strings"
    "testing"

    "goforge.dev/refine/language"
)

func TestMapTypeLiteralAndBuiltinsAreExplained(t *testing.T){
    program,err:=language.Compile(`type Counts = Map String Int
hasA :: Counts -> Bool
hasA counts = member "a" counts
example :: Map String Int
example = map {"b" = 2, "a" = 1}
`)
    if err!=nil{t.Fatal(err)}
    document,err:=Generate(program);if err!=nil{t.Fatal(err)}
    markdown:=document.Markdown()
    for _,want:=range []string{"immutable exact-string-keyed map","Entry order is not semantic","without case folding or Unicode normalization"}{if !strings.Contains(markdown,want){t.Fatalf("map explanation missing %q:\n%s",want,markdown)}}
}
