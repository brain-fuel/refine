package explain

import (
    "strings"
    "testing"

    "goforge.dev/refine/language"
)

func TestExplanationIncludesEffectiveCapabilities(t *testing.T) {
    program,err:=language.Compile("roundTrip :: a -> Result String a\nroundTrip x = read (show x)\norderedDouble :: a -> a -> Bool\norderedDouble x y = x + x < y + y")
    if err!=nil{t.Fatal(err)}
    document,err:=Generate(program);if err!=nil{t.Fatal(err)}
    found:=false;numeric:=false
    for _,definition:=range document.Definitions(){if definition.Name=="roundTrip"{
        found=true
        if !strings.Contains(definition.Signature,"(Show a, Read a) =>")||!strings.Contains(definition.English,"Show for a, Read for a") {t.Fatalf("incomplete capability explanation: %#v",definition)}
    };if definition.Name=="orderedDouble"{numeric=true;if !strings.Contains(definition.Signature,"(Ord a, Num a) =>")||!strings.Contains(definition.English,"Ord for a, Num for a"){t.Fatalf("incomplete numeric capability explanation: %#v",definition)}}}
    if !found||!numeric{t.Fatal("function explanation missing")}
}

func TestExplanationDefinesFiniteFloatTypesAndConversions(t *testing.T){
    for _,name:=range []string{"toFloat32","toFloat64","roundToFloat32","roundToFloat64","fromFloat32","fromFloat64"}{
        meaning,ok:=builtinMeaning(name);if !ok||!strings.Contains(meaning,"finite")&&!strings.Contains(meaning,"exact rational"){t.Fatalf("missing complete %s explanation: %q",name,meaning)}
    }
    program,err:=language.Compile("type Small = {single :: Float32, double :: Float64}");if err!=nil{t.Fatal(err)};document,err:=Generate(program);if err!=nil{t.Fatal(err)}
    text:=document.Markdown();for _,fragment:=range []string{"finite IEEE-754 binary32","finite IEEE-754 binary64","no distinct signed-zero identity","no implicit rounding"}{if !strings.Contains(text,fragment){t.Fatalf("missing %q from explanation",fragment)}}
}
