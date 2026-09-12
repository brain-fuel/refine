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

const readContract = `
type Integer = Int
type RealValue = Real
type TextValue = String
type Flag = Bool
type Positive = Int where it > 0 @message ("Expected positive, got " ++ show it)
type Unknown = Int where 1 / 0 > 0.0
type Both = Int where False where 1 / 0 > 0.0
type Small = Int8
type Optional = Maybe (Nullable Real)
type Record = { number :: Real, text :: Maybe String }
data Tree a = Leaf a | Branch (Tree a) (Tree a)
type IntegerTree = Tree Int
type Complex = { rational :: Real, text :: String, numbers :: [Int], optional :: Maybe (Nullable Real), tree :: Tree Int }
type Budgeted = Int where True @steps 1000000
type BadMessage = Int where False @message (if 1 / 0 > 0.0 then "a" else "b")
id :: a -> a
id x = x
parse :: String -> Result String a
parse text = read text
parseInt :: String -> Result String Int
parseInt text = read text
parsePositive :: String -> Result String Positive
parsePositive text = read text
parseUnknown :: String -> Result String Unknown
parseUnknown text = read text
parseBoth :: String -> Result String Both
parseBoth text = read text
parseBudgeted :: String -> Result String Budgeted
parseBudgeted text = read text
parseBadMessage :: String -> Result String BadMessage
parseBadMessage text = read text
parseMany :: [String] -> [Result String Int]
parseMany texts = map (id read) texts
validRead :: a -> Result String a -> Bool
validRead _ (Ok _) = True
validRead _ (Err _) = False
type Box a = { value :: a } where validRead it.value (read "1")
type IntegerBox = Box Int
type BooleanBox = Box Bool
accept :: Recursive -> Bool
accept _ = True
type Recursive = Int where (case read (show it) of { Ok x -> accept x; Err _ -> False })
recursive :: String -> Bool
recursive text = case read text of { Ok x -> accept x; Err _ -> False }
yes :: String -> Bool
yes _ = True
type ReadInt = String where length (show (parseInt it)) > 0 where False @message (show (parseInt it))
type ReadPositive = String where length (show (parsePositive it)) > 0 where False @message (show (parsePositive it))
type ReadUnknown = String where length (show (parseUnknown it)) > 0 where False @message (show (parseUnknown it))
type ReadBoth = String where length (show (parseBoth it)) > 0 where False @message (show (parseBoth it))
type ReadBudgeted = String where length (show (parseBudgeted it)) > 0 where False @message (show (parseBudgeted it))
type ReadBadMessage = String where length (show (parseBadMessage it)) > 0 where False @message (show (parseBadMessage it))
type Higher = String where length (show (parseMany [it, "1"])) > 0 where False @message (show (parseMany [it, "1"]))
type Local = String where (let f :: String -> Result String Int = read in f it == parseInt it)
type Generic = String where (case parse it of { Ok n -> n == 1; Err _ -> False })
type Anonymous = String where (let parsed :: Result String (Int where it > 0) = read it in (case parsed of { Ok _ -> True; Err _ -> False }))
type Recovery = String where satisfiesOneOf [recursive, yes] it
`

func readUnits(text value.Text)string{var b strings.Builder;for _,u:=range text.Units(){fmt.Fprintf(&b,"%04x",u)};return b.String()}

func TestGeneratedTypedRead(t *testing.T){
    compiler,vm:=javaTools(t);dependencies:=jetCheckClasspath(t)
    program,err:=language.Compile(readContract);if err!=nil{t.Fatal(err)}
    files,err:=GenerateValidator(program,"example.read","Contract");if err!=nil{t.Fatal(err)}
    root:=t.TempDir();sources:=[]string{}
    for _,file:=range files{target:=filepath.Join(root,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)}
    harness:=filepath.Join(root,"ReadConformance.java");if err:=os.WriteFile(harness,[]byte(readHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness)
    classes:=filepath.Join(root,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",dependencies,"-d",classes},sources...)
    if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("javac: %v\n%s",err,output)}
    vectors:=[]vector{}
    add:=func(mode,name string,text value.Text,total,clause uint64){
        limits:=validation.Limits{Total:total,Clause:clause};var report validation.Report;canonical:=""
        if mode=="r"{data,result:=program.ReadData(name,text,limits);report=result;if validation.StateName(report.State())=="valid"{shown,err:=language.ShowDataWithoutValidation(data,validation.Limits{});if err!=nil{t.Fatal(err)};s,err:=shown.UTF8();if err!=nil{t.Fatal(err)};canonical=fmt.Sprintf("|%x",s)}}else{report=program.ValidateData(name,value.OfText(text),limits)}
        vectors=append(vectors,vector{fmt.Sprintf("%s\t%s\t%s\t%d\t%d",mode,name,readUnits(text),total,clause),reportLine(report)+canonical})
    }
    text:=func(raw string)value.Text{v,err:=value.TextFromUTF8(raw);if err!=nil{t.Fatal(err)};return v}
    corpus:=[]string{"", "1", "-1", "0", "1/3", "-2/6", "9007199254740993", "2e-3", "127", "128", "True", "False", `"\ud800\ud83d\ude00"`, `"x"`, "[1,2,]", "{number=1/3}", "{text=Just \"x\",number=2}", "{number=2,extra=False}", "{value=1}", "{value=True}", "{𐐀=1,ﬀ=2}", "Just (NonNull (-2/6))", "Nothing", "Just Null", "Branch (Leaf 1) (Leaf (-2))", "Leaf -2", "explode", "explode 1", "read \"1\"", "1+2", "1/0", "1/-2", "1/2/3", "1.0/2", "-True", "-(1+2)", "if True then 1 else explode", "let x = 1 in x", "let x :: (Int where True @steps 1 @message \"ok\") = 1 in x", "case Just 1 of { Nothing -> 0; Just x -> x }", "case [1] of { [] -> 0; x : _ -> x; }", "case 1 of {}", "{a=1,a=2}", "{a=1}.a", "(1) 2", "00", "1e+", "\"bad\\q\"", "[", "package x", "1\n2", "--comment\n 1", "{-a {-b-} c-} 1", "{-\n-}\n(1)", "1e999999999999999999999", "(1", "{number=}", "[1;2]"}
    for _,name:=range []string{"Integer","RealValue","TextValue","Flag","Positive","Unknown","Both","Small","Optional","Record","IntegerTree","IntegerBox","BooleanBox","Recursive","missing","Tree"}{
        for _,raw:=range corpus{for _,limit:=range []uint64{0,1,8,32,128,512}{add("r",name,text(raw),limit,0);if limit!=0{add("r",name,text(raw),0,limit)}}}
    }
    for _,name:=range []string{"ReadInt","ReadPositive","ReadUnknown","ReadBoth","ReadBudgeted","ReadBadMessage","Higher","Local","Generic","Anonymous","Recovery"}{
        for _,raw:=range corpus{add("v",name,text(raw),0,0)}
        for _,raw:=range []string{"1","-1","bad","1/0","{value=1}","[1,2]"}{for limit:=uint64(1);limit<180;limit++{add("v",name,text(raw),limit,0);add("v",name,text(raw),0,limit)}}
        add("v",name,value.TextFromUnits([]uint16{0xd800}),0,0)
    }
    for _,depth:=range []int{0,80,255,256,510,511,512,513,600}{
        for _,raw:=range []string{strings.Repeat("(",depth)+"1"+strings.Repeat(")",depth),strings.Repeat("[",depth)+"1"+strings.Repeat("]",depth),strings.Repeat("1+",depth)+"1",strings.Repeat("1+",depth)+"1)","case x of { C "+strings.Repeat("_ ",depth)+"-> 1 }"}{
            add("r","Integer",text(raw),0,0);add("v","ReadInt",text(raw),0,0)
        }
    }
    syntax:=readerSyntaxCorpus(t)
    for _,source:=range syntax{vectors=append(vectors,vector{fmt.Sprintf("p\tInteger\t%s\t0\t0",readUnits(text(source))),parserShape(source)})}
    for _,resource:=range []struct{mode string;source string}{{"pbytes",strings.Repeat(" ",16*1024*1024+1)},{"punicode","--"+strings.Repeat("😀",4*1024*1024)},{"ptokens",strings.Repeat("1 ",1000001)}}{
        expected:=parserShape(resource.source);if expected!="parse:evaluation.budget"{t.Fatalf("Go parser resource fixture: %s: %s",resource.mode,expected)}
        vectors=append(vectors,vector{resource.mode+"\tInteger\t\t0\t0",expected})
    }
    var input strings.Builder;for _,v:=range vectors{input.WriteString(v.input);input.WriteByte('\n')}
    ctx,cancel:=context.WithTimeout(context.Background(),3*time.Minute);defer cancel()
    command:=exec.CommandContext(ctx,vm,"-Xss256k","-cp",classes+string(os.PathListSeparator)+dependencies,"ReadConformance");command.Stdin=strings.NewReader(input.String());var stderr bytes.Buffer;command.Stderr=&stderr
    output,err:=command.Output();if err!=nil{t.Fatalf("Java read: %v\n%s",err,stderr.String())}
    lines:=strings.Split(strings.TrimSuffix(string(output),"\n"),"\n");if len(lines)!=len(vectors){t.Fatalf("expected %d outputs, got %d",len(vectors),len(lines))}
    for i,v:=range vectors{if lines[i]!=v.expected{t.Fatalf("case %s\nJava %s\nGo   %s",v.input,lines[i],v.expected)}}
    t.Logf("%d read/report comparisons, %d parser differential/resource cases and 8000 jetCheck cases passed",len(vectors)-len(syntax)-3,len(syntax)+3)
}

const readHarnessJava = `
import example.read.*;
import java.util.List;
import java.util.HexFormat;
import java.nio.charset.StandardCharsets;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import org.jetbrains.jetCheck.Generator;
import org.jetbrains.jetCheck.PropertyChecker;
public final class ReadConformance {
` + readerParserHarnessJava + `
    static String hex(String text) { return HexFormat.of().formatHex(text.getBytes(StandardCharsets.UTF_8)); }
    static String units(String encoded) { char[] result = new char[encoded.length()/4]; for (int i = 0; i < result.length; i++) result[i] = (char)Integer.parseInt(encoded.substring(i*4,i*4+4),16); return new String(result); }
    public static void main(String[] args) throws Exception {
        var input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8)); String line;
        while ((line = input.readLine()) != null) {
            String[] f = line.split("\t", -1); String text = units(f[2]);
            if (f[0].equals("p")) { System.out.println(parseShape(text)); continue; }
            if (f[0].startsWith("p")) { text = switch (f[0]) { case "pbytes" -> " ".repeat(16*1024*1024+1); case "punicode" -> "--" + "😀".repeat(4*1024*1024); case "ptokens" -> "1 ".repeat(1000001); default -> throw new AssertionError(); }; System.out.println(parseShape(text)); continue; }
            var limits = new Budget.Limits(Long.parseLong(f[3]), Long.parseLong(f[4]));
            Validation.Outcome outcome; String canonical = "";
            if (f[0].equals("r")) {
                var read = Contract.read(f[1], text, limits); outcome = read.outcome();
                if (outcome.state() == Validation.State.VALID) canonical = "|" + hex(Contract.showWithoutValidation(read.orThrow()));
                else { if (read.data() != null) throw new AssertionError("failed read leaked a candidate"); try { read.orThrow(); throw new AssertionError("failed read accepted"); } catch (ValidationException expected) {} }
            } else outcome = Contract.validate(f[1], new Data.Text(text), limits);
            var report = new StringBuilder(outcome.state().name().toLowerCase(java.util.Locale.ROOT)).append('|').append(outcome.incomplete());
            for (var d : outcome.diagnostics()) report.append('|').append(hex(d.code())).append(',').append(hex(String.join(";", d.paths()))).append(',').append(hex(d.predicate())).append(',').append(hex(d.message()));
            System.out.println(report.append(canonical));
        }
        PropertyChecker.customized().withIterationCount(2000).forAll(Generator.stringsOf(Generator.charsInRange((char)0, (char)65535)), text -> {
            var data = new Data.Text(text); String shown = Contract.showWithoutValidation(data);
            Data read = Contract.read("TextValue", shown).orThrow(); if (!read.equals(data)) throw new AssertionError("UTF-16 round trip"); return true;
        });
        PropertyChecker.customized().withIterationCount(2000).forAll(Generator.integers(), n -> {
            var rational = Rational.parse(n + "/3"); var data = new Data.Number(rational);
            if (!Contract.read("RealValue", Contract.showWithoutValidation(data)).orThrow().equals(data)) throw new AssertionError("exact rational round trip");
            var positive = Contract.read("Positive", Integer.toString(n));
            if (positive.outcome().state() != (n > 0 ? Validation.State.VALID : Validation.State.INVALID)) throw new AssertionError("target refinement not enforced");
            if (n <= 0 && positive.data() != null) throw new AssertionError("invalid candidate leaked");
            if (Contract.read("Unknown", Integer.toString(n)).outcome().state() != Validation.State.INDETERMINATE) throw new AssertionError("unknown accepted");
            return true;
        });
        record Sample(int number, String text) {}
        PropertyChecker.customized().withIterationCount(2000).forAll(Generator.zipWith(Generator.integers(), Generator.stringsOf(Generator.charsInRange((char)0, (char)65535)), Sample::new), sample -> {
            Data number = new Data.Number(Rational.of(sample.number())), fraction = new Data.Number(Rational.parse(sample.number() + "/7"));
            Data tree = new Data.Variant("Leaf", List.of(number));
            for (int i = 0; i < (sample.number() & 7); i++) tree = new Data.Variant("Branch", List.of(tree, new Data.Variant("Leaf", List.of(new Data.Number(Rational.of(i))))));
            Data optional = switch (Math.floorMod(sample.number(), 3)) { case 0 -> new Data.Variant("Nothing", List.of()); case 1 -> new Data.Variant("Just", List.of(new Data.Variant("Null", List.of()))); default -> new Data.Variant("Just", List.of(new Data.Variant("NonNull", List.of(fraction)))); };
            Data original = new Data.Struct(List.of(new Data.Field("text", new Data.Text(sample.text())), new Data.Field("rational", fraction), new Data.Field("numbers", new Data.Sequence(List.of(number))), new Data.Field("optional", optional), new Data.Field("tree", tree)));
            String canonical = Contract.showWithoutValidation(original);
            Data decoded = Contract.read("Complex", canonical).orThrow();
            if (!Contract.showWithoutValidation(decoded).equals(canonical)) throw new AssertionError("compound canonical round trip");
            return true;
        });
        PropertyChecker.customized().withIterationCount(2000).forAll(Generator.stringsOf(Generator.charsInRange((char)0, (char)65535)), text -> {
            var first = Contract.read("Integer", text); var second = Contract.read("Integer", text);
            if (!first.equals(second)) throw new AssertionError("read is not deterministic");
            if (first.outcome().state() != Validation.State.VALID && first.data() != null) throw new AssertionError("arbitrary input leaked a candidate");
            return true;
        });
    }
}
`
