package java

import (
    "os"
    "os/exec"
    "path/filepath"
    "testing"

    "goforge.dev/refine/language"
)

// Closed generic specializations retain distinct wire descriptors even when
// their anonymous record bodies originate at the same source offset.
func TestJacksonGenericAnonymousRecordDescriptorsAreSpecializationSensitive(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=jacksonClasspath(t);program,err:=language.Compile(`
type Box a = { nested :: { value :: a } }
type Container r = { item :: r }
type AppliedBox a = { nested :: Container { value :: a } }
type IntBox = Box Int
type StringBox = Box String
type AppliedIntBox = AppliedBox Int
type AppliedStringBox = AppliedBox String
type Root = { integers :: IntBox, strings :: StringBox, appliedIntegers :: AppliedIntBox, appliedStrings :: AppliedStringBox }
`);if err!=nil{t.Fatal(err)}
    files,err:=GenerateJSONSerde(program,"example.jsonanonymous","Contract","RootModule",JSONSerdeOptions{Root:"Root"});if err!=nil{t.Fatal(err)};dir:=t.TempDir();sources:=[]string{}
    for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)}
    harness:=filepath.Join(dir,"JSONAnonymousGeneric.java");source:=`import example.jsonanonymous.*;
public final class JSONAnonymousGeneric {
  public static void main(String[] args)throws Exception {
    var mapper=tools.jackson.databind.json.JsonMapper.builder().addModule(new RootModule()).build();
    String input="{\"integers\":{\"nested\":{\"value\":1}},\"strings\":{\"nested\":{\"value\":\"text\"}},\"appliedIntegers\":{\"nested\":{\"item\":{\"value\":2}}},\"appliedStrings\":{\"nested\":{\"item\":{\"value\":\"more\"}}}}";
    var value=mapper.readValue(input,Root.class);
    if(!mapper.writeValueAsString(value).equals(input))throw new AssertionError();
  }
}`;if err:=os.WriteFile(harness,[]byte(source),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness)
    classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("anonymous generic JSON javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-cp",classes+string(os.PathListSeparator)+classpath,"JSONAnonymousGeneric").CombinedOutput();err!=nil{t.Fatalf("anonymous generic JSON runtime: %v\n%s",err,output)}
}

func TestJSONDescriptorTypeKeysHaveAggregateStructuralBounds(t *testing.T){
    work:=language.DefaultSubstitutionNodes-2;if !consumeJSONTypeKeyWork(&work,2)||work!=language.DefaultSubstitutionNodes{t.Fatal("exact descriptor-key work budget was rejected")};if consumeJSONTypeKeyWork(&work,1){t.Fatal("one-over descriptor-key work budget was accepted")}
    if jsonTypeKeyTextWork("a")!=1||jsonTypeKeyTextWork(string(make([]byte,32)))!=1||jsonTypeKeyTextWork(string(make([]byte,33)))!=2{t.Fatal("descriptor-key text charging is not ceiling(bytes/32)")}
    work=language.DefaultSubstitutionNodes-3;if !consumeJSONTypeKeyWork(&work,1)||!consumeJSONTypeKeyWork(&work,2)||consumeJSONTypeKeyWork(&work,1){t.Fatal("aggregate descriptor-key work was not shared")}
    leaf:=&language.Type{Form:language.NamedType("ExtremelyLongClosedTypeArgument")};shared:=leaf;for i:=0;i<6;i++{shared=&language.Type{Form:language.AppliedType(shared,shared)}};work=language.DefaultSubstitutionNodes-16;func(){defer func(){if _,ok:=recover().(*GenerationError);!ok{t.Error("shared structural DAG escaped descriptor-key bound")}}();jsonTypeFingerprint(shared,&work)}()
}
