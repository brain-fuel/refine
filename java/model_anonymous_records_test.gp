package java

import (
    "os"
    "os/exec"
    "path/filepath"
    "testing"

    "goforge.dev/refine/language"
)

func TestAnonymousNestedRecordModelsAndJSONSerde(t *testing.T){
    source:=`type Positive = Int where it > 0
type Document = {shipping :: {street :: String, geo :: {zone :: Int}}, items :: [{quantity :: Positive}]}
type Envelope a = {payload :: {value :: a}}
`;program,err:=language.Compile(source);if err!=nil{t.Fatal(err)};files,err:=GenerateJSONSerde(program,"example.anonymous","Contract","DocumentJSON",JSONSerdeOptions{Root:"Document",Integers:JSONIntegerNumber});if err!=nil{t.Fatal(err)}
    expected:=map[string]bool{"DocumentShippingRecord.java":false,"DocumentShippingRecordGeoRecord.java":false,"DocumentItemsItemRecord.java":false,"EnvelopePayloadRecord.java":false};for _,file:=range files{if _,ok:=expected[filepath.Base(file.Path)];ok{expected[filepath.Base(file.Path)]=true}};for name,found:=range expected{if !found{t.Fatalf("missing synthesized nested model %s",name)}}
    compiler,vm:=javaTools(t);classpath:=jacksonClasspath(t);dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)};harness:=filepath.Join(dir,"AnonymousRecordGate.java");if err:=os.WriteFile(harness,[]byte(anonymousRecordHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("anonymous record javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-cp",classes+string(os.PathListSeparator)+classpath,"AnonymousRecordGate").CombinedOutput();err!=nil{t.Fatalf("anonymous record runtime: %v\n%s",err,output)}
}

const anonymousRecordHarnessJava = `
import example.anonymous.*;
import java.math.BigInteger;
import java.util.*;
import tools.jackson.databind.json.JsonMapper;
public final class AnonymousRecordGate {
 static void require(boolean value){if(!value)throw new AssertionError();}
 static void rejects(Runnable action){try{action.run();throw new AssertionError();}catch(ValidationException expected){}}
 public static void main(String[] args)throws Exception{
  var geo=new DocumentShippingRecordGeoRecord(BigInteger.valueOf(9));var shipping=new DocumentShippingRecord("Main",geo);var item=new DocumentItemsItemRecord(new Positive(BigInteger.valueOf(2)));var document=new Document(shipping,List.of(item));require(document.shipping().street().equals("Main")&&document.shipping().geo().zone().equals(BigInteger.valueOf(9))&&document.items().getFirst().quantity().value().equals(BigInteger.valueOf(2)));
  var changed=document.update(d->d.setShipping(document.shipping().update(s->s.setStreet("Side"))));require(changed.shipping().street().equals("Side")&&document.shipping().street().equals("Main"));var invalidItem=DocumentItemsItemRecord.createWithoutValidation(Positive.createWithoutValidation(BigInteger.ZERO));rejects(()->new Document(shipping,List.of(invalidItem)));
  var payload=new EnvelopePayloadRecord<Positive>(ModelTypes.forPositive(),new Positive(BigInteger.ONE));var envelope=new Envelope<Positive>(ModelTypes.forPositive(),payload);require(envelope.payload().value().value().equals(BigInteger.ONE));
  var mapper=JsonMapper.builder().addModule(new DocumentJSON()).build();String json=mapper.writeValueAsString(document);var decoded=mapper.readValue(json,Document.class);require(decoded.shipping().geo().zone().equals(BigInteger.valueOf(9))&&mapper.writeValueAsString(decoded).equals(json));
 }
}
`
