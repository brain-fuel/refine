package java

import (
    "os"
    "os/exec"
    "path/filepath"
    "testing"

    "goforge.dev/refine/native"
    refineopenapi "goforge.dev/refine/openapi"
)

const nativeOpenAPISource=`
type Params = { id :: Int, q :: Maybe String }
type RequestHeaders = { xKey :: String }
type Input = Int where it > 10 @code "input.refined"
type RequestValue = { parameters :: Params, headers :: RequestHeaders, body :: Input }
type ResponseHeaders = { xRate :: Maybe Int }
type Output = Int
type ResponseValue = { headers :: ResponseHeaders, body :: Output }
type Context = { request :: RequestValue, response :: ResponseValue }
  where it.response.body > it.request.body @code "context.order"
type Root = {}
`

const nativeOpenAPIResource=`{
  "openapi":"3.1.0","info":{"title":"Operations","version":"1"},
  "paths":{"/items/{id}":{"post":{"operationId":"createItem",
    "parameters":[
      {"in":"path","name":"id","required":true,"schema":{"type":"integer","minimum":1}},
      {"in":"query","name":"q","schema":{"type":"string","pattern":"^[a-z]+$"}},
      {"in":"header","name":"X-Key","required":true,"schema":{"type":"string","pattern":"^key-[0-9]+$"}}
    ],
    "requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"https://example.test/schemas.json#/$defs/Input"}}}},
    "responses":{
      "200":{"description":"exact","headers":{"X-Rate":{"schema":{"type":"integer","minimum":0}}},"content":{"application/json":{"schema":{"$ref":"https://example.test/schemas.json#/$defs/Output"}}}},
      "2XX":{"description":"class","content":{"application/json":{"schema":{"$ref":"https://example.test/schemas.json#/$defs/Output"}}}},
      "default":{"description":"default","content":{"application/json":{"schema":{"$ref":"https://example.test/schemas.json#/$defs/Output"}}}}
    }
  }}},"components":{"schemas":{"Root":{"type":"object","additionalProperties":false}}}
}`

func nativeOpenAPIProject(t *testing.T)*native.Project{
    t.Helper();resources:=[]native.Resource{{URI:"https://example.test/api.json",Source:nativeOpenAPIResource},{URI:"https://example.test/schemas.json",Source:`{"$schema":"https://json-schema.org/draft/2020-12/schema","$defs":{"Input":{"type":"integer","minimum":1},"Output":{"type":"integer","minimum":2}}}`}}
    project,err:=native.IngestProjectResources(native.OpenAPI,resources,native.ProjectOptions{Root:native.ResourceSelector{Resource:"https://example.test/api.json",Pointer:"/components/schemas/Root",TypeName:"Root"}});if err!=nil{t.Fatal(err)};project,err=project.WithEditedSource(nativeOpenAPISource);if err!=nil{t.Fatal(err)}
    responses:=[]refineopenapi.ResponseBinding{{Status:"200",ResponseType:"ResponseValue",ContextType:"Context"},{Status:"2XX",ResponseType:"ResponseValue"},{Status:"default",ResponseType:"ResponseValue"}};operation:=refineopenapi.OperationBinding{OperationID:"createItem",Method:"POST",Path:"/items/{id}",RequestType:"RequestValue",Responses:responses};nativeResponses:=[]refineopenapi.NativeResponseBinding{{Status:"200",Headers:[]refineopenapi.NativeHeaderBinding{{Name:"X-Rate",FieldPath:[]string{"xRate"}}}},{Status:"2XX"},{Status:"default"}};binding:=refineopenapi.NativeOperationBinding{OperationID:"createItem",Parameters:[]refineopenapi.NativeParameterBinding{{In:"header",Name:"X-Key",FieldPath:[]string{"xKey"}}},Responses:nativeResponses};metadata:=native.WireMetadata{PublicationNamespace:"example.nativeapi",OpenAPI:&refineopenapi.Schema{Version:refineopenapi.SchemaVersion,Operations:[]refineopenapi.OperationBinding{operation},Native:&refineopenapi.NativeBindings{Version:refineopenapi.NativeBindingsVersion,Operations:[]refineopenapi.NativeOperationBinding{binding}}}}
    project,err=project.WithMetadata(metadata);if err!=nil{t.Fatal(err)};return project
}

func TestGeneratedNativeOpenAPIContextComposesAllBoundaries(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=networkntClasspath(t)+string(os.PathListSeparator)+graalJSClasspath(t);files,err:=GenerateProjectOpenAPIContext(nativeOpenAPIProject(t),"Contract","Operations");if err!=nil{t.Fatal(err)};for _,file:=range files{if filepath.Base(file.Path)=="OperationsNativeResponseParts.java"{t.Fatal("unchanged OpenAPI 3.1 resource views emitted a redundant response sidecar")}};dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)};harness:=filepath.Join(dir,"NativeOpenAPIHarness.java");if err:=os.WriteFile(harness,[]byte(nativeOpenAPIHarness),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("native OpenAPI javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-Xss256k","-Xmx64m","-cp",classes+string(os.PathListSeparator)+classpath,"NativeOpenAPIHarness").CombinedOutput();err!=nil{t.Fatalf("native OpenAPI runtime: %v\n%s",err,output)}
}

const nativeOpenAPIHarness=`
import example.nativeapi.*;
import java.nio.charset.StandardCharsets;
import java.util.List;
public final class NativeOpenAPIHarness {
 static byte[] json(String value){return value.getBytes(StandardCharsets.UTF_8);}
 static Operations.ParameterJSON parameter(String in,String name,String value){return new Operations.ParameterJSON(in,name,json(value));}
 static Operations.HeaderJSON header(String name,String value){return new Operations.HeaderJSON(name,json(value));}
 static Operations.MediaJSON body(String value){return new Operations.MediaJSON("application/json",json(value));}
 static Operations.RequestJSON request(String id,String query,String key,String value){var parameters=new java.util.ArrayList<Operations.ParameterJSON>();parameters.add(parameter("path","id",id));if(query!=null)parameters.add(parameter("query","q",query));return new Operations.RequestJSON(parameters,List.of(header("x-key",key)),body(value));}
 static Operations.ResponseJSON response(String status,String rate,String value){return new Operations.ResponseJSON(status,rate==null?List.of():List.of(header("X-Rate",rate)),body(value));}
 static void require(boolean value){if(!value)throw new AssertionError();}
 static void nativeInvalid(Runnable action){try{action.run();throw new AssertionError("native-invalid value accepted");}catch(OperationsNativeParts.NativeValidationException expected){require(expected.code()==OperationsNativeParts.Code.INVALID);}}
 static void resource(Runnable action){try{action.run();throw new AssertionError("native resource bound not enforced");}catch(OperationsNativeParts.NativeValidationException expected){require(expected.isResourceLimit()&&expected.isIndeterminate());}}
 static void refinementInvalid(Runnable action){try{action.run();throw new AssertionError("refinement-invalid value accepted");}catch(ValidationException expected){require(expected.outcome().state()==Validation.State.INVALID);}}
 public static void main(String[] args){
  var operations=new Operations();byte[] original=json("12");var immutable=new Operations.RequestJSON(List.of(parameter("path","id","1"),parameter("query","q","\"abc\"")),List.of(header("X-Key","\"key-7\"")),new Operations.MediaJSON("application/json",original));original[0]='0';var token=operations.validateRequest("createItem",immutable);require(token.operationId().equals("createItem"));
  nativeInvalid(()->operations.validateRequest("createItem",request("0","\"abc\"","\"key-7\"","12")));nativeInvalid(()->operations.validateRequest("createItem",request("1","\"ABC\"","\"key-7\"","12")));nativeInvalid(()->operations.validateRequest("createItem",request("1,\"injected\":2","\"abc\"","\"key-7\"","12")));refinementInvalid(()->operations.validateRequest("createItem",request("1",null,"\"key-7\"","5")));
  require(operations.validateResponse("createItem",response("200","0","13"),token).state()==Validation.State.VALID);require(operations.validateResponse("createItem",response("200","0","11"),token).state()==Validation.State.INVALID);var missing=operations.validateResponse("createItem",response("200","0","13"),null);require(missing.state()==Validation.State.INDETERMINATE&&missing.incomplete());require(operations.validateResponse("createItem",response("204",null,"2"),null).state()==Validation.State.VALID);require(operations.validateResponse("createItem",response("500",null,"2"),null).state()==Validation.State.VALID);
  try{new Operations().validateResponse("createItem",response("200","0","13"),token);throw new AssertionError("foreign facade token accepted");}catch(IllegalArgumentException expected){}
  var oneRegex=new Operations(Operations.Limits.defaults(),OperationsNativeParts.Limits.defaults(),new OperationsNativeParts.RegexLimits(16384,1<<20,1,8L<<20,1000));resource(()->oneRegex.validateRequest("createItem",request("1","\"abc\"","\"key-7\"","12")));
  try{new Operations(new Operations.Limits(4,4),OperationsNativeParts.Limits.defaults(),OperationsNativeParts.RegexLimits.defaults()).validateRequest("createItem",request("1",null,"\"key-7\"","12"));throw new AssertionError("aggregate byte limit accepted");}catch(Operations.OpenAPILimitException expected){require(expected.isIndeterminate());}
  try{new Operations.ParameterJSON("path","id",new byte[(1<<20)+1]);throw new AssertionError("oversized semantic value cloned");}catch(Operations.OpenAPILimitException expected){require(expected.isIndeterminate());}
 }
}
`
