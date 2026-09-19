package native

import (
    "crypto/sha256"
    "encoding/json"
    "fmt"
    "strings"
    "unicode"

    yaml "github.com/oasdiff/yaml3"
    "goforge.dev/refine/schemajson"
)

type sourceProjector struct { format Format; root schemajson.Document; names map[string]string; definitionNodes map[string]schemajson.Node; definitionPaths map[string]string; declarations []string; avroNames map[string]string; emitted map[string]bool; nextUnion int; openAPI bool; strictStructure bool; openAPIDirection OpenAPIDirection }
type jsonMapCandidate struct{node schemajson.Node;path string}

func checkedTypeName(name string)bool{if name==""{return false};for i,r:=range name{if i==0{if !unicode.IsUpper(r){return false}}else if !unicode.IsLetter(r)&&!unicode.IsDigit(r)&&r!='_'{return false}};return true}
func safeTypeName(raw string)string{var b strings.Builder;for i,r:=range raw{if unicode.IsLetter(r)||i>0&&unicode.IsDigit(r)||r=='_'{b.WriteRune(r)}else{b.WriteByte('_')}};name:=b.String();if name==""||!unicode.IsUpper([]rune(name)[0]){name="Native_"+name};if !checkedTypeName(name){sum:=sha256.Sum256([]byte(raw));name=fmt.Sprintf("Native_%x",sum[:6])};return name}

func projectJSON(doc schemajson.Document,selector ResourceSelector,openAPI bool)(string,error){
    if !openAPI{return projectJSONResources([]Resource{{URI:selector.Resource,Source:doc.Raw()}},selector)}
    p:=&sourceProjector{format:JSONSchema,root:doc,names:make(map[string]string),definitionNodes:make(map[string]schemajson.Node),definitionPaths:make(map[string]string),emitted:make(map[string]bool),openAPI:openAPI};if openAPI{p.format=OpenAPI}
    defsPointer:="/$defs";refPrefix:="#/$defs/";if openAPI{defsPointer="/components/schemas";refPrefix="#/components/schemas/"}
    if defs,err:=doc.At(defsPointer);err==nil&&schemajson.KindName(defs.Kind())=="object"{used:=map[string]bool{selector.TypeName:true};for _,member:=range defs.Members(){raw,_:=member.Key.UTF8();reference:=refPrefix+escapePointer(raw);name:=safeTypeName(raw);if used[name]{sum:=sha256.Sum256([]byte(raw));name=fmt.Sprintf("%s_%x",name,sum[:4])};used[name]=true;p.names[reference]=name;p.definitionNodes[reference]=member.Value;p.definitionPaths[reference]=defsPointer+"/"+escapePointer(raw)}}
    target,err:=doc.At(selector.Pointer);if err!=nil{return "",wrap(p.format,"native.root",selector.Pointer,err)};expr,err:=p.jsonType(target,selector.Pointer,openAPI);if err!=nil{return "",err}
    p.declarations=append(p.declarations,"type "+selector.TypeName+" = "+expr);return strings.Join(p.declarations,"\n\n")+"\n",nil
}

func (p *sourceProjector) jsonType(node schemajson.Node,path string,openAPI bool)(string,error){
    if carrier,handled:=p.jsonCarrierProjection(node);handled{return carrier,nil}
    if schemajson.KindName(node.Kind())=="boolean"{return "",&Error{Code:"native.projection",Format:p.format,Pointer:path,Message:"Boolean schemas have no safe standalone language payload type; retain them in the native sidecar"}}
    if schemajson.KindName(node.Kind())!="object"{return "",&Error{Code:"native.projection",Format:p.format,Pointer:path,Message:"schema position must be an object or Boolean"}}
    if p.strictStructure{for _,keyword:=range []string{"allOf","anyOf","oneOf","if","then","else","dependentSchemas"}{if _,ok:=node.Lookup(keyword);ok{return "",&Error{Code:"native.projection",Format:p.format,Pointer:path+"/"+keyword,Message:"automatic operation type derivation cannot infer structure through "+keyword+"; provide explicit checked OpenAPI operation metadata"}}}}
    if unevaluated,ok:=node.Lookup("unevaluatedProperties");ok&&schemajson.KindName(unevaluated.Kind())=="object"{return "",&Error{Code:"native.projection",Format:p.format,Pointer:path+"/unevaluatedProperties",Message:"schema-valued unevaluatedProperties depends on applicator evaluation and cannot yet be projected as one homogeneous Map value type; provide an explicit checked source"}}
    if ref,ok:=node.Lookup("$ref");ok{if p.strictStructure{for _,keyword:=range []string{"type","properties","required","items","prefixItems","additionalProperties","patternProperties","nullable"}{if _,sibling:=node.Lookup(keyword);sibling{return "",&Error{Code:"native.projection",Format:p.format,Pointer:path+"/"+keyword,Message:"automatic operation type derivation cannot merge a structural $ref sibling; provide explicit checked OpenAPI operation metadata"}}}};raw,ok:=nodeString(ref);if !ok{return "",&Error{Code:"native.projection",Format:p.format,Pointer:path+"/$ref",Message:"reference must be scalar text"}};if name,ok:=p.names[raw];ok{if !p.emitted[raw]{p.emitted[raw]=true;expr,err:=p.jsonType(p.definitionNodes[raw],p.definitionPaths[raw],p.openAPI);if err!=nil{return "",err};p.declarations=append(p.declarations,"type "+name+" = "+expr)};return name,nil};return "",&Error{Code:"native.projection",Format:p.format,Pointer:path+"/$ref",Message:"only local named-definition references can currently be projected; the native sidecar still retains external references"}}
    typeNode,ok:=node.Lookup("type");if !ok{return "",&Error{Code:"native.projection",Format:p.format,Pointer:path,Message:"a safe editable projection requires an explicit native type"}}
    nullable:=false;nativeType:=""
    switch schemajson.KindName(typeNode.Kind()){
    case "string":nativeType,_=nodeString(typeNode)
    case "array":for _,item:=range typeNode.Elements(){name,ok:=nodeString(item);if !ok{return "",&Error{Code:"native.projection",Format:p.format,Pointer:path+"/type",Message:"type array must contain strings"}};if name=="null"{nullable=true}else if nativeType==""{nativeType=name}else{return "",&Error{Code:"native.projection",Format:p.format,Pointer:path+"/type",Message:"only a singleton type or one non-null type plus null can be projected"}}}
    default:return "",&Error{Code:"native.projection",Format:p.format,Pointer:path+"/type",Message:"type must be a string or array"}
    }
    if openAPI{if value,exists:=node.Lookup("nullable");exists&&value.Raw()=="true"{nullable=true}}
    result:="";switch nativeType{
    case "integer":result="Int"
    case "number":result="Real"
    case "string":result="String"
    case "boolean":result="Bool"
    case "null":return "",&Error{Code:"native.projection",Format:p.format,Pointer:path,Message:"a null-only schema has no payload type"}
    case "array":if _,tuple:=node.Lookup("prefixItems");tuple{return "",&Error{Code:"native.projection",Format:p.format,Pointer:path,Message:"heterogeneous prefixItems need an explicit language type"}};items,exists:=node.Lookup("items");if !exists{return "",&Error{Code:"native.projection",Format:p.format,Pointer:path,Message:"an unconstrained array has no safe element type"}};element,err:=p.jsonType(items,path+"/items",openAPI);if err!=nil{return "",err};result="["+element+"]"
    case "object":if mapped,isMap,err:=p.jsonMapType(node,path,openAPI);err!=nil{return "",err}else if isMap{result=mapped;break};properties,exists:=node.Lookup("properties");if !exists{result="{}";break};if schemajson.KindName(properties.Kind())!="object"{return "",&Error{Code:"native.projection",Format:p.format,Pointer:path+"/properties",Message:"properties must be an object"}};required:=make(map[string]bool);if list,exists:=node.Lookup("required");exists{if schemajson.KindName(list.Kind())!="array"{return "",&Error{Code:"native.projection",Format:p.format,Pointer:path+"/required",Message:"required must be an array"}};for _,item:=range list.Elements(){name,ok:=nodeString(item);if !ok{return "",&Error{Code:"native.projection",Format:p.format,Pointer:path+"/required",Message:"required names must be strings"}};required[name]=true}}
        fields:=[]string{};for _,member:=range properties.Members(){name,_:=member.Key.UTF8();if !memberPattern.MatchString(name){return "",&Error{Code:"native.projection",Format:p.format,Pointer:path+"/properties/"+escapePointer(name),Message:"property name is not a language field identifier"}};directionalOptional,err:=p.jsonDirectionalOptional(member.Value,path+"/properties/"+escapePointer(name));if err!=nil{return "",err};fieldType,err:=p.jsonType(member.Value,path+"/properties/"+escapePointer(name),openAPI);if err!=nil{return "",err};if !required[name]||directionalOptional{fieldType="Maybe ("+fieldType+")"};fields=append(fields,name+" :: "+fieldType);delete(required,name)};if len(required)>0{return "",&Error{Code:"native.projection",Format:p.format,Pointer:path+"/required",Message:"required contains a property without a projectable declared schema"}};result="{"+strings.Join(fields,", ")+"}"
    default:return "",&Error{Code:"native.projection",Format:p.format,Pointer:path+"/type",Message:"unsupported native type "+nativeType}
    }
    if nullable{result="Nullable ("+result+")"};return result,nil
}

// A JSON object projects as a typed map only when every possible value has one
// checked type. Native pattern/required constraints remain authoritative in the
// immutable schema; this projection only establishes the homogeneous value
// domain. Heterogeneous and open domains use the explicit JSON carrier unless
// this projector is operating under strict operation-derivation rules.
func (p *sourceProjector) jsonMapType(node schemajson.Node,path string,openAPI bool)(string,bool,error){
    additional,hasAdditional:=node.Lookup("additionalProperties");additionalSchema:=hasAdditional&&schemajson.KindName(additional.Kind())=="object"
    patterns,hasPatterns:=node.Lookup("patternProperties");patterned:=hasPatterns&&schemajson.KindName(patterns.Kind())=="object"&&len(patterns.Members())>0
    if !additionalSchema&&!patterned{return "",false,nil}
    candidates:=[]jsonMapCandidate{}
    if additionalSchema{candidates=append(candidates,jsonMapCandidate{additional,path+"/additionalProperties"})}else if patterned&&(!hasAdditional||additional.Raw()!="false"){if !p.strictStructure{return "Map String JSON",true,nil};return "",false,&Error{Code:"native.projection",Format:p.format,Pointer:path+"/additionalProperties",Message:"patternProperties leaves unmatched keys with an untyped value domain; set additionalProperties to one homogeneous schema or false"}}
    if patterned{for _,member:=range patterns.Members(){name,_:=member.Key.UTF8();candidates=append(candidates,jsonMapCandidate{member.Value,path+"/patternProperties/"+escapePointer(name)})}}
    if properties,ok:=node.Lookup("properties");ok{if schemajson.KindName(properties.Kind())!="object"{return "",false,&Error{Code:"native.projection",Format:p.format,Pointer:path+"/properties",Message:"properties must be an object"}};for _,member:=range properties.Members(){name,_:=member.Key.UTF8();candidates=append(candidates,jsonMapCandidate{member.Value,path+"/properties/"+escapePointer(name)})}}
    valueType:="";for _,candidate:=range candidates{projected,err:=p.jsonType(candidate.node,candidate.path,openAPI);if err!=nil{return "",false,err};if valueType==""{valueType=projected}else if projected!=valueType{if !p.strictStructure{return "Map String JSON",true,nil};return "",false,&Error{Code:"native.projection",Format:p.format,Pointer:candidate.path,Message:"JSON map value schemas project to heterogeneous language types ("+valueType+" and "+projected+"); use an explicit annotated Refine source until a common value type is authored"}}}
    if valueType==""{return "",false,&Error{Code:"native.projection",Format:p.format,Pointer:path,Message:"typed map has no projectable value schema"}}
    return "Map String ("+valueType+")",true,nil
}

func yamlToJSONDocument(root *yaml.Node)(schemajson.Document,error){var value any;if err:=root.Decode(&value);err!=nil{return schemajson.Document{},err};data,err:=json.Marshal(value);if err!=nil{return schemajson.Document{},err};return schemajson.Parse(data,schemajson.Limits{})}

func projectAvro(doc schemajson.Document,selector ResourceSelector)(string,error){p:=&sourceProjector{format:Avro,root:doc,avroNames:make(map[string]string),emitted:make(map[string]bool)};expr,err:=p.avroType(doc.Root(),selector.TypeName);if err!=nil{return "",err};if expr!=selector.TypeName||!p.emitted[selector.TypeName]{p.declarations=append(p.declarations,"type "+selector.TypeName+" = "+expr)};return strings.Join(p.declarations,"\n\n")+"\n",nil}

func (p *sourceProjector) avroType(node schemajson.Node,hint string)(string,error){switch schemajson.KindName(node.Kind()){
case "string":name,_:=nodeString(node);switch name{case "null":return "",&Error{Code:"native.projection",Format:Avro,Message:"null-only Avro schema has no payload type"};case "boolean":return "Bool",nil;case "int":return "Int32",nil;case "long":return "Int64",nil;case "float","double":return "Real",nil;case "bytes":return "[UInt8]",nil;case "string":return "String",nil};if mapped,ok:=p.avroNames[name];ok{return mapped,nil};return safeTypeName(name),nil
case "array":items:=node.Elements();if len(items)==2{nullIndex:=-1;for i,item:=range items{if name,ok:=nodeString(item);ok&&name=="null"{nullIndex=i}};if nullIndex>=0{inner,err:=p.avroType(items[1-nullIndex],hint);if err!=nil{return "",err};return "Nullable ("+inner+")",nil}};p.nextUnion++;unionName:=safeTypeName(fmt.Sprintf("%sUnion%d",hint,p.nextUnion));variants:=[]string{};for i,item:=range items{inner,err:=p.avroType(item,fmt.Sprintf("%sBranch%d",unionName,i+1));if err!=nil{return "",err};variants=append(variants,fmt.Sprintf("%sBranch%d (%s)",unionName,i+1,inner))};p.declarations=append(p.declarations,"data "+unionName+" = "+strings.Join(variants," | "));return unionName,nil
case "object":typeNode,ok:=node.Lookup("type");if !ok{return "",&Error{Code:"native.projection",Format:Avro,Message:"Avro schema object requires type"}};if schemajson.KindName(typeNode.Kind())!="string"{return p.avroType(typeNode,hint)};nativeType,_:=nodeString(typeNode);switch nativeType{
    case "record","error":nameNode,_:=node.Lookup("name");rawName,ok:=nodeString(nameNode);if !ok{return "",&Error{Code:"native.projection",Format:Avro,Message:"record name is required"}};name:=safeTypeName(rawName);p.avroNames[rawName]=name;if p.emitted[name]{return name,nil};p.emitted[name]=true;fieldsNode,_:=node.Lookup("fields");fields:=[]string{};for _,field:=range fieldsNode.Elements(){fieldNameNode,_:=field.Lookup("name");fieldName,ok:=nodeString(fieldNameNode);if !ok||!memberPattern.MatchString(fieldName){return "",&Error{Code:"native.projection",Format:Avro,Message:"record field is not a language identifier"}};fieldTypeNode,_:=field.Lookup("type");fieldType,err:=p.avroType(fieldTypeNode,name+safeTypeName(fieldName));if err!=nil{return "",err};fields=append(fields,fieldName+" :: "+fieldType)};p.declarations=append(p.declarations,"type "+name+" = {"+strings.Join(fields,", ")+"}");return name,nil
    case "array":items,_:=node.Lookup("items");inner,err:=p.avroType(items,hint+"Item");if err!=nil{return "",err};return "["+inner+"]",nil
    case "map":values,ok:=node.Lookup("values");if !ok{return "",&Error{Code:"native.projection",Format:Avro,Message:"Avro map values schema is absent"}};inner,err:=p.avroType(values,hint+"Value");if err!=nil{return "",err};return "Map String ("+inner+")",nil
    case "enum":nameNode,_:=node.Lookup("name");rawName,_:=nodeString(nameNode);name:=safeTypeName(rawName);if !p.emitted[name]{symbols,_:=node.Lookup("symbols");variants:=[]string{};for _,symbol:=range symbols.Elements(){raw,_:=nodeString(symbol);variants=append(variants,safeTypeName(raw))};p.declarations=append(p.declarations,"data "+name+" = "+strings.Join(variants," | "));p.emitted[name]=true};return name,nil
    case "fixed":return "[UInt8]",nil
    default:return p.avroType(typeNode,hint)
    }
};return "",&Error{Code:"native.projection",Format:Avro,Message:"unsupported Avro schema node"}}
