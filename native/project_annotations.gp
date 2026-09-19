package native

import (
    "fmt"

    "goforge.dev/refine/schemajson"
)

// projectAnnotationAudit is the Project authority boundary for embedded
// executable source. Document parsing intentionally remains an inspection and
// type-checking API. A Project may consume only the annotation on its explicitly
// selected root; every other annotation at an actual schema position rejects.
type projectAnnotationAudit struct {
    format Format
    root ResourceSelector
    selected bool
    selectedSeen bool
    remaining int
    remainingBytes int
}

func auditProjectExecutableAnnotations(format Format,resources []Resource,root ResourceSelector,selected bool)error{return auditProjectExecutableAnnotationsWithLimit(format,resources,root,selected,schemajson.DefaultNodes)}

func auditProjectExecutableAnnotationsWithLimit(format Format,resources []Resource,root ResourceSelector,selected bool,limit int)error{return auditProjectExecutableAnnotationsWithLimits(format,resources,root,selected,limit,schemajson.DefaultBytes)}

func auditProjectExecutableAnnotationsWithLimits(format Format,resources []Resource,root ResourceSelector,selected bool,nodeLimit,pathLimit int)error{
    if format!=JSONSchema&&format!=Avro{return nil};if nodeLimit<1||pathLimit<1{return &Error{Code:"native.limit",Format:format,Message:"project annotation audit limits must be positive"}}
    audit:=&projectAnnotationAudit{format:format,root:root,selected:selected,remaining:nodeLimit,remainingBytes:pathLimit}
    for _,resource:=range resources{document,err:=schemajson.Parse([]byte(resource.Source),schemajson.Limits{});if err!=nil{return wrap(format,"native.syntax",resource.URI,err)};if err:=audit.chargePath(resource.URI,0);err!=nil{return err};if format==JSONSchema{err=audit.jsonSchema(resource.URI,"",document.Root())}else{err=audit.avroSchema(resource.URI,"",document.Root())};if err!=nil{return err}}
    if selected&&!audit.selectedSeen{return &Error{Code:"native.refinement",Format:format,Pointer:root.Resource,Message:"selected root annotation was not found at its authoritative schema position"}}
    return nil
}

func (a *projectAnnotationAudit)limit(message string)error{return &Error{Code:"native.limit",Format:a.format,Message:message}}
func (a *projectAnnotationAudit)take(count int)error{if count<0||count>a.remaining{return a.limit("aggregate project annotation audit exceeds the deterministic schema-position limit")};a.remaining-=count;return nil}
func (a *projectAnnotationAudit)preflight(count int)error{if count<0||count>a.remaining{return a.limit("aggregate project annotation audit exceeds the deterministic schema-position limit")};return nil}
func (a *projectAnnotationAudit)chargePath(resource string,pathLength int)error{size:=len(resource)+1+pathLength;if pathLength<0||size<pathLength||size>a.remainingBytes{return a.limit("aggregate project annotation audit retained paths exceed the deterministic byte limit")};a.remainingBytes-=size;return nil}
func (a *projectAnnotationAudit)fixedPath(resource,parent,suffix string)(string,error){length:=len(parent)+len(suffix);if length<len(parent){return "",a.limit("aggregate project annotation audit retained paths exceed the deterministic byte limit")};if err:=a.chargePath(resource,length);err!=nil{return "",err};return parent+suffix,nil}
func projectAnnotationEscapedLength(name string)int{length:=len(name);for i:=0;i<len(name);i++{if name[i]=='~'||name[i]=='/'{length++}};return length}
func (a *projectAnnotationAudit)memberPath(resource,parent,group,name string)(string,error){escapedLength:=projectAnnotationEscapedLength(name);length:=len(parent)+len(group)+escapedLength+2;if length<len(parent)||length<escapedLength{return "",a.limit("aggregate project annotation audit retained paths exceed the deterministic byte limit")};if err:=a.chargePath(resource,length);err!=nil{return "",err};return parent+"/"+group+"/"+escapePointer(name),nil}
func projectAnnotationLocation(resource,path string)string{if path==""{return resource};return resource+"#"+path}

func (a *projectAnnotationAudit)consume(resource,path string,node schemajson.Node)error{
    if _,err:=jsonAnnotation(a.format,projectAnnotationLocation(resource,path),node);err!=nil{return err}
    expected:=a.root.Pointer+"/x-refine";if a.format==Avro{expected="/x-refine"}
    if a.selected&&resource==a.root.Resource&&path==expected{a.selectedSeen=true;return nil}
    return &Error{Code:"native.refinement",Format:a.format,Pointer:projectAnnotationLocation(resource,path),Message:"executable x-refine annotation is outside the selected explicit project root"}
}

func (a *projectAnnotationAudit)jsonSchema(resource,path string,node schemajson.Node)error{
    if err:=a.take(1);err!=nil{return err};kind:=schemajson.KindName(node.Kind());if kind=="boolean"{return nil};if kind!="object"{return nil}
    if extension,ok:=node.Lookup("x-refine");ok{childPath,err:=a.fixedPath(resource,path,"/x-refine");if err!=nil{return err};if err:=a.consume(resource,childPath,extension);err!=nil{return err}}
    for _,name:=range []string{"additionalProperties","unevaluatedProperties","propertyNames","contains","items","additionalItems","unevaluatedItems","if","then","else","not","contentSchema"}{if child,ok:=node.Lookup(name);ok{childPath,err:=a.fixedPath(resource,path,"/"+name);if err!=nil{return err};if err:=a.jsonSchema(resource,childPath,child);err!=nil{return err}}}
    for _,name:=range []string{"$defs","definitions","properties","patternProperties","dependentSchemas"}{group,ok:=node.Lookup(name);if !ok||schemajson.KindName(group.Kind())!="object"{continue};if err:=a.preflight(group.MemberCount());err!=nil{return err};for _,member:=range group.Members(){key,err:=member.Key.UTF8();if err!=nil{return &Error{Code:"native.refinement",Format:JSONSchema,Message:"schema-position key is not Unicode scalar text"}};childPath,err:=a.memberPath(resource,path,name,key);if err!=nil{return err};if err:=a.jsonSchema(resource,childPath,member.Value);err!=nil{return err}}}
    for _,name:=range []string{"allOf","anyOf","oneOf","prefixItems"}{group,ok:=node.Lookup(name);if !ok||schemajson.KindName(group.Kind())!="array"{continue};if err:=a.preflight(group.ElementCount());err!=nil{return err};for index,child:=range group.Elements(){childPath,err:=a.fixedPath(resource,path,fmt.Sprintf("/%s/%d",name,index));if err!=nil{return err};if err:=a.jsonSchema(resource,childPath,child);err!=nil{return err}}}
    return nil
}

func (a *projectAnnotationAudit)avroSchema(resource,path string,node schemajson.Node)error{
    if err:=a.take(1);err!=nil{return err};kind:=schemajson.KindName(node.Kind())
    if kind=="array"{if err:=a.preflight(node.ElementCount());err!=nil{return err};for index,child:=range node.Elements(){childPath,err:=a.fixedPath(resource,path,fmt.Sprintf("/%d",index));if err!=nil{return err};if err:=a.avroSchema(resource,childPath,child);err!=nil{return err}};return nil}
    if kind!="object"{return nil};if extension,ok:=node.Lookup("x-refine");ok{childPath,err:=a.fixedPath(resource,path,"/x-refine");if err!=nil{return err};if err:=a.consume(resource,childPath,extension);err!=nil{return err}}
    typ,ok:=node.Lookup("type");if !ok{return nil};if schemajson.KindName(typ.Kind())!="string"{childPath,err:=a.fixedPath(resource,path,"/type");if err!=nil{return err};return a.avroSchema(resource,childPath,typ)};name,_:=nodeString(typ)
    switch name{
    case "record","error":if fields,ok:=node.Lookup("fields");ok&&schemajson.KindName(fields.Kind())=="array"{if err:=a.preflight(fields.ElementCount());err!=nil{return err};for index,field:=range fields.Elements(){if child,ok:=field.Lookup("type");ok{childPath,err:=a.fixedPath(resource,path,fmt.Sprintf("/fields/%d/type",index));if err!=nil{return err};if err:=a.avroSchema(resource,childPath,child);err!=nil{return err}}}}
    case "array":if child,ok:=node.Lookup("items");ok{childPath,err:=a.fixedPath(resource,path,"/items");if err!=nil{return err};return a.avroSchema(resource,childPath,child)}
    case "map":if child,ok:=node.Lookup("values");ok{childPath,err:=a.fixedPath(resource,path,"/values");if err!=nil{return err};return a.avroSchema(resource,childPath,child)}
    }
    return nil
}
