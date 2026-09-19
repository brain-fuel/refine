package provenance

import (
    "crypto/sha256"
    "encoding/json"
    "fmt"
    "strconv"
    "strings"

    "goforge.dev/refine/language"
    "goforge.dev/refine/schemajson"
    "goforge.dev/refine/value"
)

const maxAvroProvenanceSourceBytes=16*1024*1024

// Avro retains exact, independently auditable correspondences for the small
// subset of Avro structural constraints with identical refinement semantics.
// It does not validate a complete Avro schema and never replaces Original.
type Avro struct { document schemajson.Document; constraints []Constraint; sourceBytes int; numericExpansion int }

func (a *Avro)Original()string{if a==nil{return ""};return a.document.Raw()}
func (a *Avro)Constraints()[]Constraint{if a==nil{return nil};out:=make([]Constraint,len(a.constraints));for i,item:=range a.constraints{out[i]=copyConstraint(item)};return out}
// ForResource returns the same immutable correspondences with URI-framed
// identities. Multi-resource Avro projects use it so equal JSON Pointers in
// different schema documents cannot collide in one checked source module.
func (a *Avro)ForResource(resource string)*Avro{if a==nil{return nil};out:=&Avro{document:a.document,sourceBytes:a.sourceBytes,numericExpansion:a.numericExpansion,constraints:make([]Constraint,len(a.constraints))};for i,item:=range a.constraints{item.Resource=resource;identity:=avroIdentity(resource,item.Pointer);item.Name="Native_"+identity;item.Fingerprint=fmt.Sprintf("%x",sha256.Sum256([]byte("avro-1.12-provenance-v1\x00"+strconv.Itoa(len(resource))+":"+resource+"\x00"+item.Pointer+"\x00"+item.Scope+"\x00"+item.Native)));out.constraints[i]=copyConstraint(item)};return out}
func (a *Avro)ConstraintSource()string{if a==nil{return ""};var source strings.Builder;for _,constraint:=range a.constraints{source.WriteString("type "+constraint.Name+" = "+constraint.Scope+" where "+constraint.Predicate+"\n")};return source.String()}
func (a *Avro)AuditSource(source string)([]Finding,error){if a==nil{return nil,&Error{Code:"native.origin",Message:"Avro provenance is absent"}};return auditConstraintSource(a.constraints,source)}
func (a *Avro)RecoverNative(name,source string)(string,error){if a==nil{return "",&Error{Code:"native.origin",Message:"Avro provenance is absent"}};return recoverConstraintNative(a.constraints,name,source)}

// DiscoverAvro identifies only fixed size and the complete ordered enum symbol
// array at actual Avro schema positions. Defaults, docs, aliases and custom
// properties are data/metadata, never recursively guessed to be schemas.
// Structurally unsupported shapes stay opaque; full Avro validation belongs to
// the native package.
func DiscoverAvro(input []byte,limits schemajson.Limits)(*Avro,error){
    document,err:=schemajson.Parse(input,limits);if err!=nil{return nil,err};result:=&Avro{document:document};result.walk(document.Root(),"");return result,nil
}

func (a *Avro)walk(node schemajson.Node,path string){
    switch schemajson.KindName(node.Kind()){
    case "array":for i,item:=range node.Elements(){a.walk(item,fmt.Sprintf("%s/%d",path,i))}
    case "object":
        typ,ok:=node.Lookup("type");if !ok{return};kind:=schemajson.KindName(typ.Kind());if kind=="array"||kind=="object"{a.walk(typ,pointer(path,"type"));return};if kind!="string"{return};name,ok:=scalar(typ);if !ok{return}
        switch name{
        case "fixed":a.fixed(node,path)
        case "enum":a.enumeration(node,path)
        case "record","error":
            fields,ok:=node.Lookup("fields");if !ok||schemajson.KindName(fields.Kind())!="array"{return};for i,field:=range fields.Elements(){if schemajson.KindName(field.Kind())!="object"{continue};fieldType,ok:=field.Lookup("type");if ok{a.walk(fieldType,fmt.Sprintf("%s/fields/%d/type",path,i))}}
        case "array":if items,ok:=node.Lookup("items");ok{a.walk(items,pointer(path,"items"))}
        case "map":if values,ok:=node.Lookup("values");ok{a.walk(values,pointer(path,"values"))}
        }
    }
}

func (a *Avro)fixed(node schemajson.Node,path string){
    if name,ok:=node.Lookup("name");!ok||schemajson.KindName(name.Kind())!="string"{return};size,ok:=node.Lookup("size");if !ok||schemajson.KindName(size.Kind())!="number"{return};raw:=size.Raw();expansion,err:=jsonNumberExpansion(raw,maxJSONNumericExpansion);if err!=nil||expansion>maxJSONNumericExpansion-a.numericExpansion{return};a.numericExpansion+=expansion;if strings.ContainsAny(raw,"-.eE/"){return};number,err:=value.ParseNumber(raw);if err!=nil||!number.IsInteger()||number.Sign()<0{return};predicate,err:=language.ParseExpression("length it == "+number.Show());if err!=nil{return};a.add(path,"size","[UInt8]",language.FormatExpression(predicate),raw,[]string{"length"})
}

func (a *Avro)enumeration(node schemajson.Node,path string){
    if name,ok:=node.Lookup("name");!ok||schemajson.KindName(name.Kind())!="string"{return};symbols,ok:=node.Lookup("symbols");if !ok||schemajson.KindName(symbols.Kind())!="array"{return};items:=symbols.Elements();if len(items)==0{return};seen:=map[string]bool{};expressions:=make([]*language.Expr,len(items));estimated:=0
    for i,item:=range items{text,ok:=item.Text();if !ok{return};symbol,err:=text.UTF8();if err!=nil||!avroSymbolName(symbol)||seen[symbol]{return};seen[symbol]=true;quoted:=text.Show();if len(quoted)>maxAvroProvenanceSourceBytes-estimated{return};estimated+=len(quoted);expressions[i]=&language.Expr{Form:language.TextLiteral(quoted)}}
    predicate:=&language.Expr{Form:language.Apply(&language.Expr{Form:language.Apply(&language.Expr{Form:language.Variable("oneOf")},&language.Expr{Form:language.Variable("it")})},&language.Expr{Form:language.ListLiteral(expressions)})};a.add(path,"symbols","String",language.FormatExpression(predicate),symbols.Raw(),[]string{"oneOf"})
}

func (a *Avro)add(path,keyword,scope,predicate,native string,builtins []string){
    where:=pointer(path,keyword);identity:=avroIdentity("",where);name:="Native_"+identity;line:="type "+name+" = "+scope+" where "+predicate+"\n";if len(line)>maxAvroProvenanceSourceBytes-a.sourceBytes{return};a.sourceBytes+=len(line);fingerprint:=fmt.Sprintf("%x",sha256.Sum256([]byte("avro-1.12-provenance-v1\x00"+where+"\x00"+scope+"\x00"+native)));a.constraints=append(a.constraints,Constraint{Name:name,Pointer:where,SchemaPointer:path,Keyword:keyword,Scope:scope,Predicate:predicate,Native:native,Fingerprint:fingerprint,Builtins:builtins})
}

func avroIdentity(resource,where string)string{identityInput:="avro-1.12-provenance-v1\x00";if resource!=""{identityInput+=strconv.Itoa(len(resource))+":"+resource+"\x00"};identityInput+=where;return fmt.Sprintf("%x",sha256.Sum256([]byte(identityInput)))}

func avroSymbolName(name string)bool{if name==""{return false};for i,char:=range []byte(name){letter:=char>='A'&&char<='Z'||char>='a'&&char<='z'||char=='_';if i==0{if !letter{return false}}else if !letter&&(char<'0'||char>'9'){return false}};return true}

// LowerAvroConstraint is the exact structural inverse for one edited canonical
// Avro unit. It does not evaluate user functions or infer logical equivalence.
// The returned JSON token is canonical for edits; RecoverNative is the separate
// API that returns the exact original token only while the imported form holds.
func LowerAvroConstraint(program *language.Program,constraint Constraint)(string,error){
    scope,builtin:="","";switch constraint.Keyword{case "size":scope,builtin="[UInt8]","length";case "symbols":scope,builtin="String","oneOf";default:return "",avroInverseError(constraint,"unsupported Avro provenance keyword")};if program==nil{return "",avroInverseError(constraint,"a checked refinement program is required")};module:=program.Syntax();for _,fn:=range module.Functions{if fn.Name==builtin{return "",avroInverseError(constraint,"canonical builtin "+builtin+" is shadowed")}};var declaration *language.TypeDecl;for i:=range module.Types{if module.Types[i].Name==constraint.Name{item:=module.Types[i];declaration=&item;break}};if declaration==nil||len(declaration.Parameters)!=0||declaration.Body==nil{return "",avroInverseError(constraint,"canonical constraint declaration is absent or has parameters")};base:=declaration.Body;rules:=[]language.Where{};for base!=nil{advanced:=false;match base.Form{case language.RefinedType(inner,own):rules=append(rules,own...);base=inner;advanced=true;case _:};if !advanced{break}};if base==nil||language.FormatType(base)!=scope||len(rules)!=1{return "",avroInverseError(constraint,"edited unit must retain its scope and exactly one canonical clause")}
    switch constraint.Keyword{case "size":return lowerAvroSize(rules[0].Predicate,constraint);case "symbols":return lowerAvroSymbols(rules[0].Predicate,constraint)};return "",avroInverseError(constraint,"unsupported Avro provenance keyword")
}

func lowerAvroSize(predicate *language.Expr,constraint Constraint)(string,error){
    raw:="";match predicate.Form{case language.Binary(op,left,right):if op=="=="&&avroLengthIt(left){match right.Form{case language.NumberLiteral(text):raw=text;case _:}};case _:};if raw==""||strings.ContainsAny(raw,"-.eE/"){return "",avroInverseError(constraint,"fixed size must use length it == a nonnegative integer literal")};number,err:=value.ParseNumber(raw);if err!=nil||!number.IsInteger()||number.Sign()<0{return "",avroInverseError(constraint,"fixed size must be a nonnegative integer")};return number.Show(),nil
}

func avroLengthIt(expression *language.Expr)bool{match expression.Form{case language.Apply(fn,subject):match fn.Form{case language.Variable(name):if name!="length"{return false};case _:return false};match subject.Form{case language.Variable(name):return name=="it";case _:};case _:};return false}

func lowerAvroSymbols(predicate *language.Expr,constraint Constraint)(string,error){
    items:=[]*language.Expr{};match predicate.Form{case language.Apply(call,list):match call.Form{case language.Apply(fn,subject):match fn.Form{case language.Variable(name):if name!="oneOf"{return "",avroInverseError(constraint,"enum symbols must use oneOf it with an ordered string list")};case _:return "",avroInverseError(constraint,"enum symbols must use oneOf it with an ordered string list")};match subject.Form{case language.Variable(name):if name!="it"{return "",avroInverseError(constraint,"enum symbols must use oneOf it with an ordered string list")};case _:return "",avroInverseError(constraint,"enum symbols must use oneOf it with an ordered string list")};case _:return "",avroInverseError(constraint,"enum symbols must use oneOf it with an ordered string list")};match list.Form{case language.ListLiteral(values):items=values;case _:return "",avroInverseError(constraint,"enum symbols must use oneOf it with an ordered string list")};case _:return "",avroInverseError(constraint,"enum symbols must use oneOf it with an ordered string list")}
    if len(items)==0{return "",avroInverseError(constraint,"Avro enum symbols must be nonempty")};symbols:=make([]string,len(items));seen:=map[string]bool{};for i,item:=range items{quoted:="";match item.Form{case language.TextLiteral(raw):quoted=raw;case _:};text,err:=value.ReadText(quoted);if err!=nil{return "",avroInverseError(constraint,"Avro enum symbols must be string literals")};symbol,err:=text.UTF8();if err!=nil||!avroSymbolName(symbol)||seen[symbol]{return "",avroInverseError(constraint,"Avro enum symbols must be unique valid names")};seen[symbol]=true;symbols[i]=symbol};encoded,err:=json.Marshal(symbols);if err!=nil{return "",avroInverseError(constraint,"Avro enum symbols cannot be encoded")};return string(encoded),nil
}

func avroInverseError(constraint Constraint,message string)*Error{return &Error{Code:"native.inverse",Pointer:constraint.Pointer,Message:message}}
