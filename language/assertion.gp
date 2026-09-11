package language

import "goforge.dev/refine/validation"

// assertInline enforces newly asserted anonymous refinements without rerunning
// named parent predicates merely for substitution. Function contracts become
// immutable wrappers, so pre/postconditions survive higher-order use and run
// at each curried application boundary, not only after the final argument.
func (e *evaluator) assertInline(t *Type,input evalValue,types map[string]typeBinding)evalValue {
    e.enter(t.At);defer func(){e.depth--}()
    match t.Form {
    case NamedType(name):
        if bound,ok:=types[name];ok{return e.assertInline(bound.typ,input,bound.environment)}
        return input
    case RefinedType(base,rules):
        checked:=e.assertInline(base,input,types)
        v:=&payloadValidator{program:&Program{module:e.module},structure:e,enclosing:e}
        for _,rule:=range rules{v.rule(rule,checked,"",types)}
        report:=validation.Collect(v.checks)
        switch validation.StateName(report.State()) {
        case "valid":return checked
        case "invalid":evalError(t.At,"evaluation.refinement","an anonymous type refinement failed")
        default:evalError(t.At,"evaluation.refinement_unknown","an anonymous type refinement could not be determined")
        }
    case ArrowType(arg,result):
        match input.form {
        case EvalFunction(_,_,_):return evalValue{form:EvalGuardedFunction(input,arg,result,types)}
        case EvalGuardedFunction(_,_,_,_):return evalValue{form:EvalGuardedFunction(input,arg,result,types)}
        case _:evalError(t.At,"evaluation.type","a function contract requires a function value")
        }
    case ListType(element):
        items:=itemsOf(input,t.At);e.step(uint64(len(items)),t.At)
        result:=make([]evalValue,len(items));for i,item:=range items{result[i]=e.assertInline(element,item,types)}
        return evalValue{form:EvalList(result)}
    case RecordType(fields):
        match input.form {
        case EvalRecord(actual):
            e.step(uint64(len(actual)),t.At);result:=append([]evalField(nil),actual...)
            for _,field:=range fields{found:=false;for i,member:=range result{e.step(1,t.At);if member.name==field.Name{result[i].value=e.assertInline(field.Type,member.value,types);found=true;break}};if !found{evalError(t.At,"evaluation.type","a required annotated field is absent")}}
            return evalValue{form:EvalRecord(result)}
        case _:evalError(t.At,"evaluation.type","a record annotation requires a record")
        }
    case AppliedType(_,_):
        root:=t;args:=[]*Type{}
        for{stop:=false;match root.Form{case AppliedType(fn,arg):e.step(1,t.At);args=append([]*Type{arg},args...);root=fn;case _:stop=true};if stop{break}}
        match root.Form {case NamedType(name):return e.assertApplication(name,args,input,types,t.At);case _:evalError(t.At,"evaluation.type","unsupported annotated type application")}
    }
    panic("unreachable anonymous assertion")
}

func (e *evaluator) assertApplication(name string,args []*Type,input evalValue,types map[string]typeBinding,at Span)evalValue {
    if name=="Maybe" || name=="Nullable" || name=="Result" {
        match input.form {
        case EvalVariant(tag,values):
            if len(values)==0{return input}
            index:=0;if name=="Result" && tag=="Ok"{index=1}
            return evalValue{form:EvalVariant(tag,[]evalValue{e.assertInline(args[index],values[0],types)})}
        case _:evalError(at,"evaluation.type","expected a constructor for an annotated type")
        }
    }
    for _,decl:=range e.module.Types{
        e.step(1,at);if decl.Name!=name{continue}
        bindings:=make(map[string]typeBinding)
        for i,param:=range decl.Parameters{bindings[param]=typeBinding{typ:args[i],environment:types}}
        if decl.Body!=nil{return e.assertInline(e.eraseDeclaredRules(decl.Body),input,bindings)}
        match input.form {
        case EvalVariant(tag,values):
            for _,variant:=range decl.Variants{
                e.step(1,at);if variant.Name!=tag{continue}
                result:=make([]evalValue,len(values))
                for i,arg:=range variant.Arguments{result[i]=e.assertInline(e.eraseDeclaredRules(arg),values[i],bindings)}
                return evalValue{form:EvalVariant(tag,result)}
            }
        case _:
        }
        evalError(at,"evaluation.type","constructor does not match an annotated type")
    }
    evalError(at,"evaluation.type","unresolved annotated type");return evalValue{}
}

// Rules written in a named declaration are already guaranteed by its nominal
// value. Only rules newly supplied as type arguments must be checked here.
func (e *evaluator) eraseDeclaredRules(t *Type)*Type {
    e.enter(t.At);defer func(){e.depth--}()
    result:=&Type{At:t.At}
    match t.Form {
    case NamedType(_):return t
    case RefinedType(base,_):return e.eraseDeclaredRules(base)
    case ListType(element):result.Form=ListType(e.eraseDeclaredRules(element))
    case AppliedType(fn,arg):result.Form=AppliedType(e.eraseDeclaredRules(fn),e.eraseDeclaredRules(arg))
    case ArrowType(arg,out):result.Form=ArrowType(e.eraseDeclaredRules(arg),e.eraseDeclaredRules(out))
    case RecordType(fields):
        e.step(uint64(len(fields)),t.At);copied:=append([]Field(nil),fields...);for i:=range copied{copied[i].Type=e.eraseDeclaredRules(copied[i].Type)};result.Form=RecordType(copied)
    }
    return result
}
