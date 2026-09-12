package java

import (
    "bytes"
    "fmt"
    "os"
    "os/exec"
    "path/filepath"
    "strings"
    "testing"

    "goforge.dev/refine/language"
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

const fixedFloatContract=`
type F32 = Float32
type Nonnegative32 = Float32 where fromFloat32 it >= 0.0
type Sum32 = Float32 where fromFloat32 (it + it) >= 0.0
type F64 = Float64
`

func TestGeneratedFiniteFloatModelsAndRuntimeParity(t *testing.T){
    compiler,vm:=javaTools(t);program,err:=language.Compile(fixedFloatContract);if err!=nil{t.Fatal(err)}
    files,err:=GenerateModels(program,"example.fixedfloat","Contract");if err!=nil{t.Fatal(err)}
    root:=t.TempDir();sources:=[]string{}
    for _,file:=range files{target:=filepath.Join(root,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0600);err!=nil{t.Fatal(err)};sources=append(sources,target)}
    harness:=filepath.Join(root,"FixedFloatHarness.java");if err:=os.WriteFile(harness,[]byte(fixedFloatHarnessJava),0600);err!=nil{t.Fatal(err)};sources=append(sources,harness)
    classes:=filepath.Join(root,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-d",classes},sources...)
    if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("javac: %v\n%s",err,output)}
    vectors:=[]vector{};for _,tc:=range []struct{name,raw string}{{"F32","1/2"},{"F32","1/3"},{"F32","16777217"},{"Nonnegative32","-1/2"},{"Sum32","340282346638528859811704183484516925440"},{"F64","9007199254740992"},{"F64","9007199254740993"}}{
        text,_:=value.TextFromUTF8(tc.raw);_,report:=program.ReadData(tc.name,text,validation.Limits{});vectors=append(vectors,vector{fmt.Sprintf("%s\t%s",tc.name,readUnits(text)),reportLine(report)})
    }
    var input strings.Builder;for _,v:=range vectors{input.WriteString(v.input+"\n")};command:=exec.Command(vm,"-cp",classes,"example.fixedfloat.FixedFloatHarness");command.Stdin=strings.NewReader(input.String());var stderr bytes.Buffer;command.Stderr=&stderr
    output,err:=command.Output();if err!=nil{t.Fatalf("Java: %v\n%s",err,&stderr)};lines:=strings.Split(strings.TrimSuffix(string(output),"\n"),"\n")
    if len(lines)!=len(vectors){t.Fatalf("got %d reports, want %d",len(lines),len(vectors))};for i,line:=range lines{if line!=vectors[i].expected{t.Fatalf("%s\nJava %s\nGo %s",vectors[i].input,line,vectors[i].expected)}}
}

const fixedFloatHarnessJava=`
package example.fixedfloat;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
public final class FixedFloatHarness {
    static void require(boolean value){if(!value)throw new AssertionError();}
    static void rejectsArithmetic(Runnable action){try{action.run();throw new AssertionError();}catch(ArithmeticException expected){}}
    static void rejectsValidation(Runnable action){try{action.run();throw new AssertionError();}catch(ValidationException expected){}}
    static String units(String text){var out=new StringBuilder();for(int i=0;i<text.length();i+=4)out.append((char)Integer.parseInt(text.substring(i,i+4),16));return out.toString();}
    static String hex(String text){return HexFormat.of().formatHex(text.getBytes(StandardCharsets.UTF_8));}
    static String report(Validation.Outcome r){var out=new StringBuilder(r.state().name().toLowerCase(Locale.ROOT)).append('|').append(r.incomplete());for(var d:r.diagnostics())out.append('|').append(hex(d.code())).append(',').append(hex(String.join(";",d.paths()))).append(',').append(hex(d.predicate())).append(',').append(hex(d.message()));return out.toString();}
    public static void main(String[] args)throws Exception{
        require(Rational.parse("1/2").exactFloat32().show().equals("1/2"));
        require(Rational.parse("16777217").roundFloat32().show().equals("16777216"));
        require(Rational.parse("9007199254740995").roundFloat64().show().equals("9007199254740996"));
        rejectsArithmetic(()->Rational.parse("1/3").exactFloat32());
        var model=new F32(Rational.parse("1/2"));require(model.showWithoutValidation().equals("1/2")&&F32.read("1/2").value().equals(model.value()));
        rejectsValidation(()->new F32(Rational.parse("1/3")));require(ModelTypes.float32().encode(Rational.parse("1/2"),"") instanceof Data.Number);
        require(new F64(Rational.parse("9007199254740992")).value().show().equals("9007199254740992"));rejectsValidation(()->new F64(Rational.parse("9007199254740993")));
        var input=new BufferedReader(new InputStreamReader(System.in,StandardCharsets.UTF_8));String line;while((line=input.readLine())!=null){var f=line.split("\\t",-1);System.out.println(report(Contract.read(f[0],units(f[1])).outcome()));}
    }
}
`
