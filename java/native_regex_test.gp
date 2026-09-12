package java

import (
    "context"
    "crypto/sha256"
    "encoding/hex"
    "os"
    "os/exec"
    "path/filepath"
    "strings"
    "testing"
    "time"

    "goforge.dev/refine/native"
)

func graalJSClasspath(t *testing.T)string{t.Helper();dir:=os.Getenv("REFINE_GRAALJS_DIR");if dir==""{if os.Getenv("REFINE_REQUIRE_JAVA")=="1"{t.Fatal("REFINE_GRAALJS_DIR is required by the Java release gate")};t.Skip("set REFINE_GRAALJS_DIR to pinned GraalJS Community 25.0.1 jars")};jars:=[]struct{name,sum string}{
    {"collections-25.0.1.jar","ff061048f20a93b0af51d8a948556d536fb369aef6b851e698ff8743a3bc4e7f"},
    {"icu4j-25.0.1.jar","bbb95f5f2b8ab5708b52fd626dae25341117286653a44618ef203842f9602b71"},
    {"jniutils-25.0.1.jar","a6c418de8267629243787dbbd8543e23ce8f5cba1744a3a9fff3655e63c45183"},
    {"js-language-25.0.1.jar","60a48a1f54dab106dffcd18e536f5f272ec2ee99b5c960ee97c5666cb65cde9e"},
    {"nativeimage-25.0.1.jar","458bcbaaf46624c9eda49c0e499fd32af1c3774c6f8e412a509a1c422cc06cf8"},
    {"polyglot-25.0.1.jar","992099d38ab64e1a8ebb9753c1959d431c4889905ff9e8ec946911692f0879c5"},
    {"regex-25.0.1.jar","6676d06a278f39f71abc2f4dc7851a233cacf39e107eaffe6e3d3237499ecc04"},
    {"truffle-api-25.0.1.jar","9ac4298675e7ab0690ca1338999a8936ab5a11a0891ee6864b7674fda5db94e5"},
    {"truffle-compiler-25.0.1.jar","5d8eeae2647841ce5e6f1a0bfa27ef91343b9e5c0178d5153be409f792507d2c"},
    {"truffle-runtime-25.0.1.jar","0fea733ecbac7a1096f70163698fafd663224203a4f37b4ea479fec7b6ae0721"},
    {"word-25.0.1.jar","071f4a4a969977f63dc36f446e0b90b19c631f5466a715ba7d5e8f0ab9f5fc87"},
    {"xz-25.0.1.jar","db0ee6766934f58bbb6a7826c58683132b83386ef466beba609808f6d1b9799c"},
};parts:=[]string{};for _,jar:=range jars{item:=filepath.Join(dir,jar.name);data,err:=os.ReadFile(item);if err!=nil{t.Fatalf("GraalJS test dependency: %v",err)};sum:=sha256.Sum256(data);if hex.EncodeToString(sum[:])!=jar.sum{t.Fatalf("GraalJS test dependency %s has an unexpected SHA-256",jar.name)};parts=append(parts,item)};return strings.Join(parts,string(os.PathListSeparator))}

func TestNativeRegexEmissionIsConditional(t *testing.T){plain,err:=native.IngestProject(native.JSONSchema,[]byte(`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"string"}`),native.ProjectOptions{});if err!=nil{t.Fatal(err)};files,err:=GenerateProjectNativeJSONValidator(plain,"PlainCheck");if err!=nil{t.Fatal(err)};if strings.Contains(files[0].Source,"org.graalvm")||strings.Contains(files[0].Source,"RegexLimits")||strings.Contains(files[0].Source,"regularExpressionFactory"){t.Fatal("a non-regex schema acquired a GraalJS runtime dependency")}
    patterned,err:=native.IngestProject(native.JSONSchema,[]byte(`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"string","pattern":"(?<=a)b"}`),native.ProjectOptions{});if err!=nil{t.Fatal(err)};files,err=GenerateProjectNativeJSONValidator(patterned,"PatternCheck");if err!=nil{t.Fatal(err)};for _,part:=range []string{"org.graalvm.polyglot.Context","RegexLimits","regularExpressionFactory(new BoundedRegexFactory())","HostAccess.newBuilder(org.graalvm.polyglot.HostAccess.NONE)","allowIO(org.graalvm.polyglot.io.IOAccess.NONE)","Thread.ofVirtual()","inheritInheritableThreadLocals(false)","setContextClassLoader(null)","watchdog.interrupt()","Native ECMA-262 regex cleanup could not complete"}{if !strings.Contains(files[0].Source,part){t.Fatalf("regex helper omitted %q",part)}};if strings.Contains(files[0].Source,"ScheduledThreadPoolExecutor"){t.Fatal("regex helper retained a class-lifetime watchdog scheduler")}}

func TestGeneratedNativeRegexECMA262AndBudgets(t *testing.T){
    // This is a native-only validator fixture, not automatic typed-map serde.
    // Its intentionally empty Refine view is explicit; every original native
    // constraint, including patternProperties, must still be enforced.
    compiler,vm:=javaTools(t);classpath:=networkntClasspath(t)+string(os.PathListSeparator)+graalJSClasspath(t);schema:=`{"x-refine":{"source":"type ImportedRoot = {}\n","root":"ImportedRoot"},"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{"ahead":{"type":"string","pattern":"^(?=a)a+$"},"behind":{"type":"string","pattern":"(?<=prefix:)value$"},"backref":{"type":"string","pattern":"^(?<word>[a-z]+)-\\k<word>$"},"unicode":{"type":"string","pattern":"^\\u{1F600}$"},"bomb":{"type":"string","pattern":"^(a+)+\\1$"},"keys":{"type":"object","patternProperties":{"^(?<head>[a-z])\\k<head>$":{"type":"integer"}},"additionalProperties":false}},"required":["ahead","behind","backref","unicode","bomb","keys"],"additionalProperties":false}`;project,err:=native.IngestProject(native.JSONSchema,[]byte(schema),native.ProjectOptions{Metadata:native.WireMetadata{PublicationNamespace:"example.regex"}});if err!=nil{t.Fatal(err)};files,err:=GenerateProjectNativeJSONValidator(project,"RegexCheck");if err!=nil{t.Fatal(err)}
    anyOf:=`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"string","anyOf":[{"not":{"pattern":"^a+$"}},{"pattern":"^a+$"}]}`;project,err=native.IngestProject(native.JSONSchema,[]byte(anyOf),native.ProjectOptions{Metadata:native.WireMetadata{PublicationNamespace:"example.regex"}});if err!=nil{t.Fatal(err)};more,err:=GenerateProjectNativeJSONValidator(project,"AnyOfCheck");if err!=nil{t.Fatal(err)};files=append(files,more...)
    dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)};harness:=filepath.Join(dir,"NativeRegexHarness.java");if err:=os.WriteFile(harness,[]byte(nativeRegexHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("native regex javac: %v\n%s",err,output)}
    ctx,cancel:=context.WithTimeout(context.Background(),20*time.Second);defer cancel();if output,err:=exec.CommandContext(ctx,vm,"-cp",classes+string(os.PathListSeparator)+classpath,"NativeRegexHarness").CombinedOutput();err!=nil{if ctx.Err()!=nil{t.Fatalf("native regex runtime exceeded the process deadline: %v",ctx.Err())};t.Fatalf("native regex runtime: %v\n%s",err,output)}
}

func TestGeneratedProjectJSONSerdeExposesRegexLimits(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=networkntClasspath(t)+string(os.PathListSeparator)+graalJSClasspath(t);schema:=`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"string","pattern":"^(a+)+\\1$"}`;project,err:=native.IngestProject(native.JSONSchema,[]byte(schema),native.ProjectOptions{Root:native.ResourceSelector{TypeName:"Value"},Metadata:native.WireMetadata{PublicationNamespace:"example.regexserde"}});if err!=nil{t.Fatal(err)};files,err:=GenerateProjectJSONSerde(project,"Contract","ValueModule");if err!=nil{t.Fatal(err)};dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)};harness:=filepath.Join(dir,"RegexSerdeHarness.java");if err:=os.WriteFile(harness,[]byte(regexSerdeHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("regex serde javac: %v\n%s",err,output)};ctx,cancel:=context.WithTimeout(context.Background(),15*time.Second);defer cancel();if output,err:=exec.CommandContext(ctx,vm,"-cp",classes+string(os.PathListSeparator)+classpath,"RegexSerdeHarness").CombinedOutput();err!=nil{if ctx.Err()!=nil{t.Fatalf("regex serde runtime exceeded the process deadline: %v",ctx.Err())};t.Fatalf("regex serde runtime: %v\n%s",err,output)}
}

const regexSerdeHarnessJava=`
import example.regexserde.*;
public final class RegexSerdeHarness {
 static ValueModuleNativeSidecar.NativeValidationException nativeFailure(Throwable failure){for(Throwable current=failure;current!=null;current=current.getCause())if(current instanceof ValueModuleNativeSidecar.NativeValidationException nativeFailure)return nativeFailure;throw new AssertionError("native failure was not retained",failure);}
 public static void main(String[] args)throws Exception{
  var nativeLimits=ValueModuleNativeSidecar.Limits.defaults();var regexLimits=new ValueModuleNativeSidecar.RegexLimits(16384,1,100,8L<<20,1000);var module=new ValueModule(ValueModule.CodecLimits.defaults(),nativeLimits,regexLimits);var mapper=ValueModule.strictMapper(module);
  try{mapper.readValue("\"aa\"",Value.class);throw new AssertionError("tiny regex input budget accepted read");}catch(RuntimeException failure){var nativeFailure=nativeFailure(failure);if(!nativeFailure.isResourceLimit()||!nativeFailure.isIndeterminate())throw new AssertionError("read limit classification");}
  var sink=new java.io.StringWriter();try{mapper.writeValue(sink,new Value("aa"));throw new AssertionError("tiny regex input budget accepted write");}catch(RuntimeException failure){var nativeFailure=nativeFailure(failure);if(!nativeFailure.isResourceLimit()||!nativeFailure.isIndeterminate())throw new AssertionError("write limit classification");}if(!sink.toString().isEmpty())throw new AssertionError("regex-indeterminate bytes escaped");
  var defaults=ValueModule.strictMapper(new ValueModule(nativeLimits));if(!defaults.readValue("\"aa\"",Value.class).value().equals("aa"))throw new AssertionError("simple native-limit constructor changed");if(!ValueModule.strictMapper(new ValueModule(nativeLimits,ValueModuleNativeSidecar.RegexLimits.defaults())).writeValueAsString(new Value("aa")).equals("\"aa\""))throw new AssertionError("regex overload failed");
 }
}
`

const nativeRegexHarnessJava=`
import example.regex.AnyOfCheck;
import example.regex.RegexCheck;
public final class NativeRegexHarness {
 static final String VALID="{\"ahead\":\"aaaa\",\"behind\":\"prefix:value\",\"backref\":\"word-word\",\"unicode\":\"😀\",\"bomb\":\"aaaa\",\"keys\":{\"aa\":1}}";
 static void invalid(Runnable action){try{action.run();throw new AssertionError("accepted");}catch(RegexCheck.NativeValidationException expected){if(expected.code()!=RegexCheck.Code.INVALID)throw new AssertionError("invalid classification: "+expected.code());}}
 static void resource(Runnable action){try{action.run();throw new AssertionError("accepted");}catch(RegexCheck.NativeValidationException expected){if(!expected.isResourceLimit()||!expected.isIndeterminate())throw new AssertionError("resource classification: "+expected.code());}}
 static void anyResource(Runnable action){try{action.run();throw new AssertionError("accepted");}catch(AnyOfCheck.NativeValidationException expected){if(!expected.isResourceLimit()||!expected.isIndeterminate())throw new AssertionError("anyOf swallowed resource failure: "+expected.code());}}
 static void concurrentAttack(RegexCheck check,java.util.concurrent.atomic.AtomicReference<Throwable> failure,String input,java.util.concurrent.CountDownLatch ready,java.util.concurrent.CountDownLatch start){try{ready.countDown();start.await();try{check.validate(input);failure.set(new AssertionError("catastrophic regex was accepted"));}catch(RegexCheck.NativeValidationException expected){if(!expected.isResourceLimit())failure.set(new AssertionError("concurrent timeout misclassified: "+expected.code()));}}catch(Throwable problem){failure.set(problem);}}
 public static void main(String[] args){
  long start=System.nanoTime();var deadline=new RegexCheck(RegexCheck.Limits.defaults(),new RegexCheck.RegexLimits(16384,1<<20,100,8L<<20,1));resource(()->deadline.validate(VALID));if(System.nanoTime()-start>5_000_000_000L)throw new AssertionError("regex cancellation was not bounded");
  var check=new RegexCheck();check.validate(VALID);invalid(()->check.validate(VALID.replace("aaaa","ba")));invalid(()->check.validate(VALID.replace("word-word","word-words")));invalid(()->check.validate(VALID.replace("😀","x")));invalid(()->check.validate(VALID.replace("\"aa\":1","\"ab\":1")));
  String attack=VALID.replace("\"bomb\":\"aaaa\"","\"bomb\":\""+"a".repeat(32)+"!\"");var bounded=new RegexCheck(RegexCheck.Limits.defaults(),new RegexCheck.RegexLimits(16384,1<<20,100,8L<<20,50));start=System.nanoTime();resource(()->bounded.validate(attack));long elapsed=System.nanoTime()-start;if(elapsed<10_000_000L||elapsed>2_000_000_000L)throw new AssertionError("guest cancellation deadline was not observed: "+elapsed);new RegexCheck().validate(VALID);
  int count=8;var shared=new RegexCheck(RegexCheck.Limits.defaults(),new RegexCheck.RegexLimits(16384,1<<20,100,8L<<20,50));var failures=new java.util.ArrayList<java.util.concurrent.atomic.AtomicReference<Throwable>>();var threads=new java.util.ArrayList<Thread>();var ready=new java.util.concurrent.CountDownLatch(count);var release=new java.util.concurrent.CountDownLatch(1);for(int i=0;i<count;i++){var failure=new java.util.concurrent.atomic.AtomicReference<Throwable>();failures.add(failure);var thread=new Thread(()->concurrentAttack(shared,failure,attack,ready,release),"regex-attack-"+i);threads.add(thread);thread.start();}try{if(!ready.await(2,java.util.concurrent.TimeUnit.SECONDS))throw new AssertionError("regex attacks did not become ready");release.countDown();for(var thread:threads)thread.join(3000);}catch(InterruptedException failure){throw new AssertionError(failure);}for(var thread:threads)if(thread.isAlive())throw new AssertionError("concurrent regex cancellation was not bounded");for(var failure:failures)if(failure.get()!=null)throw new AssertionError(failure.get());shared.validate(VALID);new RegexCheck().validate(VALID);
  var one=new RegexCheck(RegexCheck.Limits.defaults(),new RegexCheck.RegexLimits(16384,1<<20,1,8L<<20,1000));resource(()->one.validate(VALID));var shortInput=new RegexCheck(RegexCheck.Limits.defaults(),new RegexCheck.RegexLimits(16384,4,100,8L<<20,1000));resource(()->shortInput.validate(VALID));var tinyWork=new RegexCheck(RegexCheck.Limits.defaults(),new RegexCheck.RegexLimits(16384,1<<20,100,1,1000));resource(()->tinyWork.validate(VALID));
  var any=new AnyOfCheck(AnyOfCheck.Limits.defaults(),new AnyOfCheck.RegexLimits(16384,4,100,8L<<20,1000));anyResource(()->any.validate("\"aaaaaaaa\""));
  try{new RegexCheck.RegexLimits(16385,1<<20,10000,8L<<20,1000);throw new AssertionError("relaxed pattern limit accepted");}catch(IllegalArgumentException expected){}try{new RegexCheck.RegexLimits(16384,1<<20,10000,8L<<20,1001);throw new AssertionError("relaxed deadline accepted");}catch(IllegalArgumentException expected){}
 }
}
`
