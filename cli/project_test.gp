package cli

import (
    "bytes"
    "os"
    "path/filepath"
    "strings"
    "testing"
)

func projectFixture(t *testing.T)string{
    t.Helper();root:=t.TempDir()
    for _,version:=range []string{"v0.1.0","SNAPSHOT"}{file:=filepath.Join(root,"schemata","foo",version+".refine");if err:=os.MkdirAll(filepath.Dir(file),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(file,[]byte("package com.example\ntype Thing = String where length it > 0\n"),0600);err!=nil{t.Fatal(err)}}
    if err:=os.WriteFile(filepath.Join(root,"pom.xml"),[]byte("<project/>"),0600);err!=nil{t.Fatal(err)}
    return root
}

func TestProjectCLIAllVersionsAndCheck(t *testing.T){
    root:=projectFixture(t);var out,stderr bytes.Buffer
    args:=[]string{"project","generate","--root",root,"--json"}
    if code:=Run(args,nil,&out,&stderr);code!=0{t.Fatalf("generation %d: %s %s",code,&out,&stderr)}
    for _,version:=range []string{"v0_1_0","snapshot"}{
        javaPath:=filepath.Join(root,"target","generated-sources","refine","com","example","foo",version,"Thing.java")
        if _,err:=os.Stat(javaPath);err!=nil{t.Fatal(err)}
        for _,resource:=range []string{"contract.refine","explanation.md","ordinary-json-schema.json","refined-avro.json","ordinary-openapi.json"}{if _,err:=os.Stat(filepath.Join(root,"target","generated-resources","refine","refine","foo",version,resource));err!=nil{t.Fatal(err)}}
    }
    manifest:=filepath.Join(root,".refine-generated.json");before,err:=os.ReadFile(manifest);if err!=nil{t.Fatal(err)}
    out.Reset();if code:=Run(append(args,"--check"),nil,&out,&stderr);code!=0{t.Fatal(code,out.String(),stderr.String())}
    after,err:=os.ReadFile(manifest);if err!=nil||!bytes.Equal(before,after){t.Fatal("check changed manifest")}
    edited:=filepath.Join(root,"target","generated-sources","refine","com","example","foo","snapshot","Thing.java")
    if err:=os.WriteFile(edited,[]byte("user edit"),0600);err!=nil{t.Fatal(err)}
    out.Reset();if Run(args,nil,&out,&stderr)!=1{t.Fatal("generation overwrote edited generated source")}
    content,err:=os.ReadFile(edited);if err!=nil||string(content)!="user edit"{t.Fatal("user edit lost")}
}

func TestProjectCLIConfigNoCodegenAndOverrides(t *testing.T){
    root:=projectFixture(t)
    config:=`{"families":{"foo":{"noCodegen":["v0.1.0"]}}}`
    if err:=os.WriteFile(filepath.Join(root,"refine.project.json"),[]byte(config),0600);err!=nil{t.Fatal(err)}
    var out,stderr bytes.Buffer
    if Run([]string{"project","generate","--root",root,"--package","org.override","--output","generated","--flat"},nil,&out,&stderr)!=0{t.Fatal(out.String(),stderr.String())}
    data,err:=os.ReadFile(filepath.Join(root,"generated","Thing.java"));if err!=nil||!strings.Contains(string(data),"package org.override.foo.snapshot;"){t.Fatal("package/layout override ignored",err)}
    if _,err:=os.Stat(filepath.Join(root,"target","generated-resources","refine","refine","foo","v0_1_0","contract.refine"));err!=nil{t.Fatal("no-codegen incorrectly removed schema resources",err)}
}

func TestProjectCLIInputAndConfigFailures(t *testing.T){
    for _,config:=range []string{`{"schemaDir":"../escape"}`,`{"families":{},"families":{}}`,`{"unsupported":true}`,`{"families":{"missing":{"root":"T"}}}`,`{"families":{"foo":{"noCodegen":["v99.0.0"]}}}`} {
        root:=projectFixture(t);if err:=os.WriteFile(filepath.Join(root,"refine.project.json"),[]byte(config),0600);err!=nil{t.Fatal(err)}
        var out,stderr bytes.Buffer;if Run([]string{"project","generate","--root",root},nil,&out,&stderr)!=1{t.Fatal("invalid config accepted",config)}
        if _,err:=os.Stat(filepath.Join(root,".refine-generated.json"));!os.IsNotExist(err){t.Fatal("failed validation wrote outputs")}
    }
}

func TestProjectCLILoadsOfflineImports(t *testing.T){
    root:=t.TempDir();folder:=filepath.Join(root,"schemata","foo");if err:=os.MkdirAll(folder,0755);err!=nil{t.Fatal(err)}
    files:=map[string]string{"schemata/foo/SNAPSHOT.refine":"import \"../../common.refine\"\ntype Thing = ID","common.refine":"type ID = String","refine.project.json":`{"families":{"foo":{"root":"Thing"}}}`}
    for name,source:=range files{if err:=os.WriteFile(filepath.Join(root,filepath.FromSlash(name)),[]byte(source),0600);err!=nil{t.Fatal(err)}}
    var out,stderr bytes.Buffer;if Run([]string{"project","generate","--root",root},nil,&out,&stderr)!=0{t.Fatal(out.String(),stderr.String())}
    data,err:=os.ReadFile(filepath.Join(root,"target","generated-resources","refine","refine","foo","snapshot","contract.refine"));if err!=nil||!strings.Contains(string(data),"type ID")||strings.Contains(string(data),"import "){t.Fatal("imports not bundled",err)}
}

func TestMavenCLIIsOptInOutputOnly(t *testing.T){
    var out,stderr bytes.Buffer
    if Run([]string{"project","maven","--executable","/path/with spaces/refine"},nil,&out,&stderr)!=0{t.Fatal(stderr.String())}
    for _,want:=range []string{"<maven.compiler.release>25", "<artifactId>maven-compiler-plugin", "<argument>project</argument>","<argument>generate</argument>","/path/with spaces/refine"}{if !strings.Contains(out.String(),want){t.Error("missing",want)}}
    if Run([]string{"project","maven"},nil,brokenWriter{},&stderr)!=2{t.Fatal("ignored writer failure")}
}
