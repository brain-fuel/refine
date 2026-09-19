// Package provenance tracks exact native-constraint/refinement correspondences.
// It is not a replacement for native schema structure or payload validation.
package provenance

import (
    "crypto/sha256"
    "fmt"
    "strings"

    "goforge.dev/refine/language"
    "goforge.dev/refine/schemajson"
)

type Error struct { Code string; Pointer string; Message string }
func (e *Error) Error()string{return e.Code+" at "+e.Pointer+": "+e.Message}
func valueLimit(err error)bool{problem,ok:=err.(*Error);return ok&&problem.Code=="native.value_limit"}

// Constraint describes one locally translatable native keyword. Scope is the
// Haskell type of that keyword's subject, not a claim about the whole document.
// SchemaPointer retains applicator context; e.g. a bound inside not/if/anyOf
// must never be hoisted into an unconditional root predicate.
type Constraint struct {
    Name string
    Resource string
    Pointer string
    SchemaPointer string
    Keyword string
    // PairedKeyword and PairedNative describe a second native member whose
    // semantics are inseparable from Keyword. OpenAPI 3.0 numeric bounds use
    // this for the Boolean exclusiveMinimum/exclusiveMaximum member. Empty
    // PairedNative means the member was omitted and its native default applies.
    PairedKeyword string
    PairedNative string
    Scope string
    Predicate string
    Native string
    Fingerprint string
    Builtins []string
}

// JSONSchema retains the entire original document, including native keywords
// without an exact DSL translation. Public descriptions are detached copies.
type JSONSchema struct { document schemajson.Document; constraints []Constraint; valueNodes int; numericExpansion int; sourceBytes int; maxValueNodes int; maxValueDepth int }
func (s *JSONSchema) Original()string{return s.document.Raw()}
func copyConstraint(c Constraint)Constraint{c.Builtins=append([]string(nil),c.Builtins...);return c}
func (s *JSONSchema) Constraints()[]Constraint{result:=make([]Constraint,len(s.constraints));for i,c:=range s.constraints{result[i]=copyConstraint(c)};return result}

// DiscoverJSONSchema identifies exact numeric-bound, collection-count and const/enum correspondences in
// Draft 2020-12 schema positions. It deliberately does not interpret arbitrary
// objects in annotations/examples as subschemas, infer types from constraints,
// resolve references, or substitute UTF-16 length/RE2 for native semantics.
// Full native structure validation and projection remain separate phases.
// Values that cannot fit the bounded intrinsic-JSON projection remain opaque
// native constraints instead of making an otherwise valid schema unimportable.
func DiscoverJSONSchema(input []byte,limits schemajson.Limits)(*JSONSchema,error){
    doc,err:=schemajson.Parse(input,limits);if err!=nil{return nil,err}
    inputNodes:=limits.Nodes;if inputNodes==0{inputNodes=schemajson.DefaultNodes};maxNodes:=1000000;if inputNodes<250000{maxNodes=inputNodes*4};if maxNodes<16{maxNodes=16}
    result:=&JSONSchema{document:doc,maxValueNodes:maxNodes,maxValueDepth:508}
    if err:=result.walk(doc.Root(),"");err!=nil{return nil,err}
    return result,nil
}

func pointer(path,key string)string{return path+"/"+strings.ReplaceAll(strings.ReplaceAll(key,"~","~0"),"/","~1")}
func scalar(node schemajson.Node)(string,bool){text,ok:=node.Text();if !ok{return "",false};raw,err:=text.UTF8();return raw,err==nil}

func numericScope(node schemajson.Node)string{
    typ,ok:=node.Lookup("type");if !ok{return ""}
    // A singleton type array has the same domain; heterogeneous type arrays do
    // not. A numeric keyword alone also accepts nonnumeric instances natively.
    if schemajson.KindName(typ.Kind())=="array"{items:=typ.Elements();if len(items)!=1{return ""};typ=items[0]}
    name,_:=scalar(typ)
    switch name{case "integer":return "Int";case "number":return "Real"}
    return ""
}

func canonicalBound(scope,operator,raw string)(string,error){
    left,right:="it",raw
    decimal:=strings.ContainsAny(raw,".eE")
    // Int and Real are distinct in the refinement language. Widening by exact
    // division avoids rounding a fractional integer bound or changing its native
    // token spelling. In particular, minimum 1.1 is not rewritten to minimum 2.
    if scope=="Int"&&decimal{left="it / 1"}
    if scope=="Real"&&!decimal{right="("+raw+" / 1)"}
    expression:=left+" "+operator+" "+right
    if operator=="multipleOf"{expression="isInteger (("+left+") / ("+right+"))"}
    expr,err:=language.ParseExpression(expression);if err!=nil{return "",err}
    return language.FormatExpression(expr),nil
}

const maxJSONValueSourceBytes=16*1024*1024
const maxJSONNumericExpansion=65536

func apply(name string,arg *language.Expr)*language.Expr{return &language.Expr{Form:language.Apply(&language.Expr{Form:language.Variable(name)},arg)}}

// canonicalJSONValue projects a native JSON value into the intrinsic JSON
// algebra without passing through encoding/json or floating point. Runtime
// equality then supplies exact rational numbers, ordered arrays and
// order-independent objects. Scalar Unicode is required because the
// refinement String domain cannot carry an isolated UTF-16 surrogate.
func (s *JSONSchema) chargeJSONValue(nodes,depth int)error{if depth>s.maxValueDepth{return &Error{Code:"native.value_limit",Message:"const/enum value exceeds the refinement expression depth limit"}};if nodes>s.maxValueNodes-s.valueNodes{return &Error{Code:"native.value_limit",Message:"const/enum values exceed the refinement expression node limit"}};s.valueNodes+=nodes;return nil}
func (s *JSONSchema) canonicalJSONValue(node schemajson.Node,depth int)(*language.Expr,error){
    if err:=s.chargeJSONValue(3,depth+2);err!=nil{return nil,err}
    raw:=node.Raw()
    switch schemajson.KindName(node.Kind()){
    case "null":return &language.Expr{Form:language.Variable("JSONNull")},nil
    case "boolean":value:=raw=="true";return apply("JSONBoolean",&language.Expr{Form:language.BoolLiteral(value)}),nil
    case "number":
        cost,err:=jsonNumberExpansion(raw,maxJSONNumericExpansion);if err!=nil{return nil,err};if cost>maxJSONNumericExpansion-s.numericExpansion{return nil,&Error{Code:"native.value_limit",Message:"const/enum exact numbers exceed the aggregate expansion limit"}};s.numericExpansion+=cost
        numberExpression,err:=language.ParseExpression(raw);if err!=nil{return nil,err}
        if !strings.ContainsAny(raw,".eE"){numberExpression=&language.Expr{Form:language.Binary("/",numberExpression,&language.Expr{Form:language.NumberLiteral("1")})}}
        return apply("JSONNumber",numberExpression),nil
    case "string":
        text,_:=node.Text();if _,err:=text.UTF8();err!=nil{return nil,&Error{Code:"native.value_unicode",Message:"const/enum strings must contain Unicode scalar values"}}
        return apply("JSONString",&language.Expr{Form:language.TextLiteral(text.Show())}),nil
    case "array":
        if node.ElementCount()>s.maxValueNodes-s.valueNodes{return nil,&Error{Code:"native.value_limit",Message:"const/enum array exceeds the remaining expression node limit"}}
        items:=node.Elements();expressions:=make([]*language.Expr,len(items));for i,item:=range items{expression,err:=s.canonicalJSONValue(item,depth+2);if err!=nil{return nil,err};expressions[i]=expression}
        return apply("JSONArray",&language.Expr{Form:language.ListLiteral(expressions)}),nil
    case "object":
        if node.MemberCount()>s.maxValueNodes-s.valueNodes{return nil,&Error{Code:"native.value_limit",Message:"const/enum object exceeds the remaining expression node limit"}}
        members:=node.Members();entries:=make([]language.MapValue,len(members))
        for i,member:=range members{if _,err:=member.Key.UTF8();err!=nil{return nil,&Error{Code:"native.value_unicode",Message:"const/enum object keys must contain Unicode scalar values"}};expression,err:=s.canonicalJSONValue(member.Value,depth+2);if err!=nil{return nil,err};entries[i]=language.MapValue{Key:member.Key.Show(),Value:expression}}
        return apply("JSONObject",&language.Expr{Form:language.MapLiteral(entries)}),nil
    }
    panic("unreachable JSON kind")
}

func jsonNumberExpansion(raw string,limit int)(int,error){
    if len(raw)>limit{return 0,&Error{Code:"native.value_limit",Message:"const/enum exact number token exceeds the expansion limit"}}
    exponent:="";if index:=strings.IndexAny(raw,"eE");index>=0{exponent=raw[index+1:]};if strings.HasPrefix(exponent,"+")||strings.HasPrefix(exponent,"-"){exponent=exponent[1:]}
    magnitude:=0;for _,char:=range exponent{digit:=int(char-'0');if digit<0||digit>9{return 0,&Error{Code:"native.value",Message:"const/enum contains an invalid exact JSON number"}};if magnitude>(limit-digit)/10{return 0,&Error{Code:"native.value_limit",Message:"const/enum exact number exponent exceeds the expansion limit"}};magnitude=magnitude*10+digit}
    if magnitude>limit-len(raw){return 0,&Error{Code:"native.value_limit",Message:"const/enum exact number exceeds the expansion limit"}};return len(raw)+magnitude,nil
}

func (s *JSONSchema) addConstraint(path,where,key,scope,predicate,native string,builtins []string)error{
    identity:=fmt.Sprintf("%x",sha256.Sum256([]byte("jsonschema2020-12\x00"+where)))
    fingerprint:=fmt.Sprintf("%x",sha256.Sum256([]byte("jsonschema2020-12\x00"+where+"\x00"+scope+"\x00"+native)))
    line:="type Native_"+identity+" = "+scope+" where "+predicate+"\n";if len(line)>maxJSONValueSourceBytes-s.sourceBytes{return &Error{Code:"native.value_limit",Pointer:where,Message:"canonical native constraint source exceeds the 16 MiB module limit"}};s.sourceBytes+=len(line)
    s.constraints=append(s.constraints,Constraint{Name:"Native_"+identity,Pointer:where,SchemaPointer:path,Keyword:key,Scope:scope,Predicate:predicate,Native:native,Fingerprint:fingerprint,Builtins:builtins})
    return nil
}

func (s *JSONSchema) walk(node schemajson.Node,path string)error{
    switch schemajson.KindName(node.Kind()){
    case "boolean":return nil
    case "object":
    default:return &Error{Code:"native.schema_position",Pointer:path,Message:"a JSON Schema position must contain an object or Boolean"}
    }
    if dialect,ok:=node.Lookup("$schema");ok{
        name,text:=scalar(dialect)
        if !text || strings.TrimSuffix(name,"#")!="https://json-schema.org/draft/2020-12/schema"{
            return &Error{Code:"native.dialect",Pointer:pointer(path,"$schema"),Message:"constraint discovery requires the Draft 2020-12 dialect"}
        }
    }
    scope:=numericScope(node)
    for _,member:=range node.Members(){
        key,err:=member.Key.UTF8();if err!=nil{continue} // retained native unknown key
        where:=pointer(path,key)
        if handled,err:=s.cardinalityConstraint(node,path,key,member.Value);handled{if err!=nil{return err};continue}
        if key=="const"||key=="enum"{
            priorNodes,priorExpansion:=s.valueNodes,s.numericExpansion
            values:=[]schemajson.Node{member.Value};if key=="enum"{if schemajson.KindName(member.Value.Kind())!="array"{return &Error{Code:"native.enum",Pointer:where,Message:"enum must contain an array of JSON values"}};values=member.Value.Elements()}
            expressions:=make([]*language.Expr,len(values));projectable:=true
            // Draft 2020-12 recommends, but does not require, unique enum
            // elements. Preserve duplicates exactly instead of strengthening
            // the native schema during provenance projection.
            for i,item:=range values{expression,err:=s.canonicalJSONValue(item,2);if valueLimit(err){projectable=false;break};if problem,ok:=err.(*Error);ok&&problem.Pointer==""{problem.Pointer=where};if err!=nil{return err};expressions[i]=expression}
            if !projectable{s.valueNodes=priorNodes;s.numericExpansion=priorExpansion;continue}
            var predicate *language.Expr;builtins:=[]string{}
            if key=="const"{predicate=&language.Expr{Form:language.Binary("==",&language.Expr{Form:language.Variable("it")},expressions[0])}}else{predicate=&language.Expr{Form:language.Apply(&language.Expr{Form:language.Apply(&language.Expr{Form:language.Variable("oneOf")},&language.Expr{Form:language.Variable("it")})},&language.Expr{Form:language.ListLiteral(expressions)})};builtins=[]string{"oneOf"}}
            formatted:=language.FormatExpression(predicate);if len(formatted)>maxJSONValueSourceBytes{s.valueNodes=priorNodes;s.numericExpansion=priorExpansion;continue}
            if err:=s.addConstraint(path,where,key,"JSON",formatted,member.Value.Raw(),builtins);err!=nil{if valueLimit(err){s.valueNodes=priorNodes;s.numericExpansion=priorExpansion;continue};return err}
        }
        operator:=""
        switch key{case "minimum":operator=">=";case "maximum":operator="<=";case "exclusiveMinimum":operator=">";case "exclusiveMaximum":operator="<";case "multipleOf":operator=key}
        if operator!="" {
            if schemajson.KindName(member.Value.Kind())!="number"{return &Error{Code:"native.bound",Pointer:where,Message:"numeric bounds must contain a JSON number"}}
            if key=="multipleOf"{
                // Determine positivity lexically, without expanding an arbitrary
                // decimal exponent while merely discovering schema syntax.
                raw:=member.Value.Raw();mantissa:=strings.SplitN(strings.ToLower(raw),"e",2)[0]
                if strings.HasPrefix(raw,"-")||strings.Trim(mantissa,"0.")==""{return &Error{Code:"native.multiple",Pointer:where,Message:"multipleOf must be strictly positive"}}
            }
            if scope!="" {
                predicate,err:=canonicalBound(scope,operator,member.Value.Raw());if err!=nil{return err}
                builtins:=[]string{};if key=="multipleOf"{builtins=append(builtins,"isInteger")}
                if err:=s.addConstraint(path,where,key,scope,predicate,member.Value.Raw(),builtins);err!=nil{if valueLimit(err){continue};return err}
            }
        }
        switch key{
        case "additionalProperties","unevaluatedProperties","propertyNames","contains","items","unevaluatedItems","if","then","else","not","contentSchema":
            if err:=s.walk(member.Value,where);err!=nil{return err}
        case "$defs","properties","patternProperties","dependentSchemas":
            if schemajson.KindName(member.Value.Kind())!="object"{return &Error{Code:"native.schema_map",Pointer:where,Message:"schema map must be an object"}}
            for _,child:=range member.Value.Members(){
                name,err:=child.Key.UTF8()
                if err!=nil{return &Error{Code:"native.pointer_encoding",Pointer:where,Message:"subschema names require scalar Unicode for JSON Pointer provenance"}}
                if err:=s.walk(child.Value,pointer(where,name));err!=nil{return err}
            }
        case "allOf","anyOf","oneOf","prefixItems":
            if schemajson.KindName(member.Value.Kind())!="array"{return &Error{Code:"native.schema_array",Pointer:where,Message:"schema applicator must be an array"}}
            for i,child:=range member.Value.Elements(){if err:=s.walk(child,fmt.Sprintf("%s/%d",where,i));err!=nil{return err}}
        }
    }
    return nil
}

// ConstraintSource emits independently typed, editable constraint declarations.
// It is a projection of the discovered units, NOT a standalone replacement for
// the native schema: applicators/references/API metadata remain in Original().
// Keeping that distinction prevents a local bound under `not` from accidentally
// becoming an unconditional rule. Full contract assembly uses these same units.
func (s *JSONSchema) ConstraintSource()string{
    var source strings.Builder
    for _,constraint:=range s.constraints{
        source.WriteString("type "+constraint.Name+" = "+constraint.Scope+" where "+constraint.Predicate+"\n")
    }
    return source.String()
}

type Status enum { Unchanged; Changed; Removed }
func StatusName(status Status)string{match status{case Unchanged():return "unchanged";case Changed():return "changed";case Removed():return "removed"}}
type Finding struct { Constraint Constraint; Status Status }

// AuditSource statically checks an edited constraint projection and reports each
// native correspondence independently. Formatting and extra where clauses do
// not invalidate an untouched rule; logically equivalent predicate rewrites do.
// Arbitrary new declarations/rules are allowed and have no native guarantee to
// break. No predicate executes, and no edited native output is silently emitted.
func (s *JSONSchema) AuditSource(source string)([]Finding,error){
    program,err:=language.Compile(source);if err!=nil{return nil,err}
    module:=program.Syntax()
    declarations:=make(map[string]language.TypeDecl)
    for _,decl:=range module.Types{declarations[decl.Name]=decl}
    functions:=make(map[string]bool);for _,fn:=range module.Functions{functions[fn.Name]=true}
    result:=make([]Finding,0,len(s.constraints))
    for _,constraint:=range s.constraints{
        var status Status=Removed()
        if decl,exists:=declarations[constraint.Name];exists{
            status=Changed()
            base:=decl.Body;rules:=[]language.Where{}
            for base!=nil{stop:=false;match base.Form{case language.RefinedType(inner,own):rules=append(rules,own...);base=inner;case _:stop=true};if stop{break}}
            bindingsIntact:=true;for _,builtin:=range constraint.Builtins{if functions[builtin]{bindingsIntact=false}}
            if bindingsIntact&&base!=nil&&len(decl.Parameters)==0&&language.FormatType(base)==constraint.Scope{
                for _,rule:=range rules{if language.FormatExpression(rule.Predicate)==constraint.Predicate{status=Unchanged();break}}
            }
        }
        result=append(result,Finding{Constraint:copyConstraint(constraint),Status:status})
    }
    return result,nil
}

// RecoverNative returns the exact original native token only when the selected
// constraint's canonical form still holds. A caller cannot accidentally claim
// a bijection after editing a bound. Other constraints remain recoverable.
func (s *JSONSchema) RecoverNative(name,source string)(string,error){
    findings,err:=s.AuditSource(source);if err!=nil{return "",err}
    for _,finding:=range findings{
        if finding.Constraint.Name!=name{continue}
        match finding.Status{case Unchanged():return finding.Constraint.Native,nil;case _:return "",&Error{Code:"native.bijection_changed",Pointer:finding.Constraint.Pointer,Message:"native constraint is no longer in its imported canonical refinement form"}}
    }
    return "",&Error{Code:"native.origin",Message:"constraint does not belong to this imported document"}
}
