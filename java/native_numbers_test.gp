package java

import (
    "os"
    "os/exec"
    "path/filepath"
    "testing"

    "goforge.dev/refine/native"
)

// One javac/JVM invocation covers native JSON and OpenAPI numeric defaults.
func TestGeneratedNativeNumberWireDefaultsRemainExact(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=networkntClasspath(t);files:=[]File{}
    for _,tc:=range []struct{format native.Format;source,pointer,namespace string}{
        {native.JSONSchema,`{"type":"number","minimum":0}`,"","example.nativefraction"},
        {native.OpenAPI,`{"openapi":"3.1.0","info":{"title":"Numbers","version":"1"},"paths":{},"components":{"schemas":{"Amount":{"type":"number","minimum":0}}}}`,"/components/schemas/Amount","example.apifraction"},
        {native.JSONSchema,`{"type":"object","required":["amount"],"properties":{"amount":{"type":"number"}}}`,"","example.nestedfraction"},
    }{project,err:=native.IngestProject(tc.format,[]byte(tc.source),native.ProjectOptions{Root:native.ResourceSelector{Pointer:tc.pointer,TypeName:"Amount"},Metadata:native.WireMetadata{PublicationNamespace:tc.namespace}});if err!=nil{t.Fatal(err)};generated,err:=GenerateProjectJSONSerde(project,"Contract","AmountModule");if err!=nil{t.Fatal(err)};files=append(files,generated...)}
    dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)}
    harness:=filepath.Join(dir,"NativeNumbers.java");if err:=os.WriteFile(harness,[]byte(nativeNumbersJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("native numbers javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-Xss256k","-cp",classes+string(os.PathListSeparator)+classpath,"NativeNumbers").CombinedOutput();err!=nil{t.Fatalf("native numbers runtime: %v\n%s",err,output)}
}

const nativeNumbersJava=`
public final class NativeNumbers {
 static void require(boolean ok){if(!ok)throw new AssertionError();}
 public static void main(String[] args)throws Exception{
  var json=example.nativefraction.AmountModule.strictMapper();
  var amount=json.readValue("9007199254740993.125",example.nativefraction.Amount.class);
  require(amount.value().equals(example.nativefraction.Rational.parse("9007199254740993.125")));
  require(json.writeValueAsString(amount).equals("9007199254740993.125"));
  var sink=new java.io.StringWriter();
  try{json.writeValue(sink,new example.nativefraction.Amount(example.nativefraction.Rational.parse("1/3")));throw new AssertionError("rounded nonterminating rational");}catch(example.nativefraction.ValidationException expected){}
  require(sink.toString().isEmpty());
  try{json.readValue("-0.125",example.nativefraction.Amount.class);throw new AssertionError("lost native minimum");}catch(RuntimeException expected){}
  var api=example.apifraction.AmountModule.strictMapper();
  var apiAmount=api.readValue("1.25e-3",example.apifraction.Amount.class);
  require(apiAmount.value().equals(example.apifraction.Rational.parse("1/800")));
  require(api.writeValueAsString(apiAmount).equals("0.00125"));
  var nested=example.nestedfraction.AmountModule.strictMapper();
  var row=nested.readValue("{\"amount\":0.125}",example.nestedfraction.Amount.class);
  require(row.amount().equals(example.nestedfraction.Rational.parse("1/8")));
  require(nested.writeValueAsString(row).equals("{\"amount\":0.125}"));
 }
}
`
