// Package openapi validates pure Refine request/response execution contexts.
// It models no HTTP transport and performs no I/O.
package openapi

import (
    "fmt"
    "strings"
    "unicode/utf8"

    "goforge.dev/refine/language"
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

const SchemaVersion="refine.openapi.operations/v1"

type Schema struct {Version string `json:"version"`;Operations []OperationBinding `json:"operations"`}
type OperationBinding struct {OperationID string `json:"operationId"`;Method string `json:"method"`;Path string `json:"path"`;RequestType string `json:"requestType"`;Responses []ResponseBinding `json:"responses"`}
type ResponseBinding struct {Status string `json:"status"`;ResponseType string `json:"responseType"`;ContextType string `json:"contextType,omitempty"`}
type Request struct {Parameters value.Data;Headers value.Data;Body value.Data}
type Response struct {Headers value.Data;Body value.Data}

type Error struct {Code,OperationID,Status,Message string}
func (e *Error)Error()string{location:=e.OperationID;if e.Status!=""{location+="/"+e.Status};if location!=""{location=" "+location};return e.Code+location+": "+e.Message}

type Contract struct {schema Schema;operations map[string]*operation}
type operation struct {binding OperationBinding;request *language.PayloadType;responses []checkedResponse}
type checkedResponse struct {binding ResponseBinding;response,context *language.PayloadType}

func copySchema(schema Schema)Schema{out:=Schema{Version:schema.Version,Operations:make([]OperationBinding,len(schema.Operations))};for i,item:=range schema.Operations{out.Operations[i]=item;out.Operations[i].Responses=append([]ResponseBinding(nil),item.Responses...)};return out}
func (c *Contract)Schema()Schema{if c==nil{return Schema{}};return copySchema(c.schema)}

func Compile(program *language.Program,schema *Schema)(*Contract,error){
    if program==nil{return nil,&Error{Code:"openapi.program",Message:"a compiled Refine program is required"}}
    if schema==nil||schema.Version!=SchemaVersion{return nil,&Error{Code:"openapi.metadata.version",Message:"unsupported or missing operation schema version"}}
    if len(schema.Operations)==0||len(schema.Operations)>4096{return nil,&Error{Code:"openapi.metadata",Message:"operation metadata must contain between 1 and 4096 operations"}}
    checked:=&Contract{schema:copySchema(*schema),operations:map[string]*operation{}};locations:=map[string]bool{};totalResponses:=0
    for _,binding:=range checked.schema.Operations{
        if binding.OperationID==""||!utf8.ValidString(binding.OperationID){return nil,metadata(binding,"","operationId must be nonempty Unicode text")}
        if _,exists:=checked.operations[binding.OperationID];exists{return nil,metadata(binding,"","duplicate operationId")}
        if !httpToken(binding.Method){return nil,metadata(binding,"","method must be a nonempty HTTP token")}
        if err:=pathTemplate(binding.Path);err!=nil{return nil,metadata(binding,"",err.Error())}
        location:=binding.Method+"\x00"+binding.Path;if locations[location]{return nil,metadata(binding,"","duplicate method and path binding")};locations[location]=true
        if err:=canonicalRecord(program,binding.RequestType,[]string{"parameters","headers","body"});err!=nil{return nil,metadata(binding,"","requestType: "+err.Error())}
        request,err:=program.PayloadType(binding.RequestType);if err!=nil{return nil,metadata(binding,"","requestType: "+err.Error())};item:=&operation{binding:binding,request:request}
        if len(binding.Responses)==0||len(binding.Responses)>1024{return nil,metadata(binding,"","operation must contain between 1 and 1024 response bindings")};totalResponses+=len(binding.Responses);if totalResponses>4096{return nil,metadata(binding,"","operation metadata exceeds 4096 total response bindings")}
        responseKeys:=map[string]bool{}
        for _,responseBinding:=range binding.Responses{
            if !responseStatus(responseBinding.Status){return nil,metadata(binding,responseBinding.Status,"status must be 100-599, a 1XX-5XX class, or default")}
            if responseKeys[responseBinding.Status]{return nil,metadata(binding,responseBinding.Status,"duplicate response status")};responseKeys[responseBinding.Status]=true
            if err:=canonicalRecord(program,responseBinding.ResponseType,[]string{"headers","body"});err!=nil{return nil,metadata(binding,responseBinding.Status,"responseType: "+err.Error())}
            response,err:=program.PayloadType(responseBinding.ResponseType);if err!=nil{return nil,metadata(binding,responseBinding.Status,"responseType: "+err.Error())};checkedResponse:=checkedResponse{binding:responseBinding,response:response}
            if responseBinding.ContextType!=""{
                fields,err:=canonicalRecordFields(program,responseBinding.ContextType,[]string{"request","response"});if err!=nil{return nil,metadata(binding,responseBinding.Status,"contextType: "+err.Error())}
                requestName,ok:=directName(fields["request"]);if !ok||!compatibleAlias(program,requestName,binding.RequestType){return nil,metadata(binding,responseBinding.Status,"context request field must reference requestType directly or through transparent aliases")}
                responseName,ok:=directName(fields["response"]);if !ok||!compatibleAlias(program,responseName,responseBinding.ResponseType){return nil,metadata(binding,responseBinding.Status,"context response field must reference responseType directly or through transparent aliases")}
                checkedResponse.context,err=program.PayloadType(responseBinding.ContextType);if err!=nil{return nil,metadata(binding,responseBinding.Status,"contextType: "+err.Error())}
            }
            item.responses=append(item.responses,checkedResponse)
        }
        checked.operations[binding.OperationID]=item
    }
    return checked,nil
}

func metadata(binding OperationBinding,status,message string)error{return &Error{Code:"openapi.metadata",OperationID:binding.OperationID,Status:status,Message:message}}

func httpToken(text string)bool{if text==""{return false};for i:=0;i<len(text);i++{c:=text[i];if c>127||!(c>='0'&&c<='9'||c>='A'&&c<='Z'||c>='a'&&c<='z'||strings.ContainsRune("!#$%&'*+-.^_`|~",rune(c))){return false}};return true}
func pathTemplate(text string)error{
    if text==""||text[0]!='/'||!utf8.ValidString(text){return fmt.Errorf("path must be a UTF-8 OpenAPI path template beginning with /")};if strings.ContainsAny(text,"?#\x00"){return fmt.Errorf("path template cannot contain a query, fragment, or NUL")}
    names:=map[string]bool{};for i:=0;i<len(text);{switch text[i]{case '{':end:=strings.IndexByte(text[i+1:],'}');if end<0{return fmt.Errorf("path template has an unmatched {")};end+=i+1;name:=text[i+1:end];if name==""||strings.ContainsAny(name,"{}/"){return fmt.Errorf("path template variable is empty or malformed")};if names[name]{return fmt.Errorf("path template repeats variable %s",name)};names[name]=true;i=end+1;case '}':return fmt.Errorf("path template has an unmatched }");default:i++}}
    return nil
}
func responseStatus(status string)bool{if status=="default"{return true};if len(status)!=3||status[0]<'1'||status[0]>'5'{return false};if status[1:] == "XX"{return true};return status[1]>='0'&&status[1]<='9'&&status[2]>='0'&&status[2]<='9'}
func runtimeStatus(status string)bool{return len(status)==3&&status[0]>='1'&&status[0]<='5'&&status[1]>='0'&&status[1]<='9'&&status[2]>='0'&&status[2]<='9'}

func declaration(program *language.Program,name string)(language.TypeDecl,bool){if name==""||program==nil{return language.TypeDecl{},false};for _,decl:=range program.Syntax().Types{if decl.Name==name&&len(decl.Parameters)==0{return decl,true}};return language.TypeDecl{},false}
func directName(t *language.Type)(string,bool){if t==nil{return "",false};match t.Form{case language.NamedType(name):return name,true;case _:return "",false}}
func transparentName(program *language.Program,name string)(string,bool){seen:=map[string]bool{};for{if seen[name]{return "",false};seen[name]=true;decl,ok:=declaration(program,name);if !ok{return "",false};next,alias:=directName(decl.Body);if !alias{return name,true};name=next}}
func compatibleAlias(program *language.Program,left,right string)bool{a,ok:=transparentName(program,left);if !ok{return false};b,ok:=transparentName(program,right);return ok&&a==b}

func canonicalRecord(program *language.Program,name string,names []string)error{_,err:=canonicalRecordFields(program,name,names);return err}
func canonicalRecordFields(program *language.Program,name string,names []string)(map[string]*language.Type,error){
    if direct,ok:=language.ParseTypeExpression(name);ok==nil{if _,named:=directName(direct);!named{return nil,fmt.Errorf("must be a direct named closed type")}}else{return nil,fmt.Errorf("must be a direct named closed type")}
    decl,ok:=declaration(program,name);if !ok{return nil,fmt.Errorf("must name a declared closed type")};body:=decl.Body;seen:=map[string]bool{name:true}
    for body!=nil{match body.Form{case language.RefinedType(base,_):body=base;case language.NamedType(alias):if seen[alias]{return nil,fmt.Errorf("cyclic alias")};seen[alias]=true;next,found:=declaration(program,alias);if !found{return nil,fmt.Errorf("unknown alias %s",alias)};body=next.Body;case language.RecordType(fields):out:=map[string]*language.Type{};for _,field:=range fields{out[field.Name]=field.Type};if len(out)!=len(names){return nil,fmt.Errorf("must have exactly fields %s",strings.Join(names,", "))};for _,field:=range names{if out[field]==nil{return nil,fmt.Errorf("must have exactly fields %s",strings.Join(names,", "))}};return out,nil;case _:return nil,fmt.Errorf("must resolve to a record")}}
    return nil,fmt.Errorf("must resolve to a record")
}

func requestData(request Request)value.Data{data,_:=value.Record([]value.DataField{{Name:"parameters",Value:request.Parameters},{Name:"headers",Value:request.Headers},{Name:"body",Value:request.Body}});return data}
func responseData(response Response)value.Data{data,_:=value.Record([]value.DataField{{Name:"headers",Value:response.Headers},{Name:"body",Value:response.Body}});return data}
func contextData(request Request,response Response)value.Data{data,_:=value.Record([]value.DataField{{Name:"request",Value:requestData(request)},{Name:"response",Value:responseData(response)}});return data}
func missingRequest()validation.Report{return validation.Collect([]validation.Check{validation.Undecided(validation.Diagnostic{Code:"openapi.request_context.missing",Paths:[]string{"request"},Message:"Original request context is required for response validation."})})}

func (c *Contract)operation(id string)(*operation,error){if c==nil{return nil,&Error{Code:"openapi.contract",Message:"a checked operation contract is required"}};item:=c.operations[id];if item==nil{return nil,&Error{Code:"openapi.operation",OperationID:id,Message:"unknown operationId"}};return item,nil}
func (item *operation)selectResponse(status string)(*checkedResponse,error){if !runtimeStatus(status){return nil,&Error{Code:"openapi.response",OperationID:item.binding.OperationID,Status:status,Message:"response status must be 100-599"}};class:=status[:1]+"XX";var fallback *checkedResponse;for i:=range item.responses{candidate:=&item.responses[i];if candidate.binding.Status==status{return candidate,nil};if candidate.binding.Status==class{fallback=candidate}else if candidate.binding.Status=="default"&&fallback==nil{fallback=candidate}};if fallback==nil{return nil,&Error{Code:"openapi.response",OperationID:item.binding.OperationID,Status:status,Message:"response status has no binding"}};return fallback,nil}

func (c *Contract)ValidateRequest(operationID string,request Request,limits validation.Limits)(validation.Report,error){item,err:=c.operation(operationID);if err!=nil{return validation.Report{},err};return item.request.ValidateData(requestData(request),limits),nil}
func (c *Contract)ValidateResponse(operationID,status string,response Response,original *Request,limits validation.Limits)(validation.Report,error){
    item,err:=c.operation(operationID);if err!=nil{return validation.Report{},err};selected,err:=item.selectResponse(status);if err!=nil{return validation.Report{},err}
    if selected.context==nil{return selected.response.ValidateData(responseData(response),limits),nil}
    if original==nil{return validation.MergeReports(selected.response.ValidateData(responseData(response),limits),missingRequest()),nil}
    return selected.context.ValidateData(contextData(*original,response),limits),nil
}
