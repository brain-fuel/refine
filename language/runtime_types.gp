package language

// instantiate replaces inferred type variables using the current call's type
// arguments. It retains nominal names and rules; it never mutates checked ASTs.
func (e *evaluator) instantiate(t *Type,bindings map[string]typeBinding,depth int)*Type {
    if t==nil{return nil}
    e.step(1,t.At)
    if depth>=evaluationNesting{evalError(t.At,"evaluation.depth","type instantiation nesting limit exceeded")}
    result:=&Type{At:t.At}
    match t.Form {
    case NamedType(name):
        if bound,found:=bindings[name];found{return e.instantiate(bound.typ,bound.environment,depth+1)}
        return t
    case ListType(element):result.Form=ListType(e.instantiate(element,bindings,depth+1))
    case AppliedType(fn,arg):result.Form=AppliedType(e.instantiate(fn,bindings,depth+1),e.instantiate(arg,bindings,depth+1))
    case ArrowType(arg,out):result.Form=ArrowType(e.instantiate(arg,bindings,depth+1),e.instantiate(out,bindings,depth+1))
    case RecordType(fields):
        out:=make([]Field,len(fields));for i,field:=range fields{out[i]=field;out[i].Type=e.instantiate(field.Type,bindings,depth+1)}
        result.Form=RecordType(out)
    case RefinedType(base,rules):result.Form=RefinedType(e.instantiate(base,bindings,depth+1),rules)
    }
    return result
}

func bareType(t *Type)*Type {
    if t==nil{return nil}
    for {match t.Form {case RefinedType(base,_):t=base;case _:return t}}
}

// The static checker has already proved these shapes compatible. Matching
// recovers the concrete instantiation of a polymorphic named function, including
// type arguments supplied through higher-order functions and partial application.
func (e *evaluator) bindSignature(template,actual *Type,bindings map[string]typeBinding) {
    originalActual:=actual
    template,actual=bareType(template),bareType(actual)
    if template==nil || actual==nil{return}
    e.step(1,template.At)
    match template.Form {
    case NamedType(name):if !uppercase(name){bindings[name]=typeBinding{typ:originalActual}}
    case ArrowType(arg,out):match actual.Form {case ArrowType(a,b):e.bindSignature(arg,a,bindings);e.bindSignature(out,b,bindings);case _:}
    case AppliedType(fn,arg):match actual.Form {case AppliedType(a,b):e.bindSignature(fn,a,bindings);e.bindSignature(arg,b,bindings);case _:}
    case ListType(element):match actual.Form {case ListType(other):e.bindSignature(element,other,bindings);case _:}
    case RecordType(fields):match actual.Form {
        case RecordType(others):for _,field:=range fields{for _,other:=range others{e.step(1,template.At);if field.Name==other.Name{e.bindSignature(field.Type,other.Type,bindings);break}}}
        case _:
    }
    case RefinedType(_,_):panic("bareType retained a refinement")
    }
}

func (e *evaluator) functionBindings(name string,signature *Type)map[string]typeBinding {
    bindings:=make(map[string]typeBinding)
    if signature!=nil{e.bindSignature(e.functions[name].Signature,signature,bindings)}
    for param,symbol:=range e.module.functionScopes[name]{if bound,ok:=bindings[param];ok{bindings[symbol]=bound}}
    return bindings
}
