package native

import (
    "crypto/sha256"
    "fmt"

    "goforge.dev/refine/language"
)

const DefaultLowerGenericSpecializations = 512
const MaximumLowerGenericSpecializations = 4096

// genericApplication returns all arguments in source order. The checked type
// grammar represents application as a left-associated binary tree.
func genericApplication(t *language.Type)(string,[]*language.Type,bool){
    root:=t;arguments:=[]*language.Type{}
    for{match root.Form{case language.AppliedType(constructor,argument):arguments=append([]*language.Type{argument},arguments...);root=constructor;case language.NamedType(name):return name,arguments,true;case _:return "",nil,false}}
}

func genericDefinitionSeed(name,key string)string{digest:=sha256.Sum256([]byte(key));return fmt.Sprintf("%s__%x",name,digest[:])}

// specializationName is independent of map iteration and reserves every
// authored declaration name before lowering starts. A deliberately colliding
// authored name therefore receives the unsuffixed spelling and the generated
// specialization advances through a deterministic numeric suffix.
func (l *lowerer) specializationName(name,key string)(string,error){
    if existing,ok:=l.specializationNames[key];ok{return existing,nil}
    if l.specializationCount>=l.maxSpecializations{return "",&Error{Code:"native.limit",Format:l.format,Pointer:name,Message:fmt.Sprintf("generic specialization limit of %d exceeded",l.maxSpecializations)}}
    base:=genericDefinitionSeed(name,key);candidate:=base
    for suffix:=1;;suffix++{if _,taken:=l.nativeNames[candidate];!taken{break};candidate=fmt.Sprintf("%s_%d",base,suffix)}
    l.specializationCount++;l.specializationNames[key]=candidate;l.nativeNames[candidate]=key;return candidate,nil
}

func (l *lowerer) generic(t *language.Type)(any,error){
    name,arguments,ok:=genericApplication(t);if !ok{return nil,l.unrepresentable(language.FormatType(t),"applied type constructor is not a named declaration")}
    decl,found:=l.declarations[name];if !found||len(arguments)!=len(decl.Parameters){return nil,l.unrepresentable(language.FormatType(t),"unknown or incorrectly applied generic payload type")}
    if len(decl.Parameters)==0{return nil,l.unrepresentable(language.FormatType(t),"non-generic type was applied as a constructor")}
    key:=language.FormatType(t);wireName,err:=l.specializationName(name,key);if err!=nil{return nil,err}
    bindings:=make(map[string]*language.Type,len(decl.Parameters));for i,parameter:=range decl.Parameters{bindings[parameter]=arguments[i]}
    if decl.Body==nil{return l.genericTagged(wireName,name,decl,bindings)}
    body,err:=language.SubstituteTypeBounded(decl.Body,bindings,language.DefaultSubstitutionNodes);if err!=nil{return nil,&Error{Code:"native.limit",Format:l.format,Pointer:key,Message:"generic substitution exceeded its structural bound",Cause:err}}
    if l.format==Avro{return l.genericAvro(wireName,name,body)}
    refPrefix:="#/$defs/";if l.format==OpenAPI{refPrefix="#/components/schemas/"}
    if _,exists:=l.definitions[wireName];!exists{l.definitions[wireName]=map[string]any{};l.building[wireName]=true;oldOwner:=l.owner;l.owner=name;definition,buildErr:=l.typ(body,false);l.owner=oldOwner;delete(l.building,wireName);if buildErr==nil{definition,buildErr=l.applyExtraFieldPolicy(name,body,definition)};if buildErr!=nil{delete(l.definitions,wireName);return nil,buildErr};l.definitions[wireName]=definition}
    return map[string]any{"$ref":refPrefix+wireName},nil
}

func genericRecordBody(t *language.Type)bool{for{match t.Form{case language.RefinedType(base,_):t=base;case language.RecordType(_):return true;case _:return false}}}

func (l *lowerer) genericAvro(wireName,owner string,body *language.Type)(any,error){
    // Avro can name records, enums and fixed values, but not an arbitrary
    // alias. A specialized record is defined inline on first encounter so all
    // later/self references occur after its name enters Avro's symbol table.
    if !genericRecordBody(body){oldOwner:=l.owner;l.owner=owner;result,err:=l.typ(body,false);l.owner=oldOwner;return result,err}
    if l.avroDefined[wireName]{return wireName,nil};l.avroDefined[wireName]=true;result,err:=l.genericAvroNamed(wireName,owner,body);if err!=nil{delete(l.avroDefined,wireName);return nil,err};return result,nil
}

func (l *lowerer) genericAvroNamed(wireName,owner string,t *language.Type)(any,error){oldOwner:=l.owner;l.owner=owner;defer func(){l.owner=oldOwner}();match t.Form{
case language.RecordType(fields):return l.avroRecord(wireName,fields)
case language.RefinedType(base,rules):result,err:=l.genericAvroNamed(wireName,owner,base);if err!=nil{return nil,err};for _,rule:=range rules{l.lose(rule,language.FormatType(base))};return result,nil
case _:return l.typ(t,false)
}}

func (l *lowerer) genericTagged(wireName,owner string,decl language.TypeDecl,bindings map[string]*language.Type)(any,error){
    wire,ok:=l.discriminators[owner];if !ok{return nil,l.unrepresentable(owner,"tagged alternatives require explicit wire discriminator metadata")};if l.format==Avro{return nil,l.unrepresentable(owner,"tagged discriminator objects cannot be represented as Avro unions")}
    variants:=make([]language.Variant,len(decl.Variants));for i,variant:=range decl.Variants{variants[i]=variant;variants[i].Arguments=make([]*language.Type,len(variant.Arguments));for j,argument:=range variant.Arguments{closed,err:=language.SubstituteTypeBounded(argument,bindings,language.DefaultSubstitutionNodes);if err!=nil{return nil,&Error{Code:"native.limit",Format:l.format,Pointer:owner+"."+variant.Name,Message:"generic union substitution exceeded its structural bound",Cause:err}};variants[i].Arguments[j]=closed}}
    refPrefix:="#/$defs/";if l.format==OpenAPI{refPrefix="#/components/schemas/"}
    if _,exists:=l.definitions[wireName];!exists{l.definitions[wireName]=map[string]any{};l.building[wireName]=true;oldOwner:=l.owner;l.owner=owner;alternatives:=[]any{}
        for _,variant:=range variants{properties:=map[string]any{wire.Field:map[string]any{"const":wire.Values[variant.Name]}};required:=[]string{wire.Field};for i,argument:=range variant.Arguments{member:=wire.Arguments[variant.Name][i];schema,err:=l.typ(argument,true);if err!=nil{l.owner=oldOwner;delete(l.building,wireName);delete(l.definitions,wireName);return nil,atLower(err,owner+"."+variant.Name+"."+member)};properties[member]=schema;required=append(required,member)};alternatives=append(alternatives,map[string]any{"type":"object","properties":properties,"additionalProperties":false,"required":required})}
        l.owner=oldOwner;definition:=map[string]any{"oneOf":alternatives};if l.format==OpenAPI{definition["discriminator"]=map[string]any{"propertyName":wire.Field}};l.definitions[wireName]=definition;delete(l.building,wireName)
    }
    return map[string]any{"$ref":refPrefix+wireName},nil
}
