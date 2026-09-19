package native

import (
    "crypto/sha256"
    "encoding/json"
    "fmt"
    "net/url"
    "sort"
    "strings"
    "unicode/utf8"

    "goforge.dev/refine/schemajson"
)

// openAPIOracleView is a private validation representation, never an export.
// One container per physical resource keeps no-ID schemas in the same dynamic
// resource scope. Only known schema positions move; embedded instance data is
// copied as data. Callers must use selector rather than an original pointer.
type openAPIOracleView struct {
    resources []Resource
    aliases []Resource
    selectors map[string]ResourceSelector
}

func (v *openAPIOracleView)selector(original ResourceSelector)(ResourceSelector,error){
    selected,ok:=v.selectors[jsonProjectionKey(original.Resource,original.Pointer)]
    if !ok{return ResourceSelector{},&Error{Code:"native.root",Format:OpenAPI,Message:"validation selector is not an indexed Schema Object"}}
    selected.TypeName=original.TypeName;return selected,nil
}

type openAPIOracleWriter struct {catalog *jsonProjectionCatalog;view *openAPIOracleView;bytes int;work int;limit int}
func openAPIOracleLimit()error{return &Error{Code:"native.limit",Format:OpenAPI,Message:"OpenAPI oracle view exceeds its aggregate materialization limits"}}
func (w *openAPIOracleWriter)write(out *strings.Builder,text string)error{if len(text)>w.limit-w.bytes{return openAPIOracleLimit()};w.bytes+=len(text);out.WriteString(text);return nil}
func (w *openAPIOracleWriter)quoted(out *strings.Builder,text string)error{
    // Match encoding/json's escaped size before it can allocate an expanded
    // identifier. The materialized output and retained selector index each
    // have their own aggregate 16 MiB ceiling.
    size:=2;remaining:=w.limit-w.bytes;if size>remaining{return openAPIOracleLimit()}
    for len(text)>0{r,n:=utf8.DecodeRuneInString(text);amount:=n;switch{case r==utf8.RuneError&&n==1:amount=6;case r=='"'||r=='\\'||r=='\b'||r=='\f'||r=='\n'||r=='\r'||r=='\t':amount=2;case r<0x20||r=='<'||r=='>'||r=='&'||r=='\u2028'||r=='\u2029':amount=6};if amount>remaining-size{return openAPIOracleLimit()};size+=amount;text=text[n:]}
    return nil
}
func (w *openAPIOracleWriter)quote(out *strings.Builder,text string)error{if err:=w.quoted(out,text);err!=nil{return err};encoded,_:=json.Marshal(text);return w.write(out,string(encoded))}

func oracleSchemaSingle(name string)bool{switch name{case "additionalProperties","unevaluatedProperties","propertyNames","contains","items","additionalItems","unevaluatedItems","if","then","else","not","contentSchema":return true};return false}
func oracleSchemaCollection(name string)string{switch name{case "$defs","definitions","properties","patternProperties","dependentSchemas":return "object";case "allOf","anyOf","oneOf","prefixItems":return "array"};return ""}

// Physical prefix containment alone is insufficient: an independently typed
// reference can identify a schema below an otherwise opaque data member.
func oracleSchemaParent(catalog *jsonProjectionCatalog,node jsonProjectionNode,containers map[string]bool)(jsonProjectionNode,bool,error){
    if node.pointer==""{return jsonProjectionNode{},false,nil};slash:=strings.LastIndexByte(node.pointer,'/');parentPointer:=node.pointer[:slash];token:=node.pointer[slash+1:];parent,found:=catalog.locations[jsonProjectionKey(node.resource,parentPointer)];direct:=found&&oracleSchemaSingle(token)
    if parentPointer!=""{before:=strings.LastIndexByte(parentPointer,'/');containerName:=parentPointer[before+1:];grand,exists:=catalog.locations[jsonProjectionKey(node.resource,parentPointer[:before])];kind:=oracleSchemaCollection(containerName);if exists&&kind!=""{containerKey:=jsonProjectionKey(node.resource,parentPointer);valid,cached:=containers[containerKey];if !cached{container,ok:=grand.node.Lookup(containerName);valid=ok&&schemajson.KindName(container.Kind())==kind;containers[containerKey]=valid};if valid{if direct{return jsonProjectionNode{},false,&Error{Code:"native.enforcement",Format:OpenAPI,Message:"overlapping schema containment contexts cannot be relocated exactly"}};return grand,true,nil}}}
    return parent,direct,nil
}

func newOpenAPIOracleView(catalog *jsonProjectionCatalog)(*openAPIOracleView,error){return buildOpenAPIOracleView(catalog,schemajson.DefaultBytes)}
func buildOpenAPIOracleView(catalog *jsonProjectionCatalog,byteLimit int)(*openAPIOracleView,error){
    if catalog==nil||byteLimit<1||byteLimit>schemajson.DefaultBytes{return nil,openAPIOracleLimit()}
    view:=&openAPIOracleView{selectors:map[string]ResourceSelector{}}
    keys:=make([]string,0,len(catalog.locations));for key:=range catalog.locations{keys=append(keys,key)};sort.Strings(keys)
    roots:=map[string][]jsonProjectionNode{};retained:=0;containers:=map[string]bool{}
    // A physical parent sorts before its descendants. Map each node once,
    // using the parent's already-mapped selector; cache collection lookups so
    // a wide object's linear Lookup is not repeated for every property.
    for _,key:=range keys{
        node:=catalog.locations[key];parent,child,err:=oracleSchemaParent(catalog,node,containers);if err!=nil{return nil,err};mapped:=ResourceSelector{};suffix:=""
        if child{var exists bool;mapped,exists=view.selectors[jsonProjectionKey(parent.resource,parent.pointer)];if !exists{return nil,&Error{Code:"native.enforcement",Format:OpenAPI,Message:"oracle parent was not indexed before its child"}};suffix=strings.TrimPrefix(node.pointer,parent.pointer)}else{pointer:="";if node.pointer!=""{sum:=sha256.Sum256([]byte(jsonProjectionPhysicalIdentity(node.resource,node.pointer)));pointer=fmt.Sprintf("/$defs/s%x",sum)};mapped=ResourceSelector{Resource:node.resource,Pointer:pointer};roots[node.resource]=append(roots[node.resource],node)}
        size:=len(key)+len(mapped.Resource)+len(mapped.Pointer)+len(suffix)
        if size>schemajson.DefaultBytes-retained{return nil,openAPIOracleLimit()};retained+=size
        mapped.Pointer+=suffix;view.selectors[key]=mapped
    }
    // Relocating overlapping independent roots would also rewrite data in the
    // outer root or duplicate a resource ID. Reject that unsupported embedding
    // instead of choosing one interpretation according to reference order.
    for uri,items:=range roots{for _,root:=range items{for pointer:=root.pointer;pointer!="";{slash:=strings.LastIndexByte(pointer,'/');pointer=pointer[:slash];if _,exists:=catalog.locations[jsonProjectionKey(uri,pointer)];exists{return nil,&Error{Code:"native.enforcement",Format:OpenAPI,Message:"independently referenced schemas overlap opaque data positions"}}}}}
    writer:=&openAPIOracleWriter{catalog:catalog,view:view,limit:byteLimit}
    uris:=make([]string,0,len(roots));for uri:=range roots{uris=append(uris,uri)};sort.Strings(uris)
    for _,uri:=range uris{
        var out strings.Builder;items:=roots[uri]
        if len(items)==1&&items[0].pointer==""{if err:=writer.schema(&out,items[0],"");err!=nil{return nil,err}}else{
            dialect:=openAPIBaseDialect
            if document,ok:=catalog.documents[uri];ok{if declared,ok:=document.Root().Lookup("jsonSchemaDialect");ok{dialect,_=nodeString(declared)}}
            inherited:="";for _,root:=range items{if _,ownID:=root.node.Lookup("$id");ownID{continue};candidate:=strings.TrimSuffix(root.dialect,"#");if candidate==""{candidate=openAPIBaseDialect};if inherited!=""&&inherited!=candidate{return nil,&Error{Code:"native.enforcement",Format:OpenAPI,Message:"one physical resource contains incompatible inherited schema dialects"}};inherited=candidate};if inherited!=""{dialect=inherited}
            if err:=writer.write(&out,`{"$id":`);err!=nil{return nil,err};if err:=writer.quote(&out,uri);err!=nil{return nil,err};if err:=writer.write(&out,`,"$schema":`);err!=nil{return nil,err};if err:=writer.quote(&out,dialect);err!=nil{return nil,err};if err:=writer.write(&out,`,"$defs":{`);err!=nil{return nil,err}
            for i,root:=range items{if i>0{if err:=writer.write(&out,",");err!=nil{return nil,err}};mapped:=view.selectors[jsonProjectionKey(root.resource,root.pointer)];name:=strings.TrimPrefix(mapped.Pointer,"/$defs/");if err:=writer.quote(&out,name);err!=nil{return nil,err};if err:=writer.write(&out,":");err!=nil{return nil,err};if err:=writer.schema(&out,root,"");err!=nil{return nil,err}}
            if err:=writer.write(&out,"}}");err!=nil{return nil,err}
        }
        view.resources=append(view.resources,Resource{URI:uri,Source:out.String()})
    }
    identities:=make([]string,0,len(catalog.roots));for identity,root:=range catalog.roots{if _,physical:=catalog.documents[identity];physical{continue};if _,schema:=catalog.locations[jsonProjectionKey(root.resource,root.pointer)];schema{identities=append(identities,identity)}};sort.Strings(identities)
    for _,identity:=range identities{var out strings.Builder;if err:=writer.schema(&out,catalog.roots[identity],identity);err!=nil{return nil,err};view.aliases=append(view.aliases,Resource{URI:identity,Source:out.String()})}
    return view,nil
}

func (w *openAPIOracleWriter)reference(current jsonProjectionNode,keyword,raw string)(string,error){
    target,err:=w.catalog.resolve(current,raw);if err!=nil{return "",openAPIProjectionCatalogError(current.pointer,err)}
    if keyword=="$dynamicRef"{base,err:=url.Parse(current.base);if err!=nil{return "",err};relative,err:=url.Parse(raw);if err!=nil{return "",err};resolved:=base.ResolveReference(relative);if resolved.Fragment!=""&&!strings.HasPrefix(resolved.Fragment,"/"){return resolved.String(),nil}}
    mapped,err:=w.view.selector(ResourceSelector{Resource:target.resource,Pointer:target.pointer});if err!=nil{return "",err}
    identity,err:=url.Parse(mapped.Resource);if err!=nil{return "",err};identity.Fragment=mapped.Pointer;return identity.String(),nil
}

func (w *openAPIOracleWriter)schema(out *strings.Builder,current jsonProjectionNode,alias string)error{
    w.work++;if w.work>schemajson.DefaultNodes{return openAPIOracleLimit()}
    if schemajson.KindName(current.node.Kind())!="object"{return w.write(out,current.node.Raw())}
    if err:=w.write(out,"{");err!=nil{return err};first:=true;hasID:=false;hasDialect:=false
    member:=func(name string)error{if !first{if err:=w.write(out,",");err!=nil{return err}};first=false;if err:=w.quote(out,name);err!=nil{return err};return w.write(out,":")}
    for _,item:=range current.node.Members(){name,_:=item.Key.UTF8();if err:=member(name);err!=nil{return err}
        switch name{
        case "$id":hasID=true;identity:=current.base;if alias!=""{identity=alias};if err:=w.quote(out,identity);err!=nil{return err}
        case "$schema":hasDialect=true;if err:=w.write(out,item.Value.Raw());err!=nil{return err}
        case "$ref","$dynamicRef":raw,ok:=nodeString(item.Value);if !ok{return &Error{Code:"native.enforcement",Format:OpenAPI,Message:"schema reference must be text"}};reference,err:=w.reference(current,name,raw);if err!=nil{return err};if err:=w.quote(out,reference);err!=nil{return err}
        default:
            if err:=w.schemaMember(out,current,name,item.Value);err!=nil{return err}
        }
    }
    if alias!=""&&!hasID{if err:=member("$id");err!=nil{return err};if err:=w.quote(out,alias);err!=nil{return err}}
    if !hasDialect&&(hasID||alias!=""||current.pointer==""){if err:=member("$schema");err!=nil{return err};dialect:=current.dialect;if dialect==""{dialect=openAPIBaseDialect};if err:=w.quote(out,dialect);err!=nil{return err}}
    return w.write(out,"}")
}

func (w *openAPIOracleWriter)schemaMember(out *strings.Builder,parent jsonProjectionNode,name string,node schemajson.Node)error{
    pointer:=parent.pointer+"/"+escapePointer(name)
    if oracleSchemaSingle(name){if child,ok:=w.catalog.locations[jsonProjectionKey(parent.resource,pointer)];ok{return w.schema(out,child,"")}}
    kind:=oracleSchemaCollection(name)
    if kind==""||schemajson.KindName(node.Kind())!=kind{return w.write(out,node.Raw())}
    count:=node.MemberCount();if kind=="array"{count=node.ElementCount()};if count>schemajson.DefaultNodes-w.work{return openAPIOracleLimit()}
    if kind=="object"{if err:=w.write(out,"{");err!=nil{return err};for i,item:=range node.Members(){if i>0{if err:=w.write(out,",");err!=nil{return err}};key,_:=item.Key.UTF8();if err:=w.quote(out,key);err!=nil{return err};if err:=w.write(out,":");err!=nil{return err};child,ok:=w.catalog.locations[jsonProjectionKey(parent.resource,pointer+"/"+escapePointer(key))];if !ok{return &Error{Code:"native.enforcement",Format:OpenAPI,Message:"oracle view encountered an unindexed schema child"}};if err:=w.schema(out,child,"");err!=nil{return err}};return w.write(out,"}")}
    if err:=w.write(out,"[");err!=nil{return err};for i,item:=range node.Elements(){_ = item;if i>0{if err:=w.write(out,",");err!=nil{return err}};child,ok:=w.catalog.locations[jsonProjectionKey(parent.resource,fmt.Sprintf("%s/%d",pointer,i))];if !ok{return &Error{Code:"native.enforcement",Format:OpenAPI,Message:"oracle view encountered an unindexed schema child"}};if err:=w.schema(out,child,"");err!=nil{return err}};return w.write(out,"]")
}
