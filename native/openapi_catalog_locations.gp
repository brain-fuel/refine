package native

import (
    "net/url"
    "sort"
    "strings"

    "goforge.dev/refine/schemajson"
)

// Walk only schema edges in the checked catalog. Logical references and
// dynamic-anchor candidates share exactly the resolver used by validation;
// examples and other instance-valued positions remain opaque.
func (p *Project) walkOpenAPICatalogLocations(resources []Resource,visit func(string,string,schemajson.Node)error)error{
    catalog,err:=newOpenAPIProjectionCatalog(resources,p.EntryResource());if err!=nil{return err}
    keys:=make([]string,0,len(catalog.locations));for key:=range catalog.locations{keys=append(keys,key)};sort.Strings(keys)
    children:=map[string][]string{};dynamic:=map[string][]string{};containers:=map[string]bool{}
    for _,key:=range keys{node:=catalog.locations[key];parent,child,err:=oracleSchemaParent(catalog,node,containers);if err!=nil{return err};if child{parentKey:=jsonProjectionKey(parent.resource,parent.pointer);children[parentKey]=append(children[parentKey],key)};if anchor,ok:=node.node.Lookup("$dynamicAnchor");ok{if name,valid:=nodeString(anchor);valid{dynamic[name]=append(dynamic[name],key)}}}
    pending:=[]string{};seen:=map[string]bool{};work:=0;retained:=0
    enqueue:=func(key string)error{work++;if work>schemajson.DefaultNodes{return openAPIOracleLimit()};if seen[key]{return nil};if len(key)>schemajson.DefaultBytes-retained{return openAPIOracleLimit()};retained+=len(key);if _,ok:=catalog.locations[key];!ok{return &Error{Code:"native.enforcement",Format:OpenAPI,Pointer:key,Message:"schema keyword seed is absent from the checked catalog"}};seen[key]=true;pending=append(pending,key);return nil}
    if p.HasPayloadRoot(){if err:=enqueue(jsonProjectionKey(p.root.Resource,p.root.Pointer));err!=nil{return err}}
    if p.openAPIOperations!=nil{for _,operation:=range p.openAPIOperations.catalog.Operations{for _,part:=range operation.RequestParts{if err:=enqueue(jsonProjectionKey(part.Resource,part.Pointer));err!=nil{return err}};for _,response:=range operation.Responses{for _,part:=range response.Parts{if err:=enqueue(jsonProjectionKey(part.Resource,part.Pointer));err!=nil{return err}}}}}
    // Explicit standalone JSON Schema resources are complete schema inputs.
    for _,resource:=range resources{doc:=catalog.documents[resource.URI];if _,ok:=doc.Root().Lookup("$schema");ok{if _,api:=doc.Root().Lookup("openapi");!api{if err:=enqueue(jsonProjectionKey(resource.URI,""));err!=nil{return err}}}}
    dynamicSeen:=map[string]bool{}
    for index:=0;index<len(pending);index++{key:=pending[index];node:=catalog.locations[key];if schemajson.KindName(node.node.Kind())=="boolean"{continue};if err:=visit(node.resource,node.pointer,node.node);err!=nil{return err};for _,child:=range children[key]{if err:=enqueue(child);err!=nil{return err}}
        for _,keyword:=range []string{"$ref","$dynamicRef"}{reference,ok:=node.node.Lookup(keyword);if !ok{continue};raw,valid:=nodeString(reference);if !valid{return &Error{Code:"native.enforcement",Format:OpenAPI,Pointer:key,Message:"schema reference is not text"}};target,err:=catalog.resolve(node,raw);if err!=nil{return err};if err:=enqueue(jsonProjectionKey(target.resource,target.pointer));err!=nil{return err};if keyword=="$dynamicRef"{parsed,err:=url.Parse(raw);if err!=nil{return err};anchor:=parsed.Fragment;if anchor!=""&&!strings.HasPrefix(anchor,"/")&&!dynamicSeen[anchor]{dynamicSeen[anchor]=true;for _,candidate:=range dynamic[anchor]{if err:=enqueue(candidate);err!=nil{return err}}}}}
    };return nil
}
