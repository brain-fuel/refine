package java

import (
    "os"
    "os/exec"
    "path/filepath"
    "strings"
    "testing"

    "goforge.dev/refine/language"
    "goforge.dev/refine/native"
)

const authoredOpenAPIJavaSource=`type Positive = Int where it > 0
type Tagged = Int where it /= 99 @code "tagged"
type Body = {amount :: Positive, values :: Map String Positive, items :: [Positive], left :: Tagged, right :: Tagged}
type Request = {parameters :: {id :: Positive}, headers :: {}, body :: Body}
type Response = {headers :: {}, body :: Positive}
type Context = {request :: Request, response :: Response} where it.response.body > it.request.body.amount

openapi "3.2.1" {
  title "Authored Java"
  version "1.0.0"
  operation create "POST" "/items/{id}" {
    request Request {
      parameter path "id" at parameters.id required
      body "application/json" at body required
    }
    response "201" Response "Created" {
      body "application/json" at body required
      context Context
    }
  }
}
`

func authoredRule(t *testing.T,program *language.Program,name string)language.Where{t.Helper();for _,decl:=range program.Syntax().Types{if decl.Name!=name||decl.Body==nil{continue};match decl.Body.Form{case language.RefinedType(_,rules):if len(rules)==1{return rules[0]};case _:}};t.Fatalf("%s rule is absent",name);return language.Where{}}

// This is the end-to-end standalone authoring seam: checked source creates the
// native project, which then creates both the real Java operation facade and
// every mandatory JetCheck operation property.
func TestGeneratedStandaloneOpenAPIAuthoringFacadeAndProperties(t *testing.T){
    program,err:=language.Compile(authoredOpenAPIJavaSource);if err!=nil{t.Fatal(err)};project,err:=native.AuthorOpenAPIProject(program,native.AuthorOpenAPIOptions{Metadata:native.WireMetadata{PublicationNamespace:"example.openapiauthored"}});if err!=nil{t.Fatal(err)};if !strings.Contains(project.Resources()[0].Source,`"exclusiveMinimum": 0`){t.Fatal("standalone native lowering omitted the exact Positive lower bound")}
    facade,err:=GenerateProjectOpenAPIContext(project,"Contract","OperationFacade");if err!=nil{t.Fatal(err)};properties,err:=GenerateProjectOpenAPIPropertyTests(project,"example.openapiauthored","Contract","OperationFacade",PropertyTestOptions{CaseCount:3,AttemptBudget:2048,Seed:811});if err!=nil{t.Fatal(err)};if len(properties)!=1{t.Fatalf("unexpected property output: %+v",properties)};for _,fragment:=range []string{"request create","response create 201","context create 201","invalid request create tagged /body/left","invalid request create tagged /body/right","/parameters/id","/body/amount","/body/values/~2","/body/items/~2","invalid response create 201 refine.","invalid context create 201 refine."}{if !strings.Contains(properties[0].Source,fragment){t.Fatalf("mandatory authored operation property missing %q",fragment)}}
    rule:=authoredRule(t,program,"Tagged");legacy:=PropertyTestOptions{Replays:[]PropertyReplay{{Target:OpenAPIRequestReplayTarget("create"),Kind:ReplayInvalid,DiagnosticCode:"tagged",SerializedData:"legacy"}}};if partial,legacyErr:=GenerateProjectOpenAPIPropertyTests(project,"example.openapiauthored","Contract","OperationFacade",legacy);legacyErr==nil||partial!=nil{t.Fatalf("ambiguous legacy replay returned partial output: %v %+v",legacyErr,partial)};occurrence:=OpenAPIRequestOccurrenceReplayTarget("create",[]string{"/body/left"},rule.At.Start.Offset);selected:=PropertyTestOptions{Replays:[]PropertyReplay{{Target:occurrence,Kind:ReplayInvalid,DiagnosticCode:"tagged",SerializedData:"occurrence"}}};if selectedFiles,selectedErr:=GenerateProjectOpenAPIPropertyTests(project,"example.openapiauthored","Contract","OperationFacade",selected);selectedErr!=nil||len(selectedFiles)!=1{t.Fatalf("deterministic repeated-clause occurrence replay was rejected: %v %+v",selectedErr,selectedFiles)}
    compiler,vm:=javaTools(t);classpath:=strings.Join([]string{jetCheckClasspath(t),networkntClasspath(t)},string(os.PathListSeparator));root:=t.TempDir();sources:=[]string{};for _,file:=range append(facade,properties...){target:=filepath.Join(root,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)};classes:=filepath.Join(root,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("standalone OpenAPI javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-Xss256k","-cp",classes+string(os.PathListSeparator)+classpath,"example.openapiauthored.ContractGeneratedProperties").CombinedOutput();err!=nil{t.Fatalf("standalone OpenAPI properties runtime: %v\n%s",err,output)}
}
