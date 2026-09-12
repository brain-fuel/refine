package language

import (
    "fmt"
    "sort"
    "strconv"
    "strings"

    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

// This private execution core supports validating payload and codec boundaries.
// Only compiler-owned ASTs enter it. It never resolves an import,
// loads a plugin, reflects over host values, or invokes a host callback.
// Function values are immutable partial applications of checked named functions.
type evalValue struct { form evalForm; signature *Type }
//goplus:derive off
type evalForm enum {
    EvalNumber(Value value.Number, NumericType string)
    EvalText(Value value.Text)
    EvalTimestamp(Value value.Timestamp)
    EvalBool(Value bool)
    EvalList(Items []evalValue)
    EvalRecord(Fields []evalField)
    EvalMap(Entries []evalMapEntry)
    EvalVariant(Name string, Arguments []evalValue)
    EvalFunction(Name string, Arity int, Arguments []evalValue)
    EvalGuardedFunction(Function evalValue, Argument *Type, Result *Type, Types map[string]typeBinding)
}
type evalField struct { name string; value evalValue }
type evalMapEntry struct { key value.Text; value evalValue }
type evalFailure struct { code string; at Span; message string }
func (f *evalFailure) Error() string { return fmt.Sprintf("%s at %d:%d: %s",f.code,f.at.Start.Line,f.at.Start.Column,f.message) }
type evaluator struct {
    module *Module
    functions map[string]Function
    constructors map[string]int
    meter *validation.Meter
    depth int
    typeEnvironment map[string]typeBinding
}

// Structural helper nesting is an independent deterministic safety cap.
// Named expression/function recursion uses evalWork instead, so nontermination
// is governed by the logical step budget rather than the host call stack.
const evaluationNesting = 512

func newEvaluator(module *Module, meter *validation.Meter) *evaluator {
    e := &evaluator{module:module,meter:meter,functions:make(map[string]Function),constructors:map[string]int{"Nothing":0,"Just":1,"Null":0,"NonNull":1,"Err":1,"Ok":1}}
    for _, fn := range module.Functions { e.functions[fn.Name] = fn }
    for _, decl := range module.Types { for _, variant := range decl.Variants { e.constructors[variant.Name] = len(variant.Arguments) } }
    return e
}
func evalError(at Span, code,message string) { panic(&evalFailure{code:code,at:at,message:message}) }
func (e *evaluator) step(cost uint64, at Span) {
    if err := e.meter.Step(cost); err != nil { evalError(at,"evaluation.budget","validation step budget exhausted") }
}
func (e *evaluator) enter(at Span) {
    e.step(1,at)
    if e.depth >= evaluationNesting { evalError(at,"evaluation.depth","evaluation nesting limit exceeded") }
    e.depth++
}
func boolValue(b bool) evalValue { return evalValue{form:EvalBool(b)} }
func numberValue(n value.Number,typ string) evalValue { return evalValue{form:EvalNumber(n,typ)} }
func textValue(t value.Text) evalValue { return evalValue{form:EvalText(t)} }
func timestampOf(v evalValue,at Span)value.Timestamp {
    match v.form{case EvalTimestamp(t):return t;case _:evalError(at,"evaluation.type","expected a timestamp")};return value.Timestamp{}
}
func boolean(v evalValue,at Span) bool {
    match v.form { case EvalBool(b): return b; case _: evalError(at,"evaluation.type","expected Boolean") }
    return false
}
func number(v evalValue,at Span) (value.Number,string) {
    match v.form { case EvalNumber(n,typ): return n,typ; case _: evalError(at,"evaluation.type","expected number") }
    return value.Number{},""
}
func textOf(v evalValue,at Span) value.Text {
    match v.form { case EvalText(t): return t; case _: evalError(at,"evaluation.type","expected text") }
    return value.Text{}
}
func itemsOf(v evalValue,at Span) []evalValue {
    match v.form { case EvalList(items): return items; case _: evalError(at,"evaluation.type","expected list") }
    return nil
}
func mapEntriesOf(v evalValue,at Span)[]evalMapEntry{match v.form{case EvalMap(entries):return entries;case _:evalError(at,"evaluation.type","expected map")};return nil}
func (e *evaluator) mapValue(entries []evalMapEntry,at Span)evalValue{
    levels:=uint64(1);for n:=len(entries);n>1;n>>=1{levels++};maximum:=uint64(0);for _,entry:=range entries{length:=uint64(entry.key.Length());if length>maximum{maximum=length}};per:=maximum;if per>(^uint64(0)-1)/2{evalError(at,"evaluation.budget","map ordering cost exceeds evaluation resources")};per=per*2+1;count:=uint64(len(entries));if levels>0&&count>(^uint64(0))/levels||count*levels>(^uint64(0))/per{evalError(at,"evaluation.budget","map ordering cost exceeds evaluation resources")};cost:=count*levels*per;if cost>(^uint64(0))-count{evalError(at,"evaluation.budget","map ordering cost exceeds evaluation resources")};e.step(cost+count,at)
    copied:=append([]evalMapEntry(nil),entries...)
    sort.Slice(copied,func(i,j int)bool{return compareMapText(copied[i].key,copied[j].key)<0});for i:=1;i<len(copied);i++{if copied[i-1].key.Equal(copied[i].key){evalError(at,"evaluation.map","duplicate map key")}}
    return evalValue{form:EvalMap(copied)}
}
func cloneEvalEnvironment(env map[string]evalValue) map[string]evalValue {
    result := make(map[string]evalValue,len(env)); for name,v := range env { result[name] = v }; return result
}

// attempt is the boundary for an individual predicate computation. It catches
// only explained evaluation failures, not programmer bugs in the interpreter.
func (e *evaluator) attempt(expr *Expr,env map[string]evalValue) (result evalValue,failure *evalFailure) {
    defer func() { if caught := recover(); caught != nil { if explained,ok := caught.(*evalFailure); ok { failure = explained } else { panic(caught) } } }()
    result = e.expression(expr,env); return
}

func (e *evaluator) literalNumber(raw string,at Span) evalValue {
    cost := uint64(len(raw)); typ := "Int"
    if strings.ContainsAny(raw,".eE") { typ = "Real" }
    if index := strings.IndexAny(raw,"eE"); index >= 0 {
        exponent := strings.TrimPrefix(strings.TrimPrefix(raw[index+1:],"+"),"-")
        expansion,err := strconv.ParseUint(exponent,10,64)
        if err != nil || expansion > ^uint64(0)-cost { evalError(at,"evaluation.budget","numeric literal expansion exceeds evaluation resources") }
        cost += expansion
    }
    e.step(cost,at)
    n,err := value.ParseNumber(raw)
    if err != nil { evalError(at,"evaluation.number","invalid numeric literal") }
    return numberValue(n,typ)
}

var builtinArities = map[string]int{
    "not":1,"show":1,"read":1,"length":1,"reverse":1,"unique":1,"isInteger":1,
    "map":2,"filter":2,"all":2,"any":2,"foldl":3,"oneOf":2,"elem":2,
    "satisfiesAll":2,"satisfiesOnlyOneOf":2,"satisfiesOneOf":2,"satisfiesAtLeastOneOf":2,
    "matches":2,"search":2,
    "toReal":1,"toInteger":1,"truncate":1,"floor":1,"ceiling":1,"roundHalfEven":1,
    "civilSecondsUntil":2,"siSecondsUntil":2,
    "lookup":2,"member":2,"keys":1,"values":1,"size":1,"insert":3,"delete":2,
    "mapValues":2,"filterValues":2,"allValues":2,"anyValues":2,
}
func (e *evaluator) resolve(name string,at Span) evalValue {
    return e.resolveTyped(name,nil,at)
}
func (e *evaluator) resolveTyped(name string,signature *Type,at Span) evalValue {
    if fn,found := e.functions[name]; found {
        arity := len(fn.Equations[0].Patterns)
        if arity == 0 { return e.invoke(name,nil,signature,at) }
        result:=evalValue{form:EvalFunction(name,arity,nil),signature:signature}
        if hasInlineRefinement(fn.Signature){return e.assertInline(fn.Signature,result,e.functionBindings(name,signature))}
        return result
    }
    if arity,found := e.constructors[name]; found {
        if arity == 0 { return evalValue{form:EvalVariant(name,nil)} }
        return evalValue{form:EvalFunction(name,arity,nil),signature:signature}
    }
    if arity,found := builtinArities[name]; found { return evalValue{form:EvalFunction(name,arity,nil),signature:signature} }
    if _,found:=FixedIntegerConversion(name);found{return evalValue{form:EvalFunction(name,1,nil),signature:signature}}
    if _,found:=FixedFloatConversion(name);found{return evalValue{form:EvalFunction(name,1,nil),signature:signature}}
    evalError(at,"evaluation.name","unresolved function or variable"); return evalValue{}
}
func (e *evaluator) apply(fn,arg evalValue,at Span) evalValue {
    e.enter(at); defer func(){e.depth--}()
    match fn.form {
    case EvalGuardedFunction(inner,argument,result,types):
        checked:=e.assertInline(argument,arg,types)
        return e.assertInline(result,e.apply(inner,checked,at),types)
    case EvalFunction(name,arity,previous):
        e.step(uint64(len(previous)+1),at)
        args := append(append([]evalValue(nil),previous...),arg)
        if len(args) < arity { return evalValue{form:EvalFunction(name,arity,args),signature:fn.signature} }
        return e.invoke(name,args,fn.signature,at)
    case _: evalError(at,"evaluation.type","application requires a function")
    }
    return evalValue{}
}
func (e *evaluator) invoke(name string,args []evalValue,signature *Type,at Span) evalValue {
    e.enter(at); defer func(){e.depth--}()
    if fn,found := e.functions[name]; found {
        previous:=e.typeEnvironment
        e.typeEnvironment=e.functionBindings(name,signature)
        defer func(){e.typeEnvironment=previous}()
        for _,equation := range fn.Equations {
            env := make(map[string]evalValue)
            matched := true
            for i,p := range equation.Patterns { if !e.pattern(p,args[i],env) { matched = false; break } }
            if matched {
                result:=e.expression(equation.Body,env)
                if len(args)==0 && hasInlineRefinement(fn.Signature){result=e.assertInline(fn.Signature,result,e.typeEnvironment)}
                return result
            }
        }
        evalError(at,"evaluation.pattern","no function equation matched")
    }
    if _,found := e.constructors[name]; found { return evalValue{form:EvalVariant(name,append([]evalValue(nil),args...))} }
    if name=="read" {return e.typedRead(signature,args[0],at)}
    return e.builtin(name,args,at)
}

func hasInlineRefinement(t *Type)bool {
    match t.Form {
    case RefinedType(_,_):return true
    case ArrowType(a,b):return hasInlineRefinement(a)||hasInlineRefinement(b)
    case AppliedType(a,b):return hasInlineRefinement(a)||hasInlineRefinement(b)
    case ListType(element):return hasInlineRefinement(element)
    case RecordType(fields):for _,field:=range fields {if hasInlineRefinement(field.Type){return true}};return false
    case NamedType(_):return false
    }
}

func (e *evaluator) pattern(p *Pattern,v evalValue,env map[string]evalValue) bool {
    e.enter(p.At); defer func(){e.depth--}()
    match p.Form {
    case BindPattern(name): env[name] = v; return true
    case WildPattern(): return true
    case LiteralPattern(expr): return e.equal(v,e.expression(expr,nil),p.At)
    case ConstructorPattern(name,patterns):
        match v.form {
        case EvalVariant(actual,args):
            if name != actual || len(patterns) != len(args) { return false }
            for i,child := range patterns { if !e.pattern(child,args[i],env) { return false } }; return true
        case _: return false
        }
    case ListPattern(patterns):
        match v.form {
        case EvalList(items):
            if len(items) != len(patterns) { return false }
            for i,child := range patterns { if !e.pattern(child,items[i],env) { return false } }; return true
        case _: return false
        }
    case ConsPattern(head,tail):
        match v.form {
        case EvalList(items):
            if len(items) == 0 { return false }
            return e.pattern(head,items[0],env) && e.pattern(tail,evalValue{form:EvalList(items[1:])},env)
        case _: return false
        }
    }
}

func (e *evaluator) checkedNumber(n value.Number,typ string,at Span) evalValue {
    if typ=="Float32"||typ=="Float64" {
        if _,err:=exactFloat(n,typ);err!=nil{evalError(at,"evaluation.precision","fixed-precision result is not exactly representable")}
        return numberValue(n,typ)
    }
    if typ != "Int" && typ != "Real" {
        digits := strings.TrimPrefix(strings.TrimPrefix(typ,"UInt"),"Int")
        width,err := strconv.ParseUint(digits,10,32)
        if err != nil { evalError(at,"evaluation.type","unsupported numeric representation") }
        e.step(width,at)
        if _,err := n.FixedWidth(uint(width),!strings.HasPrefix(typ,"UInt")); err != nil { evalError(at,"evaluation.overflow","fixed-width result is not representable") }
    }
    return numberValue(n,typ)
}
func (e *evaluator) binary(op string,a,b evalValue,at Span) evalValue {
    switch op {
    case "&&": return boolValue(boolean(a,at) && boolean(b,at))
    case "||": return boolValue(boolean(a,at) || boolean(b,at))
    case "==": return boolValue(e.equal(a,b,at))
    case "/=": return boolValue(!e.equal(a,b,at))
    case ":":
        tail := itemsOf(b,at); e.step(uint64(len(tail)+1),at)
        items := make([]evalValue,1,len(tail)+1); items[0] = a; return evalValue{form:EvalList(append(items,tail...))}
    case "++":
        match a.form {
        case EvalText(left): right := textOf(b,at); e.step(uint64(left.Length()+right.Length()),at); return textValue(left.Concat(right))
        case EvalList(left): right := itemsOf(b,at); e.step(uint64(len(left)+len(right)),at); return evalValue{form:EvalList(append(append([]evalValue(nil),left...),right...))}
        case _: evalError(at,"evaluation.type","concatenation requires text or lists")
        }
    }
    if op == "<" || op == "<=" || op == ">" || op == ">=" {
        comparison := e.compare(a,b,at)
        switch op { case "<": return boolValue(comparison < 0); case "<=": return boolValue(comparison <= 0); case ">": return boolValue(comparison > 0); default: return boolValue(comparison >= 0) }
    }
    left,typ := number(a,at); right,otherType := number(b,at)
    if typ != otherType { evalError(at,"evaluation.type","numeric operands need an explicit conversion") }
    cost := uint64(len(left.Show()))*uint64(len(right.Show()))+1; e.step(cost,at)
    switch op {
    case "+": return e.checkedNumber(left.Add(right),typ,at)
    case "-": return e.checkedNumber(left.Subtract(right),typ,at)
    case "*": return e.checkedNumber(left.Multiply(right),typ,at)
    case "/": result,err := left.Divide(right); if err != nil { evalError(at,"evaluation.divide","division by zero") }; return numberValue(result,"Real")
    case "%": result,err := left.Remainder(right); if err != nil { evalError(at,"evaluation.remainder","integer remainder is undefined") }; return e.checkedNumber(result,typ,at)
    }
    evalError(at,"evaluation.operator","unsupported operator"); return evalValue{}
}

func (e *evaluator) compare(a,b evalValue,at Span) int {
    match a.form {
    case EvalNumber(left,typ):
        right,otherType := number(b,at); if typ != otherType { evalError(at,"evaluation.type","comparison operands need an explicit conversion") }
        e.step(uint64(len(left.Show()))*uint64(len(right.Show()))+1,at); return left.Compare(right)
    case EvalText(left):
        right := textOf(b,at); e.step(uint64(left.Length()+right.Length()),at)
        x,y := left.Units(),right.Units()
        for i := 0; i < len(x) && i < len(y); i++ { if x[i] < y[i] { return -1 }; if x[i] > y[i] { return 1 } }
        if len(x) < len(y) { return -1 }; if len(x) > len(y) { return 1 }; return 0
    case EvalTimestamp(left):
        right:=timestampOf(b,at)
        e.step(uint64(len(left.Fraction().Show()))*uint64(len(right.Fraction().Show()))+1,at)
        return left.Compare(right)
    case _: evalError(at,"evaluation.type","unsupported ordered value")
    }
    return 0
}

func (e *evaluator) equal(a,b evalValue,at Span) bool {
    e.enter(at); defer func(){e.depth--}()
    match a.form {
    case EvalNumber(left,_): right,_ := number(b,at); e.step(uint64(len(left.Show())+len(right.Show())),at); return left.Show() == right.Show()
    case EvalText(left): right := textOf(b,at); e.step(uint64(left.Length()+right.Length()),at); return left.Equal(right)
    case EvalTimestamp(_):return e.compare(a,b,at)==0
    case EvalBool(left): return left == boolean(b,at)
    case EvalList(left):
        right := itemsOf(b,at); if len(left) != len(right) { return false }
        for i := range left { if !e.equal(left[i],right[i],at) { return false } }; return true
    case EvalMap(left):
        match b.form{case EvalMap(right):if len(left)!=len(right){return false};for i:=range left{e.step(uint64(left[i].key.Length()+right[i].key.Length()),at);if !left[i].key.Equal(right[i].key)||!e.equal(left[i].value,right[i].value,at){return false}};return true;case _:evalError(at,"evaluation.type","expected a map")}
    case EvalVariant(name,left):
        match b.form {
        case EvalVariant(otherName,right):
            if name != otherName || len(left) != len(right) { return false }
            for i := range left { if !e.equal(left[i],right[i],at) { return false } }; return true
        case _: evalError(at,"evaluation.type","expected a constructor value")
        }
    case EvalRecord(left):
        match b.form {
        case EvalRecord(right):
            if len(left) != len(right) { return false }
            for _,field := range left {
                found := false
                for _,other := range right { e.step(1,at); if field.name == other.name { if !e.equal(field.value,other.value,at) { return false }; found = true; break } }
                if !found { return false }
            }; return true
        case _: evalError(at,"evaluation.type","expected a record")
        }
    case EvalFunction(_,_,_): evalError(at,"evaluation.type","functions do not support value equality")
    case EvalGuardedFunction(_,_,_,_):evalError(at,"evaluation.type","functions do not support value equality")
    }
    return false
}
