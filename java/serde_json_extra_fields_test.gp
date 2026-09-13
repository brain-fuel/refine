package java

import (
    "os"
    "os/exec"
    "path/filepath"
    "strings"
    "testing"

    "goforge.dev/refine/language"
    "goforge.dev/refine/native"
)

const jsonExtraFieldContract=`
type Box a = {
  value :: a,
  child :: Maybe (Box a),
  detail :: { label :: String }
}
type IntBox = Box Int
type StringBox = Box String
type Root = { closed :: IntBox, ordinary :: Box Int, words :: StringBox }
`

func TestGeneratedJSONExtraFieldPoliciesArePerOccurrence(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=jacksonClasspath(t);program,err:=language.Compile(jsonExtraFieldContract);if err!=nil{t.Fatal(err)}
    files,err:=GenerateJSONSerde(program,"example.extras","Contract","DiscardModule",JSONSerdeOptions{Root:"Root"});if err!=nil{t.Fatal(err)}
    modules:=[]struct{name string;options JSONSerdeOptions}{
        {"PreserveModule",JSONSerdeOptions{Root:"Root",PreserveExtraFieldsFor:map[string]bool{"IntBox":true}}},
        {"RejectModule",JSONSerdeOptions{Root:"Root",RejectExtraFieldsFor:map[string]bool{"IntBox":true}}},
    }
    for _,item:=range modules{generated,generateErr:=GenerateJSONSerde(program,"example.extras","Contract",item.name,item.options);if generateErr!=nil{t.Fatal(generateErr)};found:=false;for _,file:=range generated{if strings.HasSuffix(file.Path,"/"+item.name+".java"){files=append(files,file);found=true}};if !found{t.Fatal("JSON module source is absent",item.name)}}
    same:=JSONSerdeOptions{Root:"IntBox",PreserveExtraFields:true,PreserveExtraFieldsFor:map[string]bool{"Box":true}};if generated,sameErr:=GenerateJSONSerde(program,"example.same","Contract","SameModule",same);sameErr!=nil||len(generated)==0{t.Fatalf("equal alias-chain policies did not coalesce: %v",sameErr)}
    guards:=[]JSONSerdeOptions{
        {Root:"IntBox",RejectExtraFields:true,PreserveExtraFieldsFor:map[string]bool{"Box":true}},
        {Root:"Root",RejectExtraFieldsFor:map[string]bool{"Missing":true}},
        {Root:"Root",RejectExtraFieldsFor:map[string]bool{"StringBox":true},PreserveExtraFieldsFor:map[string]bool{"Box":true}},
    };for _,options:=range guards{if generated,guardErr:=GenerateJSONSerde(program,"example.bad","Contract","BadModule",options);guardErr==nil||generated!=nil{t.Fatalf("invalid per-occurrence policy emitted output: %+v",options)}}
    scalar,scalarErr:=language.Compile("type Scalar = Int\n");if scalarErr!=nil{t.Fatal(scalarErr)};if generated,guardErr:=GenerateJSONSerde(scalar,"example.bad","Contract","BadModule",JSONSerdeOptions{Root:"Scalar",RejectExtraFields:true});guardErr==nil||generated!=nil{t.Fatal("non-record reject policy emitted output")}
    metadataOptions,metadataErr:=JSONSerdeOptionsFromMetadata("IntBox",native.WireMetadata{ExtraFields:map[string]native.ExtraFieldMode{"IntBox":native.RejectExtraFields}});if metadataErr!=nil||!metadataOptions.RejectExtraFields||!metadataOptions.RejectExtraFieldsFor["IntBox"]{t.Fatalf("reject metadata was not retained: %+v %v",metadataOptions,metadataErr)}
    dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)}
    harness:=filepath.Join(dir,"ExtraFieldPolicies.java");if err:=os.WriteFile(harness,[]byte(jsonExtraFieldHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("extra-field javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-cp",classes+string(os.PathListSeparator)+classpath,"ExtraFieldPolicies").CombinedOutput();err!=nil{t.Fatalf("extra-field runtime: %v\n%s",err,output)}
}

const jsonExtraFieldHarnessJava=`
import example.extras.*;
public final class ExtraFieldPolicies {
 static void require(boolean value){if(!value)throw new AssertionError();}
 static void rejects(Runnable action){try{action.run();throw new AssertionError("closed record accepted an extra member");}catch(ValidationException expected){}}
 public static void main(String[] args)throws Exception{
  String input="{\"closed\":{\"value\":1,\"child\":{\"value\":2,\"detail\":{\"label\":\"inner\",\"anonymousExtra\":true},\"childExtra\":true},\"detail\":{\"label\":\"outer\",\"anonymousExtra\":true},\"aliasExtra\":true},\"ordinary\":{\"value\":3,\"detail\":{\"label\":\"ordinary\"},\"ordinaryExtra\":true},\"words\":{\"value\":\"word\",\"detail\":{\"label\":\"words\"},\"wordExtra\":true}}";
  String clean="{\"closed\":{\"value\":1,\"child\":{\"value\":2,\"detail\":{\"label\":\"inner\",\"anonymousExtra\":true},\"childExtra\":true},\"detail\":{\"label\":\"outer\",\"anonymousExtra\":true}},\"ordinary\":{\"value\":3,\"detail\":{\"label\":\"ordinary\"},\"ordinaryExtra\":true},\"words\":{\"value\":\"word\",\"detail\":{\"label\":\"words\"},\"wordExtra\":true}}";
  String discarded="{\"closed\":{\"value\":1,\"child\":{\"value\":2,\"detail\":{\"label\":\"inner\"}},\"detail\":{\"label\":\"outer\"}},\"ordinary\":{\"value\":3,\"detail\":{\"label\":\"ordinary\"}},\"words\":{\"value\":\"word\",\"detail\":{\"label\":\"words\"}}}";
  String preserved="{\"closed\":{\"value\":1,\"child\":{\"value\":2,\"detail\":{\"label\":\"inner\"}},\"detail\":{\"label\":\"outer\"},\"aliasExtra\":true},\"ordinary\":{\"value\":3,\"detail\":{\"label\":\"ordinary\"}},\"words\":{\"value\":\"word\",\"detail\":{\"label\":\"words\"}}}";
  var discard=DiscardModule.strictMapper();var preserving=PreserveModule.strictMapper();var rejecting=RejectModule.strictMapper();
  require(discard.writeValueAsString(discard.readValue(input,Root.class)).equals(discarded));Root retained=preserving.readValue(input,Root.class);require(preserving.writeValueAsString(retained).equals(preserved));require(rejecting.writeValueAsString(rejecting.readValue(clean,Root.class)).equals(discarded));
  rejects(()->{try{rejecting.readValue(input,Root.class);}catch(tools.jackson.core.JacksonException failure){throw new AssertionError(failure);}});var rejectModule=new RejectModule();rejects(()->rejectModule.readDataWithoutRefinements(input.getBytes(java.nio.charset.StandardCharsets.UTF_8)));rejects(()->rejectModule.writeDataWithoutRefinements(retained.rawData()));
  var sink=new java.io.StringWriter();rejects(()->{try{rejecting.writeValue(sink,retained);}catch(tools.jackson.core.JacksonException failure){throw new AssertionError(failure);}});require(sink.toString().isEmpty());
 }
}
`
