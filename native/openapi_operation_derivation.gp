package native

import (
    "crypto/sha256"
    "fmt"
    "sort"
    "strings"

    refineopenapi "goforge.dev/refine/openapi"
    "goforge.dev/refine/schemajson"
)

// OpenAPIDerivationOptions selects operations for automatic checked wrapper
// derivation. An empty selection means every operation under paths and requires
// each of them to have an operationId. A nonempty selection is an explicit
// subset and leaves all other document operations unbound.
type OpenAPIDerivationOptions struct { OperationIDs []string }

type derivedOpenAPIOperation struct { declarations []string; refined refineopenapi.OperationBinding; native refineopenapi.NativeOperationBinding }
type derivedOpenAPIHeader struct { name string; node openAPINode }

// WithDerivedOpenAPIOperations returns a new project containing deterministic
// checked request/response wrappers and authoritative native operation
// bindings. Native Schema Objects remain in the immutable resource set and are
// always enforced before the derived structural types and later refinements.
// This helper does not infer request/response context predicates.
func (p *Project)WithDerivedOpenAPIOperations(options OpenAPIDerivationOptions)(*Project,error){
    if p==nil||p.program==nil{return nil,&Error{Code:"native.project",Message:"a checked project is required"}}
    if p.Format()!=OpenAPI{return nil,&Error{Code:"native.format",Format:p.Format(),Message:"OpenAPI operation derivation requires an OpenAPI project"}}
    if p.metadata.OpenAPI!=nil{return nil,&Error{Code:"native.metadata",Format:OpenAPI,Message:"automatic operation derivation will not replace existing OpenAPI metadata"}}
    if len(options.OperationIDs)>4096{return nil,&Error{Code:"native.limit",Format:OpenAPI,Message:"at most 4,096 operation IDs may be selected"}}
    resources,err:=p.canonicalJSONResources();if err!=nil{return nil,err};docs:=map[string]schemajson.Document{};for _,resource:=range resources{doc,parseErr:=schemajson.Parse([]byte(resource.Source),schemajson.Limits{});if parseErr!=nil{return nil,wrap(OpenAPI,"native.structure",resource.URI,parseErr)};docs[resource.URI]=doc}
    requireIDs:=len(options.OperationIDs)==0;operations,err:=indexOpenAPIDocumentOperationsMode(p.root.Resource,docs,requireIDs);if err!=nil{return nil,err}
    selected,err:=selectedDerivedOperationIDs(options.OperationIDs,operations);if err!=nil{return nil,err};if len(selected)==0{return nil,&Error{Code:"native.projection",Format:OpenAPI,Message:"no OpenAPI operations were selected for derivation"}}
    used:=map[string]bool{};for _,decl:=range p.program.Syntax().Types{used[decl.Name]=true}
    declarations:=[]string{};refined:=[]refineopenapi.OperationBinding{};nativeBindings:=[]refineopenapi.NativeOperationBinding{}
    openAPI30:=strings.HasPrefix(p.Version(),"3.0.");for _,id:=range selected{derived,deriveErr:=deriveOpenAPIOperation(operations[id],docs,used,openAPI30);if deriveErr!=nil{return nil,deriveErr};declarations=append(declarations,derived.declarations...);refined=append(refined,derived.refined);nativeBindings=append(nativeBindings,derived.native)}
    updated,err:=p.withDerivedOpenAPISource(declarations);if err!=nil{return nil,err};metadata:=updated.Metadata();metadata.OpenAPI=&refineopenapi.Schema{Version:refineopenapi.SchemaVersion,Operations:refined,Native:&refineopenapi.NativeBindings{Version:refineopenapi.NativeBindingsVersion,Operations:nativeBindings}}
    return updated.WithMetadata(metadata)
}

func selectedDerivedOperationIDs(requested []string,available map[string]openAPIDocumentOperation)([]string,error){
    if len(requested)==0{out:=make([]string,0,len(available));for id:=range available{out=append(out,id)};sort.Strings(out);return out,nil}
    seen:=map[string]bool{};out:=append([]string(nil),requested...);for _,id:=range out{if id==""{return nil,&Error{Code:"native.projection",Format:OpenAPI,Message:"selected operationId must be nonempty"}};if seen[id]{return nil,&Error{Code:"native.projection",Format:OpenAPI,Pointer:id,Message:"duplicate selected operationId"}};seen[id]=true;if _,ok:=available[id];!ok{return nil,&Error{Code:"native.projection",Format:OpenAPI,Pointer:id,Message:"selected operationId is absent from the OpenAPI paths document"}}};sort.Strings(out);return out,nil
}

func (p *Project)withDerivedOpenAPISource(declarations []string)(*Project,error){
    addition:=strings.Join(declarations,"\n\n");if addition==""{return nil,&Error{Code:"native.projection",Format:OpenAPI,Message:"operation derivation produced no checked declarations"}}
    appendSource:=func(source string)string{if source!=""&&!strings.HasSuffix(source,"\n"){source+="\n"};return source+"\n"+addition+"\n"}
    if p.languageEntry==""{return p.WithEditedSource(appendSource(p.source))}
    sources:=map[string]string{};found:=false;for _,file:=range p.languageFiles{source:=file.Source;if file.ID==p.languageEntry{source=appendSource(source);found=true};sources[file.ID]=source};if !found{return nil,&Error{Code:"native.project",Format:OpenAPI,Pointer:p.languageEntry,Message:"language entry source is absent"}};return p.WithEditedSources(p.languageEntry,sources)
}

func deriveOpenAPIOperation(document openAPIDocumentOperation,docs map[string]schemajson.Document,used map[string]bool,openAPI30 bool)(derivedOpenAPIOperation,error){
    requestName,err:=reserveDerivedOpenAPIName(used,document.operationID,"request");if err!=nil{return derivedOpenAPIOperation{},err}
    parameters:=[]openAPIParameter{};for _,raw:=range document.parameters{parameter,compileErr:=compileOpenAPIParameter(raw,docs);if compileErr!=nil{return derivedOpenAPIOperation{},compileErr};parameters=append(parameters,parameter)};sort.Slice(parameters,func(i,j int)bool{left:=openAPIParameterKey(parameters[i].location,parameters[i].name);right:=openAPIParameterKey(parameters[j].location,parameters[j].name);return left<right})
    declarations:=[]string{};parameterFields:=[]string{};headerFields:=[]string{};nativeParameters:=[]refineopenapi.NativeParameterBinding{};assigned:=map[string]bool{}
    for _,parameter:=range parameters{field:=directWireField(parameter.name);if field==""{return derivedOpenAPIOperation{},derivationError(document.operationID,parameter.schema,"parameter "+parameter.location+"/"+parameter.name+" is not a direct language field identifier; provide explicit checked metadata")};top:="parameters";assignment:=field;if parameter.location=="header"{top="headers";assignment=strings.ToLower(field)};key:=top+"\x00"+assignment;if assigned[key]{return derivedOpenAPIOperation{},derivationError(document.operationID,parameter.schema,"parameter names collide in the derived "+top+" record; provide explicit field mappings")};assigned[key]=true;nameParts:=[]string{document.operationID,"request",parameter.location,parameter.name};expr,decls,projectErr:=deriveOpenAPISchemaType(parameter.schema,docs,nameParts,used);if projectErr!=nil{return derivedOpenAPIOperation{},projectErr};declarations=append(declarations,decls...);if !parameter.required{expr="Maybe ("+expr+")"};if top=="headers"{headerFields=append(headerFields,field+" :: "+expr)}else{parameterFields=append(parameterFields,field+" :: "+expr)};nativeParameters=append(nativeParameters,refineopenapi.NativeParameterBinding{In:parameter.location,Name:parameter.name,FieldPath:[]string{field}})}
    bodyType:="Maybe ({})";var nativeBody *refineopenapi.NativeMediaBinding
    if document.requestBody!=nil{body,resolveErr:=resolveOpenAPIObject(*document.requestBody,docs,64);if resolveErr!=nil{return derivedOpenAPIOperation{},resolveErr};required:=false;if node,ok:=body.node.Lookup("required");ok{required=node.Raw()=="true"};media,schema,mediaErr:=selectOpenAPIMediaSchema(body,nil,docs);if mediaErr!=nil{return derivedOpenAPIOperation{},derivationError(document.operationID,body,"request body: "+mediaErr.Error())};if openAPI30{if guardErr:=rejectOpenAPI30DirectionalRequired(document.operationID,schema,docs,"request","readOnly");guardErr!=nil{return derivedOpenAPIOperation{},guardErr}};expr,decls,projectErr:=deriveOpenAPISchemaType(schema,docs,[]string{document.operationID,"request","body",media},used);if projectErr!=nil{return derivedOpenAPIOperation{},projectErr};declarations=append(declarations,decls...);bodyType=expr;if !required{bodyType="Maybe ("+bodyType+")"};nativeBody=&refineopenapi.NativeMediaBinding{MediaType:media}}
    declarations=append(declarations,"type "+requestName+" = {parameters :: {"+strings.Join(parameterFields,", ")+"}, headers :: {"+strings.Join(headerFields,", ")+"}, body :: "+bodyType+"}")
    responseKeys:=make([]string,0,len(document.responses));for status:=range document.responses{responseKeys=append(responseKeys,status)};sort.Strings(responseKeys);responses:=[]refineopenapi.ResponseBinding{};nativeResponses:=[]refineopenapi.NativeResponseBinding{}
    for _,status:=range responseKeys{raw:=document.responses[status];response,resolveErr:=resolveOpenAPIObject(raw,docs,64);if resolveErr!=nil{return derivedOpenAPIOperation{},resolveErr};responseName,nameErr:=reserveDerivedOpenAPIName(used,document.operationID,"response",status);if nameErr!=nil{return derivedOpenAPIOperation{},nameErr};headers:=[]derivedOpenAPIHeader{};if headerObject,ok:=response.node.Lookup("headers");ok{if schemajson.KindName(headerObject.Kind())!="object"{return derivedOpenAPIOperation{},derivationError(document.operationID,response,"response headers must be an object")};for _,member:=range headerObject.Members(){name,_:=member.Key.UTF8();headers=append(headers,derivedOpenAPIHeader{name:name,node:openAPINode{resource:response.resource,pointer:response.pointer+"/headers/"+escapePointer(name),node:member.Value}})};sort.Slice(headers,func(i,j int)bool{return strings.ToLower(headers[i].name)<strings.ToLower(headers[j].name)})}
        headerFields:=[]string{};nativeHeaders:=[]refineopenapi.NativeHeaderBinding{};headerNames:=map[string]bool{};for _,item:=range headers{header,headerErr:=resolveOpenAPIObject(item.node,docs,64);if headerErr!=nil{return derivedOpenAPIOperation{},headerErr};if style,ok:=header.node.Lookup("style");ok{named,_:=nodeString(style);if named!="simple"{return derivedOpenAPIOperation{},derivationError(document.operationID,header,"response header "+item.name+" uses an unsupported serialization style")}};field:=directWireField(item.name);if field==""{return derivedOpenAPIOperation{},derivationError(document.operationID,header,"response header "+item.name+" is not a direct language field identifier; provide explicit checked metadata")};folded:=strings.ToLower(field);if headerNames[folded]{return derivedOpenAPIOperation{},derivationError(document.operationID,header,"response header names collide case-insensitively")};headerNames[folded]=true;schema,schemaErr:=openAPIInlineSchema(header,docs);if schemaErr!=nil{return derivedOpenAPIOperation{},derivationError(document.operationID,header,"response header "+item.name+": "+schemaErr.Error())};expr,decls,projectErr:=deriveOpenAPISchemaType(schema,docs,[]string{document.operationID,"response",status,"header",item.name},used);if projectErr!=nil{return derivedOpenAPIOperation{},projectErr};declarations=append(declarations,decls...);headerFields=append(headerFields,field+" :: Maybe ("+expr+")");nativeHeaders=append(nativeHeaders,refineopenapi.NativeHeaderBinding{Name:item.name,FieldPath:[]string{field}})}
        responseBody:="Maybe ({})";var nativeResponseBody *refineopenapi.NativeMediaBinding;if _,hasContent:=response.node.Lookup("content");hasContent{media,schema,mediaErr:=selectOpenAPIMediaSchema(response,nil,docs);if mediaErr!=nil{return derivedOpenAPIOperation{},derivationError(document.operationID,response,"response body "+status+": "+mediaErr.Error())};if openAPI30{if guardErr:=rejectOpenAPI30DirectionalRequired(document.operationID,schema,docs,"response","writeOnly");guardErr!=nil{return derivedOpenAPIOperation{},guardErr}};expr,decls,projectErr:=deriveOpenAPISchemaType(schema,docs,[]string{document.operationID,"response",status,"body",media},used);if projectErr!=nil{return derivedOpenAPIOperation{},projectErr};declarations=append(declarations,decls...);responseBody="Maybe ("+expr+")";nativeResponseBody=&refineopenapi.NativeMediaBinding{MediaType:media}}
        declarations=append(declarations,"type "+responseName+" = {headers :: {"+strings.Join(headerFields,", ")+"}, body :: "+responseBody+"}");responses=append(responses,refineopenapi.ResponseBinding{Status:status,ResponseType:responseName});nativeResponses=append(nativeResponses,refineopenapi.NativeResponseBinding{Status:status,Headers:nativeHeaders,Body:nativeResponseBody})
    }
    refined:=refineopenapi.OperationBinding{OperationID:document.operationID,Method:strings.ToUpper(documentMethod(document.pointer)),Path:documentPath(document.pointer),RequestType:requestName,Responses:responses};native:=refineopenapi.NativeOperationBinding{OperationID:document.operationID,Parameters:nativeParameters,RequestBody:nativeBody,Responses:nativeResponses};return derivedOpenAPIOperation{declarations:declarations,refined:refined,native:native},nil
}

func deriveOpenAPISchemaType(schema openAPINode,docs map[string]schemajson.Document,nameParts []string,used map[string]bool)(string,[]string,error){
    doc,ok:=docs[schema.resource];if !ok{return "",nil,&Error{Code:"native.resource",Format:OpenAPI,Pointer:schema.resource,Message:"operation Schema Object resource is absent"}};projector:=&sourceProjector{format:OpenAPI,root:doc,names:map[string]string{},definitionNodes:map[string]schemajson.Node{},definitionPaths:map[string]string{},emitted:map[string]bool{},openAPI:true,strictStructure:true}
    addDefinitions:=func(pointer,reference string){definitions,err:=doc.At(pointer);if err!=nil||schemajson.KindName(definitions.Kind())!="object"{return};for _,member:=range definitions.Members(){raw,_:=member.Key.UTF8();ref:=reference+escapePointer(raw);semantic:=append(append([]string(nil),nameParts...),raw);name:=derivedOpenAPIName(strings.Join(nameParts,"\x00")+"\x00"+ref,semantic...);projector.names[ref]=name;projector.definitionNodes[ref]=member.Value;projector.definitionPaths[ref]=pointer+"/"+escapePointer(raw)}};addDefinitions("/components/schemas","#/components/schemas/");addDefinitions("/$defs","#/$defs/")
    expr,err:=projector.jsonType(schema.node,schema.pointer,true);if err!=nil{return "",nil,err};decls:=append([]string(nil),projector.declarations...);for _,declaration:=range decls{name:=derivedDeclarationName(declaration);if name==""||used[name]{return "",nil,&Error{Code:"native.projection",Format:OpenAPI,Pointer:schema.resource+"#"+schema.pointer,Message:"derived declaration name collides with checked source"}};used[name]=true};return expr,decls,nil
}

func reserveDerivedOpenAPIName(used map[string]bool,parts ...string)(string,error){name:=derivedOpenAPIPrefix(parts...);if used[name]{return "",&Error{Code:"native.projection",Format:OpenAPI,Pointer:strings.Join(parts,"/"),Message:"deterministic derived type name collides with checked source"}};used[name]=true;return name,nil}
func derivedOpenAPIPrefix(parts ...string)string{return derivedOpenAPIName(strings.Join(parts,"\x00"),parts...)}
func derivedOpenAPIName(identity string,parts ...string)string{const semanticLimit=72;semantic:="";for _,raw:=range parts{component:=derivedOpenAPIComponent(raw);if component==""{continue};remaining:=semanticLimit-len(semantic);if semantic!=""{remaining--;if remaining<=0{break};semantic+="_"};if len(component)>remaining{component=component[:remaining]};semantic+=component;if len(semantic)>=semanticLimit{break}};if semantic==""{semantic="Part"};return "OpenAPI_"+semantic+"_"+derivedOpenAPIHash(identity)}
func derivedOpenAPIComponent(raw string)string{const componentLimit=32;var b strings.Builder;upper:=true;for _,r:=range raw{letter:=r>='a'&&r<='z'||r>='A'&&r<='Z';digit:=r>='0'&&r<='9';if !letter&&!digit{upper=true;continue};if b.Len()>=componentLimit{break};if upper&&r>='a'&&r<='z'{r-=32};b.WriteRune(r);upper=false};return b.String()}
func derivedOpenAPIHash(text string)string{sum:=sha256.Sum256([]byte(text));return fmt.Sprintf("%x",sum[:10])}
func derivedDeclarationName(declaration string)string{fields:=strings.Fields(declaration);if len(fields)>=2&&fields[0]=="type"{return fields[1]};if len(fields)>=2&&fields[0]=="data"{return fields[1]};return ""}
func derivationError(operation string,node openAPINode,message string)error{return &Error{Code:"native.projection",Format:OpenAPI,Pointer:operation+" "+node.resource+"#"+node.pointer,Message:message}}

// OAS 3.0 makes required readOnly properties response-only and required
// writeOnly properties request-only. The generic JSON Schema oracle cannot
// reproduce that directional rule, so automatic body derivation rejects the
// affected opposite direction instead of producing a validator that rejects a
// conforming payload. Later OAS versions deliberately keep their annotation
// validation policy outside this 3.0-only guard.
func rejectOpenAPI30DirectionalRequired(operation string,schema openAPINode,docs map[string]schemajson.Document,direction,annotation string)error{
    pending:=[]openAPINode{schema};seen:=map[string]bool{};work:=0
    for len(pending)>0{work++;if work>65536{return &Error{Code:"native.limit",Format:OpenAPI,Pointer:operation,Message:"OpenAPI 3.0 directional body schema inspection limit exceeded"}};current:=pending[len(pending)-1];pending=pending[:len(pending)-1];resolved,err:=resolveOpenAPIObject(current,docs,64);if err!=nil{return err};key:=resolved.resource+"#"+resolved.pointer;if seen[key]{continue};seen[key]=true
        required:=map[string]bool{};if requiredNode,ok:=resolved.node.Lookup("required");ok&&schemajson.KindName(requiredNode.Kind())=="array"{for _,item:=range requiredNode.Elements(){if name,ok:=nodeString(item);ok{required[name]=true}}}
        if properties,ok:=resolved.node.Lookup("properties");ok&&schemajson.KindName(properties.Kind())=="object"{for _,member:=range properties.Members(){name,_:=member.Key.UTF8();child:=openAPINode{resource:resolved.resource,pointer:resolved.pointer+"/properties/"+escapePointer(name),node:member.Value};checked,checkErr:=resolveOpenAPIObject(child,docs,64);if checkErr!=nil{return checkErr};if required[name]{if flag,ok:=checked.node.Lookup(annotation);ok&&flag.Raw()=="true"{return &Error{Code:"native.projection",Format:OpenAPI,Pointer:operation+" "+checked.resource+"#"+checked.pointer+"/"+annotation,Message:"automatic OpenAPI 3.0 "+direction+" body derivation cannot model direction-dependent required "+annotation+" property "+name+"; direction-aware native body validation is not yet supported"}}};pending=append(pending,child)}}
        for _,keyword:=range []string{"items","additionalProperties","not"}{if child,ok:=resolved.node.Lookup(keyword);ok&&schemajson.KindName(child.Kind())=="object"{pending=append(pending,openAPINode{resource:resolved.resource,pointer:resolved.pointer+"/"+keyword,node:child})}}
        for _,keyword:=range []string{"allOf","anyOf","oneOf"}{if children,ok:=resolved.node.Lookup(keyword);ok&&schemajson.KindName(children.Kind())=="array"{for i,child:=range children.Elements(){if schemajson.KindName(child.Kind())=="object"{pending=append(pending,openAPINode{resource:resolved.resource,pointer:fmt.Sprintf("%s/%s/%d",resolved.pointer,keyword,i),node:child})}}}}
    };return nil
}
