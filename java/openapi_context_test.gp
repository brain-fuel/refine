package java

import (
    "fmt"
    "os"
    "os/exec"
    "path/filepath"
    "strings"
    "testing"

    "goforge.dev/refine/language"
    refineopenapi "goforge.dev/refine/openapi"
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

const javaOpenAPIContextContract=`
type Params = { id :: Int } where it.id > 0 @code "request.id"
type RequestHeaders = { trace :: Maybe String }
type EmptyBody = {}
type GetRequest = { parameters :: Params, headers :: RequestHeaders, body :: EmptyBody }
type ResultBody = { id :: Int } where it.id > 0 @code "response.id"
type ResponseHeaders = { etag :: String }
type GetResponse = { headers :: ResponseHeaders, body :: ResultBody }
type GetContext = { request :: GetRequest, response :: GetResponse }
  where it.response.body.id == it.request.parameters.id @code "response.request.id"
type ErrorBody = { message :: String }
type ErrorResponse = { headers :: RequestHeaders, body :: ErrorBody }
type WrongContext = { request :: GetRequest, response :: ErrorResponse }
`

func javaOpenAPISchema()refineopenapi.Schema{return refineopenapi.Schema{Version:refineopenapi.SchemaVersion,Operations:[]refineopenapi.OperationBinding{{OperationID:"getWidget",Method:"GET",Path:"/widgets/{id}",RequestType:"GetRequest",Responses:[]refineopenapi.ResponseBinding{{Status:"200",ResponseType:"GetResponse",ContextType:"GetContext"},{Status:"2XX",ResponseType:"GetResponse"},{Status:"default",ResponseType:"ErrorResponse"}}}}}}
func apiRecord(fields ...value.DataField)value.Data{data,err:=value.Record(fields);if err!=nil{panic(err)};return data}
func apiText(text string)value.Data{v,err:=value.TextFromUTF8(text);if err!=nil{panic(err)};return value.OfText(v)}
func apiVariant(name string)value.Data{v,err:=value.Variant(name,nil);if err!=nil{panic(err)};return v}
func apiRequest(id int64)refineopenapi.Request{return refineopenapi.Request{Parameters:apiRecord(value.DataField{Name:"id",Value:value.OfNumber(value.Integer(id))}),Headers:apiRecord(value.DataField{Name:"trace",Value:apiVariant("Nothing")}),Body:apiRecord()}}
func apiResponse(id int64)refineopenapi.Response{return refineopenapi.Response{Headers:apiRecord(value.DataField{Name:"etag",Value:apiText("v1")}),Body:apiRecord(value.DataField{Name:"id",Value:value.OfNumber(value.Integer(id))})}}
func apiErrorResponse()refineopenapi.Response{return refineopenapi.Response{Headers:apiRecord(value.DataField{Name:"trace",Value:apiVariant("Nothing")}),Body:apiRecord(value.DataField{Name:"message",Value:apiText("missing")})}}
func apiOutcome(report validation.Report)string{codes:=[]string{};for _,detail:=range report.Diagnostics(){codes=append(codes,detail.Code)};return validation.StateName(report.State())+"|"+fmt.Sprint(report.Incomplete())+"|"+strings.Join(codes,",")}

func TestGeneratedOpenAPIContextMatchesGo(t *testing.T){
    compiler,vm:=javaTools(t);dependencies:=jetCheckClasspath(t);program,err:=language.Compile(javaOpenAPIContextContract);if err!=nil{t.Fatal(err)};schema:=javaOpenAPISchema();contract,err:=refineopenapi.Compile(program,&schema);if err!=nil{t.Fatal(err)};files,err:=GenerateOpenAPIContext(program,"example.apicontext","Contract","Operations",schema);if err!=nil{t.Fatal(err)}
    dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0644);err!=nil{t.Fatal(err)};sources=append(sources,target)};harness:=filepath.Join(dir,"OpenAPIContext.java");if err:=os.WriteFile(harness,[]byte(openAPIContextHarnessJava),0644);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",dependencies,"-d",classes},sources...)
    if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("OpenAPI context javac: %v\n%s",err,output)};output,err:=exec.Command(vm,"-Xss256k","-cp",classes+string(os.PathListSeparator)+dependencies,"OpenAPIContext").CombinedOutput();if err!=nil{t.Fatalf("OpenAPI context Java: %v\n%s",err,output)}
    original:=apiRequest(7);expected:=[]string{};add:=func(report validation.Report,err error){if err!=nil{t.Fatal(err)};expected=append(expected,apiOutcome(report))};report,err:=contract.ValidateRequest("getWidget",original,validation.Limits{});add(report,err);report,err=contract.ValidateRequest("getWidget",apiRequest(0),validation.Limits{});add(report,err);report,err=contract.ValidateResponse("getWidget","200",apiResponse(7),&original,validation.Limits{});add(report,err);report,err=contract.ValidateResponse("getWidget","200",apiResponse(8),&original,validation.Limits{});add(report,err);report,err=contract.ValidateResponse("getWidget","200",apiResponse(7),nil,validation.Limits{});add(report,err);report,err=contract.ValidateResponse("getWidget","200",apiResponse(0),nil,validation.Limits{});add(report,err);report,err=contract.ValidateResponse("getWidget","201",apiResponse(9),nil,validation.Limits{});add(report,err);report,err=contract.ValidateResponse("getWidget","404",apiErrorResponse(),nil,validation.Limits{});add(report,err);report,err=contract.ValidateResponse("getWidget","200",apiResponse(7),&original,validation.Limits{Total:1});add(report,err)
    actual:=strings.Split(strings.TrimSuffix(string(output),"\n"),"\n");if len(actual)!=len(expected){t.Fatalf("got %d Java outcomes, want %d: %s",len(actual),len(expected),output)};for i:=range expected{if actual[i]!=expected[i]{t.Fatalf("outcome %d Java %q Go %q",i,actual[i],expected[i])}}
}

func TestOpenAPIContextGenerationRejectsPartialOutput(t *testing.T){
    program,err:=language.Compile(javaOpenAPIContextContract);if err!=nil{t.Fatal(err)};schema:=javaOpenAPISchema();schema.Operations[0].Responses[0].ContextType="WrongContext";if files,err:=GenerateOpenAPIContext(program,"example","Contract","Operations",schema);err==nil||files!=nil{t.Fatal("incompatible operation metadata emitted partial Java")};schema=javaOpenAPISchema();if files,err:=GenerateOpenAPIContext(program,"example","Contract","Contract",schema);err==nil||files!=nil{t.Fatal("class collision accepted")}
    schema=javaOpenAPISchema();schema.Operations[0].Responses=nil;for status:=100;status<=356;status++{schema.Operations[0].Responses=append(schema.Operations[0].Responses,refineopenapi.ResponseBinding{Status:fmt.Sprint(status),ResponseType:"GetResponse"})};if files,err:=GenerateOpenAPIContext(program,"example","Contract","Operations",schema);err==nil||files!=nil{t.Fatal("oversized Java facade emitted partial output")}
}

const openAPIContextHarnessJava=`
import example.apicontext.*;
import java.util.List;
public final class OpenAPIContext {
    static Data number(long value){return new Data.Number(Rational.of(value));}
    static Data record(Data.Field... fields){return new Data.Struct(List.of(fields));}
    static Data nothing(){return new Data.Variant("Nothing",List.of());}
    static Operations.Request request(long id){return new Operations.Request(record(new Data.Field("id",number(id))),record(new Data.Field("trace",nothing())),record());}
    static Operations.Response response(long id){return new Operations.Response(record(new Data.Field("etag",new Data.Text("v1"))),record(new Data.Field("id",number(id))));}
    static Operations.Response error(){return new Operations.Response(record(new Data.Field("trace",nothing())),record(new Data.Field("message",new Data.Text("missing"))));}
    static void print(Validation.Outcome outcome){var codes=new java.util.ArrayList<String>();for(var detail:outcome.diagnostics())codes.add(detail.code());System.out.println(outcome.state().name().toLowerCase(java.util.Locale.ROOT)+"|"+outcome.incomplete()+"|"+String.join(",",codes));}
    public static void main(String[] args){
        var original=request(7);var descriptor=Operations.operations().getFirst();if(!descriptor.operationId().equals("getWidget")||!descriptor.method().equals("GET")||!descriptor.path().equals("/widgets/{id}"))throw new AssertionError();
        print(Operations.validateRequest("getWidget",original));
        print(Operations.validateRequest("getWidget",request(0)));
        print(Operations.validateResponse("getWidget","200",response(7),original));
        print(Operations.validateResponse("getWidget","200",response(8),original));
        print(Operations.validateResponse("getWidget","200",response(7),null));
        print(Operations.validateResponse("getWidget","200",response(0),null));
        print(Operations.validateResponse("getWidget","201",response(9),null));
        print(Operations.validateResponse("getWidget","404",error(),null));
        print(Operations.validateResponse("getWidget","200",response(7),original,new Budget.Limits(1,0)));
        try{Operations.validateResponse("getWidget","099",response(1),null);throw new AssertionError();}catch(IllegalArgumentException expected){}
        try{new Operations.Request(null,record(),record());throw new AssertionError();}catch(NullPointerException expected){}
    }
}
`
