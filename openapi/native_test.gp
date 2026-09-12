package openapi

import (
    "testing"

    "goforge.dev/refine/language"
)

func TestNativeBindingsAreImmutableInRefineOnlyContract(t *testing.T){
    program,err:=language.Compile("type Request = {parameters :: {}, headers :: {}, body :: Int}\ntype Response = {headers :: {}, body :: Int}\n");if err!=nil{t.Fatal(err)}
    response:=ResponseBinding{Status:"200",ResponseType:"Response"}
    operation:=OperationBinding{OperationID:"put",Method:"POST",Path:"/values",RequestType:"Request",Responses:[]ResponseBinding{response}}
    parameter:=NativeParameterBinding{In:"query",Name:"n",FieldPath:[]string{"n"}}
    header:=NativeHeaderBinding{Name:"X-N",FieldPath:[]string{"n"}}
    nativeResponse:=NativeResponseBinding{Status:"200",Headers:[]NativeHeaderBinding{header}}
    nativeOperation:=NativeOperationBinding{OperationID:"put",Parameters:[]NativeParameterBinding{parameter},Responses:[]NativeResponseBinding{nativeResponse}}
    schema:=&Schema{Version:SchemaVersion,Operations:[]OperationBinding{operation},Native:&NativeBindings{Version:NativeBindingsVersion,Operations:[]NativeOperationBinding{nativeOperation}}}
    contract,err:=Compile(program,schema);if err!=nil{t.Fatal(err)};snapshot:=contract.Schema();snapshot.Native.Operations[0].Parameters[0].FieldPath[0]="mutated";snapshot.Native.Operations[0].Responses[0].Headers[0].FieldPath[0]="mutated";again:=contract.Schema();if again.Native.Operations[0].Parameters[0].FieldPath[0]!="n"||again.Native.Operations[0].Responses[0].Headers[0].FieldPath[0]!="n"{t.Fatal("pure Refine contract exposed mutable native metadata")}
}
