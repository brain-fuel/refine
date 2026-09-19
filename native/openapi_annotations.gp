package native

import (
    "fmt"
    "sort"
    "strings"

    "goforge.dev/refine/language"
    "goforge.dev/refine/schemajson"
)

// openAPISchemaAnnotation reads x-refine only from a proven Schema Object
// position supplied by the selected-root or checked-operation walkers. It does
// not recursively inspect examples, defaults, extension values, or arbitrary
// objects that merely resemble schemas.
func openAPISchemaAnnotation(node openAPINode)(Annotation,bool,error){
    if schemajson.KindName(node.node.Kind())!="object"{return Annotation{},false,nil}
    extension,ok:=node.node.Lookup("x-refine");if !ok{return Annotation{},false,nil}
    annotation,err:=jsonAnnotation(OpenAPI,node.pointer+"/x-refine",extension);if err!=nil{return Annotation{},false,err}
    if annotation.Root==""{return Annotation{},false,&Error{Code:"native.root",Format:OpenAPI,Pointer:annotation.Pointer+"/root",Message:"a Schema Object x-refine annotation must declare its closed payload root"}}
    return annotation,true,nil
}

func selectedOpenAPISchemaNode(resources map[string][]byte,selector ResourceSelector)(openAPINode,error){
    input,ok:=resources[selector.Resource];if !ok{return openAPINode{},&Error{Code:"native.resource",Format:OpenAPI,Pointer:selector.Resource,Message:"selected Schema Object resource is absent"}}
    limits,_:=limits(Options{});root,err:=parseYAML(input,limits);if err!=nil{return openAPINode{},wrap(OpenAPI,"native.syntax",selector.Resource,err)};document,err:=yamlToJSONDocument(root);if err!=nil{return openAPINode{},wrap(OpenAPI,"native.structure",selector.Resource,err)}
    prefix:="/components/schemas/";if !strings.HasPrefix(selector.Pointer,prefix){return openAPINode{},&Error{Code:"native.root",Format:OpenAPI,Pointer:selector.Pointer,Message:"selected OpenAPI root must be a Schema Object under /components/schemas"}}
    suffix:=strings.TrimPrefix(selector.Pointer,prefix);slash:=strings.IndexByte(suffix,'/');component:=suffix;if slash>=0{component=suffix[:slash]};if component==""{return openAPINode{},&Error{Code:"native.root",Format:OpenAPI,Pointer:selector.Pointer,Message:"selected OpenAPI component name is absent"}}
    startPointer:=prefix+component;start,err:=document.At(startPointer);if err!=nil{return openAPINode{},wrap(OpenAPI,"native.root",selector.Pointer,err)}
    var selected schemajson.Node;found:=false
    err=walkOpenAPISchemaChildren(start,startPointer,func(path string,node schemajson.Node)error{if path==selector.Pointer{selected=node;found=true};return nil});if err!=nil{return openAPINode{},wrap(OpenAPI,"native.root",selector.Pointer,err)}
    if !found{return openAPINode{},&Error{Code:"native.root",Format:OpenAPI,Pointer:selector.Pointer,Message:"selected pointer is not an actual Schema Object position"}}
    return openAPINode{resource:selector.Resource,pointer:selector.Pointer,node:selected},nil
}

func walkOpenAPISchemaChildren(node schemajson.Node,path string,visit func(string,schemajson.Node)error)error{
    kind:=schemajson.KindName(node.Kind());if kind!="object"&&kind!="boolean"{return fmt.Errorf("schema at %s is not an object or Boolean",path)};if err:=visit(path,node);err!=nil{return err};if kind=="boolean"{return nil}
    for _,name:=range []string{"additionalProperties","unevaluatedProperties","propertyNames","contains","items","additionalItems","unevaluatedItems","if","then","else","not","contentSchema"}{if child,ok:=node.Lookup(name);ok{if err:=walkOpenAPISchemaChildren(child,path+"/"+name,visit);err!=nil{return err}}}
    for _,name:=range []string{"$defs","definitions","properties","patternProperties","dependentSchemas"}{if children,ok:=node.Lookup(name);ok&&schemajson.KindName(children.Kind())=="object"{for _,member:=range children.Members(){memberName,err:=member.Key.UTF8();if err!=nil{return err};if err:=walkOpenAPISchemaChildren(member.Value,path+"/"+name+"/"+escapePointer(memberName),visit);err!=nil{return err}}}}
    for _,name:=range []string{"allOf","anyOf","oneOf","prefixItems"}{if children,ok:=node.Lookup(name);ok&&schemajson.KindName(children.Kind())=="array"{for index,child:=range children.Elements(){if err:=walkOpenAPISchemaChildren(child,fmt.Sprintf("%s/%s/%d",path,name,index),visit);err!=nil{return err}}}}
    return nil
}

func selectedOpenAPISchemaAnnotation(document *Document,resources map[string][]byte,selector ResourceSelector)(Annotation,bool,error){
    node,err:=selectedOpenAPISchemaNode(resources,selector);if err!=nil{return Annotation{},false,err};scoped,hasScoped,err:=openAPISchemaAnnotation(node);if err!=nil{return Annotation{},false,err}
    if hasScoped&&strings.HasPrefix(document.Version(),"3.0."){return Annotation{},false,&Error{Code:"native.enforcement",Format:OpenAPI,Pointer:scoped.Pointer,Message:"Schema Object x-refine annotations are supported for OpenAPI 3.1 and 3.2; OpenAPI 3.0 retains only the established document-level annotation"}}
    top,hasTop:=openAPIOperationsAnnotation(document);if hasTop&&hasScoped{return Annotation{},false,&Error{Code:"native.refinement",Format:OpenAPI,Pointer:scoped.Pointer,Message:"top-level and selected Schema Object x-refine annotations provide competing source authority"}}
    if !strings.HasPrefix(document.Version(),"3.0."){catalog,err:=openAPIAnnotationCatalog(resources,selector.Resource);if err!=nil{return Annotation{},false,err};selected,present,err:=resolveOpenAPICatalogSchemaAnnotation(catalog,node,openAPICatalogSelectedRoot);if err!=nil{return Annotation{},false,err};if present{if hasTop{return Annotation{},false,&Error{Code:"native.refinement",Format:OpenAPI,Pointer:selected.Pointer,Message:"top-level and selected Schema Object x-refine annotations provide competing source authority"}};return selected,true,nil};if hasTop&&top.Root!=""{return top,true,nil};return Annotation{},false,nil}
    consumed:="";if hasScoped{consumed=openAPISchemaNodeIdentity(node)};docs,err:=openAPIAnnotationDocuments(resources);if err!=nil{return Annotation{},false,err};if err:=auditReachableOpenAPISchemaAnnotations(node,docs,consumed);err!=nil{return Annotation{},false,err}
    if hasScoped{return scoped,true,nil};if hasTop&&top.Root!=""{return top,true,nil};return Annotation{},false,nil
}

func resolveOpenAPISchemaAnnotation(start openAPINode,docs map[string]schemajson.Document)(Annotation,bool,error){
    current:=start;seen:=map[string]bool{};annotation:=Annotation{};hasAnnotation:=false;consumed:=""
    for step:=0;step<64;step++{candidate,ok,err:=openAPISchemaAnnotation(current);if err!=nil{return Annotation{},false,err};if ok{annotation=candidate;hasAnnotation=true;consumed=openAPISchemaNodeIdentity(current);break};if schemajson.KindName(current.node.Kind())!="object"{break};reference,ok:=current.node.Lookup("$ref");if !ok{break};if _,rebased:=current.node.Lookup("$id");rebased{return Annotation{},false,openAPISchemaIDScopeError(current)};raw,ok:=nodeString(reference);if !ok{return Annotation{},false,&Error{Code:"native.refinement",Format:OpenAPI,Pointer:current.resource+"#"+current.pointer+"/$ref",Message:"Schema Object reference must be text"}};key:=openAPISchemaNodeIdentity(current);if seen[key]{return Annotation{},false,&Error{Code:"native.enforcement",Format:OpenAPI,Pointer:key,Message:"cyclic Schema Object annotation reference"}};seen[key]=true;resource,pointer,resolveErr:=resolveOpenAPIReference(current.resource,raw);if resolveErr!=nil{return Annotation{},false,resolveErr};document,exists:=docs[resource];if !exists{return Annotation{},false,&Error{Code:"native.resource",Format:OpenAPI,Pointer:resource,Message:"Schema Object annotation reference is absent from explicit resources"}};target,targetErr:=document.At(pointer);if targetErr!=nil{return Annotation{},false,wrap(OpenAPI,"native.resource",resource+"#"+pointer,targetErr)};current=openAPINode{resource:resource,pointer:pointer,node:target};if step==63{return Annotation{},false,&Error{Code:"native.limit",Format:OpenAPI,Pointer:start.resource+"#"+start.pointer,Message:"Schema Object annotation reference depth limit exceeded"}}}
    if err:=auditReachableOpenAPISchemaAnnotations(start,docs,consumed);err!=nil{return Annotation{},false,err};return annotation,hasAnnotation,nil
}

func openAPISchemaNodeIdentity(node openAPINode)string{return node.resource+"#"+node.pointer}

func openAPIAnnotationDocuments(resources map[string][]byte)(map[string]schemajson.Document,error){
    result:=map[string]schemajson.Document{};limits,_:=limits(Options{});for resource,input:=range resources{root,err:=parseYAML(input,limits);if err!=nil{return nil,wrap(OpenAPI,"native.syntax",resource,err)};document,err:=yamlToJSONDocument(root);if err!=nil{return nil,wrap(OpenAPI,"native.structure",resource,err)};result[resource]=document};return result,nil
}

func openAPIAnnotationCatalog(resources map[string][]byte,entry string)(*jsonProjectionCatalog,error){
    docs,err:=openAPIAnnotationDocuments(resources);if err!=nil{return nil,err};uris:=make([]string,0,len(docs));for uri:=range docs{uris=append(uris,uri)};sort.Strings(uris);canonical:=make([]Resource,0,len(uris));for _,uri:=range uris{canonical=append(canonical,Resource{URI:uri,Source:docs[uri].Raw()})};return newOpenAPIProjectionCatalog(canonical,entry)
}

func openAPISchemaIDScopeError(node openAPINode)error{return &Error{Code:"native.enforcement",Format:OpenAPI,Pointer:openAPISchemaNodeIdentity(node)+"/$id",Message:"Schema Object x-refine reference resolution does not guess a $id-rebased URI scope"}}

// auditReachableOpenAPISchemaAnnotations proves that every annotation in the
// selected schema closure is the one explicitly consumed by composition. The
// walker enters only Schema Object keyword positions and follows references
// only through the caller's immutable resource map; examples/defaults and
// extension payloads are never interpreted as schemas.
func auditReachableOpenAPISchemaAnnotations(start openAPINode,docs map[string]schemajson.Document,consumed string)error{
    seen:=map[string]bool{};work:=0
    var audit func(openAPINode)error
    audit=func(root openAPINode)error{key:=openAPISchemaNodeIdentity(root);if seen[key]{return nil};seen[key]=true;references:=[]openAPINode{};idScope:=openAPINode{}
        err:=walkOpenAPISchemaChildren(root.node,root.pointer,func(pointer string,node schemajson.Node)error{work++;if work>65536{return &Error{Code:"native.limit",Format:OpenAPI,Pointer:key,Message:"Schema Object annotation audit exceeds 65,536 reachable schema positions"}};current:=openAPINode{resource:root.resource,pointer:pointer,node:node};if _,ok:=node.Lookup("$id");ok&&idScope.resource==""{idScope=current};if annotation,ok,annotationErr:=openAPISchemaAnnotation(current);annotationErr!=nil{return annotationErr}else if ok&&openAPISchemaNodeIdentity(current)!=consumed{return &Error{Code:"native.refinement",Format:OpenAPI,Pointer:annotation.Pointer,Message:"reachable nested Schema Object x-refine annotation is not composed; annotate the selected or directly bound operation Schema Object instead"}};if reference,ok:=node.Lookup("$ref");ok{references=append(references,current);if _,ok:=nodeString(reference);!ok{return &Error{Code:"native.refinement",Format:OpenAPI,Pointer:openAPISchemaNodeIdentity(current)+"/$ref",Message:"Schema Object reference must be text"}}};return nil});if err!=nil{return err};if idScope.resource!=""&&len(references)>0{return openAPISchemaIDScopeError(idScope)}
        for _,current:=range references{reference,_:=current.node.Lookup("$ref");raw,_:=nodeString(reference);resource,pointer,err:=resolveOpenAPIReference(current.resource,raw);if err!=nil{return err};document,ok:=docs[resource];if !ok{return &Error{Code:"native.resource",Format:OpenAPI,Pointer:resource,Message:"Schema Object annotation audit reference is absent from explicit resources"}};target,err:=document.At(pointer);if err!=nil{return wrap(OpenAPI,"native.resource",resource+"#"+pointer,err)};if err:=audit(openAPINode{resource:resource,pointer:pointer,node:target});err!=nil{return err}}
        return nil}
    return audit(start)
}

type derivedOpenAPIAnnotationContext struct{used map[string]bool;sources map[string]bool;annotations []Annotation;openAPI30 bool;catalogBudget *openAPICatalogAnnotationBudget}

func (c *derivedOpenAPIAnnotationContext)use(annotation Annotation)(string,[]string,error){
    if c.openAPI30{return "",nil,&Error{Code:"native.enforcement",Format:OpenAPI,Pointer:annotation.Pointer,Message:"operation Schema Object x-refine annotations are supported for OpenAPI 3.1 and 3.2, not OpenAPI 3.0"}}
    base,_,present,err:=language.SplitReleasePolicyFooter(annotation.Source);if err!=nil{return "",nil,wrap(OpenAPI,"native.refinement",annotation.Pointer,err)};if present{return "",nil,&Error{Code:"native.refinement",Format:OpenAPI,Pointer:annotation.Pointer,Message:"Schema Object annotation modules cannot carry independent release-policy authority when composed into an operation project"}}
    program,err:=language.Compile(base);if err!=nil{return "",nil,wrap(OpenAPI,"native.refinement",annotation.Pointer,err)};key:=program.Formatted();if c.sources[key]{c.annotations=append(c.annotations,annotation);return annotation.Root,nil,nil}
    for _,declaration:=range program.Syntax().Types{if c.used[declaration.Name]{return "",nil,&Error{Code:"native.projection",Format:OpenAPI,Pointer:annotation.Pointer,Message:"Schema Object annotation type "+declaration.Name+" collides with the operation project's checked source"}}}
    for _,declaration:=range program.Syntax().Types{c.used[declaration.Name]=true};c.sources[key]=true;c.annotations=append(c.annotations,annotation);return annotation.Root,[]string{key},nil
}

func mergeScopedOpenAPIAnnotationMetadata(configured WireMetadata,annotations []Annotation)(WireMetadata,error){
    merged:=copyMetadata(configured)
    for _,annotation:=range annotations{if !annotation.HasMetadata{continue};incoming:=annotation.Metadata;if incoming.OpenAPI!=nil||incoming.Examples!=nil{return WireMetadata{},&Error{Code:"native.metadata",Format:OpenAPI,Pointer:annotation.Pointer+"/metadata",Message:"Schema Object metadata may configure wire types and limits, but operation bindings and example catalogs remain project-scoped"}}
        if incoming.PublicationNamespace!=""{if merged.PublicationNamespace!=""&&merged.PublicationNamespace!=incoming.PublicationNamespace{return WireMetadata{},scopedMetadataConflict(annotation,"publication namespace")};merged.PublicationNamespace=incoming.PublicationNamespace}
        if incoming.NumericExpansion!=0{if merged.NumericExpansion!=0&&merged.NumericExpansion!=incoming.NumericExpansion{return WireMetadata{},scopedMetadataConflict(annotation,"numeric expansion")};merged.NumericExpansion=incoming.NumericExpansion}
        for name,value:=range incoming.ExtraFields{if prior,ok:=merged.ExtraFields[name];ok&&prior!=value{return WireMetadata{},scopedMetadataConflict(annotation,"extra-field policy for "+name)};merged.ExtraFields[name]=value}
        for name,value:=range incoming.Scalars{if prior,ok:=merged.Scalars[name];ok&&prior!=value{return WireMetadata{},scopedMetadataConflict(annotation,"scalar policy for "+name)};merged.Scalars[name]=value}
        for name,value:=range incoming.Discriminators{if prior,ok:=merged.Discriminators[name];ok&&!metadataEqual(WireMetadata{Discriminators:map[string]Discriminator{name:prior}},WireMetadata{Discriminators:map[string]Discriminator{name:value}}){return WireMetadata{},scopedMetadataConflict(annotation,"discriminator policy for "+name)};copy:=copyMetadata(WireMetadata{Discriminators:map[string]Discriminator{name:value}});merged.Discriminators[name]=copy.Discriminators[name]}
    }
    return merged,nil
}

func scopedMetadataConflict(annotation Annotation,what string)error{return &Error{Code:"native.metadata",Format:OpenAPI,Pointer:annotation.Pointer+"/metadata",Message:"conflicting scoped "+what}}
