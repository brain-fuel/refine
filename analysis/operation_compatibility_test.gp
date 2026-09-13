package analysis

import (
    "strings"
    "testing"

    "goforge.dev/refine/language"
    "goforge.dev/refine/validation"
)

func operationProgram(t *testing.T,request,response,context string)*language.Program{t.Helper();source:="type Request = "+request+"\ntype Response = "+response+"\n";if context!=""{source+="type Context = "+context+"\n"};program,err:=language.Compile(source);if err!=nil{t.Fatal(err)};return program}
func operationContract(program *language.Program,operations ...OperationEntrypoint)OperationContract{return OperationContract{Program:program,Operations:operations}}
func operation(id,method,path string,responses ...OperationResponseEntrypoint)OperationEntrypoint{return OperationEntrypoint{OperationID:id,Method:method,Path:path,RequestRoot:"Request",Responses:responses}}
func response(status string)OperationResponseEntrypoint{return OperationResponseEntrypoint{Status:status,ResponseRoot:"Response"}}

func TestCompareOperationsUsesAsymmetricRequestAndResponseDirections(t *testing.T){
    unchanged:=operationProgram(t,"Int","Int","");base:=operationContract(unchanged,operation("get","GET","/items",response("200")))
    same,err:=CompareOperations(base,base,validation.Limits{});if err!=nil||same.Backward.Outcome!=Yes||same.Forward.Outcome!=Yes||same.Fingerprint==""{t.Fatalf("identical operations: %+v %v",same,err)}
    syntax,err:=CompareOperationContractSyntax(base,base);if err!=nil||!syntax.Equal||syntax.Version!=OperationCompatibilityVersion{t.Fatalf("operation syntax equality: %+v %v",syntax,err)}
    requestWide:=operationProgram(t,"Int where it >= 0","Int","");requestNarrow:=operationProgram(t,"Int where it >= 1","Int","");requestChange,err:=CompareOperations(operationContract(requestNarrow,base.Operations...),operationContract(requestWide,base.Operations...),validation.Limits{});if err!=nil||requestChange.Backward.Outcome!=Yes||requestChange.Forward.Outcome!=No||requestChange.Forward.Code!="analysis.operation_request_break"{t.Fatalf("request widening direction: %+v %v",requestChange,err)}
    responseWide:=operationProgram(t,"Int","Int where it >= 0","");responseNarrow:=operationProgram(t,"Int","Int where it >= 1","");responseChange,err:=CompareOperations(operationContract(responseNarrow,base.Operations...),operationContract(responseWide,base.Operations...),validation.Limits{});if err!=nil||responseChange.Backward.Outcome!=No||responseChange.Backward.Code!="analysis.operation_response_break"||responseChange.Forward.Outcome!=Yes{t.Fatalf("response widening direction: %+v %v",responseChange,err)}
}

func TestCompareOperationsClassifiesOperationAndStatusSurfaceDirection(t *testing.T){
    program:=operationProgram(t,"Int","Int","");one:=operationContract(program,operation("one","GET","/one",response("200")));two:=operationContract(program,operation("one","GET","/one",response("200")),operation("two","POST","/two",response("204")))
    added,err:=CompareOperations(one,two,validation.Limits{});if err!=nil||added.Backward.Outcome!=Yes||added.Forward.Outcome!=No||added.Forward.Code!="analysis.operation_removed"{t.Fatalf("operation addition: %+v %v",added,err)};removed,err:=CompareOperations(two,one,validation.Limits{});if err!=nil||removed.Backward.Outcome!=No||removed.Forward.Outcome!=Yes{t.Fatalf("operation removal: %+v %v",removed,err)}
    oldStatus:=operationContract(program,operation("one","GET","/one",response("200")));newStatus:=operationContract(program,operation("one","GET","/one",response("200"),response("202")));statuses,err:=CompareOperations(oldStatus,newStatus,validation.Limits{});if err!=nil||statuses.Backward.Outcome!=No||statuses.Backward.Code!="analysis.operation_response_surface"||statuses.Forward.Outcome!=Yes{t.Fatalf("response status addition: %+v %v",statuses,err)}
    changedRoute:=operationContract(program,operation("one","POST","/one",response("200")));routes,err:=CompareOperations(oldStatus,changedRoute,validation.Limits{});if err!=nil||routes.Backward.Outcome!=No||routes.Forward.Outcome!=No||routes.Backward.Code!="analysis.operation_route_changed"{t.Fatalf("route change: %+v %v",routes,err)}
    responseClass:=operationContract(program,operation("one","GET","/one",response("2XX")));exactResponse:=operationContract(program,operation("one","GET","/one",response("200")));selectors,err:=CompareOperations(responseClass,exactResponse,validation.Limits{});if err!=nil||selectors.Backward.Outcome!=Yes||selectors.Forward.Outcome!=No||selectors.Forward.Code!="analysis.operation_response_surface"{t.Fatalf("effective response selectors: %+v %v",selectors,err)}
}

func TestCompareOperationsKeepsChangedRelationalContextUnknown(t *testing.T){
    oldProgram:=operationProgram(t,"Int","Int","{request :: Request, response :: Response} where it.request <= it.response");newProgram:=operationProgram(t,"Int","Int","{request :: Request, response :: Response} where it.request < it.response");oldResponse:=OperationResponseEntrypoint{Status:"200",ResponseRoot:"Response",ContextRoot:"Context"};newResponse:=oldResponse
    compared,err:=CompareOperations(operationContract(oldProgram,operation("one","GET","/one",oldResponse)),operationContract(newProgram,operation("one","GET","/one",newResponse)),validation.Limits{});if err!=nil||compared.Backward.Outcome!=Unknown||compared.Forward.Outcome!=Unknown||compared.Backward.Code!="analysis.operation_context_unknown"{t.Fatalf("changed relation was overclaimed: %+v %v",compared,err)}
    responseOld:=operationProgram(t,"Int","Int where it >= 1","{request :: Request, response :: Response}");responseNew:=operationProgram(t,"Int","Int where it >= 0","{request :: Request, response :: Response}");relational:=OperationResponseEntrypoint{Status:"200",ResponseRoot:"Response",ContextRoot:"Context"};marginal,err:=CompareOperations(operationContract(responseOld,operation("one","GET","/one",relational)),operationContract(responseNew,operation("one","GET","/one",relational)),validation.Limits{});if err!=nil||marginal.Backward.Outcome!=Unknown||marginal.Backward.Code!="analysis.operation_context_unknown"{t.Fatalf("marginal response counterexample overclaimed relation: %+v %v",marginal,err)}
    generic,err:=language.Compile("type Pair a b = {request :: a, response :: b}\ntype Request = Int\ntype Response = Int\ntype Context = Pair Request Response\n");if err!=nil{t.Fatal(err)};genericResponse:=OperationResponseEntrypoint{Status:"200",ResponseRoot:"Response",ContextRoot:"Context"};if _,err:=CompareOperations(operationContract(generic,operation("generic","POST","/generic",genericResponse)),operationContract(generic,operation("generic","POST","/generic",genericResponse)),validation.Limits{});err!=nil{t.Fatalf("valid generic context rejected: %v",err)}
    badStatus:=OperationResponseEntrypoint{Status:"20X",ResponseRoot:"Response"};malformed:=[]OperationContract{{},operationContract(oldProgram,operation("one","GET","/one",oldResponse),operation("one","GET","/other",oldResponse)),operationContract(oldProgram,operation("one","GET","/one",oldResponse),operation("two","GET","/one",oldResponse)),operationContract(oldProgram,operation("one","GET","/one",oldResponse,oldResponse)),operationContract(oldProgram,operation("one","GET","/one",badStatus)),operationContract(oldProgram,operation("one","GET","not-a-path",oldResponse))};for _,contract:=range malformed{if _,err:=CompareOperations(contract,operationContract(oldProgram,operation("one","GET","/one",oldResponse)),validation.Limits{});err==nil{t.Fatalf("malformed operation contract accepted: %+v",contract)}}
    if next,ok:=operationCompatibilityWork(2,4,"ab");!ok||next!=4{t.Fatal("exact operation work boundary rejected")};if _,ok:=operationCompatibilityWork(2,4,"abc");ok{t.Fatal("operation work one-over accepted")}
}

func TestOperationContextResolutionBoundsGenericDAGWork(t *testing.T){
    nested,err:=language.Compile("type Pair a b = {request :: a, response :: b}\ntype Id a = a\ntype Request = Int\ntype Response = Int\ntype Context = Pair (Id (Id (Id Request))) (Id (Id (Id Response)))\n");if err!=nil{t.Fatal(err)}
    bounded:=newOperationContractChecker(nested.Syntax(),6);if err:=bounded.validateContext("Context","Request","Response");err==nil||!strings.Contains(err.Error(),"aggregate structural work limit"){t.Fatalf("nested generic context escaped shared work bound: %v",err)}
}
