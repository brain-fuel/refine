package project

import (
    "bytes"
    "os"
    "testing"

    "goforge.dev/refine/language"
    "goforge.dev/refine/native"
)

func TestGeneratedProjectCarriesExactBinaryAttribution(t *testing.T){
    repositoryLicense,err:=os.ReadFile("../LICENSE");if err!=nil{t.Fatal(err)};if !bytes.Equal(repositoryLicense,refineDistributionLicense){t.Fatal("generated Refine license diverges from repository LICENSE")}
    program,err:=language.Compile("type Root = String\n");if err!=nil{t.Fatal(err)};bundle,err:=Generate(GenerateInput{Contracts:[]Contract{{Family:"notice",Program:program,RootType:"Root",Formats:[]native.Format{native.JSONSchema}}}});if err!=nil{t.Fatal(err)}
    wanted:=map[string][]byte{"target/generated-resources/refine/META-INF/LICENSE.refine.txt":refineDistributionLicense,"target/generated-resources/refine/META-INF/NOTICE.refine.txt":refineDistributionNotice};for _,file:=range bundle.Files{if expected,ok:=wanted[file.Path];ok{if !bytes.Equal(file.Content,expected){t.Fatalf("notice content changed at %s",file.Path)};delete(wanted,file.Path)}};if len(wanted)!=0{t.Fatalf("generated attribution resources absent: %v",wanted)}
    empty,err:=Generate(GenerateInput{});if err!=nil||len(empty.Files)!=0{t.Fatalf("empty generation acquired distribution files: %+v %v",empty,err)}
}
