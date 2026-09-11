package java

import (
    "fmt"
    "path"
    "strings"

    "goforge.dev/refine/language"
    "goforge.dev/refine/value"
)

// GenerationError identifies syntax the development Java backend cannot yet
// execute. No files are returned on failure; no predicate is silently omitted.
type GenerationError struct { At language.Span; Message string }
func (e *GenerationError) Error() string { return fmt.Sprintf("java.unsupported at %d:%d: %s",e.At.Start.Line,e.At.Start.Column,e.Message) }
func unsupported(at language.Span,message string) { panic(&GenerationError{At:at,Message:message}) }

// javaQuote emits Java string literals, not JSON escapes: Java processes Unicode
// escapes before lexing, so newlines/control characters must use ordinary Java
// escapes or octal rather than \u000a, etc. Non-ASCII UTF-16 units remain exact.
func javaQuote(text string) string {
    t,err:=value.TextFromUTF8(text);if err!=nil{panic("compiler text is not UTF-8")}
    var out strings.Builder;out.WriteByte('"')
    for _,unit:=range t.Units(){
        switch unit {
        case '"':out.WriteString(`\"`)
        case '\\':out.WriteString(`\\`)
        case '\n':out.WriteString(`\n`)
        case '\r':out.WriteString(`\r`)
        case '\t':out.WriteString(`\t`)
        case '\b':out.WriteString(`\b`)
        case '\f':out.WriteString(`\f`)
        default:if unit<32{fmt.Fprintf(&out,`\%03o`,unit)}else if unit>126{fmt.Fprintf(&out,`\u%04x`,unit)}else{out.WriteByte(byte(unit))}
        }
    }
    out.WriteByte('"');return out.String()
}
func javaList(items []string)string{return "java.util.List.of("+strings.Join(items,",")+")"}
func quoteList(items []string)string{result:=make([]string,len(items));for i,item:=range items{result[i]=javaQuote(item)};return javaList(result)}

func javaClassName(className string)error {
    reserved:=" Data ContractRuntime Rational TextCodec Validation ValidationException Budget ModelSupport ModelMaybe ModelNullable ModelResult Draft record var sealed permits yield String StringBuilder Object Integer Long Boolean Character Math System Exception RuntimeException IllegalArgumentException ArithmeticException AssertionError NullPointerException UnsupportedOperationException Override SuppressWarnings Comparable "
    if className==""||strings.Contains(className,".")||strings.Contains(reserved," "+className+" "){return fmt.Errorf("invalid or reserved Java class name: %s",className)}
    return packageName(className)
}

func emitExpr(expr *language.Expr,scope map[string]bool)string {
    kind,text,flag:="","",false;args,names:=[]string{},[]string{}
    child:=func(e *language.Expr)string{return emitExpr(e,scope)}
    match expr.Form {
    case language.NumberLiteral(raw):kind,text="number",raw
    case language.TextLiteral(raw):kind,text="text",raw
    case language.BoolLiteral(b):kind,flag="bool",b
    case language.Variable(name):if !scope[name]{unsupported(expr.At,"function and constructor expressions are not yet emitted")};kind,text="variable",name
    case language.Project(record,field):kind,text="project",field;args=append(args,child(record))
    case language.Unary(op,operand):kind,text="unary",op;args=append(args,child(operand))
    case language.Binary(op,left,right):kind,text="binary",op;args=append(args,child(left),child(right))
    case language.Conditional(test,yes,no):kind="if";args=append(args,child(test),child(yes),child(no))
    case language.Let(name,annotation,bound,body):
        if annotation!=nil{unsupported(expr.At,"annotated expression bindings are not yet emitted")}
        kind,text="let",name;args=append(args,child(bound));local:=make(map[string]bool);for key,v:=range scope{local[key]=v};local[name]=true;args=append(args,emitExpr(body,local))
    case language.ListLiteral(elements):kind="list";for _,element:=range elements{args=append(args,child(element))}
    case language.RecordLiteral(fields):kind="record";for _,field:=range fields{names=append(names,field.Name);args=append(args,child(field.Value))}
    case language.Apply(_,_):unsupported(expr.At,"function application is not yet emitted")
    case language.Case(_,_):unsupported(expr.At,"pattern-match expressions are not yet emitted")
    }
    return fmt.Sprintf("new ContractRuntime.Expr(%s,%s,%v,%s,%s)",javaQuote(kind),javaQuote(text),flag,javaList(args),quoteList(names))
}

func emitType(t *language.Type)string {
    kind,name:="","";args,fields,rules:=[]string{},[]string{},[]string{}
    match t.Form {
    case language.NamedType(n):
        if n=="Timestamp"{unsupported(t.At,"Java timestamp validation is not yet emitted")};kind,name="named",n
    case language.ListType(element):kind="list";args=append(args,emitType(element))
    case language.RecordType(members):
        kind="record";for _,member:=range members{fields=append(fields,"new ContractRuntime.Member("+javaQuote(member.Name)+","+emitType(member.Type)+")")}
    case language.RefinedType(base,conditions):
        kind="refined";args=append(args,emitType(base))
        for _,rule:=range conditions{
            scope:=map[string]bool{"it":true};message:="null";if rule.Message!=nil{message=emitExpr(rule.Message,scope)}
            rules=append(rules,fmt.Sprintf("new ContractRuntime.Rule(%s,%d,%s,%s,%s,new java.math.BigInteger(%s))",javaQuote(rule.Code),rule.At.Start.Offset,javaQuote(language.FormatExpression(rule.Predicate)),emitExpr(rule.Predicate,scope),message,javaQuote(fmt.Sprint(rule.Steps))))
        }
    case language.AppliedType(_,_):
        root:=t;arguments:=[]*language.Type{}
        for{stop:=false;match root.Form{case language.AppliedType(fn,arg):arguments=append([]*language.Type{arg},arguments...);root=fn;case _:stop=true};if stop{break}}
        match root.Form{case language.NamedType(n):kind,name="named",n;case _:unsupported(t.At,"unsupported type constructor")}
        for _,arg:=range arguments{args=append(args,emitType(arg))}
    case language.ArrowType(_,_):unsupported(t.At,"function-valued types are not payload types")
    }
    return fmt.Sprintf("new ContractRuntime.Type(%s,%s,%s,%s,%s)",javaQuote(kind),javaQuote(name),javaList(args),javaList(fields),javaList(rules))
}

// GenerateValidator emits a checked contract and its Java 25 runtime. It does
// not yet emit semantic model classes or native serde. Structural records,
// aliases, lists, generic/recursive ADTs and expression-only refinements are
// supported; unsupported execution features reject the entire generation.
func GenerateValidator(program *language.Program,namespace,className string)(files []File,failure error){
    defer func(){if caught:=recover();caught!=nil{if err,ok:=caught.(*GenerationError);ok{files=nil;failure=err}else{panic(caught)}}}()
    if program==nil{return nil,fmt.Errorf("a compiled program is required")}
    if err:=packageName(namespace);err!=nil{return nil,err}
    if err:=javaClassName(className);err!=nil{return nil,err}
    for _,reserved:=range []string{"Data","ContractRuntime","Rational","TextCodec","Validation","ValidationException","Budget"}{if strings.EqualFold(className,reserved){return nil,fmt.Errorf("contract source name collides with runtime source")}}
    module:=program.Syntax()
    if len(module.Functions)!=0{unsupported(module.Functions[0].At,"named function emission remains required")}
    entries:=[]string{}
    for _,decl:=range module.Types{
        body:="null";if decl.Body!=nil{body=emitType(decl.Body)}
        alternatives:=[]string{}
        for _,variant:=range decl.Variants{args:=[]string{};for _,arg:=range variant.Arguments{args=append(args,emitType(arg))};alternatives=append(alternatives,"new ContractRuntime.Alternative("+javaQuote(variant.Name)+","+javaList(args)+")")}
        definition:=fmt.Sprintf("new ContractRuntime.Definition(%s,%s,%s)",quoteList(decl.Parameters),body,javaList(alternatives))
        entries=append(entries,"java.util.Map.entry("+javaQuote(decl.Name)+","+definition+")")
    }
    header:="// Generated by Refine: development Java 25 contract. MIT licensed.\n";if namespace!=""{header+="package "+namespace+";\n"}
    source:=fmt.Sprintf(`
public final class %s {
    private %s() {}
    private static final java.util.Map<String, ContractRuntime.Definition> DEFINITIONS = java.util.Map.ofEntries(%s);
    public static Validation.Outcome validate(String root, Data input) { return validate(root, input, Budget.Limits.defaults()); }
    public static Validation.Outcome validate(String root, Data input, Budget.Limits caller) { return ContractRuntime.validate(DEFINITIONS, root, input, caller); }
    public static Validation.Outcome validateStructure(String root, Data input, Budget.Limits caller) { return ContractRuntime.validateStructure(DEFINITIONS, root, input, caller); }
    public static Data requireValid(String root, Data input) { validate(root, input).orThrow(); return input; }
}
`,className,className,strings.Join(entries,","))
    // Development emitter guard: a future chunked initializer must lift this
    // limit without exceeding JVM method/constant-pool limits. Fail explicitly
    // now rather than return a source set known to risk an oversized initializer.
    if len(source)>48000{unsupported(language.Span{},"contract initializer exceeds the current 48000-byte emission limit; chunked emission remains required")}
    files,failure=GenerateRuntime(namespace);if failure!=nil{return nil,failure}
    prefix:=strings.ReplaceAll(namespace,".","/")
    files=append(files,File{Path:path.Join(prefix,"Data.java"),Source:header+dataJava},File{Path:path.Join(prefix,"ContractRuntime.java"),Source:header+contractRuntimeJava},File{Path:path.Join(prefix,className+".java"),Source:header+source})
    return files,nil
}
