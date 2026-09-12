package java

import (
    "bytes"
    "context"
    "fmt"
    "os"
    "os/exec"
    "path/filepath"
    "strings"
    "testing"
    "time"

    "goforge.dev/refine/language"
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

const inlineModelContract = `
type Age = Int where it >= 0 @code "age.nonnegative"
type Box a = { value :: a, note :: Maybe String }
type Pair a = { sample :: a, text :: String }
positive :: Int -> Bool
positive x = x > 0
mirror :: a -> a
mirror x = if True then x else mirror x
accept :: a -> a -> Bool
accept _ _ = True
type Positive = { box :: Box (Int where positive it @code "positive" @message "Must be positive") }
type Unknown = { box :: Box (Int where 1 / 0 > 0.0 @code "unknown") }
type Multi = { box :: Box (Int where it > 0 @code "low" where it < 10 @code "high") }
type Local a = { box :: Box (a where (let copy = it in let checked :: Bool where it = True in checked && show copy == show it) @code "local") }
type Recursive a = { box :: Box (a where show (mirror it) == show it @code "recursive") }
type Probe a = { box :: Box (Pair a where (case read it.text of { Ok parsed -> accept parsed it.sample; Err _ -> False }) @code "probe" @message ("Cannot read " ++ it.text)) }
type Collection a = { box :: Box ([a] where length it > 0 @code "nonempty") }
type Wrapped a = { box :: Box (Box (a where show it /= "" @code "inner")) }
type Optional a = { box :: Box (Maybe (a where show it /= "")) }
type ResultBox a = { box :: Box (Result (a where show it /= "") (a where show it /= "")) }
type Guarded a = { box :: Box (Maybe (a where False @code "never")) }
type Named = { box :: Box (Age where it < 18 @code "child") }
type Parent = { box :: Box (Int where it > 0) }
type Child = Parent
data Envelope = Empty | Package (Box (Int where it > 0))
type RefinedEnvelope = Envelope
`

func TestInlineRefinementModels(t *testing.T){
    compiler,vm:=javaTools(t);dependencies:=jetCheckClasspath(t)
    program,err:=language.Compile(inlineModelContract);if err!=nil{t.Fatal(err)}
    files,err:=GenerateModels(program,"example.inline","Contract");if err!=nil{t.Fatal(err)}
    dir:=t.TempDir();sources:=[]string{}
    for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)}
    harness:=filepath.Join(dir,"InlineModels.java");if err:=os.WriteFile(harness,[]byte(inlineModelHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness)
    classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",dependencies,"-d",classes},sources...)
    if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("inline model javac: %v\n%s",err,output)}
    specs:=[]string{
        `Box (Int where positive it @code "positive" @message "Must be positive")`,
        `Box (Int where 1 / 0 > 0.0 @code "unknown")`,
        `Box (Int where it > 0 @code "low" where it < 10 @code "high")`,
        `Box (Int where (let copy = it in let checked :: Bool where it = True in checked && show copy == show it) @code "local")`,
        `Box (Int where show (mirror it) == show it @code "recursive")`,
        `Box (Pair Age where (case read it.text of { Ok parsed -> accept parsed it.sample; Err _ -> False }) @code "probe" @message ("Cannot read " ++ it.text))`,
    }
    vectors:=[]vector{}
    for index,spec:=range specs{
        target,err:=program.PayloadType(spec);if err!=nil{t.Fatal(err)}
        for _,n:=range []int64{-1,0,1,10}{for limit:=uint64(0);limit<300;limit++{
            payload:=testNumber(fmt.Sprint(n));if index==5{payload=testRecord(value.DataField{Name:"sample",Value:testNumber("1")},value.DataField{Name:"text",Value:testText(fmt.Sprint(n))})}
            raw:=testRecord(value.DataField{Name:"value",Value:payload},value.DataField{Name:"note",Value:testVariant("Nothing")})
            report:=target.ValidateData(raw,validation.Limits{Total:limit})
            vectors=append(vectors,vector{fmt.Sprintf("%d\t%d\t%d",index,n,limit),reportLine(report)})
        }}
    }
    var input strings.Builder;for _,v:=range vectors{input.WriteString(v.input);input.WriteByte('\n')}
    ctx,cancel:=context.WithTimeout(context.Background(),3*time.Minute);defer cancel();command:=exec.CommandContext(ctx,vm,"-Xss256k","-cp",classes+string(os.PathListSeparator)+dependencies,"InlineModels");command.Stdin=strings.NewReader(input.String());var stderr bytes.Buffer;command.Stderr=&stderr
    output,err:=command.Output();if err!=nil{t.Fatalf("inline models: %v\n%s",err,stderr.String())}
    lines:=strings.Split(strings.TrimSuffix(string(output),"\n"),"\n");if len(lines)!=len(vectors){t.Fatalf("expected %d reports, got %d",len(vectors),len(lines))}
    for i,v:=range vectors{if v.expected!=lines[i]{t.Fatalf("%s\nJava %s\nGo   %s",v.input,lines[i],v.expected)}}
    t.Logf("%d full Go/Java inline-witness reports and 6000 JetCheck cases passed",len(vectors))
}

const inlineModelHarnessJava = `
import example.inline.*;
import java.math.BigInteger;
import java.util.List;
import java.util.Locale;
import java.util.HexFormat;
import java.nio.charset.StandardCharsets;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import org.jetbrains.jetCheck.Generator;
import org.jetbrains.jetCheck.PropertyChecker;
public final class InlineModels {
    static BigInteger n(long value){return BigInteger.valueOf(value);}
    static Box<BigInteger> box(long value){return new Box<>(ModelTypes.integer(),n(value),new ModelMaybe.Nothing<>());}
    static Box<String> text(long value){return new Box<>(ModelTypes.text(),Long.toString(value),new ModelMaybe.Nothing<>());}
    static <A> Box<Pair<A>> pair(ModelType<A> type,A sample,long value){return new Box<>(ModelTypes.forPair(type),new Pair<>(type,sample,Long.toString(value)),new ModelMaybe.Nothing<>());}
    static void require(boolean test){if(!test)throw new AssertionError();}
    static void rejects(Runnable action){try{action.run();throw new AssertionError("invalid accepted");}catch(ValidationException expected){}}
    static String hex(String text){return HexFormat.of().formatHex(text.getBytes(StandardCharsets.UTF_8));}
    static void print(Validation.Outcome outcome){var report=new StringBuilder(outcome.state().name().toLowerCase(Locale.ROOT)).append('|').append(outcome.incomplete());for(var d:outcome.diagnostics())report.append('|').append(hex(d.code())).append(',').append(hex(String.join(";",d.paths()))).append(',').append(hex(d.predicate())).append(',').append(hex(d.message()));System.out.println(report);}
    public static void main(String[] args)throws Exception{
        var input=new BufferedReader(new InputStreamReader(System.in,StandardCharsets.UTF_8));String line;
        while((line=input.readLine())!=null){String[] f=line.split("\t");int which=Integer.parseInt(f[0]);long value=Long.parseLong(f[1]);var limits=new Budget.Limits(Long.parseLong(f[2]),0);
            print(switch(which){
                case 0 -> Positive.createWithoutValidation(box(value)).box().validate(limits);
                case 1 -> Unknown.createWithoutValidation(box(value)).box().validate(limits);
                case 2 -> Multi.createWithoutValidation(box(value)).box().validate(limits);
                case 3 -> Local.createWithoutValidation(ModelTypes.integer(),box(value)).box().validate(limits);
                case 4 -> Recursive.createWithoutValidation(ModelTypes.integer(),box(value)).box().validate(limits);
                case 5 -> Probe.createWithoutValidation(ModelTypes.forAge(),pair(ModelTypes.forAge(),new Age(n(1)),value)).box().validate(limits);
                default -> throw new AssertionError();
            });
        }
        var outer=new Positive(box(1));require(outer.box().value().equals(n(1)));
        rejects(()->new Positive(box(0)));rejects(()->Positive.read("{box = {value = 0}}"));
        var nested=Positive.read("{box = {value = 1}}").box();rejects(()->nested.update(d->d.setValue(n(0))));
        require(nested.updateWithoutValidation(d->d.setValue(n(0))).validate().state()==Validation.State.INVALID);
        var invalid=Positive.createWithoutValidation(box(-1));require(invalid.box().value().equals(n(-1)));require(invalid.box().validate().state()==Validation.State.INVALID);
        require(new Child(box(1)).box().validate().state()==Validation.State.VALID);
        rejects(()->new Child(box(-1)));
        var union=new RefinedEnvelope.Package(box(1));rejects(()->union.value().update(d->d.setValue(n(0))));
        require(Envelope.Package.createWithoutValidation(box(-1)).value().validate().state()==Validation.State.INVALID);
        var age=ModelTypes.forAge();var integer=ModelTypes.integer();
        require(new Probe<>(integer,pair(integer,n(1),-1)).box().validate().state()==Validation.State.VALID);
        rejects(()->new Probe<>(age,pair(age,new Age(n(1)),-1)));
        require(Probe.createWithoutValidation(age,pair(age,new Age(n(1)),-1)).box().validate().state()==Validation.State.INVALID);
        require(new Local<>(age,new Box<>(age,new Age(n(1)),new ModelMaybe.Nothing<>())).box().value().value().equals(n(1)));
        require(new Collection<>(age,new Box<>(ModelTypes.list(age),List.of(new Age(n(1))),new ModelMaybe.Nothing<>())).box().validate().state()==Validation.State.VALID);
        rejects(()->new Collection<>(age,new Box<>(ModelTypes.list(age),List.of(),new ModelMaybe.Nothing<>())));
        var wrapped=new Wrapped<>(age,new Box<>(ModelTypes.forBox(age),new Box<>(age,new Age(n(1)),new ModelMaybe.Nothing<>()),new ModelMaybe.Nothing<>()));
        require(wrapped.box().value().value().value().equals(n(1)));
        require(new Optional<>(age,new Box<>(ModelTypes.maybe(age),new ModelMaybe.Nothing<>(),new ModelMaybe.Nothing<>())).box().validate().state()==Validation.State.VALID);
        require(new ResultBox<>(age,new Box<>(ModelTypes.result(age,age),new ModelResult.Ok<Age,Age>(new Age(n(1))),new ModelMaybe.Nothing<>())).box().validate().state()==Validation.State.VALID);
        var emptyGuard=new Guarded<>(age,new Box<>(ModelTypes.maybe(age),new ModelMaybe.Nothing<>(),new ModelMaybe.Nothing<>()));
        rejects(()->emptyGuard.box().update(d->d.setValue(new ModelMaybe.Just<>(new Age(n(1))))));
        require(new Named(new Box<>(age,new Age(n(17)),new ModelMaybe.Nothing<>())).box().value().value().equals(n(17)));
        rejects(()->new Named(new Box<>(age,new Age(n(18)),new ModelMaybe.Nothing<>())));
        rejects(()->new Named(new Box<>(age,new Age(n(17)),new ModelMaybe.Nothing<>())).box().update(d->d.setValue(new Age(n(18)))));
        var shared=new Probe<>(age,pair(age,new Age(n(1)),1)).box();var failures=new java.util.concurrent.atomic.AtomicInteger();var threads=new java.util.ArrayList<Thread>();
        for(int i=0;i<8;i++){var thread=new Thread(()->{for(int j=0;j<100;j++)if(shared.validate().state()!=Validation.State.VALID)failures.incrementAndGet();});threads.add(thread);thread.start();}for(var thread:threads)thread.join();require(failures.get()==0);
        PropertyChecker.customized().withIterationCount(2000).forAll(Generator.integers(),seed->{
            var candidate=Positive.createWithoutValidation(box(seed)).box();require((candidate.validate().state()==Validation.State.VALID)==(seed>0));
            var updated=candidate.update(d->d.setValue(n(1)));require(updated.value().equals(n(1)));require(candidate.value().equals(n(seed)));return true;
        });
        PropertyChecker.customized().withIterationCount(2000).forAll(Generator.integers(),seed->{
            var candidate=Probe.createWithoutValidation(age,pair(age,new Age(n(1)),seed)).box();require((candidate.validate().state()==Validation.State.VALID)==(seed>=0));
            require(new Probe<>(integer,pair(integer,n(1),seed)).box().validate().state()==Validation.State.VALID);return true;
        });
        PropertyChecker.customized().withIterationCount(2000).forAll(Generator.integers(),seed->{
            var candidate=new Local<>(integer,box(seed)).box();require(candidate.validate().state()==Validation.State.VALID);
            require(new Recursive<>(integer,box(seed)).box().validate().state()==Validation.State.VALID);return true;
        });
    }
}
`

func TestInlineWitnessScale(t *testing.T){
    compiler,vm:=javaTools(t)
    var source,harness strings.Builder
    source.WriteString("type Box a = { value :: a }\ntype Wide a = {")
    for i:=0;i<1100;i++{if i>0{source.WriteString(",")};fmt.Fprintf(&source," f%d :: Box (a where show it /= \"\")",i)}
    source.WriteString(" }\ntype Deep a = { box :: Box (a where ")
    for i:=0;i<200;i++{source.WriteString("True && (")};source.WriteString("show it /= \"\"");source.WriteString(strings.Repeat(")",200));source.WriteString(") }\n")
    program,err:=language.Compile(source.String());if err!=nil{t.Fatal(err)}
    files,err:=GenerateModels(program,"","Contract");if err!=nil{t.Fatal(err)}
    harness.WriteString("import java.math.BigInteger; public final class InlineScale { public static void main(String[] args) { var integer=ModelTypes.integer(); var box=new Box<>(integer,BigInteger.ONE); var wide=Wide.create(integer,d -> {\n")
    for i:=0;i<1100;i++{fmt.Fprintf(&harness,"d.setF%d(box);\n",i)};harness.WriteString("});\n")
    for i:=0;i<1100;i++{fmt.Fprintf(&harness,"if(wide.f%d().validate().state()!=Validation.State.VALID)throw new AssertionError();\n",i)}
    harness.WriteString("var deep=new Deep<>(integer,box); if(deep.box().validate().state()!=Validation.State.VALID)throw new AssertionError(); } }\n")
    dir:=t.TempDir();sources:=[]string{}
    for _,file:=range files{target:=filepath.Join(dir,file.Path);if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)}
    target:=filepath.Join(dir,"InlineScale.java");if err:=os.WriteFile(target,[]byte(harness.String()),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)
    classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-d",classes},sources...)
    if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("inline scale compile: %v\n%s",err,output)}
    if output,err:=exec.Command(vm,"-Xss256k","-cp",classes,"InlineScale").CombinedOutput();err!=nil{t.Fatalf("inline scale execution: %v\n%s",err,output)}
}
