package java

import (
    "os"
    "os/exec"
    "path/filepath"
    "testing"

    "goforge.dev/refine/language"
)

// This is deliberately a separate JVM with a small stack and heap. The
// hostile documents are small enough that a resource-limit failure, rather
// than a VM error, is the required result.
func TestGeneratedJSONCodecResourceLimits(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=jacksonClasspath(t);program,err:=language.Compile("type Root = { value :: Int }\n");if err!=nil{t.Fatal(err)}
    options:=JSONSerdeOptions{Root:"Root",PreserveExtraFields:true,NumericExpansion:32,CodecLimits:JSONCodecLimits{Bytes:1024,Depth:128,Nodes:1000,NumberLength:1000,StringLength:1024,NameLength:100}}
    files,err:=GenerateJSONSerde(program,"example.jsonlimits","Contract","RootModule",options);if err!=nil{t.Fatal(err)};dir:=t.TempDir();sources:=[]string{}
    for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)}
    harness:=filepath.Join(dir,"JSONLimits.java");if err:=os.WriteFile(harness,[]byte(jsonLimitsHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...)
    if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("bounded JSON javac: %v\n%s",err,output)};command:=exec.Command(vm,"-Xss256k","-Xmx32m","-cp",classes+string(os.PathListSeparator)+classpath,"JSONLimits");if output,err:=command.CombinedOutput();err!=nil{t.Fatalf("bounded JSON runtime: %v\n%s",err,output)}
}

func TestJSONCodecGenerationLimitsFailClosed(t *testing.T){
    program,err:=language.Compile("type Root = Int\n");if err!=nil{t.Fatal(err)}
    cases:=[]JSONCodecLimits{{Bytes:-1},{Depth:129},{Nodes:1000001},{NumberLength:1000001},{StringLength:(16<<20)+1},{NameLength:1000001}}
    for _,limits:=range cases{files,err:=GenerateJSONSerde(program,"example","Contract","RootModule",JSONSerdeOptions{Root:"Root",CodecLimits:limits});if err==nil||files!=nil{t.Fatalf("unsafe codec limits accepted: %+v",limits)}}
}

const jsonLimitsHarnessJava = `
import example.jsonlimits.*;
import java.math.BigInteger;
import java.util.ArrayList;
import java.util.List;
public final class JSONLimits {
    @FunctionalInterface interface Action { void run() throws Exception; }
    record Envelope(Root root,int sibling) {}
    static void require(boolean value){if(!value)throw new AssertionError();}
    static void limited(Action action){
        try{action.run();throw new AssertionError("resource limit was not enforced");}
        catch(ValidationException expected){require(expected.outcome().state()==Validation.State.INDETERMINATE);require(expected.outcome().diagnostics().stream().allMatch(d->d.code().equals("validation.limit")));}
        catch(Exception other){throw new AssertionError("wrong resource-limit classification",other);}
    }
    static void structurallyInvalid(Action action){
        try{action.run();throw new AssertionError("invalid Unicode was accepted");}
        catch(ValidationException expected){require(expected.outcome().state()==Validation.State.INVALID);require(expected.outcome().diagnostics().stream().allMatch(d->d.code().equals("validation.structure")));}
        catch(Exception other){throw new AssertionError("wrong structural classification",other);}
    }
    static Data.Struct raw(Data extra){return new Data.Struct(List.of(new Data.Field("value",new Data.Number(Rational.ONE)),new Data.Field("x",extra)));}
    static Data deep(int depth){Data value=new Data.Number(Rational.ZERO);for(int i=0;i<depth;i++)value=new Data.Sequence(List.of(value));return value;}
    static Data wide(int width){var values=new ArrayList<Data>();for(int i=0;i<width;i++)values.add(new Data.Bool(true));return new Data.Sequence(values);}
    static String controls(int count){var units=new char[count];java.util.Arrays.fill(units,(char)1);return new String(units);}
    public static void main(String[] args)throws Exception{
        var limits=new RootModule.CodecLimits(64,8,12,16,16,8,32);
        var module=new RootModule(limits);
        var interoperable=tools.jackson.databind.json.JsonMapper.builder().addModule(module).build();
        var strict=RootModule.strictMapper(module);
        var value=strict.readValue("{\"value\":1,\"x\":true}",Root.class);
        require(value.value().equals(BigInteger.ONE));
        require(strict.writeValueAsString(value).equals("{\"value\":1,\"x\":true}"));
        var envelope=interoperable.readValue("{\"root\":{\"value\":2},\"sibling\":3}",Envelope.class);
        require(envelope.root().value().equals(BigInteger.TWO)&&envelope.sibling()==3);
        try{strict.readValue("{\"value\":1} {\"value\":2}",Root.class);throw new AssertionError("strict root accepted trailing JSON");}catch(tools.jackson.core.JacksonException expected){}

        limited(()->interoperable.readValue("{\"value\":1,\"x\":[[[[[[[[[0]]]]]]]]]}",Root.class));
        limited(()->interoperable.readValue("{\"value\":1,\"x\":[0,0,0,0,0,0,0,0,0,0,0,0]}",Root.class));
        limited(()->interoperable.readValue("{\"value\":1,\"x\":\"abcdefghijklmnopq\"}",Root.class));
        limited(()->interoperable.readValue("{\"value\":1,\"123456789\":0}",Root.class));
        limited(()->interoperable.readValue("{\"value\":12345678901234567}",Root.class));
        limited(()->interoperable.readValue("{\"value\":1e1000000000}",Root.class));
        String escaped="{\"value\":1,\"x\":\""+"\\"+"u"+"d800\"}";
        structurallyInvalid(()->interoperable.readValue(escaped,Root.class));

        limited(()->interoperable.writeValueAsString(Root.fromDataWithoutValidation(raw(deep(10)))));
        limited(()->interoperable.writeValueAsString(Root.fromDataWithoutValidation(raw(wide(20)))));
        limited(()->interoperable.writeValueAsString(Root.fromDataWithoutValidation(raw(new Data.Text("abcdefghijklmnopq")))));
        limited(()->interoperable.writeValueAsString(Root.fromDataWithoutValidation(new Data.Struct(List.of(new Data.Field("value",new Data.Number(Rational.ONE)),new Data.Field("123456789",new Data.Bool(true)))))));
        limited(()->interoperable.writeValueAsString(Root.fromDataWithoutValidation(new Data.Struct(List.of(new Data.Field("value",new Data.Number(Rational.of(new BigInteger("12345678901234567")))))))));
        structurallyInvalid(()->interoperable.writeValueAsString(Root.fromDataWithoutValidation(raw(new Data.Text(new String(new char[]{(char)0xd800}))))));
        var sink=new java.io.StringWriter();limited(()->interoperable.writeValue(sink,Root.fromDataWithoutValidation(raw(new Data.Text(controls(16))))));require(sink.toString().isEmpty());

        var maximum=new RootModule(new RootModule.CodecLimits(1024,128,1000,1000,1024,100,32));
        var maximumMapper=tools.jackson.databind.json.JsonMapper.builder().addModule(maximum).build();
        limited(()->maximumMapper.readValue("{\"value\":1,\"x\":"+"[".repeat(129)+"0"+"]".repeat(129)+"}",Root.class));
        limited(()->maximumMapper.writeValueAsString(Root.fromDataWithoutValidation(raw(deep(129)))));
        try{new RootModule(new RootModule.CodecLimits(1025,128,1000,1000,1024,100,32));throw new AssertionError("runtime limits relaxed generated maxima");}catch(IllegalArgumentException expected){}
    }
}
`
