package language

import (
    "strings"

    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

func (e *evaluator) checkedValue(t *Type,input evalValue)(result evalValue,report validation.Report) {
    v:=&payloadValidator{program:&Program{module:e.module},declarations:make(map[string]TypeDecl),structure:e,enclosing:e}
    for _,decl:=range e.module.Types{v.declarations[decl.Name]=decl}
    defer func(){
        if caught:=recover();caught!=nil{
            if failure,ok:=caught.(*evalFailure);ok{
                v.checks=append(v.checks,validation.Undecided(validation.Diagnostic{Code:failure.code,Paths:[]string{v.currentPath},Message:failure.message}))
            }else{panic(caught)}
        }
        report=validation.Collect(v.checks)
    }()
    result,_=v.check(t,input,e.typeEnvironment,"")
    return
}

func readError(at Span,message string){evalError(at,"read.syntax",message)}
func (e *evaluator) decodeText(text value.Text,at Span)evalValue {
    e.step(uint64(text.Length()),at)
    raw,err:=text.UTF8();if err!=nil{readError(at,"read input must contain Unicode scalar text; surrogate payloads must use quoted escapes")}
    e.step(uint64(len(raw)),at)
    syntax,err:=ParseExpression(raw)
    if err!=nil{
        if detail,ok:=err.(*Error);ok && detail.Code=="language.limit"{evalError(at,"evaluation.budget","read syntax exceeds parser resources")}
        readError(at,"input is not a value in the canonical text grammar")
    }
    return e.decodeLiteral(syntax,at)
}

// This is a data interpreter, not expression evaluation. Only literal forms,
// constructor applications and signed/exact numeric literals are admissible.
// A parsed function, field projection, conditional or arithmetic operation can
// never run merely because it appeared in text supplied to read.
func (e *evaluator) decodeLiteral(expr *Expr,at Span)evalValue {
    e.enter(at);defer func(){e.depth--}()
    match expr.Form {
    case NumberLiteral(raw):return e.literalNumber(raw,at)
    case TextLiteral(raw):e.step(uint64(len(raw)),at);t,err:=value.ReadText(raw);if err!=nil{readError(at,"invalid quoted text")};return textValue(t)
    case BoolLiteral(b):return boolValue(b)
    case Unary(op,operand):
        if op!="-"{readError(at,"only signed numeric literals are allowed")}
        match operand.Form {case NumberLiteral(raw):return e.literalNumber("-"+raw,at);case _:readError(at,"only signed numeric literals are allowed")}
    case Binary(op,left,right):
        if op!="/" || !integerSyntax(left,true) || !integerSyntax(right,false){readError(at,"only exact integer fractions are allowed, not arithmetic")}
        a,_:=number(e.decodeLiteral(left,at),at);b,_:=number(e.decodeLiteral(right,at),at)
        if b.Sign()<=0{readError(at,"a fraction denominator must be positive")}
        e.step(uint64(len(a.Show()))*uint64(len(b.Show()))+1,at)
        result,err:=a.Divide(b);if err!=nil{readError(at,"invalid exact fraction")};return numberValue(result,"Real")
    case ListLiteral(items):
        e.step(uint64(len(items)),at);result:=make([]evalValue,len(items));for i,item:=range items{result[i]=e.decodeLiteral(item,at)}
        return evalValue{form:EvalList(result)}
    case RecordLiteral(fields):
        e.step(uint64(len(fields)),at);result:=make([]evalField,len(fields));for i,field:=range fields{result[i]=evalField{name:field.Name,value:e.decodeLiteral(field.Value,at)}}
        return evalValue{form:EvalRecord(result)}
    case Variable(name):
        if !uppercase(name){readError(at,"functions and variables are not readable values")}
        return evalValue{form:EvalVariant(name,nil)}
    case Apply(_,_):
        root:=expr;arguments:=[]*Expr{}
        for{stop:=false;match root.Form{case Apply(fn,arg):e.step(1,at);arguments=append(arguments,arg);root=fn;case _:stop=true};if stop{break}}
        match root.Form {
        case Variable(name):
            if !uppercase(name){readError(at,"function calls are not readable values")}
            result:=make([]evalValue,len(arguments));for i:=range arguments{result[i]=e.decodeLiteral(arguments[len(arguments)-1-i],at)}
            return evalValue{form:EvalVariant(name,result)}
        case _:readError(at,"only constructor applications are readable values")
        }
    case _:readError(at,"expressions are not readable values")
    }
    panic("unreachable readable value")
}
func integerSyntax(expr *Expr,signed bool)bool {
    match expr.Form {
    case NumberLiteral(raw):return !strings.ContainsAny(raw,".eE")
    case Unary(op,operand):return signed && op=="-" && integerSyntax(operand,false)
    case _:return false
    }
}

func readTarget(signature *Type,at Span)*Type {
    signature=bareType(signature)
    if signature==nil{evalError(at,"evaluation.type","read target type is unresolved")}
    match signature.Form {
    case ArrowType(_,result):
        match bareType(result).Form {
        case AppliedType(prefix,target):
            match bareType(prefix).Form {case AppliedType(root,_):match root.Form {case NamedType(name):if name=="Result"{return target};case _:};case _:}
        case _:
        }
    case _:
    }
    evalError(at,"evaluation.type","read needs an inferred Result target");return nil
}
func (e *evaluator) typedRead(signature *Type,input evalValue,at Span)(result evalValue) {
    defer func(){if caught:=recover();caught!=nil{
        if failure,ok:=caught.(*evalFailure);ok && failure.code=="read.syntax"{
            message,_:=value.TextFromUTF8(failure.message);result=evalValue{form:EvalVariant("Err",[]evalValue{textValue(message)})}
        }else{panic(caught)}
    }}()
    target:=readTarget(signature,at)
    decoded:=e.decodeText(textOf(input,at),at)
    checked,report:=e.checkedValue(target,decoded)
    switch validation.StateName(report.State()) {
    case "valid":return evalValue{form:EvalVariant("Ok",[]evalValue{checked})}
    case "invalid":
        message,_:=value.TextFromUTF8("read value does not satisfy the target type")
        return evalValue{form:EvalVariant("Err",[]evalValue{textValue(message)})}
    default:evalError(at,"read.indeterminate","read target validation could not finish conclusively")
    }
    return evalValue{}
}

// ReadData is the validating canonical-text boundary for a named root. It never
// evaluates source text. An invalid or indeterminate result exposes no candidate
// value; callers must check the report before using the returned Data.
func (p *Program) ReadData(root string,text value.Text,caller validation.Limits)(data value.Data,report validation.Report) {
    var rootType *Type
    for _,decl:=range p.module.Types{if decl.Name==root && len(decl.Parameters)==0{rootType=&Type{Form:NamedType(root),At:decl.At};break}}
    if rootType==nil{return value.Data{},validation.Collect([]validation.Check{validation.Violated(validation.Diagnostic{Code:"validation.root",Paths:[]string{""},Message:"Choose a declared root type with no unbound type parameters."})})}
    return p.readDataType(rootType,text,caller)
}

func (p *Program) readDataType(rootType *Type,text value.Text,caller validation.Limits)(data value.Data,report validation.Report) {
    e:=newEvaluator(p.module,validation.NewBudget(validation.Limits{},caller).BeginStructure())
    defer func(){if caught:=recover();caught!=nil{
        if failure,ok:=caught.(*evalFailure);ok{
            detail:=validation.Diagnostic{Code:failure.code,Paths:[]string{""},Message:failure.message}
            if failure.code=="read.syntax"{report=validation.Collect([]validation.Check{validation.Violated(detail)})}else{report=validation.Collect([]validation.Check{validation.Undecided(detail)})}
            data=value.Data{}
        }else{panic(caught)}
    }}()
    candidate:=e.decodeText(text,rootType.At)
    checked,report:=e.checkedValue(rootType,candidate)
    if validation.StateName(report.State())=="valid"{data=e.toData(checked,rootType.At)}
    return data,report
}

// ShowDataWithoutValidation displays a structurally representable in-memory
// payload without asserting its refinements. Invalid bypass-created values may
// be shown, but validating ReadData never accepts them without checking rules.
func ShowDataWithoutValidation(data value.Data,limits validation.Limits)(text value.Text,failure error) {
    e:=newEvaluator(&Module{},validation.NewBudget(validation.Limits{},limits).BeginStructure())
    defer func(){if caught:=recover();caught!=nil{if explained,ok:=caught.(*evalFailure);ok{failure=explained}else{panic(caught)}}}()
    shown:=e.show(e.fromData(data,Span{}),Span{})
    e.step(uint64(len(shown)),Span{})
    text,failure=value.TextFromUTF8(shown);return
}
