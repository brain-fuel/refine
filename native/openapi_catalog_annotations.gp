package native

import (
    "net/url"
    "sort"
    "strconv"
    "strings"

    "goforge.dev/refine/schemajson"
)

type openAPICatalogAnnotationSelection int
const (
    openAPICatalogSelectedRoot openAPICatalogAnnotationSelection=iota
    openAPICatalogDirectOperation
)

type openAPICatalogAnnotationWalker struct{
    catalog *jsonProjectionCatalog
    remaining int
    remainingBytes int
    auditSeen map[string]map[string]bool
    selectionSeen map[string]map[string]bool
    dynamicScanned map[string]bool
    consumedResource string
    consumedPointer string
    unconsumed openAPINode
}
type openAPICatalogAnnotationBudget struct{remaining int;remainingBytes int}
func newOpenAPICatalogAnnotationBudget()*openAPICatalogAnnotationBudget{return &openAPICatalogAnnotationBudget{remaining:65536,remainingBytes:schemajson.DefaultBytes}}

// resolveOpenAPICatalogSchemaAnnotation selects the one annotation whose
// source a caller can actually compose, then audits every actual Schema Object
// edge in the shared logical-resource catalog. A selected payload root may
// consume only its physical start node. A directly bound operation part may
// consume the first annotation on its leading static $ref chain. Dynamic
// references are never assumed to choose their static initial target: that
// target and every matching dynamic-anchor override are audited only.
func resolveOpenAPICatalogSchemaAnnotation(catalog *jsonProjectionCatalog,start openAPINode,selection openAPICatalogAnnotationSelection)(Annotation,bool,error){return resolveOpenAPICatalogSchemaAnnotationWithBudget(catalog,start,selection,newOpenAPICatalogAnnotationBudget())}

func resolveOpenAPICatalogSchemaAnnotationWithLimits(catalog *jsonProjectionCatalog,start openAPINode,selection openAPICatalogAnnotationSelection,workLimit,pathLimit int)(Annotation,bool,error){
    return resolveOpenAPICatalogSchemaAnnotationWithBudget(catalog,start,selection,&openAPICatalogAnnotationBudget{remaining:workLimit,remainingBytes:pathLimit})
}

func resolveOpenAPICatalogSchemaAnnotationWithBudget(catalog *jsonProjectionCatalog,start openAPINode,selection openAPICatalogAnnotationSelection,budget *openAPICatalogAnnotationBudget)(Annotation,bool,error){
    if catalog==nil{return Annotation{},false,&Error{Code:"native.project",Format:OpenAPI,Message:"a checked Schema Object catalog is required"}};if budget==nil||budget.remaining<1||budget.remainingBytes<1{return Annotation{},false,&Error{Code:"native.limit",Format:OpenAPI,Message:"Schema Object annotation catalog limits must be positive"}}
    if len(start.resource)+1+len(start.pointer)>budget.remainingBytes{return Annotation{},false,&Error{Code:"native.limit",Format:OpenAPI,Message:"Schema Object annotation audit retained paths exceed the deterministic byte limit"}}
    target,ok:=catalog.locations[jsonProjectionKey(start.resource,start.pointer)];if !ok{return Annotation{},false,&Error{Code:"native.root",Format:OpenAPI,Pointer:openAPISchemaNodeIdentity(start),Message:"selected Schema Object is absent from the logical resource catalog"}}
    walker:=&openAPICatalogAnnotationWalker{catalog:catalog,remaining:budget.remaining,remainingBytes:budget.remainingBytes,auditSeen:map[string]map[string]bool{},selectionSeen:map[string]map[string]bool{},dynamicScanned:map[string]bool{}};defer func(){budget.remaining=walker.remaining;budget.remainingBytes=walker.remainingBytes}()
    annotation:=Annotation{};hasAnnotation:=false
    switch selection{
    case openAPICatalogSelectedRoot:
        if err:=walker.take(target);err!=nil{return Annotation{},false,err};candidate,present,err:=openAPISchemaAnnotation(openAPINode{resource:target.resource,pointer:target.pointer,node:target.node});if err!=nil{return Annotation{},false,err};if present{annotation,hasAnnotation=candidate,true;walker.consumedResource,walker.consumedPointer=target.resource,target.pointer}
    case openAPICatalogDirectOperation:
        current:=target
        for{
            if err:=walker.take(current);err!=nil{return Annotation{},false,err};if walker.mark(walker.selectionSeen,current){return Annotation{},false,&Error{Code:"native.enforcement",Format:OpenAPI,Pointer:jsonProjectionKey(current.resource,current.pointer),Message:"cyclic static Schema Object annotation reference"}}
            candidate,present,err:=openAPISchemaAnnotation(openAPINode{resource:current.resource,pointer:current.pointer,node:current.node});if err!=nil{return Annotation{},false,err};if present{annotation,hasAnnotation=candidate,true;walker.consumedResource,walker.consumedPointer=current.resource,current.pointer;break}
            reference,exists:=current.node.Lookup("$ref");if !exists{break};raw,valid:=nodeString(reference);if !valid{return Annotation{},false,&Error{Code:"native.refinement",Format:OpenAPI,Pointer:jsonProjectionKey(current.resource,current.pointer)+"/$ref",Message:"Schema Object reference must be text"}};origin:=current;current,err=catalog.resolve(current,raw);if err!=nil{return Annotation{},false,wrap(OpenAPI,"native.resource",jsonProjectionKey(origin.resource,origin.pointer)+"/$ref",err)}
        }
    default:return Annotation{},false,&Error{Code:"native.project",Format:OpenAPI,Message:"unknown Schema Object annotation selection mode"}
    }
    if err:=walker.audit(target);err!=nil{return Annotation{},false,err};if walker.unconsumed.resource!=""{candidate,_,err:=openAPISchemaAnnotation(walker.unconsumed);if err!=nil{return Annotation{},false,err};return Annotation{},false,&Error{Code:"native.refinement",Format:OpenAPI,Pointer:candidate.Pointer,Message:"reachable nested Schema Object x-refine annotation is not composed; annotate the selected or directly bound operation Schema Object instead"}}
    return annotation,hasAnnotation,nil
}

func (w *openAPICatalogAnnotationWalker)limit(node jsonProjectionNode,message string)error{return &Error{Code:"native.limit",Format:OpenAPI,Pointer:jsonProjectionKey(node.resource,node.pointer),Message:message}}
func (w *openAPICatalogAnnotationWalker)charge(size int,node jsonProjectionNode)error{if size<0||size>w.remainingBytes{return w.limit(node,"Schema Object annotation audit retained paths exceed the deterministic byte limit")};w.remainingBytes-=size;return nil}
func (w *openAPICatalogAnnotationWalker)take(node jsonProjectionNode)error{if w.remaining<1{return w.limit(node,"Schema Object annotation audit exceeds the deterministic aggregate work limit")};w.remaining--;return w.charge(len(node.resource)+1+len(node.pointer),node)}
func (w *openAPICatalogAnnotationWalker)preflight(count int,node jsonProjectionNode)error{if count<0||count>w.remaining{return w.limit(node,"Schema Object annotation audit exceeds the deterministic aggregate work limit")};return nil}
func (w *openAPICatalogAnnotationWalker)marked(seen map[string]map[string]bool,node jsonProjectionNode)bool{pointers:=seen[node.resource];return pointers!=nil&&pointers[node.pointer]}
func (w *openAPICatalogAnnotationWalker)mark(seen map[string]map[string]bool,node jsonProjectionNode)bool{pointers:=seen[node.resource];if pointers==nil{pointers=map[string]bool{};seen[node.resource]=pointers};if pointers[node.pointer]{return true};pointers[node.pointer]=true;return false}
func (w *openAPICatalogAnnotationWalker)isConsumed(node jsonProjectionNode)bool{return node.resource==w.consumedResource&&node.pointer==w.consumedPointer}
func (w *openAPICatalogAnnotationWalker)rememberUnconsumed(node jsonProjectionNode){if w.unconsumed.resource==""||node.resource<w.unconsumed.resource||node.resource==w.unconsumed.resource&&node.pointer<w.unconsumed.pointer{w.unconsumed=openAPINode{resource:node.resource,pointer:node.pointer,node:node.node}}}

func (w *openAPICatalogAnnotationWalker)child(parent jsonProjectionNode,suffix string)(jsonProjectionNode,error){length:=len(parent.pointer)+len(suffix);if length<len(parent.pointer){return jsonProjectionNode{},w.limit(parent,"Schema Object annotation audit retained paths exceed the deterministic byte limit")};if err:=w.charge(len(parent.resource)+1+length,parent);err!=nil{return jsonProjectionNode{},err};pointer:=parent.pointer+suffix;child,ok:=w.catalog.locations[jsonProjectionKey(parent.resource,pointer)];if !ok{return jsonProjectionNode{},&Error{Code:"native.enforcement",Format:OpenAPI,Pointer:jsonProjectionKey(parent.resource,pointer),Message:"logical Schema Object catalog omitted an actual schema edge"}};return child,nil}

func (w *openAPICatalogAnnotationWalker)audit(current jsonProjectionNode)error{
    if w.marked(w.auditSeen,current){return nil};if err:=w.take(current);err!=nil{return err};w.mark(w.auditSeen,current);kind:=schemajson.KindName(current.node.Kind());if kind=="boolean"{return nil};if kind!="object"{return &Error{Code:"native.enforcement",Format:OpenAPI,Pointer:jsonProjectionKey(current.resource,current.pointer),Message:"logical Schema Object catalog contains a non-schema node"}}
    if _,present:=current.node.Lookup("x-refine");present&&!w.isConsumed(current){w.rememberUnconsumed(current)}
    for _,name:=range []string{"additionalProperties","unevaluatedProperties","propertyNames","contains","items","additionalItems","unevaluatedItems","if","then","else","not","contentSchema"}{if _,ok:=current.node.Lookup(name);ok{child,err:=w.child(current,"/"+name);if err!=nil{return err};if err:=w.audit(child);err!=nil{return err}}}
    for _,name:=range []string{"$defs","definitions","properties","patternProperties","dependentSchemas"}{group,ok:=current.node.Lookup(name);if !ok||schemajson.KindName(group.Kind())!="object"{continue};if err:=w.preflight(group.MemberCount(),current);err!=nil{return err};for _,member:=range group.Members(){memberName,err:=member.Key.UTF8();if err!=nil{return &Error{Code:"native.refinement",Format:OpenAPI,Pointer:jsonProjectionKey(current.resource,current.pointer)+"/"+name,Message:"schema-position key is not Unicode scalar text"}};escapedLength:=openAPICatalogEscapedLength(memberName);if escapedLength<0||escapedLength>w.remainingBytes{return w.limit(current,"Schema Object annotation audit retained paths exceed the deterministic byte limit")};child,err:=w.child(current,"/"+name+"/"+escapePointer(memberName));if err!=nil{return err};if err:=w.audit(child);err!=nil{return err}}}
    for _,name:=range []string{"allOf","anyOf","oneOf","prefixItems"}{group,ok:=current.node.Lookup(name);if !ok||schemajson.KindName(group.Kind())!="array"{continue};if err:=w.preflight(group.ElementCount(),current);err!=nil{return err};for index:=range group.Elements(){child,err:=w.child(current,"/"+name+"/"+strconv.Itoa(index));if err!=nil{return err};if err:=w.audit(child);err!=nil{return err}}}
    for _,keyword:=range []string{"$ref","$dynamicRef"}{reference,ok:=current.node.Lookup(keyword);if !ok{continue};raw,valid:=nodeString(reference);if !valid{return &Error{Code:"native.refinement",Format:OpenAPI,Pointer:jsonProjectionKey(current.resource,current.pointer)+"/"+keyword,Message:"Schema Object reference must be text"}};target,err:=w.catalog.resolve(current,raw);if err!=nil{return wrap(OpenAPI,"native.resource",jsonProjectionKey(current.resource,current.pointer)+"/"+keyword,err)};if err:=w.audit(target);err!=nil{return err};if keyword=="$dynamicRef"{if err:=w.auditDynamicOverrides(current,raw);err!=nil{return err}}}
    return nil
}

func openAPICatalogEscapedLength(text string)int{length:=len(text);for i:=0;i<len(text);i++{if text[i]=='~'||text[i]=='/'{if length==int(^uint(0)>>1){return -1};length++}};return length}

func (w *openAPICatalogAnnotationWalker)auditDynamicOverrides(current jsonProjectionNode,raw string)error{if len(raw)>w.remainingBytes{return w.limit(current,"Schema Object annotation audit retained paths exceed the deterministic byte limit")};parsed,err:=url.Parse(raw);if err!=nil{return &Error{Code:"native.refinement",Format:OpenAPI,Pointer:jsonProjectionKey(current.resource,current.pointer)+"/$dynamicRef",Message:"dynamic Schema Object reference URI is invalid"}};anchor:=parsed.Fragment;if anchor==""||strings.HasPrefix(anchor,"/"){return nil};if w.dynamicScanned[anchor]{return nil};if err:=w.charge(len(anchor),current);err!=nil{return err};w.dynamicScanned[anchor]=true
    count:=len(w.catalog.locations);rounds:=0;for width:=count;width>1;width=(width+1)/2{rounds++};sortWork:=count*rounds;if count>0&&sortWork/count!=rounds||sortWork>w.remaining-count{return w.limit(current,"Schema Object annotation audit exceeds the deterministic aggregate work limit")};sliceBytes:=count*16;if count>0&&sliceBytes/count!=16{return w.limit(current,"Schema Object annotation audit retained paths exceed the deterministic byte limit")};if err:=w.charge(sliceBytes,current);err!=nil{return err};w.remaining-=sortWork
    keys:=make([]string,0,count);for key:=range w.catalog.locations{keys=append(keys,key)};sort.Strings(keys);for _,key:=range keys{if w.remaining<1{return w.limit(current,"Schema Object annotation audit exceeds the deterministic aggregate work limit")};w.remaining--;candidate:=w.catalog.locations[key];declared,ok:=candidate.node.Lookup("$dynamicAnchor");if !ok{continue};name,valid:=nodeString(declared);if valid&&name==anchor{if err:=w.audit(candidate);err!=nil{return err}}};return nil
}
