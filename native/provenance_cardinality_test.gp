package native

import (
    "fmt"
    "strings"
    "testing"
    "goforge.dev/refine/language"
)

func TestCollectionCardinalityLoweringAndScopedEdits(t *testing.T){
    for _,kind:=range []string{"array","object"}{t.Run(kind,func(t *testing.T){minimum,maximum:="minItems","maxItems";one,two,three,four:=`[null]`,`[null,null]`,`[null,null,null]`,`[null,null,null,null]`;if kind=="object"{minimum,maximum="minProperties","maxProperties";one,two,three,four=`{"a":null}`,`{"a":null,"b":null}`,`{"a":null,"b":null,"c":null}`,`{"a":null,"b":null,"c":null,"d":null}`};original:=fmt.Sprintf(`{"type":%q,%q:1.0,%q:3}`,kind,minimum,maximum);project,err:=IngestProject(JSONSchema,[]byte(original),ProjectOptions{Root:ResourceSelector{TypeName:"Collection"}});if err!=nil{t.Fatal(err)};low,high:=constraintByKeyword(t,project,minimum),constraintByKeyword(t,project,maximum);source:=project.ResourceConstraintSource("urn:refine:root");changed:=strings.Replace(source,low.Predicate,strings.Replace(low.Predicate,">= 1",">= 2",1),1);edited,err:=project.WithEditedNativeConstraintSource("urn:refine:root",changed);if err!=nil{t.Fatal(err)}
        for _,raw:=range []string{two,three}{if err:=edited.ValidateJSON([]byte(raw));err!=nil{t.Fatal(err)}};for _,raw:=range []string{one,four}{if err:=edited.ValidateJSON([]byte(raw));problemCode(err)!="native.payload"{t.Fatalf("changed count was not enforced: %s %v",raw,err)}};if err:=project.ValidateJSON([]byte(one));err!=nil{t.Fatalf("original project mutated: %v",err)};if original!=project.Resources()[0].Source{t.Fatal("original bytes changed")};if got,err:=edited.RecoverResourceNative("urn:refine:root",high.Name,changed);err!=nil||got!="3"{t.Fatalf("untouched maximum recovery: %q %v",got,err)}
        bundle,err:=edited.Bundle();if err!=nil{t.Fatal(err)};again,err:=ParseBundle(bundle);if err!=nil{t.Fatal(err)};if err:=again.ValidateJSON([]byte(one));problemCode(err)!="native.payload"{t.Fatalf("bundle lost edit: %v",err)};exported,err:=edited.Export(LowerOptions{Mode:Refined});if err!=nil{t.Fatal(err)};if !strings.Contains(exported.Resources()[0].Source,`"`+minimum+`": 2`){t.Fatal("export omitted changed count")}
        program,err:=language.Compile(changed);if err!=nil{t.Fatal(err)};payload,err:=program.PayloadType(low.Name);if err!=nil{t.Fatal(err)};lowered,err:=LowerPayload(JSONSchema,payload,LowerOptions{Mode:Ordinary});if err!=nil{t.Fatal(err)};if !strings.Contains(lowered.String(),`"`+minimum+`": 2`){t.Fatal(lowered.String())}
    })}
}

func TestCollectionCardinalityDoesNotLowerStringLengthOrShadowedBuiltins(t *testing.T){
    for _,source:=range []string{`type Count = String where length it >= 2`,"length :: [JSON] -> Int\nlength _ = 100\ntype Count = [JSON] where length it >= 2", "size :: Map String JSON -> Int\nsize _ = 100\ntype Count = Map String JSON where size it >= 2"}{program,err:=language.Compile(source);if err!=nil{t.Fatal(err)};payload,err:=program.PayloadType("Count");if err!=nil{t.Fatal(err)};if _,err:=LowerPayload(JSONSchema,payload,LowerOptions{Mode:Ordinary});problemCode(err)!="native.unrepresentable"{t.Fatalf("non-native count acquired lowering authority: %v",err)}}
}

func TestNumericBuiltinShadowingDoesNotAcquireNativeAuthority(t *testing.T){
    program,err:=language.Compile("isInteger :: Real -> Bool\nisInteger _ = True\ntype Count = Int where isInteger (it / 2)\n");if err!=nil{t.Fatal(err)};payload,err:=program.PayloadType("Count");if err!=nil{t.Fatal(err)}
    if _,err:=LowerPayload(JSONSchema,payload,LowerOptions{Mode:Ordinary});problemCode(err)!="native.unrepresentable"{t.Fatalf("shadowed numeric builtin acquired authority: %v",err)}
    lowered,err:=LowerPayload(JSONSchema,payload,LowerOptions{Mode:Ordinary,AllowDocumentedLoss:true});if err!=nil{t.Fatal(err)};if strings.Contains(lowered.String(),"multipleOf")||len(lowered.Losses())!=1{t.Fatalf("shadowed numeric predicate not accounted for: %s",lowered.String())}
}
