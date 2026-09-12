package language

import "fmt"

const DefaultSubstitutionNodes = 1 << 20

// SubstituteType performs capture-free simultaneous replacement of named type
// parameters. Replacement trees are caller-owned checked ASTs and are returned
// as-is: they are never recursively rebound through the same substitution.
// Unchanged Where expressions and source spans are retained by shallow copy.
func SubstituteType(t *Type,bindings map[string]*Type)(*Type,error){return SubstituteTypeBounded(t,bindings,DefaultSubstitutionNodes)}

// SubstituteTypeBounded applies the same operation with an explicit visited-node
// bound. Checked language types already obey the parser's depth bound; this
// additional bound makes the helper safe for manually assembled pathological ASTs.
func SubstituteTypeBounded(t *Type,bindings map[string]*Type,maxNodes int)(*Type,error){
    if t==nil{return nil,fmt.Errorf("type substitution requires a type")};if maxNodes<=0{return nil,fmt.Errorf("type substitution node limit must be positive")};visited:=0
    var walk func(*Type,int)(*Type,error);walk=func(current *Type,depth int)(*Type,error){
        if current==nil{return nil,fmt.Errorf("type substitution encountered a nil child")};visited++;if visited>maxNodes{return nil,fmt.Errorf("type substitution node limit exceeded")};if depth>512{return nil,fmt.Errorf("type substitution depth limit exceeded")}
        match current.Form{
        case NamedType(name):if replacement,ok:=bindings[name];ok{if replacement==nil{return nil,fmt.Errorf("type substitution for %s is nil",name)};return replacement,nil};copy:=*current;return &copy,nil
        case ListType(element):next,err:=walk(element,depth+1);if err!=nil{return nil,err};return &Type{Form:ListType{Element:next},At:current.At},nil
        case AppliedType(fn,arg):left,err:=walk(fn,depth+1);if err!=nil{return nil,err};right,err:=walk(arg,depth+1);if err!=nil{return nil,err};return &Type{Form:AppliedType{Constructor:left,Argument:right},At:current.At},nil
        case ArrowType(arg,result):left,err:=walk(arg,depth+1);if err!=nil{return nil,err};right,err:=walk(result,depth+1);if err!=nil{return nil,err};return &Type{Form:ArrowType{Argument:left,Result:right},At:current.At},nil
        case RecordType(fields):next:=make([]Field,len(fields));for i,field:=range fields{typ,err:=walk(field.Type,depth+1);if err!=nil{return nil,err};next[i]=field;next[i].Type=typ};return &Type{Form:RecordType{Fields:next},At:current.At},nil
        case RefinedType(base,rules):next,err:=walk(base,depth+1);if err!=nil{return nil,err};return &Type{Form:RefinedType{Base:next,Rules:append([]Where(nil),rules...)},At:current.At},nil
        };return nil,fmt.Errorf("unknown type form")
    };return walk(t,0)
}
