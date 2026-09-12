package language

import (
    "crypto/sha256"
    "fmt"
    "strconv"
    "strings"

    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

type typeBinding struct { typ *Type; environment map[string]typeBinding }
type payloadValidator struct {
    program *Program
    declarations map[string]TypeDecl
    budget *validation.Budget
    structure *evaluator
    checks []validation.Check
    currentPath string
    enclosing *evaluator
    withoutRefinements bool
}

// ValidateData checks a named, non-parameterized root declaration against an
// immutable language payload. Parameterized types may occur inside that root.
// This is not JSON/Avro decoding: Maybe/Nullable/data alternatives use Data's
// explicit constructors. No native wire representation is guessed here.
// Unsupported execution features produce Indeterminate, never silent success.
// Program and Data are immutable; each call owns its meters and diagnostics.
func (p *Program) ValidateData(root string,data value.Data,caller validation.Limits) validation.Report {
    return p.validateData(root,data,caller,false)
}

// ValidateDataWithoutRefinements is the explicit structural-only bypass used by
// generated model factories. It still checks declared shapes, fixed-width
// representability, timestamps and resource limits; it never changes the input.
func (p *Program) ValidateDataWithoutRefinements(root string,data value.Data,caller validation.Limits) validation.Report {
    return p.validateData(root,data,caller,true)
}

func (p *Program) validateData(root string,data value.Data,caller validation.Limits,withoutRefinements bool) validation.Report {
    v:=&payloadValidator{program:p,declarations:make(map[string]TypeDecl),budget:validation.NewBudget(validation.Limits{},caller),withoutRefinements:withoutRefinements}
    for _,decl:=range p.module.Types {v.declarations[decl.Name]=decl}
    decl,found:=v.declarations[root]
    if !found || len(decl.Parameters)!=0 {
        return validation.Collect([]validation.Check{validation.Violated(validation.Diagnostic{Code:"validation.root",Paths:[]string{""},Message:"Choose a declared root type with no unbound type parameters."})})
    }
    v.structure=newEvaluator(p.module,v.budget.BeginStructure())
    v.run(&Type{Form:NamedType(root),At:decl.At},data)
    return validation.Collect(v.checks)
}

func (v *payloadValidator) run(root *Type,data value.Data) {
    defer func(){
        if caught:=recover();caught!=nil {
            if failure,ok:=caught.(*evalFailure);ok {
                v.checks=append(v.checks,validation.Undecided(validation.Diagnostic{Code:failure.code,Paths:[]string{v.currentPath},Message:failure.message}))
            }else{panic(caught)}
        }
    }()
    input:=v.structure.fromData(data,root.At)
    v.check(root,input,nil,"")
}
func pointerField(path,name string)string { return path+"/"+strings.ReplaceAll(strings.ReplaceAll(name,"~","~0"),"/","~1") }
func (v *payloadValidator) wrong(path,message string)(evalValue,bool) {
    v.checks=append(v.checks,validation.Violated(validation.Diagnostic{Code:"validation.structure",Paths:[]string{path},Message:message}))
    return evalValue{},false
}

func (v *payloadValidator) check(t *Type,input evalValue,env map[string]typeBinding,path string)(evalValue,bool) {
    v.currentPath=path
    v.structure.enter(t.At);defer func(){v.structure.depth--}()
    match t.Form {
    case RefinedType(base,rules):
        result,ok:=v.check(base,input,env,path)
        if ok && !v.withoutRefinements {for _,rule:=range rules {v.rule(rule,result,path,env)}}
        return result,ok
    case NamedType(name):
        if bound,found:=env[name];found {return v.check(bound.typ,input,bound.environment,path)}
        return v.named(name,nil,input,env,path,t.At)
    case AppliedType(_,_):
        root:=t;args:=[]*Type{}
        for {stop:=false;match root.Form {case AppliedType(fn,arg):args=append([]*Type{arg},args...);root=fn;case _:stop=true};if stop{break}}
        match root.Form {case NamedType(name):return v.named(name,args,input,env,path,t.At);case _:evalError(t.At,"evaluation.type","unsupported applied payload type")}
    case ListType(element):
        match input.form {
        case EvalList(items):
            v.structure.step(uint64(len(items)),t.At)
            result:=make([]evalValue,len(items));all:=true
            for i,item:=range items {var ok bool;result[i],ok=v.check(element,item,env,pointerField(path,strconv.Itoa(i)));all=all&&ok}
            return evalValue{form:EvalList(result)},all
        case _:return v.wrong(path,"Expected a list.")
        }
    case RecordType(fields):
        match input.form {
        case EvalRecord(actual):
            v.structure.step(uint64(len(actual)+len(fields)),t.At)
            byName:=make(map[string]evalValue,len(actual));for _,field:=range actual {byName[field.name]=field.value}
            result:=make([]evalField,0,len(fields));all:=true
            for _,field:=range fields {
                fieldPath:=pointerField(path,field.Name)
                item,found:=byName[field.Name]
                if !found {
                    if v.optional(field.Type,env,0) {item=evalValue{form:EvalVariant("Nothing",nil)}}else{v.wrong(fieldPath,"Required field is absent.");all=false;continue}
                }
                checked,ok:=v.check(field.Type,item,env,fieldPath);all=all&&ok
                result=append(result,evalField{name:field.Name,value:checked})
            }
            // Standalone records permit extras. The typed view uses declared
            // fields; the immutable caller's raw payload is never modified.
            return evalValue{form:EvalRecord(result)},all
        case _:return v.wrong(path,"Expected a record.")
        }
    case ArrowType(_,_):return v.wrong(path,"A function is not a payload value.")
    }
    panic("unreachable payload type")
}

func (v *payloadValidator) named(name string,args []*Type,input evalValue,env map[string]typeBinding,path string,at Span)(evalValue,bool) {
    switch name {
    case "Bool":match input.form {case EvalBool(_):return input,true;case _:return v.wrong(path,"Expected a Boolean.")}
    case "String":match input.form {case EvalText(_):return input,true;case _:return v.wrong(path,"Expected text.")}
    case "Timestamp":
        match input.form {
        case EvalTimestamp(_):return input,true
        case EvalText(text):
            size:=uint64(text.Length())
            if size>0 && size>(^uint64(0)-1)/size{evalError(at,"evaluation.budget","timestamp parsing cost exceeds evaluation resources")}
            v.structure.step(size*size+1,at)
            raw,err:=text.UTF8();if err!=nil{return v.wrong(path,"Expected an RFC 3339 timestamp.")}
            parsed,err:=value.ParseTimestamp(raw)
            if err!=nil{
                problem:=err.(*value.TimestampError)
                detail:=validation.Diagnostic{Code:problem.Code,Paths:[]string{path},Message:problem.Message}
                if problem.Code=="timestamp.unknown_leap"{v.checks=append(v.checks,validation.Undecided(detail))}else{v.checks=append(v.checks,validation.Violated(detail))}
                return evalValue{},false
            }
            return evalValue{form:EvalTimestamp(parsed)},true
        case _:return v.wrong(path,"Expected an RFC 3339 timestamp.")
        }
    case "Maybe","Nullable","Result":
        match input.form {
        case EvalVariant(tag,values):
            none,some,index:="Nothing","Just",0
            if name=="Nullable" {none,some="Null","NonNull"}
            if name=="Result" {none,some="Err","Ok";if tag=="Ok"{index=1}}
            if name!="Result" && tag==none && len(values)==0{return input,true}
            if (tag==some || name=="Result" && tag==none) && len(values)==1 {
                checked,ok:=v.check(args[index],values[0],env,path)
                return evalValue{form:EvalVariant(tag,[]evalValue{checked})},ok
            }
            return v.wrong(path,"Constructor does not match the declared optional, nullable, or result type.")
        case _:return v.wrong(path,"Expected an explicit optional, nullable, or result constructor.")
        }
    case "Map":
        if len(args)!=2{return v.wrong(path,"Map requires String keys and one value type.")};match input.form{case EvalMap(entries):
            v.structure.step(uint64(len(entries)),at);result:=make([]evalMapEntry,len(entries));all:=true;for i,entry:=range entries{checked,ok:=v.check(args[1],entry.value,env,pointerField(path,strconv.Itoa(i)));all=all&&ok;result[i]=evalMapEntry{key:entry.key,value:checked}};return v.structure.mapValue(result,at),all
        case _:return v.wrong(path,"Expected a map.")}
    }
    if primitive(name) {
        match input.form {
        case EvalNumber(n,_):
            v.structure.step(uint64(len(n.Show())),at)
            if name=="Float32"||name=="Float64" {
                v.structure.step(64,at)
                if _,err:=exactFloat(n,name);err!=nil{return v.wrong(path,"Number is not exactly representable as finite "+name+".")}
                return numberValue(n,name),true
            }
            if name!="Real" && !n.IsInteger(){return v.wrong(path,"Expected an integer without fractional coercion.")}
            if name!="Int" && name!="Real" {
                digits:=strings.TrimPrefix(strings.TrimPrefix(name,"UInt"),"Int");width,err:=strconv.ParseUint(digits,10,32)
                if err!=nil {evalError(at,"evaluation.type","unsupported numeric width")}
                v.structure.step(width,at)
                if width>65536 {evalError(at,"evaluation.unsupported","integer width exceeds the current numeric backend limit")}
                if _,err:=n.FixedWidth(uint(width),!strings.HasPrefix(name,"UInt"));err!=nil{return v.wrong(path,"Integer is outside its declared fixed-width range.")}
            }
            return numberValue(n,name),true
        case _:return v.wrong(path,"Expected an exact number.")
        }
    }
    decl,found:=v.declarations[name]
    if !found || len(args)!=len(decl.Parameters){evalError(at,"evaluation.type","unresolved payload type or type arguments")}
    bindings:=make(map[string]typeBinding)
    for i,param:=range decl.Parameters {bindings[param]=typeBinding{typ:args[i],environment:env}}
    for param,symbol:=range v.program.module.declarationScopes[name]{if bound,ok:=bindings[param];ok{bindings[symbol]=bound}}
    if decl.Body!=nil{return v.check(decl.Body,input,bindings,path)}
    match input.form {
    case EvalVariant(tag,values):
        for _,variant:=range decl.Variants {
            v.structure.step(1,at)
            if tag!=variant.Name {continue}
            if len(values)!=len(variant.Arguments){return v.wrong(path,"Constructor has the wrong number of arguments.")}
            result:=make([]evalValue,len(values));all:=true
            for i,arg:=range variant.Arguments {var ok bool;result[i],ok=v.check(arg,values[i],bindings,pointerField(path,strconv.Itoa(i)));all=all&&ok}
            return evalValue{form:EvalVariant(tag,result)},all
        }
        return v.wrong(path,"Constructor does not belong to the declared data type.")
    case _:return v.wrong(path,"Expected a tagged data alternative.")
    }
}

func (v *payloadValidator) optional(t *Type,env map[string]typeBinding,depth int)bool {
    v.structure.step(1,t.At)
    if depth>=evaluationNesting {evalError(t.At,"evaluation.depth","optional type expansion nesting limit exceeded")}
    match t.Form {
    case RefinedType(base,_):return v.optional(base,env,depth+1)
    case NamedType(name):
        if bound,found:=env[name];found{return v.optional(bound.typ,bound.environment,depth+1)}
        if decl,found:=v.declarations[name];found && decl.Body!=nil && len(decl.Parameters)==0{return v.optional(decl.Body,nil,depth+1)}
    case AppliedType(_,_):
        root:=t;args:=[]*Type{}
        for {stop:=false;match root.Form {case AppliedType(fn,arg):args=append([]*Type{arg},args...);root=fn;case _:stop=true};if stop{break}}
        match root.Form {
        case NamedType(name):
            if name=="Maybe" && len(args)==1{return true}
            if decl,found:=v.declarations[name];found && decl.Body!=nil && len(decl.Parameters)==len(args) {
                bindings:=make(map[string]typeBinding)
                for i,param:=range decl.Parameters {bindings[param]=typeBinding{typ:args[i],environment:env}}
                return v.optional(decl.Body,bindings,depth+1)
            }
        case _:
        }
    case _:
    }
    return false
}

func (v *payloadValidator) rule(rule Where,input evalValue,path string,types map[string]typeBinding) {
    predicate:=FormatExpression(rule.Predicate)
    code:=rule.Code
    if code==""{digest:=sha256.Sum256([]byte(fmt.Sprintf("%s:%d:%s",path,rule.At.Start.Offset,predicate)));code=fmt.Sprintf("refine.%x",digest[:8])}
    detail:=validation.Diagnostic{Code:code,Paths:[]string{path},Predicate:predicate,Message:"Value must satisfy the declared condition: "+predicate+"."}
    var meter *validation.Meter
    depth:=0
    if v.enclosing!=nil{meter=v.enclosing.meter.Nested(rule.Steps);depth=v.enclosing.depth}else{meter=v.budget.BeginClause(rule.Steps)}
    e:=&evaluator{module:v.program.module,functions:v.structure.functions,constructors:v.structure.constructors,meter:meter,depth:depth,typeEnvironment:types}
    env:=map[string]evalValue{"it":input}
    result,failure:=e.attempt(rule.Predicate,env)
    if failure!=nil {
        detail.Message="Could not determine whether the condition holds: "+failure.code+": "+failure.message+"."
        v.checks=append(v.checks,validation.Undecided(detail));return
    }
    if boolean(result,rule.At){v.checks=append(v.checks,validation.Satisfied());return}
    if rule.Message!=nil {
        custom,failed:=e.attempt(rule.Message,env)
        if failed==nil {
            match custom.form {
            case EvalText(text):if message,err:=text.UTF8();err==nil{detail.Message=message}
            case _:
            }
        }
    }
    // Message failure cannot erase the conclusive violation or mark it unknown.
    v.checks=append(v.checks,validation.Violated(detail))
}
