package project

import (
    "fmt"
    "os"
    "os/exec"
    "path/filepath"
    "strconv"
    "strings"
    "testing"

    "goforge.dev/refine/java"
    "goforge.dev/refine/language"
    "goforge.dev/refine/native"
    refineopenapi "goforge.dev/refine/openapi"
)

const projectOperationSource=`
type Root = { value :: Int }
type Params = { id :: Int }
type Headers = {}
type Body = {}
type Request = { parameters :: Params, headers :: Headers, body :: Body }
type ResponseBody = { id :: Int }
type Response = { headers :: Headers, body :: ResponseBody }
type Context = { request :: Request, response :: Response }
  where it.request.parameters.id == it.response.body.id @code "same.id" @message "Response id must match request id"
`

func projectOperationWire()native.WireMetadata{
    response:=refineopenapi.ResponseBinding{Status:"200",ResponseType:"Response",ContextType:"Context"};operation:=refineopenapi.OperationBinding{OperationID:"get",Method:"GET",Path:"/items/{id}",RequestType:"Request",Responses:[]refineopenapi.ResponseBinding{response}};return native.WireMetadata{OpenAPI:&refineopenapi.Schema{Version:refineopenapi.SchemaVersion,Operations:[]refineopenapi.OperationBinding{operation}}}
}

func projectOperationNative(t *testing.T)*native.Project{
    t.Helper();imported,err:=native.IngestProject(native.JSONSchema,[]byte(`{"type":"object","required":["value"],"properties":{"value":{"type":"integer"}}}`),native.ProjectOptions{Root:native.ResourceSelector{TypeName:"Root"}});if err!=nil{t.Fatal(err)};imported,err=imported.WithEditedSource(projectOperationSource);if err!=nil{t.Fatal(err)};imported,err=imported.WithMetadata(projectOperationWire());if err!=nil{t.Fatal(err)};return imported
}

func TestGenerateIncludesCheckedOpenAPIContextFacade(t *testing.T){
    program,err:=language.Compile(projectOperationSource);if err!=nil{t.Fatal(err)};contract:=Contract{Family:"items",Program:program,RootType:"Root",Formats:[]native.Format{native.JSONSchema},Wire:projectOperationWire()};bundle,err:=Generate(GenerateInput{Contracts:[]Contract{contract}});if err!=nil{t.Fatal(err)}
    facade,contracts,english,jsonEnglish:=false,0,false,false;for _,file:=range bundle.Files{if strings.HasSuffix(file.Path,"/RefineOpenAPIOperations.java"){facade=true;source:=string(file.Content);for _,part:=range []string{"get","GET","/items/{id}","Context"}{if !strings.Contains(source,part){t.Fatalf("facade lost %q",part)}}};if strings.HasSuffix(file.Path,"/Contract.java"){contracts++};if strings.HasSuffix(file.Path,"/explanation.md"){english=strings.Contains(string(file.Content),"Response id must match request id")};if strings.HasSuffix(file.Path,"/explanation.json"){jsonEnglish=strings.Contains(string(file.Content),"Response id must match request id")}}
    if !facade||contracts!=1||!english||!jsonEnglish{t.Fatalf("facade=%t shared contracts=%d English=%t JSON English=%t",facade,contracts,english,jsonEnglish)}
    models,err:=java.GenerateModels(program,"example.projectcontext","Contract");if err!=nil{t.Fatal(err)};sources,err:=mergeOpenAPIContext(contract,"example.projectcontext","Contract",models);if err!=nil{t.Fatal(err)};compileProjectContext(t,sources)
    nativeBundle,err:=Generate(GenerateInput{Contracts:[]Contract{{Family:"bundled",NativeProject:projectOperationNative(t),Formats:[]native.Format{native.JSONSchema}}}});if err!=nil{t.Fatal(err)};facade=false;for _,file:=range nativeBundle.Files{if strings.HasSuffix(file.Path,"/RefineOpenAPIOperations.java"){facade=true}};if !facade{t.Fatal("versioned native operation metadata did not emit Java facade")}
}

func TestGenerateRejectsInvalidOrExternalNativeOpenAPIMetadata(t *testing.T){
    program,err:=language.Compile(projectOperationSource);if err!=nil{t.Fatal(err)};wire:=projectOperationWire();wire.OpenAPI.Operations[0].Responses[0].ResponseType="Request";input:=GenerateInput{Contracts:[]Contract{{Family:"bad",Program:program,RootType:"Root",Formats:[]native.Format{native.JSONSchema},Wire:wire}}};if bundle,err:=Generate(input);err==nil||len(bundle.Files)!=0{t.Fatal("invalid operation metadata emitted partial project")}
    imported,err:=native.IngestProject(native.JSONSchema,[]byte(`{"type":"object"}`),native.ProjectOptions{Root:native.ResourceSelector{TypeName:"Root"}});if err!=nil{t.Fatal(err)};input=GenerateInput{Contracts:[]Contract{{Family:"native",NativeProject:imported,Formats:[]native.Format{native.JSONSchema},Wire:projectOperationWire()}}};if bundle,err:=Generate(input);err==nil||len(bundle.Files)!=0{t.Fatal("external native operation metadata override accepted")}
}

func TestGenerateIncludesComposedNativeOpenAPIOperationFacade(t *testing.T){
    document:=`{"openapi":"3.1.0","info":{"title":"Items","version":"1"},"paths":{"/items/{id}":{"get":{"operationId":"get","parameters":[{"in":"path","name":"id","required":true,"schema":{"type":"integer","minimum":1}}],"responses":{"200":{"description":"ok","content":{"application/json":{"schema":{"type":"object","required":["id"],"properties":{"id":{"type":"integer"}},"additionalProperties":false}}}}}}}},"components":{"schemas":{"Root":{"type":"object","required":["value"],"properties":{"value":{"type":"integer"}},"additionalProperties":false}}}}`
    imported,err:=native.IngestProjectResources(native.OpenAPI,[]native.Resource{{URI:"https://example.test/items.json",Source:document}},native.ProjectOptions{Root:native.ResourceSelector{Resource:"https://example.test/items.json",Pointer:"/components/schemas/Root",TypeName:"Root"}});if err!=nil{t.Fatal(err)};imported,err=imported.WithEditedSource(projectOperationSource);if err!=nil{t.Fatal(err)};wire:=projectOperationWire();wire.OpenAPI.Native=&refineopenapi.NativeBindings{Version:refineopenapi.NativeBindingsVersion,Operations:[]refineopenapi.NativeOperationBinding{{OperationID:"get",Responses:[]refineopenapi.NativeResponseBinding{{Status:"200",Body:&refineopenapi.NativeMediaBinding{MediaType:"application/json"}}}}}};imported,err=imported.WithMetadata(wire);if err!=nil{t.Fatal(err)}
    bundle,err:=Generate(GenerateInput{Contracts:[]Contract{{Family:"nativeitems",NativeProject:imported,Formats:[]native.Format{native.OpenAPI}}}});if err!=nil{t.Fatal(err)};facade,sidecar,requestCodec,responseCodec:=false,false,false,false;for _,file:=range bundle.Files{name:=filepath.Base(file.Path);source:=string(file.Content);if name=="RefineOpenAPIOperations.java"{facade=strings.Contains(source,"ValidatedRequest")&&strings.Contains(source,"validateNative")};if strings.Contains(name,"NativeParts"){sidecar=strings.Contains(source,"urn:refine:openapi-parts:")};if strings.Contains(name,"JSON0"){requestCodec=strings.Contains(source,"readDataWithoutRefinements")};if strings.Contains(name,"JSON1"){responseCodec=strings.Contains(source,"readDataWithoutRefinements")}}
    if !facade||!sidecar||!requestCodec||!responseCodec{t.Fatalf("composed facade=%t sidecar=%t request codec=%t response codec=%t",facade,sidecar,requestCodec,responseCodec)}
}

func compileProjectContext(t *testing.T,files []java.File){
    t.Helper();compiler,vm,err:=projectJavaTools();if err!=nil{if os.Getenv("REFINE_REQUIRE_JAVA")=="1"{t.Fatal(err)};t.Skipf("Java 25 unavailable: %v",err)}
    dir:=t.TempDir();paths:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};paths=append(paths,target)};harness:=filepath.Join(dir,"ProjectContext.java");if err:=os.WriteFile(harness,[]byte(projectContextHarness),0644);err!=nil{t.Fatal(err)};paths=append(paths,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-d",classes},paths...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("project context javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-Xss256k","-cp",classes,"ProjectContext").CombinedOutput();err!=nil{t.Fatalf("project context Java: %v\n%s",err,output)}
}

func projectJavaTools()(string,string,error){
    javaHome:=os.Getenv("REFINE_JAVA_HOME");if javaHome==""{javaHome=os.Getenv("JAVA_HOME")};compiler:="";vm:=""
    if javaHome!=""{compiler=filepath.Join(javaHome,"bin","javac");vm=filepath.Join(javaHome,"bin","java")}else{var err error;compiler,err=exec.LookPath("javac");if err!=nil{return "","",fmt.Errorf("find javac on PATH: %w",err)};vm,err=exec.LookPath("java");if err!=nil{return "","",fmt.Errorf("find java on PATH: %w",err)}}
    if _,err:=os.Stat(compiler);err!=nil{return "","",fmt.Errorf("Java compiler %s: %w",compiler,err)};if _,err:=os.Stat(vm);err!=nil{return "","",fmt.Errorf("Java VM %s: %w",vm,err)}
    output,err:=exec.Command(compiler,"-version").CombinedOutput();if err!=nil{return "","",fmt.Errorf("inspect Java compiler %s: %w (%s)",compiler,err,output)};fields:=strings.Fields(string(output));major:=0;if len(fields)>1{major,_=strconv.Atoi(strings.Split(fields[1],".")[0])};if major<25{return "","",fmt.Errorf("Java 25 compiler required, found %q",strings.TrimSpace(string(output)))};return compiler,vm,nil
}

const projectContextHarness=`
import example.projectcontext.*;
import java.util.List;
public final class ProjectContext {
 static Data record(Data.Field... fields){return new Data.Struct(List.of(fields));}
 static Data number(long n){return new Data.Number(Rational.of(n));}
 static RefineOpenAPIOperations.Request request(long id){return new RefineOpenAPIOperations.Request(record(new Data.Field("id",number(id))),record(),record());}
 static RefineOpenAPIOperations.Response response(long id){return new RefineOpenAPIOperations.Response(record(),record(new Data.Field("id",number(id))));}
 public static void main(String[] args){var request=request(4);if(RefineOpenAPIOperations.validateResponse("get","200",response(4),request).state()!=Validation.State.VALID)throw new AssertionError();if(RefineOpenAPIOperations.validateResponse("get","200",response(5),request).state()!=Validation.State.INVALID)throw new AssertionError();}
}
`
