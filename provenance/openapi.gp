package provenance

import (
    "crypto/sha256"
    "errors"
    "fmt"
    "io"
    "net/url"
    "sort"
    "strconv"
    "strings"
    "unicode/utf8"

    yaml "github.com/oasdiff/yaml3"
    "goforge.dev/refine/language"
    "goforge.dev/refine/schemajson"
)

type OpenAPISyntax string
const ( OpenAPIJSON OpenAPISyntax="json"; OpenAPIYAML OpenAPISyntax="yaml" )
type OpenAPIResourceRole string
const ( OpenAPIDocument OpenAPIResourceRole="document"; OpenAPISchema OpenAPIResourceRole="schema"; OpenAPIFragment OpenAPIResourceRole="fragment" )

type OpenAPIResource struct { URI string; Source []byte; Syntax OpenAPISyntax; Role OpenAPIResourceRole; Dialect string }
type OpenAPIOptions struct { EntryResource string; Limits schemajson.Limits }
type OpenAPI struct { resources []OpenAPIResource; constraints []Constraint; constraintsByResource map[string][]Constraint }

func copyOpenAPIResource(in OpenAPIResource)OpenAPIResource{in.Source=append([]byte(nil),in.Source...);return in}
func (o *OpenAPI)Resources()[]OpenAPIResource{if o==nil{return nil};out:=make([]OpenAPIResource,len(o.resources));for i,item:=range o.resources{out[i]=copyOpenAPIResource(item)};return out}
func (o *OpenAPI)Constraints()[]Constraint{if o==nil{return nil};out:=make([]Constraint,len(o.constraints));for i,item:=range o.constraints{out[i]=copyConstraint(item)};return out}
func (o *OpenAPI)ConstraintSource()string{if o==nil{return ""};var source strings.Builder;for _,constraint:=range o.constraints{source.WriteString("type "+constraint.Name+" = "+constraint.Scope+" where "+constraint.Predicate+"\n")};return source.String()}
func (o *OpenAPI)AuditSource(source string)([]Finding,error){if o==nil{return nil,errors.New("OpenAPI provenance is absent")};return auditConstraintSource(o.constraints,source)}
func (o *OpenAPI)RecoverNative(name,source string)(string,error){if o==nil{return "",errors.New("OpenAPI provenance is absent")};return recoverConstraintNative(o.constraints,name,source)}
func (o *OpenAPI)ResourceConstraints(resource string)[]Constraint{if o==nil{return nil};owned:=o.constraintsByResource[resource];out:=make([]Constraint,len(owned));for i,item:=range owned{out[i]=copyConstraint(item)};return out}
func (o *OpenAPI)ResourceConstraintSource(resource string)string{if o==nil{return ""};var source strings.Builder;for _,constraint:=range o.constraintsByResource[resource]{source.WriteString("type "+constraint.Name+" = "+constraint.Scope+" where "+constraint.Predicate+"\n")};return source.String()}
func (o *OpenAPI)AuditResourceSource(resource,source string)([]Finding,error){if o==nil{return nil,errors.New("OpenAPI provenance is absent")};return auditConstraintSource(o.constraintsByResource[resource],source)}
func (o *OpenAPI)RecoverResourceNative(resource,name,source string)(string,error){if o==nil{return "",errors.New("OpenAPI provenance is absent")};return recoverConstraintNative(o.constraintsByResource[resource],name,source)}

type openAPIProvenanceDoc struct { resource OpenAPIResource; root *yaml.Node; json schemajson.Document; isJSON bool; lineStarts []int }
type openAPIProvenanceWalker struct { docs map[string]*openAPIProvenanceDoc; constraints []Constraint; constraintNames map[string]bool; seen map[string]bool; steps int; refs int; maxSteps int; maxDepth int; maxRefs int; retainedBytes int; maxRetainedBytes int; schemaRoot func(openAPIProvenanceNode,string)error; sourceBytes int; cardinalityExpansion int; openAPI30 bool; openAPI32 bool }
type openAPIProvenanceNode struct { doc *openAPIProvenanceDoc; node *yaml.Node; pointer string }

const openAPIProvenanceSourceBytes=16*1024*1024
const openAPIProvenanceRefs=100000
const openAPIProvenanceResources=1024
const openAPIBase="https://spec.openapis.org/oas/3.1/dialect/base"
const openAPI30Dialect="https://spec.openapis.org/oas/3.0/schema"
const jsonSchema202012="https://json-schema.org/draft/2020-12/schema"

func DiscoverOpenAPI(resources []OpenAPIResource,options OpenAPIOptions)(*OpenAPI,error){
    if len(resources)==0{return nil,&Error{Code:"openapi.resources",Message:"at least one explicit OpenAPI resource is required"}}
    if len(resources)>openAPIProvenanceResources{return nil,&Error{Code:"openapi.limit",Message:"explicit resource count limit exceeded"}}
    limits,err:=openAPIProvenanceLimits(options.Limits);if err!=nil{return nil,err};walker:=&openAPIProvenanceWalker{docs:map[string]*openAPIProvenanceDoc{},constraintNames:map[string]bool{},seen:map[string]bool{},maxSteps:limits.Nodes,maxDepth:limits.Depth}
    copied:=make([]OpenAPIResource,len(resources));uris:=map[string]bool{};totalBytes:=0;for i,item:=range resources{copy:=copyOpenAPIResource(item);if err:=validateOpenAPIResource(copy,limits);err!=nil{return nil,err};if uris[copy.URI]{return nil,&Error{Code:"openapi.resources",Pointer:copy.URI,Message:"duplicate resource URI"}};uris[copy.URI]=true;if len(copy.Source)>limits.Bytes-totalBytes{return nil,&Error{Code:"openapi.limit",Pointer:copy.URI,Message:"aggregate resource byte limit exceeded"}};totalBytes+=len(copy.Source);copied[i]=copy};for _,copy:=range copied{doc,err:=parseOpenAPIProvenanceResource(copy,limits);if err!=nil{return nil,err};walker.docs[copy.URI]=doc}
    entry:=options.EntryResource;if entry==""{return nil,&Error{Code:"openapi.resources",Message:"EntryResource is required"}};entryDoc,ok:=walker.docs[entry];if !ok||entryDoc.resource.Role!=OpenAPIDocument{return nil,&Error{Code:"openapi.resources",Pointer:entry,Message:"entry resource must be an explicit OpenAPI document"}}
    version,err:=openAPIVersion(entryDoc.root);if err!=nil{return nil,err};walker.openAPI30=strings.HasPrefix(version,"3.0.");if !walker.openAPI30&&!strings.HasPrefix(version,"3.1.")&&!strings.HasPrefix(version,"3.2."){return nil,&Error{Code:"openapi.version",Pointer:entry+"#/openapi",Message:"constraint provenance requires OpenAPI 3.0.x, 3.1.x, or 3.2.x"}};walker.openAPI32=strings.HasPrefix(version,"3.2.")
    dialect:=openAPIBase;if walker.openAPI30{dialect=openAPI30Dialect}else{if raw,ok:=yamlMappingValue(entryDoc.root,"jsonSchemaDialect");ok{dialect,err=yamlScalarString(raw);if err!=nil{return nil,&Error{Code:"openapi.dialect",Pointer:entry+"#/jsonSchemaDialect",Message:err.Error()}}};if err:=supportedOpenAPIDialect(dialect,entry+"#/jsonSchemaDialect");err!=nil{return nil,err}}
    if err:=walker.walkDocument(openAPIProvenanceNode{doc:entryDoc,node:entryDoc.root,pointer:""},dialect,0);err!=nil{return nil,err}
    for _,item:=range copied{if item.Role!=OpenAPISchema{continue};if walker.openAPI30{return nil,&Error{Code:"openapi.resources",Pointer:item.URI,Message:"OpenAPI 3.0 external Schema Objects must be explicit referenced fragments, not standalone JSON Schema resources"}};doc:=walker.docs[item.URI];dialect:=item.Dialect;if raw,ok:=yamlMappingValue(doc.root,"$schema");ok{declared,scalarErr:=yamlScalarString(raw);if scalarErr!=nil{return nil,&Error{Code:"openapi.dialect",Pointer:item.URI+"#/$schema",Message:scalarErr.Error()}};if dialect!=""&&strings.TrimSuffix(dialect,"#")!=strings.TrimSuffix(declared,"#"){return nil,&Error{Code:"openapi.dialect",Pointer:item.URI+"#/$schema",Message:"resource Dialect conflicts with its $schema"}};dialect=declared};if dialect==""{return nil,&Error{Code:"openapi.dialect",Pointer:item.URI,Message:"standalone schema resources require Dialect or a root $schema"}};if err:=supportedOpenAPIDialect(dialect,item.URI+"#/$schema");err!=nil{return nil,err};root:=openAPIProvenanceNode{doc:doc,node:doc.root,pointer:""};if err:=walker.walkSchema(root,dialect,item.URI,root,0);err!=nil{return nil,err}}
    sort.Slice(walker.constraints,func(i,j int)bool{if walker.constraints[i].Resource!=walker.constraints[j].Resource{return walker.constraints[i].Resource<walker.constraints[j].Resource};if walker.constraints[i].Pointer!=walker.constraints[j].Pointer{return walker.constraints[i].Pointer<walker.constraints[j].Pointer};return walker.constraints[i].Keyword<walker.constraints[j].Keyword})
    byResource:=map[string][]Constraint{};for _,constraint:=range walker.constraints{byResource[constraint.Resource]=append(byResource[constraint.Resource],constraint)}
    return &OpenAPI{resources:copied,constraints:walker.constraints,constraintsByResource:byResource},nil
}

func openAPIProvenanceLimits(in schemajson.Limits)(schemajson.Limits,error){if in.Bytes<0||in.Depth<0||in.Nodes<0{return in,&Error{Code:"openapi.limit",Message:"limits must be nonnegative"}};if in.Bytes==0{in.Bytes=schemajson.DefaultBytes};if in.Depth==0{in.Depth=schemajson.DefaultDepth};if in.Nodes==0{in.Nodes=schemajson.DefaultNodes};return in,nil}
func validateOpenAPIResource(item OpenAPIResource,limits schemajson.Limits)error{parsed,err:=url.Parse(item.URI);if err!=nil||!parsed.IsAbs()||parsed.Fragment!=""{return &Error{Code:"openapi.resources",Pointer:item.URI,Message:"resource URI must be absolute and contain no fragment"}};if item.Syntax!=OpenAPIJSON&&item.Syntax!=OpenAPIYAML{return &Error{Code:"openapi.resources",Pointer:item.URI,Message:"resource syntax must be explicitly json or yaml"}};if item.Role!=OpenAPIDocument&&item.Role!=OpenAPISchema&&item.Role!=OpenAPIFragment{return &Error{Code:"openapi.resources",Pointer:item.URI,Message:"resource role must be explicitly document, schema, or fragment"}};if len(item.Source)>limits.Bytes{return &Error{Code:"openapi.limit",Pointer:item.URI,Message:"resource byte limit exceeded"}};if !utf8.Valid(item.Source){return &Error{Code:"openapi.encoding",Pointer:item.URI,Message:"resource is not UTF-8"}};return nil}

func parseOpenAPIProvenanceResource(item OpenAPIResource,limits schemajson.Limits)(*openAPIProvenanceDoc,error){
    var jsonDoc schemajson.Document;isJSON:=item.Syntax==OpenAPIJSON;if isJSON{parsed,err:=schemajson.Parse(item.Source,limits);if err!=nil{return nil,err};jsonDoc=parsed}
    decoder:=yaml.NewDecoder(strings.NewReader(string(item.Source)));var document yaml.Node;if err:=decoder.Decode(&document);err!=nil{return nil,&Error{Code:"openapi.syntax",Pointer:item.URI,Message:err.Error()}};if len(document.Content)!=1{return nil,&Error{Code:"openapi.syntax",Pointer:item.URI,Message:"resource must contain exactly one document"}};var extra yaml.Node;if err:=decoder.Decode(&extra);err!=io.EOF{return nil,&Error{Code:"openapi.syntax",Pointer:item.URI,Message:"resource must contain exactly one document"}}
    count:=0;if err:=checkOpenAPIProvenanceYAML(document.Content[0],0,limits,&count,item.URI,"",map[*yaml.Node]bool{});err!=nil{return nil,err};starts:=[]int{0};for i,b:=range item.Source{if b=='\n'{starts=append(starts,i+1)}}
    return &openAPIProvenanceDoc{resource:item,root:document.Content[0],json:jsonDoc,isJSON:isJSON,lineStarts:starts},nil
}

func checkOpenAPIProvenanceYAML(node *yaml.Node,depth int,limits schemajson.Limits,count *int,resource,path string,active map[*yaml.Node]bool)error{if depth>limits.Depth{return &Error{Code:"openapi.limit",Pointer:resource+"#"+path,Message:"resource depth limit exceeded"}};*count=*count+1;if *count>limits.Nodes{return &Error{Code:"openapi.limit",Pointer:resource+"#"+path,Message:"resource node limit exceeded"}};if active[node]{return &Error{Code:"openapi.syntax",Pointer:resource+"#"+path,Message:"cyclic YAML alias"}};active[node]=true;defer delete(active,node);if node.Kind==yaml.AliasNode||node.Anchor!=""{return &Error{Code:"openapi.syntax",Pointer:resource+"#"+path,Message:"YAML anchors and aliases are not supported by exact provenance"}};if node.Kind==yaml.MappingNode{seen:=map[string]bool{};if len(node.Content)%2!=0{return &Error{Code:"openapi.syntax",Pointer:resource+"#"+path,Message:"malformed mapping"}};for i:=0;i<len(node.Content);i+=2{key:=node.Content[i];if key.Kind!=yaml.ScalarNode||key.ShortTag()!="!!str"{return &Error{Code:"openapi.syntax",Pointer:resource+"#"+path,Message:"mapping keys must be strings"}};if seen[key.Value]{return &Error{Code:"openapi.syntax",Pointer:resource+"#"+path,Message:"duplicate mapping key"}};seen[key.Value]=true;if err:=checkOpenAPIProvenanceYAML(node.Content[i+1],depth+1,limits,count,resource,path+"/"+pointerKeyOpenAPI(key.Value),active);err!=nil{return err}}}else{for i,child:=range node.Content{if err:=checkOpenAPIProvenanceYAML(child,depth+1,limits,count,resource,fmt.Sprintf("%s/%d",path,i),active);err!=nil{return err}}};return nil}

func pointerKeyOpenAPI(text string)string{return strings.ReplaceAll(strings.ReplaceAll(text,"~","~0"),"/","~1")}
func yamlMappingValue(node *yaml.Node,name string)(*yaml.Node,bool){if node==nil||node.Kind!=yaml.MappingNode{return nil,false};for i:=0;i<len(node.Content);i+=2{if node.Content[i].Value==name{return node.Content[i+1],true}};return nil,false}
func yamlScalarString(node *yaml.Node)(string,error){if node==nil||node.Kind!=yaml.ScalarNode||node.ShortTag()!="!!str"{return "",errors.New("value must be a string")};return node.Value,nil}
func openAPIVersion(root *yaml.Node)(string,error){value,ok:=yamlMappingValue(root,"openapi");if !ok{return "",&Error{Code:"openapi.version",Message:"entry document has no openapi version"}};version,err:=yamlScalarString(value);if err!=nil{return "",&Error{Code:"openapi.version",Pointer:"/openapi",Message:err.Error()}};return version,nil}
func supportedOpenAPIDialect(dialect,pointer string)error{trimmed:=strings.TrimSuffix(dialect,"#");if trimmed!=openAPIBase&&trimmed!=jsonSchema202012{return &Error{Code:"openapi.dialect",Pointer:pointer,Message:"only the OpenAPI 3.1 base dialect and JSON Schema Draft 2020-12 are supported"}};return nil}

func (w *openAPIProvenanceWalker)chargeRetainedLocation(kind string,node openAPIProvenanceNode)error{if w.maxRetainedBytes==0{return nil};size:=len(kind)+1+len(node.doc.resource.URI)+1+len(node.pointer);if size<0||size>w.maxRetainedBytes-w.retainedBytes{return &Error{Code:"openapi.limit",Message:"OpenAPI wrapper traversal retained paths exceed the deterministic byte limit"}};w.retainedBytes+=size;return nil}
func (w *openAPIProvenanceWalker)enter(node openAPIProvenanceNode,kind string,depth int)error{if depth>w.maxDepth{return &Error{Code:"openapi.limit",Pointer:node.doc.resource.URI+"#"+node.pointer,Message:"provenance traversal depth limit exceeded"}};w.steps++;if w.steps>w.maxSteps{return &Error{Code:"openapi.limit",Pointer:node.doc.resource.URI+"#"+node.pointer,Message:"provenance traversal work limit exceeded"}};if err:=w.chargeRetainedLocation(kind,node);err!=nil{return err};key:=kind+"\x00"+node.doc.resource.URI+"\x00"+node.pointer;if w.seen[key]{return io.EOF};w.seen[key]=true;return nil}

func (w *openAPIProvenanceWalker)add(node openAPIProvenanceNode,keyword,scope,predicate,native,dialect string,builtins []string)error{return w.addMembers(node,keyword,"",scope,predicate,native,"",dialect,builtins)}
func (w *openAPIProvenanceWalker)addMembers(node openAPIProvenanceNode,keyword,pairedKeyword,scope,predicate,native,pairedNative,dialect string,builtins []string)error{where:=node.pointer+"/"+pointerKeyOpenAPI(keyword);identityInput:="openapi-provenance-v1\x00"+strconv.Itoa(len(node.doc.resource.URI))+":"+node.doc.resource.URI+strconv.Itoa(len(where))+":"+where;identity:=fmt.Sprintf("%x",sha256.Sum256([]byte(identityInput)));name:="Native_"+identity;if w.constraintNames[name]{return nil};line:="type "+name+" = "+scope+" where "+predicate+"\n";if len(line)>openAPIProvenanceSourceBytes-w.sourceBytes{return nil};w.sourceBytes+=len(line);fingerprintInput:=identityInput+"\x00"+dialect+"\x00"+scope+"\x00"+native;if pairedKeyword!=""{fingerprintInput+="\x00openapi30-pair-v1\x00"+strconv.Itoa(len(pairedKeyword))+":"+pairedKeyword+strconv.Itoa(len(pairedNative))+":"+pairedNative};fingerprint:=fmt.Sprintf("%x",sha256.Sum256([]byte(fingerprintInput)));w.constraintNames[name]=true;w.constraints=append(w.constraints,Constraint{Name:name,Resource:node.doc.resource.URI,Pointer:where,SchemaPointer:node.pointer,Keyword:keyword,PairedKeyword:pairedKeyword,PairedNative:pairedNative,Scope:scope,Predicate:predicate,Native:native,Fingerprint:fingerprint,Builtins:builtins});return nil}

func auditConstraintSource(constraints []Constraint,source string)([]Finding,error){program,err:=language.Compile(source);if err!=nil{return nil,err};module:=program.Syntax();declarations:=map[string]language.TypeDecl{};for _,decl:=range module.Types{declarations[decl.Name]=decl};functions:=map[string]bool{};for _,fn:=range module.Functions{functions[fn.Name]=true};result:=make([]Finding,0,len(constraints));for _,constraint:=range constraints{var status Status=Removed();if decl,exists:=declarations[constraint.Name];exists{status=Changed();base:=decl.Body;rules:=[]language.Where{};for base!=nil{stop:=false;match base.Form{case language.RefinedType(inner,own):rules=append(rules,own...);base=inner;case _:stop=true};if stop{break}};bindings:=true;for _,builtin:=range constraint.Builtins{if functions[builtin]{bindings=false}};if bindings&&base!=nil&&len(decl.Parameters)==0&&language.FormatType(base)==constraint.Scope{for _,rule:=range rules{if language.FormatExpression(rule.Predicate)==constraint.Predicate{status=Unchanged();break}}}};result=append(result,Finding{Constraint:copyConstraint(constraint),Status:status})};return result,nil}
func recoverConstraintNative(constraints []Constraint,name,source string)(string,error){findings,err:=auditConstraintSource(constraints,source);if err!=nil{return "",err};for _,finding:=range findings{if finding.Constraint.Name!=name{continue};if StatusName(finding.Status)=="unchanged"{return finding.Constraint.Native,nil};return "",&Error{Code:"native.bijection_changed",Pointer:finding.Constraint.Resource+"#"+finding.Constraint.Pointer,Message:"native constraint is no longer in its imported canonical refinement form"}};return "",&Error{Code:"native.origin",Message:"constraint does not belong to this imported document set"}}
