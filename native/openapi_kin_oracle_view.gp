package native

import (
    "encoding/json"
    "net/url"
    "sort"
    "strconv"
    "strings"
    "unicode/utf8"

    "goforge.dev/refine/schemajson"
)

// openAPIKinOracleResources is a private structural-validation view. It keeps
// every OpenAPI wrapper, Schema Object annotation, and instance-valued member,
// changing only static $ref strings at positions proven by the shared catalog.
// The returned strings never replace or mutate the project's exact resources.
func openAPIKinOracleResources(catalog *jsonProjectionCatalog)([]Resource,error){return buildOpenAPIKinOracleResources(catalog,schemajson.DefaultBytes,schemajson.DefaultNodes)}

type openAPIKinRewriteIndex struct{
    refs map[string]map[string]string
    needed map[string]map[string]bool
    retained int
    work int
    byteLimit int
    workLimit int
}

func openAPIKinOracleLimit()error{return &Error{Code:"native.limit",Format:OpenAPI,Message:"OpenAPI structural oracle view exceeds its aggregate materialization limits"}}
func (x *openAPIKinRewriteIndex)step()error{if x.work>=x.workLimit{return openAPIKinOracleLimit()};x.work++;return nil}
func (x *openAPIKinRewriteIndex)chargeRetained(amount int)error{if amount<0||amount>x.byteLimit-x.retained{return openAPIKinOracleLimit()};x.retained+=amount;return nil}
func (x *openAPIKinRewriteIndex)paths(resource string)(map[string]string,map[string]bool,error){refs:=x.refs[resource];needed:=x.needed[resource];if refs!=nil{return refs,needed,nil};if err:=x.chargeRetained(len(resource));err!=nil{return nil,nil,err};refs=map[string]string{};needed=map[string]bool{};x.refs[resource]=refs;x.needed[resource]=needed;return refs,needed,nil}
func (x *openAPIKinRewriteIndex)add(resource,pointer,replacement string)error{
    refs,needed,err:=x.paths(resource);if err!=nil{return err}
    if prior,exists:=refs[pointer];exists{if prior!=replacement{return &Error{Code:"native.enforcement",Format:OpenAPI,Pointer:resource+"#"+pointer,Message:"one Schema Object reference resolved to conflicting physical locations"}};return nil}
    if err:=x.chargeRetained(len(pointer)+len(replacement));err!=nil{return err};refs[pointer]=replacement
    for current:=pointer;;{if !needed[current]{if err:=x.step();err!=nil{return err};if err:=x.chargeRetained(len(current));err!=nil{return err};needed[current]=true};if current==""{break};slash:=strings.LastIndexByte(current,'/');if slash<0{return &Error{Code:"native.enforcement",Format:OpenAPI,Pointer:resource+"#"+pointer,Message:"indexed Schema Object reference has a malformed physical pointer"}};current=current[:slash]}
    return nil
}

func openAPIKinPhysicalReference(target jsonProjectionNode,remaining int)(string,error){
    // A fragment byte may become a three-byte percent escape. Admit that
    // conservative maximum before url.URL can allocate the escaped spelling.
    if remaining<0||len(target.resource)>remaining{return "",openAPIKinOracleLimit()};left:=remaining-len(target.resource);if target.pointer!=""{if left<1||len(target.pointer)>(left-1)/3{return "",openAPIKinOracleLimit()}}
    identity,err:=url.Parse(target.resource);if err!=nil{return "",err};identity.Fragment=target.pointer;return identity.String(),nil
}

func buildOpenAPIKinRewriteIndex(catalog *jsonProjectionCatalog,byteLimit,workLimit int)(*openAPIKinRewriteIndex,error){
    if catalog==nil||byteLimit<1||byteLimit>schemajson.DefaultBytes||workLimit<1||workLimit>schemajson.DefaultNodes{return nil,openAPIKinOracleLimit()}
    if len(catalog.locations)>workLimit{return nil,openAPIKinOracleLimit()}
    index:=&openAPIKinRewriteIndex{refs:map[string]map[string]string{},needed:map[string]map[string]bool{},byteLimit:byteLimit,workLimit:workLimit}
    keys:=make([]string,0,len(catalog.locations));for key:=range catalog.locations{keys=append(keys,key)};sort.Strings(keys)
    for _,key:=range keys{
        if err:=index.step();err!=nil{return nil,err};current:=catalog.locations[key];ref,exists:=current.node.Lookup("$ref");if !exists{continue};raw,ok:=nodeString(ref);if !ok{return nil,&Error{Code:"native.projection",Format:OpenAPI,Pointer:current.resource+"#"+current.pointer+"/$ref",Message:"Schema Object $ref must be text"}}
        target,err:=catalog.resolve(current,raw);if err!=nil{return nil,openAPIProjectionCatalogError(current.pointer+"/$ref",err)};replacement,err:=openAPIKinPhysicalReference(target,byteLimit-index.retained);if err!=nil{if _,bounded:=err.(*Error);bounded{return nil,err};return nil,wrap(OpenAPI,"native.projection",current.pointer+"/$ref",err)}
        if len(current.pointer)>byteLimit-index.retained-len("/$ref"){return nil,openAPIKinOracleLimit()};pointer:=current.pointer+"/$ref";if err:=index.add(current.resource,pointer,replacement);err!=nil{return nil,err}
    }
    return index,nil
}

type openAPIKinWriter struct{index *openAPIKinRewriteIndex;bytes int}
func (w *openAPIKinWriter)write(out *strings.Builder,text string)error{if len(text)>w.index.byteLimit-w.bytes{return openAPIKinOracleLimit()};w.bytes+=len(text);out.WriteString(text);return nil}
func (w *openAPIKinWriter)quote(out *strings.Builder,text string)error{
    size:=2;remaining:=w.index.byteLimit-w.bytes;if size>remaining{return openAPIKinOracleLimit()}
    for scan:=text;len(scan)>0;{r,n:=utf8.DecodeRuneInString(scan);amount:=n;switch{case r==utf8.RuneError&&n==1:amount=6;case r=='"'||r=='\\'||r=='\b'||r=='\f'||r=='\n'||r=='\r'||r=='\t':amount=2;case r<0x20||r=='<'||r=='>'||r=='&'||r=='\u2028'||r=='\u2029':amount=6};if amount>remaining-size{return openAPIKinOracleLimit()};size+=amount;scan=scan[n:]}
    encoded,_:=json.Marshal(text);return w.write(out,string(encoded))
}
func openAPIKinEscapedPointerSize(text string)int{size:=len(text);for i:=0;i<len(text);i++{if text[i]=='~'||text[i]=='/'{size++}};return size}
func (w *openAPIKinWriter)childPointer(parent,name string)(string,error){size:=len(parent)+1+openAPIKinEscapedPointerSize(name);if size>w.index.byteLimit-w.index.retained{return "",openAPIKinOracleLimit()};w.index.retained+=size;return parent+"/"+escapePointer(name),nil}

func (w *openAPIKinWriter)node(out *strings.Builder,resource,pointer string,node schemajson.Node)error{
    if err:=w.index.step();err!=nil{return err};if replacement,ok:=w.index.refs[resource][pointer];ok{return w.quote(out,replacement)};if !w.index.needed[resource][pointer]{return w.write(out,node.Raw())}
    switch schemajson.KindName(node.Kind()){
    case "object":
        count:=node.MemberCount();if count>w.index.workLimit-w.index.work{return openAPIKinOracleLimit()};if err:=w.write(out,"{");err!=nil{return err};for i,member:=range node.Members(){if i>0{if err:=w.write(out,",");err!=nil{return err}};name,utf8Err:=member.Key.UTF8();if utf8Err!=nil{remaining:=w.index.byteLimit-w.bytes;if remaining<2||member.Key.Length()>(remaining-2)/6{return openAPIKinOracleLimit()};encoded:=member.Key.Show();if err:=w.write(out,encoded);err!=nil{return err};if err:=w.write(out,":");err!=nil{return err};if err:=w.write(out,member.Value.Raw());err!=nil{return err};continue};if err:=w.quote(out,name);err!=nil{return err};if err:=w.write(out,":");err!=nil{return err};child,err:=w.childPointer(pointer,name);if err!=nil{return err};if err:=w.node(out,resource,child,member.Value);err!=nil{return err}};return w.write(out,"}")
    case "array":
        count:=node.ElementCount();if count>w.index.workLimit-w.index.work{return openAPIKinOracleLimit()};if err:=w.write(out,"[");err!=nil{return err};for i,element:=range node.Elements(){if i>0{if err:=w.write(out,",");err!=nil{return err}};child,err:=w.childPointer(pointer,strconv.Itoa(i));if err!=nil{return err};if err:=w.node(out,resource,child,element);err!=nil{return err}};return w.write(out,"]")
    default:return w.write(out,node.Raw())
    }
}

func buildOpenAPIKinOracleResources(catalog *jsonProjectionCatalog,byteLimit,workLimit int)([]Resource,error){
    if catalog==nil||byteLimit<1||byteLimit>schemajson.DefaultBytes||workLimit<1||workLimit>schemajson.DefaultNodes{return nil,openAPIKinOracleLimit()};total:=0;for _,document:=range catalog.documents{if len(document.Raw())>byteLimit-total{return nil,openAPIKinOracleLimit()};total+=len(document.Raw())}
    index,err:=buildOpenAPIKinRewriteIndex(catalog,byteLimit,workLimit);if err!=nil{return nil,err};uris:=make([]string,0,len(catalog.documents));for uri:=range catalog.documents{uris=append(uris,uri)};sort.Strings(uris)
    writer:=&openAPIKinWriter{index:index};out:=make([]Resource,0,len(uris));for _,uri:=range uris{document:=catalog.documents[uri];var source strings.Builder;if index.needed[uri]==nil{if err:=writer.write(&source,document.Raw());err!=nil{return nil,err}}else if err:=writer.node(&source,uri,"",document.Root());err!=nil{return nil,err};out=append(out,Resource{URI:uri,Source:source.String()})};return out,nil
}
