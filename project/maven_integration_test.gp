package project_test

import (
    "bytes"
    "context"
    "crypto/sha256"
    "os"
    "os/exec"
    "path/filepath"
    "strings"
    "testing"
    "time"

    "goforge.dev/refine/project"
    "goforge.dev/refine/native"
    "goforge.dev/refine/release"
)

func TestMavenRegenerationAndReproducibleArtifact(t *testing.T){
    // Stop the actual JVM before Go's package alarm can abandon it. The same
    // deadline covers all lifecycle phases; it is not renewed per build.
    processContext:=t.Context();cancel:=func(){};if deadline,ok:=t.Deadline();ok{processContext,cancel=context.WithDeadline(processContext,deadline.Add(-5*time.Second))};defer cancel()
    mavenHome:=os.Getenv("REFINE_MAVEN_HOME")
    if mavenHome==""{if os.Getenv("REFINE_REQUIRE_MAVEN")=="1"{t.Fatal("REFINE_MAVEN_HOME is required")};t.Skip("set REFINE_MAVEN_HOME for the unsigned Maven integration gate")}
    maven:=filepath.Join(mavenHome,"bin","mvn");if _,err:=os.Stat(maven);err!=nil{t.Fatal(err)}
    root:=t.TempDir();executable:=filepath.Join(root,"refine")
    build:=exec.CommandContext(processContext,"go","build","-o",executable,"./cmd/refine");build.Dir="..";if output,err:=build.CombinedOutput();err!=nil{t.Fatalf("CLI build: %v\n%s",err,output)}
    snippet:=project.MavenSnippet(project.MavenOptions{CLIExecutable:executable})
    pom:=`<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion><groupId>example.test</groupId><artifactId>refine-fixture</artifactId><version>0.0.1</version>`+snippet+`</project>`
    if err:=os.WriteFile(filepath.Join(root,"pom.xml"),[]byte(pom),0600);err!=nil{t.Fatal(err)}
    schemaDir:=filepath.Join(root,"schemata","greeting");if err:=os.MkdirAll(schemaDir,0755);err!=nil{t.Fatal(err)}
    schema:=[]byte("package example.test\ntype Greeting = {text :: String where length it > 0}\n")
    for _,version:=range []string{"v1.0.0","SNAPSHOT"}{if err:=os.WriteFile(filepath.Join(schemaDir,version+".refine"),schema,0600);err!=nil{t.Fatal(err)}}
    // Native bundles exercise exact numeric and ECMA oracles in the same four
    // lifecycle builds, not separate Maven campaigns for each adapter.
    nativeProject,err:=native.IngestProject(native.JSONSchema,[]byte(`{"type":"integer","multipleOf":3}`),native.ProjectOptions{Root:native.ResourceSelector{TypeName:"Multiple"}});if err!=nil{t.Fatal(err)}
    nativeProject,err=nativeProject.WithMetadata(native.WireMetadata{PublicationNamespace:"example.test"});if err!=nil{t.Fatal(err)}
    nativeBundle,err:=nativeProject.Bundle();if err!=nil{t.Fatal(err)};nativeDir:=filepath.Join(root,"schemata","multiple");if err=os.MkdirAll(nativeDir,0755);err!=nil{t.Fatal(err)};if err=os.WriteFile(filepath.Join(nativeDir,"SNAPSHOT.refined.json"),nativeBundle,0600);err!=nil{t.Fatal(err)}
    patternProject,err:=native.IngestProject(native.JSONSchema,[]byte(`{"type":"string","pattern":"^[a-z]+$"}`),native.ProjectOptions{Root:native.ResourceSelector{TypeName:"Code"},Metadata:native.WireMetadata{PublicationNamespace:"example.test"}});if err!=nil{t.Fatal(err)};patternBundle,err:=patternProject.Bundle();if err!=nil{t.Fatal(err)};patternDir:=filepath.Join(root,"schemata","code");if err=os.MkdirAll(patternDir,0755);err!=nil{t.Fatal(err)};if err=os.WriteFile(filepath.Join(patternDir,"SNAPSHOT.refined.json"),patternBundle,0600);err!=nil{t.Fatal(err)}
    operationsProject,err:=native.IngestOpenAPIOperations([]byte(`{"openapi":"3.1.2","info":{"title":"Health","version":"1"},"paths":{"/healthy":{"post":{"operationId":"checkHealth","requestBody":{"required":true,"content":{"application/json":{"schema":{"type":"boolean"}}}},"responses":{"204":{"description":"healthy"}}}}}}`),native.OpenAPIOperationIngestOptions{EntryResource:"https://example.test/health.openapi.json",Metadata:native.WireMetadata{PublicationNamespace:"example.test"}});if err!=nil{t.Fatal(err)};operationsBundle,err:=operationsProject.Bundle();if err!=nil{t.Fatal(err)};operationsDir:=filepath.Join(root,"schemata","health");if err=os.MkdirAll(operationsDir,0755);err!=nil{t.Fatal(err)};if err=os.WriteFile(filepath.Join(operationsDir,"SNAPSHOT.refined.json"),operationsBundle,0600);err!=nil{t.Fatal(err)}
    if err=os.WriteFile(filepath.Join(root,"refine.project.json"),[]byte(`{"families":{"multiple":{"formats":["json-schema"]},"code":{"formats":["json-schema"]},"health":{"formats":["openapi"]}}}`),0600);err!=nil{t.Fatal(err)}
    fragment:=exec.CommandContext(processContext,executable,"project","maven","--root",root,"--executable",executable);fragment.Dir=root;detected,err:=fragment.Output();if err!=nil{t.Fatal("Maven dependency detection",err)};if !strings.Contains(string(detected),"com.dylibso.chicory")||strings.Contains(string(detected),"org.graalvm"){t.Fatal("native regex dependency was not inferred")};pom=`<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion><groupId>example.test</groupId><artifactId>refine-fixture</artifactId><version>0.0.1</version>`+string(detected)+`</project>`;if err=os.WriteFile(filepath.Join(root,"pom.xml"),[]byte(pom),0600);err!=nil{t.Fatal(err)}
    run:=func(){t.Helper();command:=exec.CommandContext(processContext,maven,"--batch-mode","--no-transfer-progress","package");command.Dir=root;command.Env=os.Environ();if javaHome:=os.Getenv("REFINE_JAVA_HOME");javaHome!=""{command.Env=append(command.Env,"JAVA_HOME="+javaHome)};if output,err:=command.CombinedOutput();err!=nil{t.Fatalf("unsigned Maven build: %v\n%s",err,output)}}
    t.Log("Maven phase 1/4: generate, validate and package")
    run()
    jar:=filepath.Join(root,"target","refine-fixture-0.0.1.jar");first,err:=os.ReadFile(jar);if err!=nil{t.Fatal(err)}
    // Inspect the artifact from the existing build; do not launch another
    // Maven lifecycle merely to exercise the offline inventory boundary.
    inventory,err:=release.InspectJavaArtifact(first,release.DefaultJavaArtifactLimits());if err!=nil{t.Fatal("inspect actual Maven JAR",err)}
    if inventory.ArtifactSHA256()!=release.Digest(first){t.Fatal("actual Maven artifact digest mismatch")}
    foundGreeting,foundOperations:=false,false;for _,class:=range inventory.Classes(){if class.Path=="example/test/greeting/snapshot/Greeting.class"{foundGreeting=true};if class.Path=="example/test/health/snapshot/RefineOpenAPIOperations.class"{foundOperations=true}}
    if !foundGreeting||!foundOperations{t.Fatalf("actual Maven JAR inventory omitted generated families: greeting=%t rootless-operations=%t",foundGreeting,foundOperations)}
    operationSource,err:=os.ReadFile(filepath.Join(root,"target","generated-sources","refine","example","test","health","snapshot","RefineOpenAPIOperations.java"));if err!=nil||!strings.Contains(string(operationSource),"checkHealth"){t.Fatal("Maven did not generate the rootless OpenAPI operation facade",err)}
    operationProperties,err:=os.ReadFile(filepath.Join(root,"target","generated-test-sources","refine","example","test","health","snapshot","ContractGeneratedProperties.java"));if err!=nil||!strings.Contains(string(operationProperties),"request checkHealth")||!strings.Contains(string(operationProperties),"response checkHealth 204"){t.Fatal("Maven did not generate complete rootless OpenAPI properties",err)}
    t.Log("Maven phase 2/4: verify unchanged artifact reproducibility")
    run();second,err:=os.ReadFile(jar);if err!=nil{t.Fatal(err)}
    if sha256.Sum256(first)!=sha256.Sum256(second){t.Fatal("unchanged unsigned artifact is not reproducible")}
    generated:=filepath.Join(root,"target","generated-sources","refine","example","test","greeting","snapshot","Greeting.java")
    before,err:=os.ReadFile(generated);if err!=nil{t.Fatal(err)}
    changed:=[]byte("package example.test\ntype Greeting = {text :: String where length it > 0, label :: String}\n")
    if err:=os.WriteFile(filepath.Join(schemaDir,"SNAPSHOT.refine"),changed,0600);err!=nil{t.Fatal(err)}
    t.Log("Maven phase 3/4: regenerate after schema edit")
    run();after,err:=os.ReadFile(generated);if err!=nil||bytes.Equal(before,after){t.Fatal("Maven did not automatically regenerate changed schema",err)}
    released,err:=os.ReadFile(filepath.Join(schemaDir,"v1.0.0.refine"));if err!=nil||!bytes.Equal(released,schema){t.Fatal("build mutated released schema")}
    launcher,err:=os.ReadFile(filepath.Join(root,"target","generated-test-sources","refine","refine","generated","RefineGeneratedTests.java"));if err!=nil||!strings.Contains(string(launcher),"greeting.v1_0_0.ContractGeneratedProperties.main")||!strings.Contains(string(launcher),"greeting.snapshot.ContractGeneratedProperties.main")||!strings.Contains(string(launcher),"health.snapshot.ContractGeneratedProperties.main"){t.Fatal("all schema versions and rootless operation families must execute generated properties",err)}
    impossible:=[]byte("package example.test\ntype Greeting = {text :: String where length it > 100}\n")
    if err:=os.WriteFile(filepath.Join(schemaDir,"SNAPSHOT.refine"),impossible,0600);err!=nil{t.Fatal(err)}
    t.Log("Maven phase 4/4: reject exhausted property generation")
    command:=exec.CommandContext(processContext,maven,"--batch-mode","--no-transfer-progress","package");command.Dir=root;command.Env=os.Environ();if javaHome:=os.Getenv("REFINE_JAVA_HOME");javaHome!=""{command.Env=append(command.Env,"JAVA_HOME="+javaHome)}
    output,err:=command.CombinedOutput();if err==nil||!strings.Contains(string(output),"property generation exhausted: valid Greeting"){t.Fatalf("Maven must run generated properties and fail on exhaustion: %v\n%s",err,output)}
}
