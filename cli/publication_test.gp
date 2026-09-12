// GoPlus-authored CLI publication-gate tests.
package cli

import (
    "bytes"
    "encoding/json"
    "os"
    "path/filepath"
    "sort"
    "strings"
    "testing"

    "goforge.dev/refine/release"
)

func writePublicationRecord(t *testing.T,root,family,version string,state release.PublicationState,generated []release.PublicationFile){
    t.Helper();schemaPath:=filepath.Join(root,"schemata",family,"v"+version+".refine");schema,err:=os.ReadFile(schemaPath);if err!=nil{t.Fatal(err)};record:=release.PublicationRecord{State:state,Family:family,SchemaVersion:version,SchemaSHA256:release.Digest(schema),GeneratedSources:generated,Reason:"checked publication inventory"};if state==release.PublicationPublished{record.ArtifactVersion="1.0.0";record.ArtifactSHA256=release.Digest([]byte("published jar"));record.Classes=[]release.PublicationFile{{Path:"example/Foo.class",SHA256:release.Digest([]byte("class bytes"))}}};record.InventorySHA256=release.PublicationInventoryDigest(record);raw,err:=json.MarshalIndent(release.PublicationLedger{Version:1,GroupID:"dev.example",ArtifactID:"models",Records:[]release.PublicationRecord{record}},"","  ");if err!=nil{t.Fatal(err)};if err=os.WriteFile(filepath.Join(root,"refine.publications.json"),append(raw,'\n'),0600);err!=nil{t.Fatal(err)}
}
func generatedSourceInventory(t *testing.T,root,prefix string)[]release.PublicationFile{t.Helper();files:=[]release.PublicationFile{};err:=filepath.WalkDir(filepath.Join(root,filepath.FromSlash(prefix)),func(name string,entry os.DirEntry,walkErr error)error{if walkErr!=nil{return walkErr};if entry.IsDir()||!strings.HasSuffix(name,".java"){return nil};raw,err:=os.ReadFile(name);if err!=nil{return err};relative,err:=filepath.Rel(root,name);if err!=nil{return err};files=append(files,release.PublicationFile{Path:filepath.ToSlash(relative),SHA256:release.Digest(raw)});return nil});if err!=nil{t.Fatal(err)};sort.Slice(files,func(i,j int)bool{return files[i].Path<files[j].Path});return files}

func TestProjectPublicationGateRequiresEffectiveMavenAndExactLedger(t *testing.T){
    root:=releaseFixture(t,map[string]string{"schemata/foo/v1.0.0.refine":"type Foo = String\n","schemata/foo/SNAPSHOT.refine":"type Foo = String\n"},`{"families":{"foo":{"root":"Foo"}}}`);var out,stderr bytes.Buffer;if code:=projectCommand([]string{"generate","--root",root},&out,&stderr);code!=0{t.Fatal(code,out.String(),stderr.String())};relative:="target/generated-sources/refine/foo/v1_0_0/Foo.java";inventory:=generatedSourceInventory(t,root,"target/generated-sources/refine/foo/v1_0_0");writePublicationRecord(t,root,"foo","1.0.0",release.PublicationPublished,inventory)
    config:=`{"release":{"maven":{"current":"1.0.0","intended":"1.1.0"}},"families":{"foo":{"root":"Foo","noCodegen":["v1.0.0"]}}}`;if err:=os.WriteFile(filepath.Join(root,"refine.project.json"),[]byte(config),0600);err!=nil{t.Fatal(err)};out.Reset();stderr.Reset();if code:=projectCommand([]string{"generate","--root",root},&out,&stderr);code!=1||!strings.Contains(stderr.String(),"--maven-group-id"){t.Fatalf("missing effective Maven evidence accepted: %d %s %s",code,&out,&stderr)};if _,err:=os.Stat(filepath.Join(root,relative));err!=nil{t.Fatal("failed gate changed outputs",err)}
    out.Reset();stderr.Reset();args:=[]string{"generate","--root",root,"--maven-group-id","dev.example","--maven-artifact-id","models","--maven-version","1.1.0"};if code:=projectCommand(args,&out,&stderr);code!=0{t.Fatalf("attested removal rejected: %d %s %s",code,&out,&stderr)};if _,err:=os.Stat(filepath.Join(root,relative));!os.IsNotExist(err){t.Fatal("attested no-codegen source was retained")}
}

func TestProjectPublicationLedgerStrictAndUnpublished(t *testing.T){
    root:=projectFixture(t);config:=`{"families":{"foo":{"noCodegen":["v0.1.0"]}}}`;if err:=os.WriteFile(filepath.Join(root,"refine.project.json"),[]byte(config),0600);err!=nil{t.Fatal(err)};writePublicationRecord(t,root,"foo","0.1.0",release.PublicationUnpublished,nil);var out,stderr bytes.Buffer;if code:=projectCommand([]string{"generate","--root",root},&out,&stderr);code!=0{t.Fatalf("unpublished attestation rejected: %d %s %s",code,&out,&stderr)}
    ledger:=filepath.Join(root,"refine.publications.json");raw,err:=os.ReadFile(ledger);if err!=nil{t.Fatal(err)};raw=bytes.Replace(raw,[]byte(`"version": 1`),[]byte(`"version": 1, "unknown": true`),1);if err=os.WriteFile(ledger,raw,0600);err!=nil{t.Fatal(err)};out.Reset();stderr.Reset();if code:=projectCommand([]string{"generate","--root",root},&out,&stderr);code!=1||!strings.Contains(stderr.String(),"unknown field"){t.Fatalf("unknown ledger field accepted: %d %s %s",code,&out,&stderr)}
}
