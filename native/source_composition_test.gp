package native

import (
    "encoding/json"
    "strings"
    "testing"

    "goforge.dev/refine/language"
)

func assertComposedFooter(t *testing.T,original,composed string){
    t.Helper()
    base,_,present,err:=language.SplitReleasePolicyFooter(original);if err!=nil||!present{t.Fatalf("invalid fixture footer: %v",err)}
    _,policy,present,err:=language.SplitReleasePolicyFooter(composed);if err!=nil||!present||policy==nil{t.Fatalf("composed footer lost: %v",err)}
    if !strings.HasPrefix(composed,base)||!strings.HasSuffix(composed,original[len(base):]){t.Fatal("composition changed original contract prefix or exact release footer")}
    if _,err:=language.Parse(composed);err!=nil{t.Fatalf("composed source is invalid: %v",err)}
}

func TestNativeAnnotationRootAliasesPreserveReleaseFooter(t *testing.T){
    source,err:=language.AppendReleasePolicyFooter("-- preserve this prefix\ntype Original = Int32\n",nativePolicyFixture());if err!=nil{t.Fatal(err)}
    annotation:=map[string]any{"source":source,"root":"Original"}
    cases:=[]struct{name string;format Format;schema map[string]any;pointer string}{
        {"jsonschema",JSONSchema,map[string]any{"type":"integer","x-refine":annotation},""},
        {"avro",Avro,map[string]any{"type":"int","x-refine":annotation},""},
        {"openapi",OpenAPI,map[string]any{"openapi":"3.1.0","info":map[string]any{"title":"Aliases","version":"1"},"paths":map[string]any{},"components":map[string]any{"schemas":map[string]any{"Alias":map[string]any{"type":"integer"}}},"x-refine":annotation},"/components/schemas/Alias"},
    }
    for _,tc:=range cases{for _,multi:=range []bool{false,true}{name:=tc.name+"/single";if multi{name=tc.name+"/resources"};t.Run(name,func(t *testing.T){
        data,err:=json.Marshal(tc.schema);if err!=nil{t.Fatal(err)};options:=ProjectOptions{ResourceID:"https://example.test/aliases.json",Root:ResourceSelector{Resource:"https://example.test/aliases.json",Pointer:tc.pointer,TypeName:"Alias"}}
        var project *Project;if multi{project,err=IngestProjectResources(tc.format,[]Resource{{URI:options.ResourceID,Source:string(data)}},options)}else{project,err=IngestProject(tc.format,data,options)};if err!=nil{t.Fatal(err)}
        assertComposedFooter(t,source,project.EditableSource());if !strings.Contains(project.EditableSource(),"type Alias = Original"){t.Fatal("selected root alias was not emitted")};if project.ReleasePolicy()!=nil{t.Fatal("source footer acquired native bundle authority")}
        bundle,err:=project.Bundle();if err!=nil{t.Fatal(err)};restored,err:=ParseBundle(bundle);if err!=nil{t.Fatal(err)};if restored.EditableSource()!=project.EditableSource()||restored.ReleasePolicy()!=nil{t.Fatal("bundle changed composed source or authority")}
    })}}
}

func TestDerivedOpenAPISourceKeepsEntryReleaseFooterAndImportBytes(t *testing.T){
    nativeSource:=`{"openapi":"3.1.0","info":{"title":"Footer","version":"1"},"paths":{"/health":{"get":{"operationId":"health","responses":{"204":{"description":"healthy"}}}}},"components":{"schemas":{"Root":{"type":"object","additionalProperties":false}}}}`
    base,err:=IngestProject(OpenAPI,[]byte(nativeSource),ProjectOptions{Root:ResourceSelector{Pointer:"/components/schemas/Root",TypeName:"Root"}});if err!=nil{t.Fatal(err)}
    for _,imports:=range []bool{false,true}{name:="single";if imports{name="imports"};t.Run(name,func(t *testing.T){
        entry:="-- keep entry comments\ntype Root = {}\n";dependency:="";if imports{entry="-- keep entry comments\nimport \"./types.refine\"\ntype Root = Base\n";dependency,err=language.AppendReleasePolicyFooter("-- untouched dependency\ntype Base = {}\n",nativePolicyFixture());if err!=nil{t.Fatal(err)}}
        source,err:=language.AppendReleasePolicyFooter(entry,nativePolicyFixture());if err!=nil{t.Fatal(err)};var before *Project
        if imports{before,err=base.WithEditedSources("main.refine",map[string]string{"main.refine":source,"types.refine":dependency})}else{before,err=base.WithEditedSource(source)};if err!=nil{t.Fatal(err)}
        derived,err:=before.WithDerivedOpenAPIOperations(OpenAPIDerivationOptions{});if err!=nil{t.Fatal(err)};if !derived.HasOpenAPINativeBindings()||derived.ReleasePolicy()!=nil{t.Fatal("derived operation authority is missing or source footer was promoted")}
        if imports{found:=false;for _,file:=range derived.LanguageFiles(){if file.ID=="main.refine"{assertComposedFooter(t,source,file.Source);found=true};if file.ID=="types.refine"&&file.Source!=dependency{t.Fatal("derivation rewrote an imported file")}};if !found{t.Fatal("language entry was lost")}}else{assertComposedFooter(t,source,derived.EditableSource())}
        if before.Metadata().OpenAPI!=nil{t.Fatal("derivation mutated the previous project")};bundle,err:=derived.Bundle();if err!=nil{t.Fatal(err)};restored,err:=ParseBundle(bundle);if err!=nil{t.Fatal(err)};if restored.EditableSource()!=derived.EditableSource()||restored.ReleasePolicy()!=nil{t.Fatal("derived bundle changed entry policy or source")}
    })}
}

func TestNativeSourceCompositionRejectsInvalidFooterAndBounds(t *testing.T){
    if _,err:=appendNativeSourceDeclarations("type Root = Int\n@releasePolicy \"{}\"\n","type Alias = Root");err==nil{t.Fatal("malformed footer accepted")}
    if _,err:=appendNativeSourceDeclarations("type Root = Int\n",strings.Repeat(" ",16<<20));err==nil{t.Fatal("oversized composed source accepted")}
    original:="-- @releasePolicy inside a comment\ntype Root = Int"
    composed,err:=appendNativeSourceDeclarations(original,"type Alias = Root");if err!=nil||composed!=original+"\n\ntype Alias = Root\n"{t.Fatalf("ordinary composition changed: %v",err)}
}
