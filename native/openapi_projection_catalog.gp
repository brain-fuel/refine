package native

import (
    "errors"
    "fmt"
    "net/url"
    "sort"
    "strings"

    "goforge.dev/refine/provenance"
    "goforge.dev/refine/schemajson"
)

type openAPIProjectionPending struct{cause error}
func (e *openAPIProjectionPending)Error()string{return e.cause.Error()}
func (e *openAPIProjectionPending)Unwrap()error{return e.cause}

func openAPIProjectionCatalogError(pointer string,err error)error{var problem *Error;if errors.As(err,&problem)&&problem.Code=="native.limit"{return &Error{Code:"native.limit",Format:OpenAPI,Message:"Schema Object catalog exceeds its deterministic limits",Cause:err}};return wrap(OpenAPI,"native.projection",pointer,err)}

// newOpenAPIProjectionCatalog indexes Schema Objects, not the enclosing API
// document or its examples. Wrapper references are interpreted by the OpenAPI
// root index; references inside those roots use the shared JSON Schema resolver.
// Inputs are exact JSON resources, after the existing bounded YAML conversion.
func newOpenAPIProjectionCatalog(resources []Resource,entry string)(*jsonProjectionCatalog,error){
    catalog,err:=newJSONProjectionDocuments(resources);if err!=nil{return nil,openAPIProjectionCatalogError(entry,err)}
    entryDoc,ok:=catalog.documents[entry];if !ok{return nil,&Error{Code:"native.resource",Format:OpenAPI,Pointer:entry,Message:"OpenAPI entry resource is absent"}}
    versionNode,ok:=entryDoc.Root().Lookup("openapi");version,text:=nodeString(versionNode)
    if !ok||!text||!strings.HasPrefix(version,"3.1.")&&!strings.HasPrefix(version,"3.2."){return nil,&Error{Code:"native.projection",Format:OpenAPI,Pointer:entry,Message:"logical Schema Object catalogs require OpenAPI 3.1 or 3.2"}}
    inputs:=make([]provenance.OpenAPIResource,len(resources));roles:=map[string]provenance.OpenAPIResourceRole{}
    for i,resource:=range resources{
        doc:=catalog.documents[resource.URI];role:=provenance.OpenAPIFragment
        if _,document:=doc.Root().Lookup("openapi");document{role=provenance.OpenAPIDocument}else if _,schema:=doc.Root().Lookup("$schema");schema{role=provenance.OpenAPISchema}
        roles[resource.URI]=role
        inputs[i]=provenance.OpenAPIResource{URI:resource.URI,Source:[]byte(resource.Source),Syntax:provenance.OpenAPIJSON,Role:role}
        // Physical document roots establish pointer bases, but are not placed
        // in locations unless a typed schema edge actually identifies them.
        if err:=catalog.chargeIdentifier(resource.URI);err!=nil{return nil,openAPIProjectionCatalogError("",err)}
        if err:=catalog.registerRoot(resource.URI,jsonProjectionNode{resource:resource.URI,node:doc.Root(),base:resource.URI});err!=nil{return nil,openAPIProjectionCatalogError("",err)}
    }
    roots,err:=provenance.IndexOpenAPISchemaRoots(inputs,provenance.OpenAPIOptions{EntryResource:entry});if err!=nil{return nil,wrap(OpenAPI,"native.projection",entry,err)}
    for _,root:=range roots{
        doc,exists:=catalog.documents[root.Resource];if !exists{return nil,&Error{Code:"native.resource",Format:OpenAPI,Pointer:root.Resource,Message:"indexed schema resource is absent"}}
        node,err:=doc.At(root.Pointer);if err!=nil{return nil,wrap(OpenAPI,"native.projection",root.Pointer,err)}
        if err:=indexOpenAPIProjectionRoot(catalog,jsonProjectionNode{resource:root.Resource,pointer:root.Pointer,node:node,base:root.Resource,dialect:root.Dialect});err!=nil{return nil,err}
    }
    if err:=completeOpenAPIProjectionReferences(catalog,roles);err!=nil{return nil,err}
    for _,node:=range catalog.locations{if node.dialect!=""&&strings.TrimSuffix(node.dialect,"#")!=openAPIBaseDialect&&strings.TrimSuffix(node.dialect,"#")!="https://json-schema.org/draft/2020-12/schema"{return nil,&Error{Code:"native.projection",Format:OpenAPI,Message:"unsupported Schema Object dialect in logical resource catalog"}}}
    return catalog,nil
}

func indexOpenAPIProjectionRoot(catalog *jsonProjectionCatalog,node jsonProjectionNode)error{
    key:=jsonProjectionKey(node.resource,node.pointer)
    if prior,exists:=catalog.locations[key];exists{if err:=checkIndexedJSONProjectionContext(node,prior);err!=nil{return openAPIProjectionCatalogError(node.pointer,err)};return nil}
    if err:=catalog.index(node,0);err!=nil{return openAPIProjectionCatalogError(node.pointer,err)}
    if node.pointer==""{return catalog.registerRoot(node.resource,catalog.locations[key])}
    return nil
}

// Resolve a fixed point because a physical Schema Object edge can introduce a
// previously unclassified fragment containing logical IDs referenced elsewhere.
// Unknown logical IDs are reported only after no more such roots can be found.
func completeOpenAPIProjectionReferences(catalog *jsonProjectionCatalog,roles map[string]provenance.OpenAPIResourceRole)error{
    processed:=map[string]bool{};work:=0
    for round:=0;round<=schemajson.DefaultDepth;round++{
        keys:=make([]string,0,len(catalog.locations));for key:=range catalog.locations{keys=append(keys,key)};sort.Strings(keys)
        before:=len(catalog.locations);var pending error
        for _,key:=range keys{
            current:=catalog.locations[key]
            for _,keyword:=range []string{"$ref","$dynamicRef"}{
                ref,exists:=current.node.Lookup(keyword);if !exists{continue}
                identity:=key+"/"+keyword;if processed[identity]{continue}
                work++;if work>schemajson.DefaultNodes{return &Error{Code:"native.limit",Format:OpenAPI,Message:"Schema Object reference indexing exceeds the aggregate work limit"}}
                raw,valid:=nodeString(ref);if !valid{return &Error{Code:"native.projection",Format:OpenAPI,Pointer:identity,Message:"schema reference must be text"}}
                err:=admitOpenAPIProjectionReference(catalog,roles,current,raw)
                if err!=nil{var unresolved *openAPIProjectionPending;if !errors.As(err,&unresolved){return err};if pending==nil{pending=unresolved.cause};continue}
                processed[identity]=true
            }
        }
        if pending==nil&&len(catalog.locations)==before{return nil}
        if len(catalog.locations)==before{return pending}
    }
    return &Error{Code:"native.limit",Format:OpenAPI,Message:"Schema Object reference indexing exceeds the deterministic depth limit"}
}

func admitOpenAPIProjectionReference(catalog *jsonProjectionCatalog,roles map[string]provenance.OpenAPIResourceRole,current jsonProjectionNode,raw string)error{
    base,err:=url.Parse(current.base);if err!=nil{return err};relative,err:=url.Parse(raw);if err!=nil{return err};resolved:=base.ResolveReference(relative);fragment:=resolved.Fragment;resolved.Fragment="";physical:=resolved.String()
    if doc,exists:=catalog.documents[physical];exists&&roles[physical]==provenance.OpenAPIFragment{
        pointer:=fragment;if pointer!=""&&!strings.HasPrefix(pointer,"/"){pointer=""}
        key:=jsonProjectionKey(physical,pointer)
        if prior,indexed:=catalog.locations[key];indexed{
            if err:=checkIndexedJSONProjectionContext(jsonProjectionNode{resource:physical,pointer:pointer,node:prior.node,base:physical,dialect:current.dialect},prior);err!=nil{return openAPIProjectionCatalogError(pointer,err)}
        }else{
            target,err:=doc.At(pointer);if err!=nil{return wrap(OpenAPI,"native.projection",physical,err)}
            if err:=indexOpenAPIProjectionRoot(catalog,jsonProjectionNode{resource:physical,pointer:pointer,node:target,base:physical,dialect:current.dialect});err!=nil{return err}
        }
    }
    target,err:=catalog.resolve(current,raw);if err!=nil{return &openAPIProjectionPending{cause:wrap(OpenAPI,"native.projection",current.pointer,err)}}
    if _,schema:=catalog.locations[jsonProjectionKey(target.resource,target.pointer)];!schema{return &Error{Code:"native.projection",Format:OpenAPI,Pointer:current.resource+"#"+current.pointer,Message:fmt.Sprintf("reference %q does not identify a Schema Object",raw)}}
    return nil
}
