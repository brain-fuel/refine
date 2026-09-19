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
    "goforge.dev/refine/native"
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

const codePointLengthContract=`
type One = String where codePointLength it == 1 @code "one"
type Two = String where codePointLength it == 2 @code "two"
type UTF16Two = String where length it == 2 @code "utf16-two"
`

const codePointLengthShadowContract=`
codePointLength :: String -> Int
codePointLength _ = 41
type Shadowed = String where codePointLength it == 41 @code "shadowed"
`

func codePointText(units ...uint16)value.Data{return value.OfText(value.TextFromUnits(units))}

func TestGeneratedCodePointLengthRuntimeParityAndNativeStringLengthSerde(t *testing.T){
    program,err:=language.Compile(codePointLengthContract);if err!=nil{t.Fatal(err)}
    shadow,err:=language.Compile(codePointLengthShadowContract);if err!=nil{t.Fatal(err)}
    files,err:=GenerateValidator(program,"example.codepoints","Contract");if err!=nil{t.Fatal(err)}
    shadowFiles,err:=GenerateValidator(shadow,"example.codepointshadow","Contract");if err!=nil{t.Fatal(err)};files=append(files,shadowFiles...)
    schema:=`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"string","minLength":1.0,"maxLength":3}`;project,err:=native.IngestProject(native.JSONSchema,[]byte(schema),native.ProjectOptions{Root:native.ResourceSelector{TypeName:"Text"},Metadata:native.WireMetadata{PublicationNamespace:"example.codepointnative"}});if err!=nil{t.Fatal(err)}
    minimum:="";for _,item:=range project.NativeConstraints(){if item.Constraint.Keyword=="minLength"{minimum=item.Constraint.Predicate}};if minimum!="((codePointLength it) >= 1)"{t.Fatalf("unexpected minLength provenance: %q",minimum)};source:=project.ResourceConstraintSource("urn:refine:root");editedMinimum:=strings.Replace(minimum,">= 1",">= 2",1);changed:=strings.Replace(source,minimum,editedMinimum,1);if editedMinimum==minimum||changed==source{t.Fatal("minLength edit was not applied")};project,err=project.WithEditedNativeConstraintSource("urn:refine:root",changed);if err!=nil{t.Fatal(err)};if err:=project.ValidateJSON([]byte(`"😀😀"`));err!=nil{t.Fatal(err)};if err:=project.ValidateJSON([]byte(`"😀"`));err==nil{t.Fatal("edited native minLength was not enforced")};nativeFiles,err:=GenerateProjectJSONSerde(project,"Contract","TextModule");if err!=nil{t.Fatal(err)};files=append(files,nativeFiles...)
    dir:=t.TempDir();sources:=[]string{}
    for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)}
    harness:=filepath.Join(dir,"CodePointLengthHarness.java");if err:=os.WriteFile(harness,[]byte(codePointLengthHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness)
    classes:=filepath.Join(dir,"classes");compiler,vm:=javaTools(t);classpath:=networkntClasspath(t);args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...)
    compileContext,stopCompile:=context.WithTimeout(context.Background(),time.Minute);defer stopCompile();if output,err:=exec.CommandContext(compileContext,compiler,args...).CombinedOutput();err!=nil{if compileContext.Err()!=nil{t.Fatalf("codePointLength javac exceeded the process deadline: %v",compileContext.Err())};t.Fatalf("codePointLength javac: %v\n%s",err,output)}

    vectors:=[]vector{};add:=func(contract,root string,data value.Data,limits validation.Limits){owner:=program;if contract=="shadow"{owner=shadow};text,ok:=data.Text();if !ok{t.Fatal("codePointLength vector is not text")};vectors=append(vectors,vector{fmt.Sprintf("%s\t%s\t%s\t%d\t%d",contract,root,unitsHex(text.Units()),limits.Total,limits.Clause),reportLine(owner.ValidateData(root,data,limits))})}
    semantic:=[]struct{root string;data value.Data;valid bool}{
        {"One",codePointText('a'),true},
        {"One",codePointText(0x00e9),true},
        {"One",codePointText(0xd83d,0xde00),true},
        {"One",codePointText(0xd800),true},
        {"One",codePointText(0xdc00),true},
        {"Two",codePointText(0xd83d,0xde00,0xd83d,0xde01),true},
        {"Two",codePointText('e',0x0301),true},
        {"Two",codePointText(0xd800,'a'),true},
        {"Two",codePointText(0xd800,0xd801),true},
        {"One",codePointText('e',0x0301),false},
        {"One",codePointText(0x00e9),true},
        {"UTF16Two",codePointText(0xd83d,0xde00),true},
    };for _,item:=range semantic{report:=program.ValidateData(item.root,item.data,validation.Limits{});if (validation.StateName(report.State())=="valid")!=item.valid||report.Incomplete(){t.Fatalf("bad semantic fixture %s: %+v",item.root,report.Diagnostics())};add("base",item.root,item.data,validation.Limits{})}
    for _,data:=range []value.Data{codePointText('a'),codePointText(0xd83d,0xde00),codePointText(0xd83d,0xde00,0xd83d,0xde01),codePointText(0xd800)}{for limit:=uint64(1);limit<=20;limit++{add("base","One",data,validation.Limits{Total:limit});add("base","One",data,validation.Limits{Clause:limit})}}
    add("shadow","Shadowed",codePointText(0xd83d,0xde00),validation.Limits{});add("shadow","Shadowed",codePointText(0xd800),validation.Limits{})
    var input strings.Builder;for _,item:=range vectors{input.WriteString(item.input);input.WriteByte('\n')}
    runContext,stopRun:=context.WithTimeout(context.Background(),time.Minute);defer stopRun();command:=exec.CommandContext(runContext,vm,"-Xss256k","-Xmx64m","-cp",classes+string(os.PathListSeparator)+classpath,"CodePointLengthHarness");command.Stdin=strings.NewReader(input.String());var stderr bytes.Buffer;command.Stderr=&stderr;output,err:=command.Output();if err!=nil{if runContext.Err()!=nil{t.Fatalf("codePointLength JVM exceeded the process deadline: %v",runContext.Err())};t.Fatalf("codePointLength JVM: %v\n%s",err,stderr.String())};lines:=strings.Split(strings.TrimSuffix(string(output),"\n"),"\n");if len(lines)!=len(vectors){t.Fatalf("expected %d Java reports, got %d",len(vectors),len(lines))};for i,item:=range vectors{if lines[i]!=item.expected{t.Fatalf("case %s\nJava %s\nGo   %s",item.input,lines[i],item.expected)}}
}

const codePointLengthHarnessJava=`
import java.nio.charset.StandardCharsets;
import java.util.HexFormat;
import java.util.Locale;
import java.io.BufferedReader;
import java.io.InputStreamReader;
public final class CodePointLengthHarness {
  interface Checked{void run()throws Exception;}
  static String units(String encoded){char[] result=new char[encoded.length()/4];for(int i=0;i<result.length;i++)result[i]=(char)Integer.parseInt(encoded.substring(i*4,i*4+4),16);return new String(result);}
  static String hex(String text){return HexFormat.of().formatHex(text.getBytes(StandardCharsets.UTF_8));}
  static void require(boolean value){if(!value)throw new AssertionError();}
  static void rejects(Checked action){try{action.run();throw new AssertionError("accepted");}catch(AssertionError failure){throw failure;}catch(Exception expected){}}
  static String report(example.codepoints.Validation.Outcome outcome){var result=new StringBuilder(outcome.state().name().toLowerCase(Locale.ROOT)).append('|').append(outcome.incomplete());for(var d:outcome.diagnostics())result.append('|').append(hex(d.code())).append(',').append(hex(String.join(";",d.paths()))).append(',').append(hex(d.predicate())).append(',').append(hex(d.message()));return result.toString();}
  static String report(example.codepointshadow.Validation.Outcome outcome){var result=new StringBuilder(outcome.state().name().toLowerCase(Locale.ROOT)).append('|').append(outcome.incomplete());for(var d:outcome.diagnostics())result.append('|').append(hex(d.code())).append(',').append(hex(String.join(";",d.paths()))).append(',').append(hex(d.predicate())).append(',').append(hex(d.message()));return result.toString();}
  static void serde()throws Exception{String point="😀";var mapper=tools.jackson.databind.json.JsonMapper.builder().addModule(new example.codepointnative.TextModule()).build();var valid=mapper.readValue("\""+point+point+"\"",example.codepointnative.Text.class);require(valid.value().equals(point+point));require(mapper.readValue("\"e\\u0301\"",example.codepointnative.Text.class).value().equals("e\u0301"));rejects(()->mapper.readValue("\""+point+"\"",example.codepointnative.Text.class));rejects(()->mapper.readValue("\"é\"",example.codepointnative.Text.class));rejects(()->mapper.readValue("\"abcd\"",example.codepointnative.Text.class));var sink=new java.io.StringWriter();rejects(()->mapper.writeValue(sink,example.codepointnative.Text.createWithoutValidation(point)));require(sink.toString().isEmpty());}
  public static void main(String[] args)throws Exception{serde();var input=new BufferedReader(new InputStreamReader(System.in,StandardCharsets.UTF_8));String line;while((line=input.readLine())!=null){String[] f=line.split("\\t",-1);String text=units(f[2]);long total=Long.parseLong(f[3]),clause=Long.parseLong(f[4]);if(f[0].equals("shadow"))System.out.println(report(example.codepointshadow.Contract.validate(f[1],new example.codepointshadow.Data.Text(text),new example.codepointshadow.Budget.Limits(total,clause))));else System.out.println(report(example.codepoints.Contract.validate(f[1],new example.codepoints.Data.Text(text),new example.codepoints.Budget.Limits(total,clause))));}}
}
`
