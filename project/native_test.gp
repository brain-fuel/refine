package project

import (
    "encoding/json"
    "strings"
    "testing"

    "goforge.dev/refine/native"
)

func TestGenerateNativeBundlePreservesOracleResourcesAndMetadata(t *testing.T){
    resources:=[]native.Resource{{URI:"https://example.test/value.json",Source:`{"$schema":"https://json-schema.org/draft/2020-12/schema","$ref":"https://example.test/base.json"}`},{URI:"https://example.test/base.json",Source:`{"type":"integer","multipleOf":3}`}}
    imported,err:=native.IngestProjectResources(native.JSONSchema,resources,native.ProjectOptions{ResourceID:resources[0].URI,Root:native.ResourceSelector{TypeName:"Value"}});if err!=nil{t.Fatal(err)}
    imported,err=imported.WithMetadata(native.WireMetadata{PublicationNamespace:"com.example",NumericExpansion:1234});if err!=nil{t.Fatal(err)}
    input:=GenerateInput{Contracts:[]Contract{{Family:"value",NativeProject:imported,Formats:[]native.Format{native.JSONSchema}}}}
    bundle,err:=Generate(input);if err!=nil{t.Fatal(err)}
    found:=map[string]bool{}
    for _,file:=range bundle.Files{source:=string(file.Content)
        if strings.HasSuffix(file.Path,"Value.java"){found["model"]=true;if !strings.Contains(file.Path,"com/example/value/snapshot/"){t.Fatal("bundle namespace lost",file.Path)}}
        if strings.HasSuffix(file.Path,"RefineJSONModuleNativeSidecar.java"){found["oracle"]=true}
        if strings.HasSuffix(file.Path,"ContractGeneratedProperties.java"){found["properties"]=true;if !strings.Contains(source,"acceptsNativeCandidate(data)"){t.Fatal("native candidate generation not wired")}}
        if strings.HasSuffix(file.Path,"contract.refined.json"){found["bundle"]=true;again,err:=native.ParseBundle(file.Content);if err!=nil{t.Fatal(err)};if again.Metadata().NumericExpansion!=1234||len(again.Resources())!=2{t.Fatal("bundle metadata/resources lost")}}
        if strings.HasSuffix(file.Path,"ordinary-json-schema-resources.json"){found["manifest"]=true;var manifest struct{Resources []struct{URI,Path string};Metadata native.WireMetadata;NativeConstraintSources []native.Resource};if err:=json.Unmarshal(file.Content,&manifest);err!=nil{t.Fatal(err)};if len(manifest.Resources)!=2||manifest.Resources[1].URI!=resources[1].URI||manifest.Metadata.NumericExpansion!=1234||len(manifest.NativeConstraintSources)!=len(imported.NativeConstraintSources()){t.Fatal("manifest lost native identity")}}
        if strings.HasSuffix(file.Path,"ordinary-json-schema-resources/0001.json"){found["dependency"]=true;if !strings.Contains(source,`"multipleOf": 3`)&&!strings.Contains(source,`"multipleOf":3`){t.Fatal("opaque native rule lost")}}
    }
    for _,name:=range []string{"model","oracle","properties","bundle","manifest","dependency"}{if !found[name]{t.Fatal("missing native output",name)}}
    input.Contracts[0].NoCodegen=true;bundle,err=Generate(input);if err!=nil{t.Fatal(err)};for _,file:=range bundle.Files{if strings.HasSuffix(file.Path,"Value.java")||strings.HasSuffix(file.Path,"ContractGeneratedProperties.java"){t.Fatal("no-codegen emitted per-contract Java")}}
}

func TestGenerateNativeBundleRejectsConflictingOrLossyConfiguration(t *testing.T){
    imported,err:=native.IngestProject(native.JSONSchema,[]byte(`{"type":"integer"}`),native.ProjectOptions{Root:native.ResourceSelector{TypeName:"Value"}});if err!=nil{t.Fatal(err)}
    for _,which:=range []string{"implicit formats","cross format","root","program","wire"}{t.Run(which,func(t *testing.T){c:=Contract{Family:"value",NativeProject:imported,Formats:[]native.Format{native.JSONSchema}};switch which{case "implicit formats":c.Formats=nil;case "cross format":c.Formats=[]native.Format{native.Avro};case "root":c.RootType="Other";case "program":c.Program=program(t);case "wire":c.Wire.NumericExpansion=12};bundle,err:=Generate(GenerateInput{Contracts:[]Contract{c}});if err==nil||len(bundle.Files)!=0{t.Fatal("conflicting configuration emitted output",which,err)}})}
}

func TestMavenInfersOnlyRequiredNativeRegexDependency(t *testing.T){
    for _,tc:=range []struct{schema string;excluded,want bool}{
        {`{"type":"string","pattern":"a+"}`,false,true},
        {`{"type":"string","pattern":"a+"}`,true,false},
        {`{"type":"string","examples":[{"pattern":"a+"}]}`,false,false},
    }{p,err:=native.IngestProject(native.JSONSchema,[]byte(tc.schema),native.ProjectOptions{Root:native.ResourceSelector{TypeName:"Code"}});if err!=nil{t.Fatal(err)};snippet,err:=MavenSnippetForProject(GenerateInput{Contracts:[]Contract{{Family:"code",NativeProject:p,NoCodegen:tc.excluded}}},MavenOptions{});if err!=nil{t.Fatal(err)};if strings.Contains(snippet,"com.dylibso.chicory")!=tc.want||strings.Contains(snippet,"org.graalvm"){t.Fatal("wrong optional regex dependency selection",tc)}}
    if strings.Contains(MavenSnippet(MavenOptions{}),"com.dylibso.chicory"){t.Fatal("plain Maven snippet acquired optional regex runtime")}
    if !strings.Contains(MavenSnippet(MavenOptions{NativeRegex:true}),"com.dylibso.chicory"){t.Fatal("explicit regex bootstrap option ignored")}
    snippet:=MavenSnippet(MavenOptions{NativeRegex:true})
    if !strings.Contains(snippet,"<artifactId>runtime</artifactId><version>1.7.5</version></dependency>")||!strings.Contains(snippet,"<artifactId>wasm</artifactId><version>1.7.5</version></dependency>")||strings.Contains(snippet,"org.graalvm"){t.Fatal("regex adapter must compile against the pinned Chicory runtime and parser")}
}
