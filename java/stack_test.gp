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

// Logical resource policy must not depend on the host JVM's stack size.
// Compare complete reports, including budget boundaries and deep mismatches.
func TestGeneratedJavaStackSafety(t *testing.T) {
    compiler,vm:=javaTools(t)
    chain:=func(depth int,last string)value.Data{
        result:=testRecord(value.DataField{Name:"value",Value:testNumber(last)},value.DataField{Name:"next",Value:testVariant("Nothing")})
        for i:=0;i<depth;i++{result=testRecord(value.DataField{Name:"value",Value:testNumber("0")},value.DataField{Name:"next",Value:testVariant("Just",result)})}
        return result
    }
    for _,kind:=range []string{"equality","expression"}{t.Run(kind,func(t *testing.T){
        source:="type Chain = { value :: Int, next :: Maybe Chain }\ntype Check = { left :: Chain, right :: Chain } where it.left == it.right"
        if kind=="expression"{source="type Check = Int where "+strings.Repeat("it + ",159)+"it == it * 160"}
        program,err:=language.Compile(source);if err!=nil{t.Fatal(err)}
        files,err:=GenerateValidator(program,"example.stack","Contract");if err!=nil{t.Fatal(err)}
        root:=t.TempDir();sources:=[]string{}
        for _,file:=range files{target:=filepath.Join(root,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)}
        harness:=filepath.Join(root,"StackConformance.java");if err:=os.WriteFile(harness,[]byte(stackHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness)
        classes:=filepath.Join(root,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-d",classes},sources...)
        if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("javac: %v\n%s",err,output)}
        vectors:=[]vector{}
        add:=func(depth int,last string,total,clause uint64){
            data:=testNumber(last)
            if kind=="equality"{data=testRecord(value.DataField{Name:"left",Value:chain(depth,"0")},value.DataField{Name:"right",Value:chain(depth,last)})}
            for _,bypass:=range []bool{false,true}{
                limits:=validation.Limits{Total:total,Clause:clause}
                report:=program.ValidateData("Check",data,limits)
                if bypass{report=program.ValidateDataWithoutRefinements("Check",data,limits)}
                if total==0&&clause==0&&(kind=="expression"||depth<=120){
                    expected:="valid";if kind=="equality"&&last!="0"&&!bypass{expected="invalid"}
                    if validation.StateName(report.State())!=expected||report.Incomplete(){t.Fatalf("in-policy case unexpectedly limited: %s depth %d: %s",kind,depth,reportLine(report))}
                }
                vectors=append(vectors,vector{fmt.Sprintf("%s\t%d\t%s\t%d\t%d\t%v",kind,depth,last,total,clause,bypass),reportLine(report)})
            }
        }
        if kind=="equality"{
            for _,depth:=range []int{0,1,40,80,120,160,169,170,180,260,512}{for _,last:=range []string{"0","1"}{
                for _,limit:=range []uint64{0,1,40,500,2000,10000}{add(depth,last,limit,0);add(depth,last,0,limit)}
            }}
        }else{
            for _,number:=range []string{"0","1","-123456789"}{for limit:=uint64(1);limit<=1500;limit++{add(0,number,limit,0);add(0,number,0,limit)};add(0,number,0,0)}
        }
        var input strings.Builder;for _,v:=range vectors{input.WriteString(v.input);input.WriteByte('\n')}
        ctx,cancel:=context.WithTimeout(context.Background(),time.Minute);defer cancel()
        command:=exec.CommandContext(ctx,vm,"-Xss256k","-cp",classes,"StackConformance");command.Stdin=strings.NewReader(input.String())
        var stderr bytes.Buffer;command.Stderr=&stderr
        output,err:=command.Output();if err!=nil{t.Fatalf("Java: %v\n%s",err,stderr.String())}
        lines:=strings.Split(strings.TrimSuffix(string(output),"\n"),"\n");if len(lines)!=len(vectors){t.Fatalf("expected %d results, got %d",len(vectors),len(lines))}
        for i,v:=range vectors{if lines[i]!=v.expected{t.Fatalf("case %s\nJava %s\nGo   %s",v.input,lines[i],v.expected)}}
        t.Logf("%d full-report comparisons with a 256 KiB JVM stack passed",len(vectors))
    })}
}

const stackHarnessJava = `
import example.stack.*;
import java.util.List;
import java.util.HexFormat;
import java.nio.charset.StandardCharsets;
import java.io.BufferedReader;
import java.io.InputStreamReader;
public final class StackConformance {
    static Data number(String raw) { return new Data.Number(Rational.parse(raw)); }
    static Data chain(int depth, String last) {
        Data result = new Data.Struct(List.of(new Data.Field("value", number(last)), new Data.Field("next", new Data.Variant("Nothing", List.of()))));
        for (int i = 0; i < depth; i++) result = new Data.Struct(List.of(new Data.Field("value", number("0")), new Data.Field("next", new Data.Variant("Just", List.of(result)))));
        return result;
    }
    static String hex(String text) { return HexFormat.of().formatHex(text.getBytes(StandardCharsets.UTF_8)); }
    public static void main(String[] args) throws Exception {
        var input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        String line;
        while ((line = input.readLine()) != null) {
            String[] f = line.split("\t", -1);
            int depth = Integer.parseInt(f[1]);
            Data data = f[0].equals("expression") ? number(f[2]) : new Data.Struct(List.of(
                new Data.Field("left", chain(depth, "0")), new Data.Field("right", chain(depth, f[2]))));
            var limits = new Budget.Limits(Long.parseLong(f[3]), Long.parseLong(f[4]));
            var outcome = Boolean.parseBoolean(f[5]) ? Contract.validateStructure("Check", data, limits) : Contract.validate("Check", data, limits);
            var report = new StringBuilder(outcome.state().name().toLowerCase(java.util.Locale.ROOT)).append('|').append(outcome.incomplete());
            for (var d : outcome.diagnostics()) report.append('|').append(hex(d.code())).append(',').append(hex(String.join(";", d.paths()))).append(',').append(hex(d.predicate())).append(',').append(hex(d.message()));
            System.out.println(report);
        }
    }
}
`
