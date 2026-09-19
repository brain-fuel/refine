package native

import (
    "bytes"
    "encoding/json"
    "fmt"
    "math/big"
    "sort"
    "strings"

    jsonoracle "github.com/santhosh-tekuri/jsonschema/v6"
    yaml "github.com/oasdiff/yaml3"
    "goforge.dev/refine/schemajson"
)

const openAPIBaseDialect="https://spec.openapis.org/oas/3.1/dialect/base"

// The OAS base vocabulary contains annotations only. This local dialect
// declaration tells the Draft 2020-12 compiler that those optional vocabulary
// keywords do not add assertions; kin-openapi already validates their shapes.
const openAPIBaseDialectAdapter=`{
  "$id":"https://spec.openapis.org/oas/3.1/dialect/base",
  "$schema":"https://json-schema.org/draft/2020-12/schema",
  "$vocabulary":{
    "https://json-schema.org/draft/2020-12/vocab/core":true,
    "https://json-schema.org/draft/2020-12/vocab/applicator":true,
    "https://json-schema.org/draft/2020-12/vocab/unevaluated":true,
    "https://json-schema.org/draft/2020-12/vocab/validation":true,
    "https://json-schema.org/draft/2020-12/vocab/meta-data":true,
    "https://json-schema.org/draft/2020-12/vocab/format-annotation":true,
    "https://json-schema.org/draft/2020-12/vocab/content":true,
    "https://spec.openapis.org/oas/3.1/vocab/base":false
  },
  "$dynamicAnchor":"meta",
  "type":["object","boolean"]
}`

type openAPIValidationResourceLoader struct{resources map[string]string}
func newOpenAPIValidationResourceLoader(view *OpenAPIValidationView)openAPIValidationResourceLoader{resources:=map[string]string{openAPIBaseDialect:openAPIBaseDialectAdapter};if view!=nil{for _,resource:=range view.Resources(){resources[resource.URI]=resource.Source}};return openAPIValidationResourceLoader{resources:resources}}
func (l openAPIValidationResourceLoader)Load(uri string)(any,error){source,ok:=l.resources[uri];if !ok{return nil,fmt.Errorf("resource %s is not in the checked OpenAPI validation view",uri)};return jsonoracle.UnmarshalJSON(strings.NewReader(source))}

type openAPIValidationCompileTarget struct{id string;selector ResourceSelector}
func compileOpenAPIValidationView(view *OpenAPIValidationView,targets []openAPIValidationCompileTarget)(map[string]*jsonoracle.Schema,*regexScope,error){
    if view==nil{return nil,nil,&Error{Code:"native.project",Format:OpenAPI,Message:"an OpenAPI validation view is required"}};scope:=newRegexScope();schemas:=map[string]*jsonoracle.Schema{};locations:=map[string]string{};loader:=newOpenAPIValidationResourceLoader(view)
    err:=scope.run(OpenAPI,true,func()error{compiler:=newOfflineJSONCompiler();compiler.DefaultDraft(jsonoracle.Draft2020);compiler.UseRegexpEngine(scope.jsonRegexp);compiler.UseLoader(loader);for _,target:=range targets{location,err:=validationViewReference(target.selector,schemajson.DefaultBytes);if err!=nil{return err};if prior,exists:=locations[target.id];exists&&prior!=location{return &Error{Code:"native.enforcement",Format:OpenAPI,Pointer:target.id,Message:"stable OpenAPI validation target collision"}};schema,err:=compiler.Compile(location);if err!=nil{return wrap(OpenAPI,"native.enforcement",target.id,err)};locations[target.id]=location;schemas[target.id]=schema};return nil});if err!=nil{return nil,nil,wrapRegexResult(OpenAPI,"native.enforcement","",err)};return schemas,scope,nil
}
func compileOpenAPIValidationRoot(view *OpenAPIValidationView,selector ResourceSelector)error{schemas,_,err:=compileOpenAPIValidationView(view,[]openAPIValidationCompileTarget{{id:"root",selector:selector}});if err!=nil{return err};if schemas["root"]==nil{return &Error{Code:"native.enforcement",Format:OpenAPI,Pointer:selector.Pointer,Message:"selected OpenAPI Schema Object did not compile"}};return nil}

// CanonicalJSONResources returns an immutable snapshot of the exact JSON
// resources used by JSON payload validators. OpenAPI YAML is converted without
// passing numeric values through float64. The method rejects formats and
// dialects for which exact JSON Schema validation is unavailable.
func (p *Project) CanonicalJSONResources()([]Resource,error){
    resources,err:=p.canonicalJSONResources();if err!=nil{return nil,err};if p.Format()==OpenAPI{if strings.HasPrefix(p.Version(),"3.0."){return p.adaptOpenAPI30Resources(resources)};if err:=p.validateOpenAPIDialects(resources);err!=nil{return nil,err}};return resources,nil
}
func (p *Project) canonicalJSONResources()([]Resource,error){
    if p==nil||p.document==nil{return nil,&Error{Code:"native.project",Message:"a project is required"}}
    if p.Format()!=JSONSchema&&p.Format()!=OpenAPI{return nil,&Error{Code:"native.enforcement",Format:p.Format(),Message:"canonical JSON validation resources are unavailable for this format"}}
    resources:=make([]Resource,len(p.resources));numericExpansion:=0;for i,resource:=range p.resources{
        raw:=[]byte(resource.Source);if p.Format()==OpenAPI{var err error;raw,err=openAPIResourceJSON(raw);if err!=nil{return nil,wrap(OpenAPI,"native.structure",resource.URI,err)}}
        doc,err:=schemajson.Parse(raw,schemajson.Limits{});if err!=nil{return nil,wrap(p.Format(),"native.structure",resource.URI,err)};if err:=scalarJSONBudget(doc.Root(),"",DefaultNumericExpansion,&numericExpansion);err!=nil{return nil,wrap(p.Format(),"native.structure",resource.URI,err)}
        resources[i]=Resource{URI:resource.URI,Source:doc.Raw()}
    };return p.effectiveJSONSchemaResources(resources)
}

func (p *Project) validateOpenAPIJSON(input []byte)(failure error){defer recoverRegexEvaluation(OpenAPI,&failure)
    instance,err:=schemajson.Parse(input,schemajson.Limits{});if err!=nil{return wrap(OpenAPI,"native.payload","",err)};if err:=scalarJSONWithNumericExpansion(instance.Root(),"",p.metadata.NumericExpansionLimit());err!=nil{return wrap(OpenAPI,"native.limit","",err)};value,err:=jsonoracle.UnmarshalJSON(strings.NewReader(instance.Raw()));if err!=nil{return wrap(OpenAPI,"native.payload","",err)}
    resources,err:=p.CanonicalJSONResources();if err!=nil{return err};if strings.HasPrefix(p.Version(),"3.0."){scope:=newRegexScope();err=scope.run(OpenAPI,false,func()error{compiler:=newOfflineJSONCompiler();compiler.DefaultDraft(jsonoracle.Draft2020);compiler.UseRegexpEngine(scope.jsonRegexp);dialect,parseErr:=jsonoracle.UnmarshalJSON(strings.NewReader(openAPIBaseDialectAdapter));if parseErr!=nil{panic(parseErr)};if addErr:=compiler.AddResource(openAPIBaseDialect,dialect);addErr!=nil{panic(addErr)};for _,resource:=range resources{schemaValue,parseErr:=jsonoracle.UnmarshalJSON(strings.NewReader(resource.Source));if parseErr!=nil{return wrap(OpenAPI,"native.structure",resource.URI,parseErr)};if addErr:=compiler.AddResource(resource.URI,schemaValue);addErr!=nil{return wrap(OpenAPI,"native.structure",resource.URI,addErr)}};location:=p.root.Resource;if p.root.Pointer!=""{location+="#"+p.root.Pointer};schema,compileErr:=compiler.Compile(location);if compileErr!=nil{return wrap(OpenAPI,"native.enforcement",p.root.Pointer,compileErr)};if validateErr:=schema.Validate(value);validateErr!=nil{return wrap(OpenAPI,"native.payload",p.root.Pointer,validateErr)};return nil});if err!=nil{return wrapRegexResult(OpenAPI,"native.enforcement",p.root.Pointer,err)};return nil}
    view,err:=NewOpenAPIValidationView(resources,p.EntryResource());if err!=nil{return err};mapped,err:=view.Selector(p.root);if err!=nil{return err};schemas,scope,err:=compileOpenAPIValidationView(view,[]openAPIValidationCompileTarget{{id:"root",selector:mapped}});if err!=nil{return err};err=scope.run(OpenAPI,false,func()error{return schemas["root"].Validate(value)});if err!=nil{return wrapRegexResult(OpenAPI,"native.payload",p.root.Pointer,err)};return nil
}

// adaptOpenAPI30Resources translates the normative OAS 3.0 Schema Object
// subset to equivalent Draft 2020-12 assertions. It changes only reachable
// Schema Object positions. Examples, defaults, and payload properties whose
// names resemble keywords remain ordinary data. All input documents were
// already validated by kin-openapi before this adapter runs.
func (p *Project) adaptOpenAPI30Resources(resources []Resource)([]Resource,error){
    locations:=map[string][]string{};if err:=p.walkJSONSchemaLocations(resources,func(resource,path string,node schemajson.Node)error{if schemajson.KindName(node.Kind())=="object"{locations[resource]=append(locations[resource],path)};return nil});err!=nil{return nil,&Error{Code:"native.enforcement",Format:OpenAPI,Message:"OpenAPI 3.0 schema locations cannot be adapted exactly",Cause:err}}
    out:=make([]Resource,len(resources));for i,resource:=range resources{decoder:=json.NewDecoder(strings.NewReader(resource.Source));decoder.UseNumber();var root any;if err:=decoder.Decode(&root);err!=nil{return nil,wrap(OpenAPI,"native.structure",resource.URI,err)};paths:=locations[resource.URI];sort.Slice(paths,func(i,j int)bool{return strings.Count(paths[i],"/")>strings.Count(paths[j],"/")});for _,path:=range paths{target,err:=openAPI30At(root,path);if err!=nil{return nil,&Error{Code:"native.enforcement",Format:OpenAPI,Pointer:resource.URI+"#"+path,Message:"OpenAPI 3.0 Schema Object cannot be adapted exactly",Cause:err}};if err:=adaptOpenAPI30Schema(target);err!=nil{return nil,&Error{Code:"native.enforcement",Format:OpenAPI,Pointer:resource.URI+"#"+path,Message:err.Error()}}};encoded,err:=json.Marshal(root);if err!=nil{return nil,wrap(OpenAPI,"native.structure",resource.URI,err)};doc,err:=schemajson.Parse(encoded,schemajson.Limits{});if err!=nil{return nil,wrap(OpenAPI,"native.structure",resource.URI,err)};out[i]=Resource{URI:resource.URI,Source:doc.Raw()}}
    return out,nil
}

func openAPI30PointerTokens(pointer string)([]string,error){if pointer==""{return nil,nil};if !strings.HasPrefix(pointer,"/"){return nil,fmt.Errorf("JSON Pointer must start with slash")};parts:=strings.Split(pointer[1:],"/");for i,part:=range parts{var decoded strings.Builder;for j:=0;j<len(part);j++{if part[j]!='~'{decoded.WriteByte(part[j]);continue};j++;if j>=len(part)||part[j]!='0'&&part[j]!='1'{return nil,fmt.Errorf("invalid JSON Pointer escape")};if part[j]=='0'{decoded.WriteByte('~')}else{decoded.WriteByte('/')}};parts[i]=decoded.String()};return parts,nil}
func openAPI30At(root any,pointer string)(map[string]any,error){tokens,err:=openAPI30PointerTokens(pointer);if err!=nil{return nil,err};current:=root;for _,token:=range tokens{switch value:=current.(type){case map[string]any:next,ok:=value[token];if !ok{return nil,fmt.Errorf("object member does not exist")};current=next;case []any:index,ok:=new(big.Int).SetString(token,10);if !ok||!index.IsInt64()||index.Sign()<0||index.Int64()>=int64(len(value)){return nil,fmt.Errorf("array index does not exist")};current=value[index.Int64()];default:return nil,fmt.Errorf("cannot descend into scalar")}};object,ok:=current.(map[string]any);if !ok{return nil,fmt.Errorf("OAS 3.0 Schema Object is not an object")};return object,nil}

func adaptOpenAPI30Schema(schema map[string]any)error{
    // OAS 3.0 Reference Objects ignore every sibling of $ref. Do not reject a
    // valid document or accidentally reinterpret a sibling as a JSON Schema
    // adjacent applicator; retain only the authoritative reference.
    if _,hasRef:=schema["$ref"];hasRef{for key:=range schema{if key!="$ref"{delete(schema,key)}};return nil}
    if raw,ok:=schema["nullable"];ok{nullable,ok:=raw.(bool);if !ok{return fmt.Errorf("OpenAPI 3.0 nullable must be Boolean")};if nullable{if typ,hasType:=schema["type"];hasType{named,ok:=typ.(string);if !ok{return fmt.Errorf("OpenAPI 3.0 type must be a string")};schema["type"]=[]any{named,"null"}}};delete(schema,"nullable")}
    for _,pair:=range [][2]string{{"exclusiveMinimum","minimum"},{"exclusiveMaximum","maximum"}}{exclusive,ok:=schema[pair[0]];if !ok{continue};enabled,ok:=exclusive.(bool);if !ok{return fmt.Errorf("OpenAPI 3.0 %s must be Boolean",pair[0])};delete(schema,pair[0]);if enabled{if bound,hasBound:=schema[pair[1]];hasBound{schema[pair[0]]=bound;delete(schema,pair[1])}}}
    return nil
}

// openAPI30IgnoredRefSiblingFields returns the field names that kin-openapi
// must allow while checking an OAS 3.0 document. The 3.0 Reference Object says
// every sibling of $ref is ignored; the library otherwise rejects those
// documents before our schema-position adapter can discard the ignored data.
// The caller has already applied syntax depth/node limits and rejected aliases.
func openAPI30IgnoredRefSiblingFields(roots ...*yaml.Node)[]string{found:=map[string]bool{};var walk func(*yaml.Node);walk=func(node *yaml.Node){if node==nil{return};if node.Kind==yaml.MappingNode{hasRef:=false;for i:=0;i<len(node.Content);i+=2{if node.Content[i].Value=="$ref"{hasRef=true;break}};if hasRef{for i:=0;i<len(node.Content);i+=2{name:=node.Content[i].Value;if name!="$ref"{found[name]=true}}}};for _,child:=range node.Content{walk(child)}};for _,root:=range roots{walk(root)};out:=make([]string,0,len(found));for name:=range found{out=append(out,name)};sort.Strings(out);return out}

func (p *Project) validateOpenAPIDialects(resources []Resource)error{docs:=map[string]schemajson.Document{};for _,resource:=range resources{doc,err:=schemajson.Parse([]byte(resource.Source),schemajson.Limits{});if err!=nil{return err};docs[resource.URI]=doc};entry:=p.EntryResource();if root,ok:=docs[entry];ok{if dialectNode,ok:=root.Root().Lookup("jsonSchemaDialect");ok{if err:=supportedOpenAPIDialectValue(dialectNode,entry+"#/jsonSchemaDialect");err!=nil{return err}}};return p.walkJSONSchemaLocations(resources,func(resource,path string,node schemajson.Node)error{if dialectNode,ok:=node.Lookup("$schema");ok{return supportedOpenAPIDialectValue(dialectNode,resource+"#"+path+"/$schema")};return nil})}
func supportedOpenAPIDialectValue(node schemajson.Node,path string)error{dialect,ok:=nodeString(node);if !ok{return &Error{Code:"native.enforcement",Format:OpenAPI,Pointer:path,Message:"schema dialect must be a string"}};dialect=strings.TrimSuffix(dialect,"#");if dialect!=openAPIBaseDialect&&dialect!="https://json-schema.org/draft/2020-12/schema"{return &Error{Code:"native.enforcement",Format:OpenAPI,Pointer:path,Message:fmt.Sprintf("dialect %q is not supported for exact payload validation",dialect)}};return nil}

func openAPIResourceJSON(input []byte)([]byte,error){trimmed:=bytes.TrimSpace(input);if len(trimmed)>0&&(trimmed[0]=='{'||trimmed[0]=='['){doc,err:=schemajson.Parse(input,schemajson.Limits{});if err!=nil{return nil,err};if err:=scalarJSON(doc.Root(),"");err!=nil{return nil,err};return []byte(doc.Raw()),nil};l,_:=limits(Options{});root,err:=parseYAML(input,l);if err!=nil{return nil,err};var out bytes.Buffer;if err:=writeYAMLJSON(&out,root,"");err!=nil{return nil,err};doc,err:=schemajson.Parse(out.Bytes(),schemajson.Limits{});if err!=nil{return nil,err};return []byte(doc.Raw()),nil}

func writeYAMLJSON(out *bytes.Buffer,node *yaml.Node,path string)error{switch node.Kind{
case yaml.MappingNode:out.WriteByte('{');for i:=0;i<len(node.Content);i+=2{if i>0{out.WriteByte(',')};key:=node.Content[i];if key.Kind!=yaml.ScalarNode||key.Tag!="!!str"{return fmt.Errorf("OpenAPI mapping key at %s must be a string",path)};encoded,_:=json.Marshal(key.Value);out.Write(encoded);out.WriteByte(':');if err:=writeYAMLJSON(out,node.Content[i+1],path+"/"+escapePointer(key.Value));err!=nil{return err}};out.WriteByte('}')
case yaml.SequenceNode:out.WriteByte('[');for i,child:=range node.Content{if i>0{out.WriteByte(',')};if err:=writeYAMLJSON(out,child,fmt.Sprintf("%s/%d",path,i));err!=nil{return err}};out.WriteByte(']')
case yaml.ScalarNode:switch node.Tag{case "!!str":encoded,_:=json.Marshal(node.Value);out.Write(encoded);case "!!null":out.WriteString("null");case "!!bool":value:=strings.ToLower(node.Value);if value!="true"&&value!="false"{return fmt.Errorf("invalid YAML Boolean at %s",path)};out.WriteString(value);case "!!int":value,err:=yamlIntegerJSON(node.Value);if err!=nil{return fmt.Errorf("invalid YAML integer at %s: %w",path,err)};out.WriteString(value);case "!!float":value,err:=yamlFloatJSON(node.Value);if err!=nil{return fmt.Errorf("invalid YAML float at %s: %w",path,err)};out.WriteString(value);default:return fmt.Errorf("YAML scalar tag %s at %s has no exact JSON representation",node.Tag,path)}
default:return fmt.Errorf("YAML node at %s has no exact JSON representation",path)};return nil}

func yamlIntegerJSON(raw string)(string,error){text:=strings.ReplaceAll(raw,"_","");negative:=false;if strings.HasPrefix(text,"+"){text=text[1:]}else if strings.HasPrefix(text,"-"){negative=true;text=text[1:]};base:=10;if len(text)>2&&text[0]=='0'{switch text[1]{case 'b','B':base=2;text=text[2:];case 'o','O':base=8;text=text[2:];case 'x','X':base=16;text=text[2:]}};integer,ok:=new(big.Int).SetString(text,base);if !ok{return "",fmt.Errorf("invalid integer spelling")};if negative{integer.Neg(integer)};return integer.String(),nil}
func yamlFloatJSON(raw string)(string,error){text:=strings.ReplaceAll(strings.ToLower(raw),"_","");if strings.Contains(text,"inf")||strings.Contains(text,"nan"){return "",fmt.Errorf("non-finite numbers are not JSON values")};sign:="";if strings.HasPrefix(text,"+"){text=text[1:]}else if strings.HasPrefix(text,"-"){sign="-";text=text[1:]};parts:=strings.SplitN(text,"e",2);mantissa:=parts[0];if strings.HasPrefix(mantissa,"."){mantissa="0"+mantissa};if strings.HasSuffix(mantissa,"."){mantissa+="0"};candidate:=sign+mantissa;if len(parts)==2{exponent:=parts[1];if strings.HasPrefix(exponent,"+"){exponent=exponent[1:]};if _,ok:=new(big.Int).SetString(exponent,10);!ok{return "",fmt.Errorf("invalid exponent")};candidate+="e"+exponent};doc,err:=schemajson.Parse([]byte(candidate),schemajson.Limits{Bytes:1024,Depth:2,Nodes:2});if err!=nil||schemajson.KindName(doc.Root().Kind())!="number"{return "",fmt.Errorf("invalid finite float spelling")};return candidate,nil}
