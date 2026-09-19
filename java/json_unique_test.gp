package java

import (
    "context"
    "os"
    "os/exec"
    "path/filepath"
    "strings"
    "testing"
    "time"

    "goforge.dev/refine/language"
    "goforge.dev/refine/native"
)

func TestGeneratedIntrinsicJSONUniqueMatchesJSONSchemaEquality(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=networkntClasspath(t)
    program,err:=language.Compile(`type Values = [JSON] where unique it @code "items.unique"`);if err!=nil{t.Fatal(err)};files,err:=GenerateJSONSerde(program,"example.unique.refine","Contract","RefineModule",JSONSerdeOptions{Root:"Values"});if err!=nil{t.Fatal(err)}
    schema:=`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"array","uniqueItems":true}`;project,err:=native.IngestProject(native.JSONSchema,[]byte(schema),native.ProjectOptions{Root:native.ResourceSelector{TypeName:"Values"},Metadata:native.WireMetadata{PublicationNamespace:"example.unique.schema"}});if err!=nil{t.Fatal(err)};editable:=project.EditableSource();if !strings.HasPrefix(editable,"type Values = [JSON]\n")||strings.Contains(editable,"type Values = [JSON] where"){t.Fatalf("native uniqueness attached to the semantic payload root: %q",editable)};nativeFiles,err:=GenerateProjectJSONSerde(project,"Contract","SchemaModule");if err!=nil{t.Fatal(err)};files=append(files,nativeFiles...)
    dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)};harness:=filepath.Join(dir,"JSONUniqueHarness.java");if err:=os.WriteFile(harness,[]byte(jsonUniqueHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...)
    compileContext,stopCompile:=context.WithTimeout(context.Background(),time.Minute);defer stopCompile();if output,err:=exec.CommandContext(compileContext,compiler,args...).CombinedOutput();err!=nil{if compileContext.Err()!=nil{t.Fatalf("JSON equality javac exceeded the process deadline: %v",compileContext.Err())};t.Fatalf("JSON equality javac: %v\n%s",err,output)}
    runContext,stopRun:=context.WithTimeout(context.Background(),time.Minute);defer stopRun();if output,err:=exec.CommandContext(runContext,vm,"-Xss256k","-Xmx64m","-cp",classes+string(os.PathListSeparator)+classpath,"JSONUniqueHarness").CombinedOutput();err!=nil{if runContext.Err()!=nil{t.Fatalf("JSON equality runtime exceeded the process deadline: %v",runContext.Err())};t.Fatalf("JSON equality runtime: %v\n%s",err,output)}
}

const jsonUniqueHarnessJava=`
public final class JSONUniqueHarness {
 interface Checked { void run() throws Exception; }
 static boolean accepts(Checked action){try{action.run();return true;}catch(Exception rejected){return false;}}
 static void vector(String raw,boolean expected){
  boolean refine=accepts(()->example.unique.refine.RefineModule.strictMapper().readValue(raw,example.unique.refine.Values.class));
  boolean schema=accepts(()->example.unique.schema.SchemaModule.strictMapper().readValue(raw,example.unique.schema.Values.class));
  if(refine!=expected||schema!=expected||refine!=schema)throw new AssertionError(raw+" refine="+refine+" schema="+schema+" expected="+expected);
 }
 public static void main(String[] args){
  vector("[1,1.0]",false);
  vector("[{\"a\":1,\"b\":2},{\"b\":2,\"a\":1}]",false);
  vector("[\"a\",\"\\u0061\"]",false);
  vector("[[1,2],[2,1]]",true);
  vector("[\"é\",\"é\"]",true);
  vector("[{}, {\"a\":null}]",true);
  vector("[{\"a\":1},{\"a\":1,\"extra\":null}]",true);
 }
}
`
