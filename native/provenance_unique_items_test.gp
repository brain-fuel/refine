package native

import (
    "strings"
    "testing"

    "goforge.dev/refine/language"
)

func TestUniqueItemsLowersOnlyDetachedIntrinsicJSON(t *testing.T){
    canonical:=`type Values = [JSON] where unique it`;program,err:=language.Compile(canonical);if err!=nil{t.Fatal(err)};payload,err:=program.PayloadType("Values");if err!=nil{t.Fatal(err)};lowered,err:=LowerPayload(JSONSchema,payload,LowerOptions{Mode:Ordinary});if err!=nil{t.Fatal(err)};if !strings.Contains(lowered.String(),`"uniqueItems": true`){t.Fatalf("uniqueItems absent: %s",lowered.String())}
    unsupported:=[]string{`type Values = [Int] where unique it`,"unique :: [JSON] -> Bool\nunique _ = True\ntype Values = [JSON] where unique it",`type Values = [JSON] where not (unique it)`}
    for _,source:=range unsupported{program,err:=language.Compile(source);if err!=nil{t.Fatal(err)};payload,err:=program.PayloadType("Values");if err!=nil{t.Fatal(err)};if _,err:=LowerPayload(JSONSchema,payload,LowerOptions{Mode:Ordinary});problemCode(err)!="native.unrepresentable"{t.Fatalf("unsupported uniqueness acquired native authority: %s: %v",source,err)}}
}

func TestUniqueItemsDetachedEditRemovalIsAtomicAndIsolated(t *testing.T){
    resource:="https://example.test/unique.json";original:=`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"array","minItems":1,"uniqueItems":true,"items":{"type":"object","properties":{"a":{"type":"integer"}}}}`
    project,err:=IngestProject(JSONSchema,[]byte(original),ProjectOptions{ResourceID:resource,Root:ResourceSelector{TypeName:"Values"}});if err!=nil{t.Fatal(err)};unique:=constraintByKeyword(t,project,"uniqueItems");minimum:=constraintByKeyword(t,project,"minItems");if unique.Scope!="[JSON]"{t.Fatalf("unsafe scope: %+v",unique)}
    compiled,err:=language.Compile(project.EditableSource());if err!=nil{t.Fatal(err)};var root language.TypeDecl;found:=false;for _,decl:=range compiled.Syntax().Types{if decl.Name=="Values"{root=decl;found=true;break}};if !found{t.Fatal("projected root absent")};_,rules:=effectiveDeclarationShape(root,true);if rules!=0{t.Fatal("native uniqueness was attached to the typed payload root")}
    duplicate:=`[{"a":1,"extra":1},{"a":1,"extra":2}]`;if err:=project.ValidateJSON([]byte(duplicate));err!=nil{t.Fatalf("native JSON equality discarded extra fields: %v",err)};equal:=`[{"a":1,"extra":1},{"extra":1,"a":1}]`;if err:=project.ValidateJSON([]byte(equal));problemCode(err)!="native.payload"{t.Fatalf("object-order duplicate accepted: %v",err)}
    source:=project.ResourceConstraintSource(resource);noncanonical:=strings.Replace(source,unique.Predicate,"not (unique it)",1);if changed,err:=project.WithEditedNativeConstraintSource(resource,noncanonical);changed!=nil||problemCode(err)!="native.enforcement"{t.Fatalf("noncanonical uniqueness changed native authority: %v",err)}
    shadowed:=source+"\nunique :: [JSON] -> Bool\nunique _ = True\n";if changed,err:=project.WithEditedNativeConstraintSource(resource,shadowed);changed!=nil||problemCode(err)!="native.enforcement"{t.Fatalf("shadowed unique acquired native authority: %v",err)}
    lines:=[]string{};for _,line:=range strings.Split(source,"\n"){if !strings.HasPrefix(line,"type "+unique.Name+" = "){lines=append(lines,line)}};removedSource:=strings.Join(lines,"\n");removed,err:=project.WithEditedNativeConstraintSource(resource,removedSource);if err!=nil{t.Fatal(err)};if err:=removed.ValidateJSON([]byte(equal));err!=nil{t.Fatalf("removed uniqueItems remained active: %v",err)};if err:=removed.ValidateJSON([]byte(`[]`));problemCode(err)!="native.payload"{t.Fatalf("removing uniqueItems invalidated minItems: %v",err)};if got,err:=removed.RecoverResourceNative(resource,minimum.Name,removedSource);err!=nil||got!="1"{t.Fatalf("unrelated native recovery: %q %v",got,err)}
    effective,err:=removed.EffectiveResources();if err!=nil{t.Fatal(err)};if strings.Contains(effective[0].Source,"uniqueItems")||!strings.Contains(effective[0].Source,"minItems"){t.Fatalf("effective isolation: %s",effective[0].Source)};bundle,err:=removed.Bundle();if err!=nil{t.Fatal(err)};again,err:=ParseBundle(bundle);if err!=nil{t.Fatal(err)};if err:=again.ValidateJSON([]byte(equal));err!=nil{t.Fatalf("bundle lost explicit removal: %v",err)};if project.Resources()[0].Source!=original{t.Fatal("effective edit mutated immutable native origin")}
}
