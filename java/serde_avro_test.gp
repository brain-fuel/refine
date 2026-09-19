package java

import (
    "crypto/sha256"
    "encoding/hex"
    "os"
    "os/exec"
    "path/filepath"
    "strings"
    "testing"

    "goforge.dev/refine/language"
    "goforge.dev/refine/native"
)

func avroClasspath(t *testing.T)string{
    dir:=os.Getenv("REFINE_AVRO_DIR");if dir==""{if os.Getenv("REFINE_REQUIRE_JAVA")=="1"{t.Fatal("REFINE_AVRO_DIR is required by the Java release gate")};t.Skip("set REFINE_AVRO_DIR to pinned Apache Avro 1.12 test jars")}
    jars:=[]struct{name,sum string}{
        {"avro-1.12.0.jar","1f5fbfff9b7427d6832cc3031a3c81413d3e21d9e2551847d9231c28493f9492"},{"jackson-core-2.17.2.jar","721a189241dab0525d9e858e5cb604d3ecc0ede081e2de77d6f34fa5779a5b46"},{"jackson-databind-2.17.2.jar","c04993f33c0f845342653784f14f38373d005280e6359db5f808701cfae73c0c"},{"jackson-annotations-2.17.2.jar","873a606e23507969f9bbbea939d5e19274a88775ea5a169ba7e2d795aa5156e1"},{"commons-compress-1.26.2.jar","9168a03141d8fc7eda21a2360d83cc0412bcbb1d6204d992bd48c2573cb3c6b8"},{"commons-codec-1.17.0.jar","f700de80ac270d0344fdea7468201d8b9c805e5c648331c3619f2ee067ccfc59"},{"commons-io-2.16.1.jar","f41f7baacd716896447ace9758621f62c1c6b0a91d89acee488da26fc477c84f"},{"commons-lang3-3.14.0.jar","7b96bf3ee68949abb5bc465559ac270e0551596fa34523fddf890ec418dde13c"},{"slf4j-api-2.0.13.jar","e7c2a48e8515ba1f49fa637d57b4e2f590b3f5bd97407ac699c3aa5efb1204a9"},{"slf4j-simple-2.0.13.jar","3153fe1d689cffb94f1530b58470c306685ba68844de8857116e3b6ebb81d9f7"},
    };parts:=[]string{};for _,jar:=range jars{item:=filepath.Join(dir,jar.name);data,err:=os.ReadFile(item);if err!=nil{t.Fatalf("Avro test dependency: %v",err)};sum:=sha256.Sum256(data);if hex.EncodeToString(sum[:])!=jar.sum{t.Fatalf("Avro test dependency %s has an unexpected SHA-256",jar.name)};parts=append(parts,item)};return strings.Join(parts,string(os.PathListSeparator))
}

func TestGeneratedAvroBinaryJSONResolutionAndValidation(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=avroClasspath(t);schema:=`{"type":"record","name":"Payload","aliases":["Old"],"fields":[{"name":"renamed","type":"long","aliases":["oldName"]},{"name":"added","type":"long","default":5},{"name":"accepted","type":"boolean","aliases":["valid"],"default":true}]}`;project,err:=native.IngestProject(native.Avro,[]byte(schema),native.ProjectOptions{ResourceID:"urn:avro:new",Root:native.ResourceSelector{TypeName:"PayloadRoot"},Metadata:native.WireMetadata{PublicationNamespace:"example.avro"}});if err!=nil{t.Fatal(err)};project,err=project.WithEditedSource("type Accepted = Bool where it\ntype PayloadRoot = {renamed :: Int64, added :: Int64, accepted :: Accepted}\n");if err!=nil{t.Fatal(err)};files,err:=GenerateProjectAvroSerde(project,"Contract","PayloadAvroSerde");if err!=nil{t.Fatal(err)}
    dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)};harness:=filepath.Join(dir,"AvroGate.java");if err:=os.WriteFile(harness,[]byte(avroHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("Avro 1.12 javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-cp",classes+string(os.PathListSeparator)+classpath,"AvroGate").CombinedOutput();err!=nil{t.Fatalf("Avro 1.12 runtime: %v\n%s",err,output)}
}

func TestAvroSerdeRejectsUnboundedOrUnimplementedShapes(t *testing.T){
    schema:=`{"type":"record","name":"Wire","fields":[{"name":"value","type":"long"}]}`;base,err:=native.IngestProject(native.Avro,[]byte(schema),native.ProjectOptions{ResourceID:"urn:avro:gate",Root:native.ResourceSelector{TypeName:"Payload"}});if err!=nil{t.Fatal(err)};cases:=[]struct{name,source string}{{name:"arbitrary",source:"type Payload = Int\n"},{name:"real",source:"type Payload = Real\n"}};for _,tc:=range cases{project,err:=base.WithEditedSource(tc.source);if err!=nil{t.Fatalf("%s fixture: %v",tc.name,err)};if files,err:=GenerateProjectAvroSerde(project,"Contract","Serde");err==nil||files!=nil{t.Fatalf("%s shape was accepted",tc.name)}}
}

func TestAvroSchemaSourcesAreChunkedBelowJavaConstantLimit(t *testing.T){expression:=avroJavaString(strings.Repeat("x",70000));if !strings.HasPrefix(expression,"join(")||strings.Contains(expression,strings.Repeat("x",65000))||strings.Count(expression,"\",\"")<10{t.Fatal("large Avro schema was not split into runtime string chunks")}}

func TestAvroSerdeBoundsExpandingGenericSchemaPair(t *testing.T){schema:=`{"type":"record","name":"GrowWire","fields":[{"name":"value","type":"int"},{"name":"next","type":"GrowWire"}]}`;project,err:=native.IngestProject(native.Avro,[]byte(schema),native.ProjectOptions{Root:native.ResourceSelector{TypeName:"Payload"}});if err!=nil{t.Fatal(err)};project,err=project.WithEditedSource("type Grow a = {value :: Int32, next :: Grow [a]}\ntype Payload = Grow Int32\n");if err!=nil{t.Fatal(err)};if files,err:=GenerateProjectAvroSerde(project,"Contract","Serde");err==nil||files!=nil||!strings.Contains(err.Error(),"specialization limit"){t.Fatalf("expanding generic schema pair was not bounded: %v",err)}}

func TestGeneratedAvroClosedGenericProjectPipeline(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=avroClasspath(t);source:="type Box a = {value :: a}\ntype Pair a b = {left :: Box a, right :: Box b}\ntype Swap a b = Pair b a\ntype Node a = {value :: a, children :: [Node a]}\ntype Positive = Int32 where fromInt32 it > 0 @code \"positive\"\ntype Payload = {swapped :: Swap String Positive, tree :: Node Positive}\n";program,err:=language.Compile(source);if err!=nil{t.Fatal(err)};payload,err:=program.PayloadType("Payload");if err!=nil{t.Fatal(err)};lowered,err:=native.LowerPayload(native.Avro,payload,native.LowerOptions{Mode:native.Refined,AllowDocumentedLoss:true});if err!=nil{t.Fatal(err)};if strings.Count(lowered.String(),`"name": "Payload"`)!=1{t.Fatalf("monomorphic root wire name changed: %s",lowered.String())}
    project,err:=native.IngestProject(native.Avro,lowered.Bytes(),native.ProjectOptions{ResourceID:"urn:avro:generic-project",Root:native.ResourceSelector{TypeName:"Payload"}});if err!=nil{t.Fatal(err)};project,err=project.WithEditedSource(source);if err!=nil{t.Fatal(err)};project,err=project.WithMetadata(native.WireMetadata{PublicationNamespace:"example.genericavro"});if err!=nil{t.Fatal(err)};files,err:=GenerateProjectAvroSerde(project,"Contract","GenericAvroSerde");if err!=nil{t.Fatal(err)}
    dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)};harness:=filepath.Join(dir,"GenericAvroGate.java");if err:=os.WriteFile(harness,[]byte(genericAvroHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("closed generic Avro javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-cp",classes+string(os.PathListSeparator)+classpath,"GenericAvroGate").CombinedOutput();err!=nil{t.Fatalf("closed generic Avro runtime: %v\n%s",err,output)}
}

func TestGeneratedAvroArraysAndRecursiveRecordsAreBounded(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=avroClasspath(t);schema:=`{"type":"record","name":"Node","fields":[{"name":"value","type":"long"},{"name":"children","type":{"type":"array","items":"Node"}}]}`;project,err:=native.IngestProject(native.Avro,[]byte(schema),native.ProjectOptions{ResourceID:"urn:avro:recursive",Root:native.ResourceSelector{TypeName:"NodeRoot"},Metadata:native.WireMetadata{PublicationNamespace:"example.recursive"}});if err!=nil{t.Fatal(err)};files,err:=GenerateProjectAvroSerde(project,"Contract","NodeAvroSerde");if err!=nil{t.Fatal(err)}
    dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)};harness:=filepath.Join(dir,"RecursiveAvroGate.java");if err:=os.WriteFile(harness,[]byte(recursiveAvroHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("recursive Avro javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-cp",classes+string(os.PathListSeparator)+classpath,"RecursiveAvroGate").CombinedOutput();err!=nil{t.Fatalf("recursive Avro runtime: %v\n%s",err,output)}
}

func TestGeneratedAvroNamedUnionPreservesWireBranchIdentity(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=avroClasspath(t);schema:=`["long","string"]`;project,err:=native.IngestProject(native.Avro,[]byte(schema),native.ProjectOptions{ResourceID:"urn:avro:choice",Root:native.ResourceSelector{TypeName:"Choice"},Metadata:native.WireMetadata{PublicationNamespace:"example.choice"}});if err!=nil{t.Fatal(err)};files,err:=GenerateProjectAvroSerde(project,"Contract","ChoiceAvroSerde");if err!=nil{t.Fatal(err)}
    dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)};harness:=filepath.Join(dir,"UnionAvroGate.java");if err:=os.WriteFile(harness,[]byte(unionAvroHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("union Avro javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-cp",classes+string(os.PathListSeparator)+classpath,"UnionAvroGate").CombinedOutput();err!=nil{t.Fatalf("union Avro runtime: %v\n%s",err,output)}
}

func TestGeneratedAvroEnumBytesAndFixed(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=avroClasspath(t);schema:=`{"type":"record","name":"Blob","fields":[{"name":"color","type":{"type":"enum","name":"Color","symbols":["RED","Blue"]}},{"name":"bytes","type":"bytes"},{"name":"fixed","type":{"type":"fixed","name":"Hash","size":4}}]}`;project,err:=native.IngestProject(native.Avro,[]byte(schema),native.ProjectOptions{ResourceID:"urn:avro:blob",Root:native.ResourceSelector{TypeName:"BlobRoot"},Metadata:native.WireMetadata{PublicationNamespace:"example.blob"}});if err!=nil{t.Fatal(err)};source:=strings.Replace(project.EditableSource(),"data Color = RED | Blue","data Color = Blue | RED",1);for _,item:=range project.NativeConstraints(){switch item.Constraint.Keyword{case "symbols":source=strings.Replace(source,item.Constraint.Predicate,`oneOf it ["Blue", "RED"]`,1);case "size":source=strings.Replace(source,item.Constraint.Predicate,"length it == 3",1)}};project,err=project.WithEditedSource(source);if err!=nil{t.Fatal(err)};files,err:=GenerateProjectAvroSerde(project,"Contract","BlobAvroSerde");if err!=nil{t.Fatal(err)}
    dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)};harness:=filepath.Join(dir,"BlobAvroGate.java");if err:=os.WriteFile(harness,[]byte(blobAvroHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("enum/bytes Avro javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-cp",classes+string(os.PathListSeparator)+classpath,"BlobAvroGate").CombinedOutput();err!=nil{t.Fatalf("enum/bytes Avro runtime: %v\n%s",err,output)}
}

func TestGeneratedAvroStringsRejectMalformedWireAndJavaText(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=avroClasspath(t);project,err:=native.IngestProject(native.Avro,[]byte(`"string"`),native.ProjectOptions{ResourceID:"urn:avro:text",Root:native.ResourceSelector{TypeName:"TextRoot"},Metadata:native.WireMetadata{PublicationNamespace:"example.text"}});if err!=nil{t.Fatal(err)};files,err:=GenerateProjectAvroSerde(project,"Contract","TextAvroSerde");if err!=nil{t.Fatal(err)}
    dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)};harness:=filepath.Join(dir,"TextAvroGate.java");if err:=os.WriteFile(harness,[]byte(textAvroHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("text Avro javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-cp",classes+string(os.PathListSeparator)+classpath,"TextAvroGate").CombinedOutput();err!=nil{t.Fatalf("text Avro runtime: %v\n%s",err,output)}
}

func TestGeneratedAvroExplicitExactScalarPolicies(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=avroClasspath(t);schema:=`{"type":"record","name":"Scalars","fields":[{"name":"big","type":"string"},{"name":"moment","type":"string"},{"name":"ratio","type":{"type":"record","name":"RatioWire","fields":[{"name":"numerator","type":"bytes"},{"name":"denominator","type":"bytes"}]}},{"name":"money","type":{"type":"bytes","logicalType":"decimal","precision":6,"scale":2}},{"name":"uuid","type":{"type":"string","logicalType":"uuid"}},{"name":"time","type":{"type":"int","logicalType":"time-millis"}}]}`;project,err:=native.IngestProject(native.Avro,[]byte(schema),native.ProjectOptions{ResourceID:"urn:avro:scalars",Root:native.ResourceSelector{TypeName:"ScalarsRoot"}});if err!=nil{t.Fatal(err)};project,err=project.WithEditedSource("type Big = Int\ntype Moment = Timestamp\ntype Ratio = Real\ntype Money = Real\ntype ScalarsRoot = {big :: Big, moment :: Moment, ratio :: Ratio, money :: Money, uuid :: String, time :: Int32}\n");if err!=nil{t.Fatal(err)};project,err=project.WithMetadata(native.WireMetadata{PublicationNamespace:"example.scalars",Scalars:map[string]native.ScalarEncoding{"Big":{Kind:native.DecimalString},"Moment":{Kind:native.TimestampString},"Ratio":{Kind:native.RationalRecord},"Money":{Kind:native.AvroBytesDecimal,Precision:6,Scale:2}}});if err!=nil{t.Fatal(err)};files,err:=GenerateProjectAvroSerde(project,"Contract","ScalarsAvroSerde");if err!=nil{t.Fatal(err)}
    dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)};harness:=filepath.Join(dir,"ScalarAvroGate.java");if err:=os.WriteFile(harness,[]byte(scalarAvroHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("scalar Avro javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-cp",classes+string(os.PathListSeparator)+classpath,"ScalarAvroGate").CombinedOutput();err!=nil{t.Fatalf("scalar Avro runtime: %v\n%s",err,output)}
}

func TestGeneratedAvroFloatDoubleOnlyAcceptExactFiniteReals(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=avroClasspath(t);schema:=`{"type":"record","name":"Floating","fields":[{"name":"single","type":"float"},{"name":"double_","type":"double"}]}`;project,err:=native.IngestProject(native.Avro,[]byte(schema),native.ProjectOptions{ResourceID:"urn:avro:floating",Root:native.ResourceSelector{TypeName:"FloatingRoot"},Metadata:native.WireMetadata{PublicationNamespace:"example.floating"}});if err!=nil{t.Fatal(err)};files,err:=GenerateProjectAvroSerde(project,"Contract","FloatingAvroSerde");if err!=nil{t.Fatal(err)}
    dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)};harness:=filepath.Join(dir,"FloatingAvroGate.java");if err:=os.WriteFile(harness,[]byte(floatingAvroHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("floating Avro javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-cp",classes+string(os.PathListSeparator)+classpath,"FloatingAvroGate").CombinedOutput();err!=nil{t.Fatalf("floating Avro runtime: %v\n%s",err,output)}
}

const avroHarnessJava = `
import example.avro.*;
import java.io.*;
import java.math.BigInteger;
import java.util.*;
public final class AvroGate {
 static final org.apache.avro.Schema WRITER=new org.apache.avro.SchemaParser().parse("{\"type\":\"record\",\"name\":\"Old\",\"fields\":[{\"name\":\"oldName\",\"type\":\"long\"},{\"name\":\"valid\",\"type\":\"boolean\"}]}").mainSchema();
 static final org.apache.avro.Schema SKIP_WRITER=new org.apache.avro.SchemaParser().parse("{\"type\":\"record\",\"name\":\"Old\",\"fields\":[{\"name\":\"oldName\",\"type\":\"long\"},{\"name\":\"valid\",\"type\":\"boolean\"},{\"name\":\"dropped\",\"type\":\"string\"}]}").mainSchema();
 static void require(boolean value){if(!value)throw new AssertionError();}
 static void rejects(Runnable action){try{action.run();throw new AssertionError();}catch(ValidationException expected){}}
 static Data raw(long renamed,long added,boolean accepted){return new Data.Struct(List.of(new Data.Field("renamed",new Data.Number(Rational.of(BigInteger.valueOf(renamed)))),new Data.Field("added",new Data.Number(Rational.of(BigInteger.valueOf(added)))),new Data.Field("accepted",new Data.Bool(accepted))));}
 static byte[] oldBinary(long value,boolean valid)throws IOException{var record=new org.apache.avro.generic.GenericData.Record(WRITER);record.put("oldName",value);record.put("valid",valid);var out=new ByteArrayOutputStream();var encoder=org.apache.avro.io.EncoderFactory.get().binaryEncoder(out,null);new org.apache.avro.generic.GenericDatumWriter<Object>(WRITER).write(record,encoder);encoder.flush();return out.toByteArray();}
 public static void main(String[] args)throws Exception{
  var serde=new PayloadAvroSerde();var binary=oldBinary(7,true);var resolved=serde.readBinary(binary,WRITER);require(resolved.renamed().equals(BigInteger.valueOf(7))&&resolved.added().equals(BigInteger.valueOf(5))&&resolved.accepted().value());
  var jsonResolved=serde.readJson("{\"oldName\":7,\"valid\":true}",WRITER);require(jsonResolved.renamed().equals(BigInteger.valueOf(7))&&jsonResolved.added().equals(BigInteger.valueOf(5))&&jsonResolved.accepted().value());
  String json=serde.writeJson(resolved);require(json.strip().equals("{\"renamed\":7,\"added\":5,\"accepted\":true}"));
  var roundTrip=serde.readBinary(serde.writeBinary(resolved));require(roundTrip.renamed().equals(resolved.renamed())&&roundTrip.added().equals(resolved.added())&&roundTrip.accepted().value());
  rejects(()->{try{serde.readBinary(oldBinary(7,false),WRITER);}catch(IOException failure){throw new AssertionError(failure);}});
  rejects(()->{try{serde.readJson("{\"oldName\":7,\"valid\":false}",WRITER);}catch(IOException failure){throw new AssertionError(failure);}});
  var bypass=PayloadAvroSerde.withoutRefinementValidation(Budget.Limits.defaults(),PayloadAvroSerde.CodecLimits.defaults());require(!bypass.readBinary(oldBinary(7,false),WRITER).accepted().value());
  var unsafe=PayloadRoot.fromDataWithoutValidation(raw(7,5,false));var sink=new ByteArrayOutputStream();rejects(()->{try{serde.writeBinary(unsafe,sink);}catch(IOException failure){throw new AssertionError(failure);}});require(sink.size()==0);
  var trailing=Arrays.copyOf(binary,binary.length+1);rejects(()->{try{serde.readBinary(trailing,WRITER);}catch(IOException failure){throw new AssertionError(failure);}});
  rejects(()->{try{serde.readJson("{\"oldName\":7,\"valid\":true} {\"oldName\":8,\"valid\":true}",WRITER);}catch(IOException failure){throw new AssertionError(failure);}});
  rejects(()->{try{serde.readBinary(new byte[]{14,1,2,(byte)255},SKIP_WRITER);}catch(IOException failure){throw new AssertionError(failure);}});
  var tiny=new PayloadAvroSerde(Budget.Limits.defaults(),new PayloadAvroSerde.CodecLimits(1,10,10));rejects(()->{try{tiny.readJson("{\"oldName\":7,\"valid\":true}",WRITER);}catch(IOException failure){throw new AssertionError(failure);}});
 }
}
`

const genericAvroHarnessJava = `
import example.genericavro.*;
import java.math.BigInteger;
public final class GenericAvroGate {
 static void require(boolean value){if(!value)throw new AssertionError();}
 public static void main(String[] args)throws Exception{
  var serde=new GenericAvroSerde();require(GenericAvroSerde.schema().getName().equals("Payload"));
  String json="{\"swapped\":{\"left\":{\"value\":7},\"right\":{\"value\":\"ok\"}},\"tree\":{\"value\":1,\"children\":[{\"value\":2,\"children\":[]}]}}";
  var value=serde.readJson(json);require(value.swapped().left().value().value().equals(BigInteger.valueOf(7)));require(value.swapped().right().value().equals("ok"));require(value.tree().value().value().equals(BigInteger.ONE));require(value.tree().children().getFirst().value().value().equals(BigInteger.valueOf(2)));
  byte[] binary=serde.writeBinary(value);var round=serde.readBinary(binary);require(round.rawData().equals(value.rawData()));require(serde.readJson(serde.writeJson(value)).rawData().equals(value.rawData()));
  try{serde.readJson("{\"swapped\":{\"left\":{\"value\":-7},\"right\":{\"value\":\"ok\"}},\"tree\":{\"value\":1,\"children\":[]}}");throw new AssertionError();}catch(ValidationException expected){}
  var bypass=GenericAvroSerde.withoutRefinementValidation(Budget.Limits.defaults(),GenericAvroSerde.CodecLimits.defaults());require(bypass.readJson("{\"swapped\":{\"left\":{\"value\":-7},\"right\":{\"value\":\"ok\"}},\"tree\":{\"value\":1,\"children\":[]}}").swapped().left().value().value().equals(BigInteger.valueOf(-7)));
 }
}
`

const recursiveAvroHarnessJava = `
import example.recursive.*;
import java.math.BigInteger;
import java.util.*;
public final class RecursiveAvroGate {
 static void require(boolean value){if(!value)throw new AssertionError();}
 static void rejects(Runnable action){try{action.run();throw new AssertionError();}catch(ValidationException expected){}}
 static Data node(long value,Data... children){return new Data.Struct(List.of(new Data.Field("value",new Data.Number(Rational.of(BigInteger.valueOf(value)))),new Data.Field("children",new Data.Sequence(List.of(children)))));}
 public static void main(String[] args)throws Exception{
  Data raw=node(1,node(2),node(3,node(4)));var model=NodeRoot.fromData(raw);var serde=new NodeAvroSerde();byte[] binary=serde.writeBinary(model);require(serde.readBinary(binary).rawData().equals(raw));String json=serde.writeJson(model);require(serde.readJson(json).rawData().equals(raw));
  var tiny=NodeAvroSerde.withoutRefinementValidation(Budget.Limits.defaults(),new NodeAvroSerde.CodecLimits(1<<20,32,3));rejects(()->{try{tiny.readBinary(binary);}catch(java.io.IOException failure){throw new AssertionError(failure);}});rejects(()->{try{tiny.writeBinary(model);}catch(java.io.IOException failure){throw new AssertionError(failure);}});
 }
}
`

const unionAvroHarnessJava = `
import example.choice.*;
import java.math.BigInteger;
import java.util.*;
public final class UnionAvroGate {
 static void require(boolean value){if(!value)throw new AssertionError();}
 static Choice choice(String name,Data value){return Choice.fromData(new Data.Variant(name,List.of(value)));}
 public static void main(String[] args)throws Exception{
  var serde=new ChoiceAvroSerde();var number=choice("ChoiceUnion1Branch1",new Data.Number(Rational.of(BigInteger.valueOf(7))));var text=choice("ChoiceUnion1Branch2",new Data.Text("seven"));
  require(serde.readBinary(serde.writeBinary(number)).rawData().equals(number.rawData()));require(serde.readBinary(serde.writeBinary(text)).rawData().equals(text.rawData()));require(serde.readJson(serde.writeJson(number)).rawData().equals(number.rawData()));require(serde.readJson(serde.writeJson(text)).rawData().equals(text.rawData()));
 }
}
`

const blobAvroHarnessJava = `
import example.blob.*;
import java.math.BigInteger;
import java.util.*;
public final class BlobAvroGate {
 static void require(boolean value){if(!value)throw new AssertionError();}
 static Data bytes(int... values){var result=new ArrayList<Data>();for(int value:values)result.add(new Data.Number(Rational.of(BigInteger.valueOf(value)),"UInt8"));return new Data.Sequence(result);}
 public static void main(String[] args)throws Exception{
  var schema=BlobAvroSerde.schema();require(schema.getField("color").schema().getEnumSymbols().equals(List.of("Blue","RED")));require(schema.getField("fixed").schema().getFixedSize()==3);Data raw=new Data.Struct(List.of(new Data.Field("color",new Data.Variant("Blue",List.of())),new Data.Field("bytes",bytes(0,127,128,255)),new Data.Field("fixed",bytes(1,2,3))));var model=BlobRoot.fromData(raw);var serde=new BlobAvroSerde();require(serde.readBinary(serde.writeBinary(model)).rawData().equals(raw));require(serde.readJson(serde.writeJson(model)).rawData().equals(raw));
 }
}
`

const textAvroHarnessJava = `
import example.text.*;
import java.io.*;
public final class TextAvroGate {
 static void rejects(Runnable action){try{action.run();throw new AssertionError();}catch(ValidationException expected){}}
 public static void main(String[] args)throws Exception{
  var serde=new TextAvroSerde();rejects(()->{try{serde.readBinary(new byte[]{2,(byte)255});}catch(IOException failure){throw new AssertionError(failure);}});rejects(()->{try{serde.readBinary(new byte[]{(byte)128,(byte)128,(byte)128,(byte)128,8});}catch(IOException failure){throw new AssertionError(failure);}});
  var malformed=TextRoot.fromData(new Data.Text("\uD800"));var sink=new ByteArrayOutputStream();rejects(()->{try{serde.writeBinary(malformed,sink);}catch(IOException failure){throw new AssertionError(failure);}});if(sink.size()!=0)throw new AssertionError();
  var small=new TextAvroSerde(Budget.Limits.defaults(),new TextAvroSerde.CodecLimits(4,10,10));var longText=TextRoot.fromData(new Data.Text("long text"));rejects(()->{try{small.writeBinary(longText,sink);}catch(IOException failure){throw new AssertionError(failure);}});if(sink.size()!=0)throw new AssertionError();
 }
}
`

const scalarAvroHarnessJava = `
import example.scalars.*;
import java.io.*;
import java.math.BigInteger;
import java.util.*;
public final class ScalarAvroGate {
 static void require(boolean value){if(!value)throw new AssertionError();}
 static void rejects(Runnable action){try{action.run();throw new AssertionError();}catch(ValidationException expected){}}
 static Data raw(String money,String uuid,int time){return new Data.Struct(List.of(new Data.Field("big",new Data.Number(Rational.of(new BigInteger("123456789012345678901234567890")))),new Data.Field("moment",new Data.Text("2024-01-02T03:04:05.006-08:00")),new Data.Field("ratio",new Data.Number(Rational.parse("-1/3"))),new Data.Field("money",new Data.Number(Rational.parse(money))),new Data.Field("uuid",new Data.Text(uuid)),new Data.Field("time",new Data.Number(Rational.of(BigInteger.valueOf(time))))));}
 public static void main(String[] args)throws Exception{
  var serde=new ScalarsAvroSerde();var model=ScalarsRoot.fromData(raw("617/50","123e4567-e89b-12d3-a456-426614174000",86399999));require(serde.readBinary(serde.writeBinary(model)).rawData().equals(model.rawData()));require(serde.readJson(serde.writeJson(model)).rawData().equals(model.rawData()));
  var rounding=ScalarsRoot.fromData(raw("1/3","123e4567-e89b-12d3-a456-426614174000",0));var sink=new ByteArrayOutputStream();rejects(()->{try{serde.writeBinary(rounding,sink);}catch(IOException failure){throw new AssertionError(failure);}});require(sink.size()==0);
  var precision=ScalarsRoot.fromData(raw("1234567/100","123e4567-e89b-12d3-a456-426614174000",0));rejects(()->{try{serde.writeBinary(precision);}catch(IOException failure){throw new AssertionError(failure);}});var uuid=ScalarsRoot.fromData(raw("1","not-a-uuid",0));rejects(()->{try{serde.writeBinary(uuid);}catch(IOException failure){throw new AssertionError(failure);}});var time=ScalarsRoot.fromData(raw("1","123e4567-e89b-12d3-a456-426614174000",86400000));rejects(()->{try{serde.writeBinary(time);}catch(IOException failure){throw new AssertionError(failure);}});
 }
}
`

const floatingAvroHarnessJava = `
import example.floating.*;
import java.io.*;
import java.util.*;
public final class FloatingAvroGate {
 static void require(boolean value){if(!value)throw new AssertionError();}
 static void rejects(Runnable action){try{action.run();throw new AssertionError();}catch(ValidationException expected){}}
 static void limit(Runnable action){try{action.run();throw new AssertionError();}catch(ValidationException expected){require(expected.outcome().diagnostics().stream().allMatch(d->d.code().equals("validation.limit")));}}
 static FloatingRoot model(String single,String double_){return FloatingRoot.fromData(new Data.Struct(List.of(new Data.Field("single",new Data.Number(Rational.parse(single))),new Data.Field("double_",new Data.Number(Rational.parse(double_))))));}
 static byte[] nonfinite()throws IOException{var schema=FloatingAvroSerde.schema();var record=new org.apache.avro.generic.GenericData.Record(schema);record.put("single",Float.POSITIVE_INFINITY);record.put("double_",0.0d);var out=new ByteArrayOutputStream();var encoder=org.apache.avro.io.EncoderFactory.get().binaryEncoder(out,null);new org.apache.avro.generic.GenericDatumWriter<Object>(schema).write(record,encoder);encoder.flush();return out.toByteArray();}
 public static void main(String[] args)throws Exception{
  var serde=new FloatingAvroSerde();var exact=model("13421773/134217728","3602879701896397/36028797018963968");var decoded=serde.readBinary(serde.writeBinary(exact));require(decoded.single().numerator().equals(exact.single().numerator())&&decoded.single().denominator().equals(exact.single().denominator())&&decoded.double_().numerator().equals(exact.double_().numerator())&&decoded.double_().denominator().equals(exact.double_().denominator()));require(serde.acceptsNativeCandidate(exact.rawData()));
  var rounded=model("1/10","1/10");require(!serde.acceptsNativeCandidate(rounded.rawData()));var tiny=new FloatingAvroSerde(Budget.Limits.defaults(),new FloatingAvroSerde.CodecLimits(1<<20,128,1));limit(()->tiny.acceptsNativeCandidate(exact.rawData()));rejects(()->{try{serde.writeBinary(rounded);}catch(IOException failure){throw new AssertionError(failure);}});rejects(()->{try{serde.readBinary(nonfinite());}catch(IOException failure){throw new AssertionError(failure);}});
 }
}
`
