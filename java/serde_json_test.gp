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
)

func jacksonClasspath(t *testing.T)string{
    dir:=os.Getenv("REFINE_JACKSON_DIR");if dir==""{if os.Getenv("REFINE_REQUIRE_JAVA")=="1"{t.Fatal("REFINE_JACKSON_DIR is required by the Java release gate")};t.Skip("set REFINE_JACKSON_DIR to pinned Jackson 3 test jars")}
    jars:=[]struct{name,sum string}{{"jackson-databind-3.2.0.jar","3ef94a3dddeafc247c50230fad0315981b2ce4ae6e91cfb4368a86f328904e4f"},{"jackson-core-3.2.0.jar","5e353ce53c6901105dfcbf183e3220c17072e334e552b818a4bb1b99decea596"},{"jackson-annotations-2.22.jar","21ddb598807d3a51a876704eb979d9296e1c6a6f47ab1826ff88c6d6a127a2d0"}};parts:=[]string{}
    for _,jar:=range jars{item:=filepath.Join(dir,jar.name);data,err:=os.ReadFile(item);if err!=nil{t.Fatalf("Jackson test dependency: %v",err)};sum:=sha256.Sum256(data);if hex.EncodeToString(sum[:])!=jar.sum{t.Fatalf("Jackson test dependency %s has an unexpected SHA-256",jar.name)};parts=append(parts,item)};return strings.Join(parts,string(os.PathListSeparator))
}

func TestGeneratedJackson3JSONSerde(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=jacksonClasspath(t);program,err:=language.Compile(`
type Age = Int where it >= 0 @code "age.nonnegative"
type Sample = { id :: Int, name :: String, age :: Age, tags :: [String], note :: Maybe String, nullable :: Nullable Int }
  where it.id > 0 @code "sample.id"
`);if err!=nil{t.Fatal(err)}
    files,err:=GenerateJSONSerde(program,"example.jsonserde","Contract","SampleJacksonModule",JSONSerdeOptions{Root:"Sample"});if err!=nil{t.Fatal(err)};dir:=t.TempDir();sources:=[]string{}
    for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)}
    harness:=filepath.Join(dir,"JSONSerde.java");if err:=os.WriteFile(harness,[]byte(jsonSerdeHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...)
    if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("Jackson 3 javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-cp",classes+string(os.PathListSeparator)+classpath,"JSONSerde").CombinedOutput();err!=nil{t.Fatalf("Jackson 3 runtime: %v\n%s",err,output)}
}

const jsonSerdeHarnessJava = `
import example.jsonserde.*;
import java.math.BigInteger;
import java.util.List;
public final class JSONSerde {
    static void require(boolean value){if(!value)throw new AssertionError();}
    static void rejects(Runnable action){try{action.run();throw new AssertionError();}catch(ValidationException expected){}}
    public static void main(String[] args)throws Exception{
        var mapper=tools.jackson.databind.json.JsonMapper.builder().addModule(new SampleJacksonModule()).build();
        var value=mapper.readValue("{\"id\":1,\"name\":\"Ada\",\"age\":21,\"tags\":[\"a\"],\"nullable\":null,\"future\":true}",Sample.class);
        require(value.id().equals(BigInteger.ONE)&&value.note() instanceof ModelMaybe.Nothing<?> && value.nullable() instanceof ModelNullable.Null<?>);
        String json=mapper.writeValueAsString(value);require(json.equals("{\"id\":1,\"name\":\"Ada\",\"age\":21,\"tags\":[\"a\"],\"nullable\":null}"));
        rejects(()->{try{mapper.readValue("{\"id\":1,\"id\":1,\"name\":\"Ada\",\"age\":21,\"tags\":[],\"nullable\":null}",Sample.class);}catch(tools.jackson.core.JacksonException failure){throw new AssertionError(failure);}});
        rejects(()->{try{mapper.readValue("{\"id\":0,\"name\":\"Ada\",\"age\":21,\"tags\":[],\"nullable\":null}",Sample.class);}catch(tools.jackson.core.JacksonException failure){throw new AssertionError(failure);}});
        rejects(()->{try{mapper.readValue("null",Sample.class);}catch(tools.jackson.core.JacksonException failure){throw new AssertionError(failure);}});
        var unsafe=Sample.createWithoutValidation(BigInteger.ZERO,"Ada",new Age(BigInteger.ONE),List.of(),new ModelMaybe.Nothing<>(),new ModelNullable.Null<>());var sink=new java.io.StringWriter();rejects(()->{try{mapper.writeValue(sink,unsafe);}catch(tools.jackson.core.JacksonException failure){throw new AssertionError(failure);}});require(sink.toString().isEmpty());
    }
}
`

func TestJacksonExactRealPolicies(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=jacksonClasspath(t);program,err:=language.Compile("type Exact = Real\n");if err!=nil{t.Fatal(err)}
    decimal,err:=GenerateJSONSerde(program,"example.jsonnumbers","Contract","DecimalModule",JSONSerdeOptions{Root:"Exact",Reals:JSONRealExactDecimal});if err!=nil{t.Fatal(err)};rational,err:=GenerateJSONSerde(program,"example.jsonnumbers","Contract","RationalModule",JSONSerdeOptions{Root:"Exact",Reals:JSONRealRationalString});if err!=nil{t.Fatal(err)}
    files:=decimal;for _,file:=range rational{if strings.HasSuffix(file.Path,"RationalModule.java"){files=append(files,file)}};dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)}
    harness:=filepath.Join(dir,"JSONNumbers.java");if err:=os.WriteFile(harness,[]byte(jsonNumbersJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("exact JSON javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-cp",classes+string(os.PathListSeparator)+classpath,"JSONNumbers").CombinedOutput();err!=nil{t.Fatalf("exact JSON runtime: %v\n%s",err,output)}
}

const jsonNumbersJava = `
import example.jsonnumbers.*;
public final class JSONNumbers {
 static void require(boolean value){if(!value)throw new AssertionError();}
 static void rejects(Runnable action){try{action.run();throw new AssertionError();}catch(ValidationException expected){}}
 public static void main(String[] args)throws Exception{
  var decimal=tools.jackson.databind.json.JsonMapper.builder().addModule(new DecimalModule()).build();var rational=tools.jackson.databind.json.JsonMapper.builder().addModule(new RationalModule()).build();
  var finite=new Exact(Rational.parse("1/8"));require(decimal.writeValueAsString(finite).equals("0.125"));require(decimal.readValue("0.125",Exact.class).value().equals(Rational.parse("1/8")));
  var repeating=new Exact(Rational.parse("1/3"));var sink=new java.io.StringWriter();rejects(()->{try{decimal.writeValue(sink,repeating);}catch(tools.jackson.core.JacksonException failure){throw new AssertionError(failure);}});require(sink.toString().isEmpty());
  require(rational.writeValueAsString(repeating).equals("\"1/3\""));require(rational.readValue("\"1/3\"",Exact.class).value().equals(Rational.parse("1/3")));
 }
}
`

func TestJSONSerdeRequiresExplicitWirePolicies(t *testing.T){
    cases:=[]struct{source,root,want string}{{"type T = { value :: Real }","T","exact Real"},{"type T = { value :: Timestamp }","T","Timestamp JSON"},{"data T = A Int","T","discriminator"},{"type T a = { value :: a }","T","closed"}}
    for _,tc:=range cases{program,err:=language.Compile(tc.source);if err!=nil{t.Fatal(err)};files,err:=GenerateJSONSerde(program,"example","Contract","Module",JSONSerdeOptions{Root:tc.root});if err==nil||files!=nil||!strings.Contains(err.Error(),tc.want){t.Fatalf("expected %q rejection, got %v",tc.want,err)}}
}

func TestJacksonClosedGenericRoot(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=jacksonClasspath(t);program,err:=language.Compile("type Box a = { value :: a }\ntype Age = Int where it >= 0\ntype AgeBox = Box Age\n");if err!=nil{t.Fatal(err)};files,err:=GenerateJSONSerde(program,"example.jsongeneric","Contract","AgeBoxModule",JSONSerdeOptions{Root:"AgeBox"});if err!=nil{t.Fatal(err)}
    dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)};harness:=filepath.Join(dir,"JSONGeneric.java");source:=`import example.jsongeneric.*; public final class JSONGeneric { public static void main(String[] a)throws Exception{var mapper=tools.jackson.databind.json.JsonMapper.builder().addModule(new AgeBoxModule()).build();var box=mapper.readValue("{\"value\":21}",AgeBox.class);if(!box.value().value().equals(java.math.BigInteger.valueOf(21)))throw new AssertionError();if(!mapper.writeValueAsString(box).equals("{\"value\":21}"))throw new AssertionError();}}`;if err:=os.WriteFile(harness,[]byte(source),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("generic JSON javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-cp",classes+string(os.PathListSeparator)+classpath,"JSONGeneric").CombinedOutput();err!=nil{t.Fatalf("generic JSON runtime: %v\n%s",err,output)}
}

func TestJacksonNestedRecursiveAndGenericRecords(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=jacksonClasspath(t);program,err:=language.Compile(`
type Node = { value :: Int, children :: [Node] }
type Box a = { value :: a }
type Root = { node :: Node, box :: Box Int }
`);if err!=nil{t.Fatal(err)};files,err:=GenerateJSONSerde(program,"example.jsonnested","Contract","RootModule",JSONSerdeOptions{Root:"Root"});if err!=nil{t.Fatal(err)};preserved,err:=GenerateJSONSerde(program,"example.jsonnested","Contract","PreserveModule",JSONSerdeOptions{Root:"Root",PreserveExtraFieldsFor:map[string]bool{"Node":true,"Box":true}});if err!=nil{t.Fatal(err)};for _,file:=range preserved{if strings.HasSuffix(file.Path,"PreserveModule.java"){files=append(files,file)}}
    module:="";dir:=t.TempDir();sources:=[]string{};for _,file:=range files{if strings.HasSuffix(file.Path,"RootModule.java"){module=file.Source};target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)};if !strings.Contains(module,"Node")||!strings.Contains(module,"Box<Int>"){t.Fatal("nested specialization descriptors were not emitted")}
    harness:=filepath.Join(dir,"JSONNested.java");if err:=os.WriteFile(harness,[]byte(jsonNestedJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("nested JSON javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-cp",classes+string(os.PathListSeparator)+classpath,"JSONNested").CombinedOutput();err!=nil{t.Fatalf("nested JSON runtime: %v\n%s",err,output)}
}

func TestJacksonExplicitTaggedUnionsAndResult(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=jacksonClasspath(t);program,err:=language.Compile(`
data Choice = None | Number Int | Pair String Int
type Root = { choice :: Choice, outcome :: Result String Int }
`);if err!=nil{t.Fatal(err)};options:=JSONSerdeOptions{Root:"Root",Discriminators:map[string]JSONDiscriminator{
        "Choice":{Field:"kind",Values:map[string]string{"None":"none","Number":"number","Pair":"pair"},Arguments:map[string][]string{"None":{},"Number":{"value"},"Pair":{"label","count"}}},
        "Result":{Field:"status",Values:map[string]string{"Err":"error","Ok":"ok"},Arguments:map[string][]string{"Err":{"error"},"Ok":{"value"}}},
    }};files,err:=GenerateJSONSerde(program,"example.jsonunion","Contract","RootModule",options);if err!=nil{t.Fatal(err)};dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)};harness:=filepath.Join(dir,"JSONUnion.java");if err:=os.WriteFile(harness,[]byte(jsonUnionJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("union JSON javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-cp",classes+string(os.PathListSeparator)+classpath,"JSONUnion").CombinedOutput();err!=nil{t.Fatalf("union JSON runtime: %v\n%s",err,output)}
    bad:=options;bad.Discriminators=map[string]JSONDiscriminator{"Choice":{Field:"kind",Values:map[string]string{"None":"same","Number":"same","Pair":"pair"},Arguments:map[string][]string{"None":{},"Number":{"value"},"Pair":{"label","count"}}},"Result":options.Discriminators["Result"]};if generated,err:=GenerateJSONSerde(program,"example","Contract","BadModule",bad);err==nil||generated!=nil{t.Fatal("duplicate discriminator values accepted")}
}

const jsonUnionJava = `
import example.jsonunion.*;
import java.math.BigInteger;
public final class JSONUnion {
 static void require(boolean value){if(!value)throw new AssertionError();}
 static void rejects(Runnable action){try{action.run();throw new AssertionError();}catch(ValidationException expected){}}
 public static void main(String[] args)throws Exception{
  var mapper=tools.jackson.databind.json.JsonMapper.builder().addModule(new RootModule()).build();String input="{\"choice\":{\"kind\":\"pair\",\"label\":\"x\",\"count\":2,\"ignored\":true},\"outcome\":{\"status\":\"ok\",\"value\":3}}";
  var root=mapper.readValue(input,Root.class);require(root.choice() instanceof Choice.Pair pair&&pair.value1().equals("x")&&pair.value2().equals(BigInteger.TWO));require(root.outcome() instanceof ModelResult.Ok<String,BigInteger> ok&&ok.value().equals(BigInteger.valueOf(3)));require(mapper.writeValueAsString(root).equals("{\"choice\":{\"kind\":\"pair\",\"label\":\"x\",\"count\":2},\"outcome\":{\"status\":\"ok\",\"value\":3}}"));
  rejects(()->{try{mapper.readValue("{\"choice\":{\"label\":\"x\",\"count\":2},\"outcome\":{\"status\":\"ok\",\"value\":3}}",Root.class);}catch(tools.jackson.core.JacksonException failure){throw new AssertionError(failure);}});
  rejects(()->{try{mapper.readValue("{\"choice\":{\"kind\":\"other\"},\"outcome\":{\"status\":\"ok\",\"value\":3}}",Root.class);}catch(tools.jackson.core.JacksonException failure){throw new AssertionError(failure);}});
 }
}
`

const jsonNestedJava = `
import example.jsonnested.*;
import java.math.BigInteger;
public final class JSONNested {
 static void require(boolean value){if(!value)throw new AssertionError();}
 static void rejects(Runnable action){try{action.run();throw new AssertionError();}catch(ValidationException expected){}}
 public static void main(String[] args)throws Exception{
  var mapper=tools.jackson.databind.json.JsonMapper.builder().addModule(new RootModule()).build();var preserving=tools.jackson.databind.json.JsonMapper.builder().addModule(new PreserveModule()).build();
  String input="{\"node\":{\"value\":1,\"children\":[{\"value\":2,\"children\":[],\"ignored\":true}]},\"box\":{\"value\":3,\"ignored\":false}}";
  var root=mapper.readValue(input,Root.class);require(root.node().value().equals(BigInteger.ONE));require(root.node().children().getFirst().value().equals(BigInteger.TWO));require(root.box().value().equals(BigInteger.valueOf(3)));
  require(mapper.writeValueAsString(root).equals("{\"node\":{\"value\":1,\"children\":[{\"value\":2,\"children\":[]}]},\"box\":{\"value\":3}}"));
  var kept=preserving.readValue(input,Root.class);require(preserving.writeValueAsString(kept).equals(input));
  rejects(()->{try{mapper.readValue("{\"node\":{\"value\":1,\"value\":2,\"children\":[]},\"box\":{\"value\":3}}",Root.class);}catch(tools.jackson.core.JacksonException failure){throw new AssertionError(failure);}});
 }
}
`
