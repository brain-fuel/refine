package java

import (
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
    "goforge.dev/refine/schemajson"
)

func nativeStringPatternForTest(t *testing.T,source string)(nativeStringPattern,bool){t.Helper();document,err:=schemajson.Parse([]byte(source),schemajson.Limits{});if err!=nil{t.Fatal(err)};return nativeStringPatternAt(document.Root())}
func nativeStringAlphabet(pattern nativeStringPattern)string{var result strings.Builder;for _,item:=range pattern.alphabet{result.WriteByte(byte(item))};return result.String()}

func TestNativeRootStringPropertyStrategyIsExactAndBounded(t *testing.T){
    cases:=[]struct{schema,alphabet string;minimum,maximum int}{
        {`{"type":"string","pattern":"^[a-z]+$"}`,"abcdefghijklmnopqrstuvwxyz",1,24},
        {`{"type":"string","pattern":"^[q]$"}`,"q",1,1},
        {`{"type":"string","pattern":"^[q]?$"}`,"q",0,1},
        {`{"type":"string","pattern":"^[A-C0-2_-]{2,5}$"}`,"-012ABC_",2,5},
        {`{"type":"string","pattern":"^[a-ca-b]{2,}$"}`,"abc",2,24},
        {`{"type":"string","pattern":"^[x]*$","minLength":3,"maxLength":30}`,"x",3,24},
        {`{"type":"string","pattern":"^[x]{1000,2000}$"}`,"x",1000,1000},
        {`{"type":"string","pattern":"^[x]{1024}$"}`,"x",1024,1024},
    }
    for _,test:=range cases{strategy,ok:=nativeStringPatternForTest(t,test.schema);if !ok||strategy.minimum!=test.minimum||strategy.maximum!=test.maximum||nativeStringAlphabet(strategy)!=test.alphabet{t.Fatalf("unexpected native string strategy for %s: %+v %q",test.schema,strategy,nativeStringAlphabet(strategy))}}
    rejected:=[]string{
        `{"type":"string","pattern":"^[x]{1025}$"}`,
        `{"type":"string","pattern":"^[x]{999999999999999999999999999999999}$"}`,
        `{"type":"string","pattern":"^[x]{1,2,3}$"}`,
        `{"type":"string","pattern":"^[x]+$","maxLength":0}`,
        `{"type":"string","pattern":"(?=x)x"}`,
        `{"type":"string","pattern":"^\\p{Script=Greek}+$"}`,
        `{"type":"string","pattern":"^[^x]+$"}`,
        `{"type":"string","pattern":"^[z-a]+$"}`,
        `{"type":"string","pattern":"^[x]+$","anyOf":[true]}`,
        `{"$ref":"#/$defs/Text","$defs":{"Text":{"type":"string","pattern":"^[x]+$"}}}`,
        `{"type":"string","pattern":"^[x]+$","minLength":1e0}`,
    }
    for _,schema:=range rejected{if strategy,ok:=nativeStringPatternForTest(t,schema);ok{t.Fatalf("unsafe native string strategy accepted for %s: %+v",schema,strategy)}}
    program,err:=language.Compile("type Identity a = a\ntype Other a = a\ntype Alias = Identity (Other String)\ntype Wrong = Identity Int\n");if err!=nil{t.Fatal(err)};if !nativeStringSemanticTarget(program,"Alias")||nativeStringSemanticTarget(program,"Wrong"){t.Fatal("closed semantic String alias classification failed")}
}

func nativeStringPropertyProject(t *testing.T,maximum int)*native.Project{t.Helper();schema:=`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"string","pattern":"^[a-z]+$","minLength":1,"maxLength":`+fmt.Sprint(maximum)+`}`;project,err:=native.IngestProject(native.JSONSchema,[]byte(schema),native.ProjectOptions{Root:native.ResourceSelector{TypeName:"Code"},Metadata:native.WireMetadata{PublicationNamespace:"example.nativepattern"}});if err!=nil{t.Fatal(err)};return project}

func TestGeneratedNativeRootStringPropertyStrategyPreservesValidation(t *testing.T){
    project:=nativeStringPropertyProject(t,2);edited,err:=project.WithEditedSource("type Identity a = a\ntype Code = Identity String where length it >= 2 @code \"code.minimum\"\ntype Other = String\n");if err!=nil{t.Fatal(err)};program,err:=language.Compile(edited.EditableSource());if err!=nil{t.Fatal(err)}
    generated,err:=GenerateProjectPropertyTests(edited,"example.nativepattern","Contract",PropertyTestOptions{Targets:[]PropertyTarget{{Name:"Code"},{Name:"Other"}},CaseCount:8,AttemptBudget:8,Seed:887});if err!=nil{t.Fatal(err)};source:=generated[0].Source
    if !strings.Contains(source,"IntDistribution.uniform(1,2)")||!strings.Contains(source,"Generator.<Character>sampledFrom((char)97")||strings.Count(source,"asciiPrintableChars()")!=1{t.Fatal("native root strategy was not isolated from the unrelated target")}
    validator,err:=JSONNativeValidatorName(program,"Contract","ValueModule");if err!=nil{t.Fatal(err)};options:=PropertyTestOptions{Targets:[]PropertyTarget{{Name:"Code"}},CaseCount:8,AttemptBudget:8,Seed:887,JSONModule:"ValueModule",NativeJSONValidator:validator};generated,err=GenerateProjectPropertyTests(edited,"example.nativepattern","Contract",options);if err!=nil{t.Fatal(err)};source=generated[0].Source
    for _,required:=range []string{"nativeCandidate(d) && Contract.validate(\"Code\",d).state() == Validation.State.VALID","nativeCandidate(d) && targeted(Contract.validate(\"Code\",d),\"code.minimum\")","wireValid(data,model)","IntDistribution.uniform(1,2)"}{if !strings.Contains(source,required){t.Fatalf("specialized suite omitted %q",required)}}
}

func TestGeneratedNativeRootStringPropertyStrategyExecutesBoundaries(t *testing.T){
    project:=nativeStringPropertyProject(t,2);program,err:=language.Compile(project.EditableSource());if err!=nil{t.Fatal(err)};validator,err:=JSONNativeValidatorName(program,"Contract","ValueModule");if err!=nil{t.Fatal(err)};options:=PropertyTestOptions{Targets:[]PropertyTarget{{Name:"Code"}},CaseCount:8,AttemptBudget:8,Seed:887,JSONModule:"ValueModule",NativeJSONValidator:validator}
    files,err:=GenerateProjectJSONSerde(project,"Contract","ValueModule");if err!=nil{t.Fatal(err)};properties,err:=GenerateProjectPropertyTests(project,"example.nativepattern","Contract",options);if err!=nil{t.Fatal(err)};files=append(files,properties...)
    compiler,vm:=javaTools(t);classpath:=jetCheckClasspath(t)+string(os.PathListSeparator)+networkntClasspath(t)+string(os.PathListSeparator)+chicoryClasspath(t);root:=t.TempDir();sources:=[]string{}
    for _,file:=range files{target:=filepath.Join(root,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)}
    classes:=filepath.Join(root,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("native root string property javac: %v\n%s",err,output)};writeNativeRegexResources(t,classes,project)
    ctx,cancel:=context.WithTimeout(context.Background(),60*time.Second);defer cancel();if output,err:=exec.CommandContext(ctx,vm,"-cp",classes+string(os.PathListSeparator)+classpath,"example.nativepattern.ContractGeneratedProperties").CombinedOutput();err!=nil{if ctx.Err()!=nil{t.Fatalf("native root string properties exceeded the process deadline: %v",ctx.Err())};t.Fatalf("native root string properties: %v\n%s",err,output)}
}
