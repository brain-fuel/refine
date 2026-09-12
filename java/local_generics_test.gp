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

func TestGeneratedLocallyAnnotatedGenerics(t *testing.T){
    source:=`copy :: a -> a
copy x = let y :: a = x in y
roundTrip :: (Show a, Read a) => a -> Result String a
roundTrip x = let restored :: Result String a = read (show x) in restored
checked :: a -> a
checked x = let y :: (a where True) = x in y
twice :: Num a => a -> a
twice x = x + x
less :: Ord a => a -> a -> Bool
less x y = x < y
remainder :: Integral a => a -> a -> a
remainder x y = x % y
sumDown :: Int -> Int
sumDown 0 = 0
sumDown n = 1 + sumDown (n - 1)
type Box a = { value :: a } where (let same :: a = it.value in length (show same) > 0)
type IntegerBox = Box Int
type BooleanBox = Box Bool
type Number = Int where copy it == it where checked it == it where twice it == it + it where less it (it + 1) where remainder (it - it + 5) 2 == 1 where sumDown 700 == 700 where case roundTrip it of { Ok n -> n == it; Err _ -> False }
type Message = Int where False @message (let result :: Int = copy it in show result)
`
    program,err:=language.Compile(source);if err!=nil{t.Fatal(err)};compiler,vm:=javaTools(t)
    files,err:=GenerateModels(program,"example.locals","Contract");if err!=nil{t.Fatal(err)};root:=t.TempDir();sources:=[]string{}
    for _,file:=range files{target:=filepath.Join(root,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0600);err!=nil{t.Fatal(err)};sources=append(sources,target)}
    harness:=filepath.Join(root,"Conversions.java");if err:=os.WriteFile(harness,[]byte(strings.ReplaceAll(conversionHarnessJava,"example.conversions","example.locals")),0600);err!=nil{t.Fatal(err)};sources=append(sources,harness)
    classes:=filepath.Join(root,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("javac %v\n%s",err,output)}
    vectors:=[]vector{}
    for _,sample:=range []struct{name string;raw string}{{"IntegerBox","{value = 1}"},{"BooleanBox","{value = True}"},{"Number","4"},{"Number","-7"},{"Message","9007199254740993"}}{
        text,err:=value.TextFromUTF8(sample.raw);if err!=nil{t.Fatal(err)}
        for budget:=uint64(0);budget<350;budget++{for _,limits:=range []validation.Limits{{Total:budget},{Clause:budget}}{_,report:=program.ReadData(sample.name,text,limits);vectors=append(vectors,vector{fmt.Sprintf("%s\t%s\t%d\t%d",sample.name,readUnits(text),limits.Total,limits.Clause),reportLine(report)})}}
    }
    var input strings.Builder;for _,v:=range vectors{input.WriteString(v.input+"\n")};command:=exec.Command(vm,"-Xss256k","-cp",classes,"Conversions");command.Stdin=strings.NewReader(input.String());var stderr bytes.Buffer;command.Stderr=&stderr;output,err:=command.Output();if err!=nil{t.Fatalf("Java %v\n%s",err,&stderr)}
    lines:=strings.Split(strings.TrimSuffix(string(output),"\n"),"\n");if len(lines)!=len(vectors){t.Fatalf("got%d want%d",len(lines),len(vectors))};for i,line:=range lines{if line!=vectors[i].expected{t.Fatalf("%s\nJava %s\nGo %s",vectors[i].input,line,vectors[i].expected)}}
    t.Logf("%d complete generic-local annotation reports",len(vectors))
}
