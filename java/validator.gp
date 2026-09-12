package java

import (
    "fmt"
    "path"
    "slices"
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

func javaClassName(className string)error {
    reserved:=" Data ContractRuntime Rational TextCodec Validation ValidationException Budget ModelSupport ModelMaybe ModelNullable ModelResult Draft record var sealed permits yield String StringBuilder Object Integer Long Boolean Character Math System Exception RuntimeException IllegalArgumentException ArithmeticException AssertionError NullPointerException UnsupportedOperationException Override SuppressWarnings Comparable "
    if className==""||strings.Contains(className,".")||strings.Contains(reserved," "+className+" "){return fmt.Errorf("invalid or reserved Java class name: %s",className)}
    return packageName(className)
}

func (e *initializer) expr(expr *language.Expr,scope map[string]bool)string {
    kind,text,flag:="","",false;args,names,arms:=[]string{},[]string{},[]string{};signature,annotationType:="null","null"
    child:=func(arg *language.Expr)string{return e.expr(arg,scope)}
    match expr.Form {
    case language.NumberLiteral(raw):kind,text="number",raw
    case language.TextLiteral(raw):kind,text="text",raw
    case language.BoolLiteral(b):kind,flag="bool",b
    case language.Variable(name):
        kind,text="variable",name
        if !scope[name]{
            if name=="read"||name=="show"||name=="matches"||name=="search"{
                declared:=false;for _,fn:=range e.checked.Syntax.Functions{if fn.Name==name{declared=true;break}}
                if !declared{unsupported(expr.At,"Java execution for "+name+" remains required")}
            }
            kind="global";signature=e.signature(e.checked.Inferred[expr])
        }
    case language.Project(record,field):kind,text="project",field;args=append(args,child(record))
    case language.Unary(op,operand):kind,text="unary",op;args=append(args,child(operand))
    case language.Binary(op,left,right):kind,text="binary",op;args=append(args,child(left),child(right))
    case language.Conditional(test,yes,no):kind="if";args=append(args,child(test),child(yes),child(no))
    case language.Let(name,annotation,bound,body):
        if annotation!=nil&&inlineRefinement(annotation){annotationType=e.meta(annotation)}
        kind,text="let",name;args=append(args,child(bound));local:=make(map[string]bool);for key,v:=range scope{local[key]=v};local[name]=true;args=append(args,e.expr(body,local))
    case language.ListLiteral(elements):kind="list";for _,element:=range elements{args=append(args,child(element))}
    case language.RecordLiteral(fields):kind="record";for _,field:=range fields{names=append(names,field.Name);args=append(args,child(field.Value))}
    case language.Apply(fn,arg):kind="apply";args=append(args,child(fn),child(arg))
    case language.Case(subject,branches):
        kind="case";args=append(args,child(subject))
        for _,arm:=range branches{local:=make(map[string]bool);for name,v:=range scope{local[name]=v};pattern:=e.pattern(arm.Pattern,local);arms=append(arms,e.node("ContractRuntime.Arm","new ContractRuntime.Arm("+pattern+","+e.expr(arm.Body,local)+")"))}
    }
    source:=fmt.Sprintf("new ContractRuntime.Expr(%s,%s,%v,%s,%s,%s,%s,%s)",javaQuote(kind),e.literal(text),flag,e.list("ContractRuntime.Expr",args),e.strings(names),signature,e.list("ContractRuntime.Arm",arms),annotationType)
    return e.node("ContractRuntime.Expr",source)
}

func (e *initializer) typ(t *language.Type)string {
    kind,name:="","";args,fields,rules:=[]string{},[]string{},[]string{}
    match t.Form {
    case language.NamedType(n):
        if n=="Timestamp"{unsupported(t.At,"Java timestamp validation is not yet emitted")};kind,name="named",n
    case language.ListType(element):kind="list";args=append(args,e.typ(element))
    case language.RecordType(members):
        kind="record";for _,member:=range members{source:="new ContractRuntime.Member("+e.literal(member.Name)+","+e.typ(member.Type)+")";fields=append(fields,e.node("ContractRuntime.Member",source))}
    case language.RefinedType(base,conditions):
        kind="refined";args=append(args,e.typ(base))
        for _,rule:=range conditions{
            scope:=map[string]bool{"it":true};message:="null";if rule.Message!=nil{message=e.expr(rule.Message,scope)}
            source:=fmt.Sprintf("new ContractRuntime.Rule(%s,%d,%s,%s,%s,new java.math.BigInteger(%s))",e.literal(rule.Code),rule.At.Start.Offset,e.literal(language.FormatExpression(rule.Predicate)),e.expr(rule.Predicate,scope),message,javaQuote(fmt.Sprint(rule.Steps)))
            rules=append(rules,e.node("ContractRuntime.Rule",source))
        }
    case language.AppliedType(fn,arg):kind="applied";args=append(args,e.typ(fn),e.typ(arg))
    case language.ArrowType(_,_):unsupported(t.At,"function-valued types are not payload types")
    }
    source:=fmt.Sprintf("new ContractRuntime.Type(%s,%s,%s,%s,%s)",javaQuote(kind),e.literal(name),e.list("ContractRuntime.Type",args),e.list("ContractRuntime.Member",fields),e.list("ContractRuntime.Rule",rules))
    return e.node("ContractRuntime.Type",source)
}

// GenerateValidator emits a checked contract and its Java 25 runtime. It does
// not yet emit semantic model classes or native serde. Structural records,
// aliases, lists, generic/recursive ADTs, named/recursive/higher-order functions
// and pattern matching are supported. Unsupported execution features reject
// the entire generation; see docs/JAVA-RUNTIME.md for the current boundaries.
func GenerateValidator(program *language.Program,namespace,className string)(files []File,failure error){
    defer func(){if caught:=recover();caught!=nil{if err,ok:=caught.(*GenerationError);ok{files=nil;failure=err}else{panic(caught)}}}()
    if program==nil{return nil,fmt.Errorf("a compiled program is required")}
    if err:=packageName(namespace);err!=nil{return nil,err}
    if err:=javaClassName(className);err!=nil{return nil,err}
    for _,reserved:=range []string{"Data","ContractRuntime","Rational","TextCodec","Validation","ValidationException","Budget"}{if strings.EqualFold(className,reserved){return nil,fmt.Errorf("contract source name collides with runtime source")}}
    checked:=program.CheckedSyntax();module:=checked.Syntax
    e:=&initializer{prefix:className+"$Refine",checked:&checked};entries:=[]string{}
    for _,decl:=range module.Types{
        body:="null";if decl.Body!=nil{body=e.typ(decl.Body)}
        alternatives:=[]string{}
        for _,variant:=range decl.Variants{args:=[]string{};for _,arg:=range variant.Arguments{args=append(args,e.typ(arg))};source:="new ContractRuntime.Alternative("+e.literal(variant.Name)+","+e.list("ContractRuntime.Type",args)+")";alternatives=append(alternatives,e.node("ContractRuntime.Alternative",source))}
        definition:=e.node("ContractRuntime.Definition",fmt.Sprintf("new ContractRuntime.Definition(%s,%s,%s,%s)",e.strings(decl.Parameters),body,e.list("ContractRuntime.Alternative",alternatives),e.scopes(checked.DeclarationScopes[decl.Name])))
        entries=append(entries,e.node("java.util.Map.Entry<String, ContractRuntime.Definition>","java.util.Map.entry("+e.literal(decl.Name)+","+definition+")"))
    }
    definitions:=e.node("java.util.Map<String, ContractRuntime.Definition>",e.prefix+"Support.dictionary("+e.list("java.util.Map.Entry<String, ContractRuntime.Definition>",entries)+")")
    functionEntries:=[]string{}
    for _,fn:=range module.Functions{
        equations:=[]string{}
        for _,equation:=range fn.Equations{scope:=map[string]bool{};patterns:=[]string{};for _,p:=range equation.Patterns{patterns=append(patterns,e.pattern(p,scope))};equations=append(equations,e.node("ContractRuntime.Equation","new ContractRuntime.Equation("+e.list("ContractRuntime.Pattern",patterns)+","+e.expr(equation.Body,scope)+")"))}
        definition:=e.node("ContractRuntime.FunctionDef","new ContractRuntime.FunctionDef("+e.meta(fn.Signature)+","+e.list("ContractRuntime.Equation",equations)+","+e.scopes(checked.FunctionScopes[fn.Name])+")")
        functionEntries=append(functionEntries,e.node("java.util.Map.Entry<String, ContractRuntime.FunctionDef>","java.util.Map.entry("+e.literal(fn.Name)+","+definition+")"))
    }
    functions:=e.node("java.util.Map<String, ContractRuntime.FunctionDef>",e.prefix+"Support.dictionary("+e.list("java.util.Map.Entry<String, ContractRuntime.FunctionDef>",functionEntries)+")")
    // Recursive contract predicates can refer back to their own inferred
    // function signatures. Emit those links lazily through a finite type table,
    // rather than recursively expanding expression/type metadata at generation.
    signatureRefs:=[]string{};for i:=0;i<len(e.signatures);i++{signatureRefs=append(signatureRefs,e.meta(e.signatures[i]))}
    signatures:=e.list("ContractRuntime.Type",signatureRefs)
    header:="// Generated by Refine: development Java 25 contract. MIT licensed.\n";if namespace!=""{header+="package "+namespace+";\n"}
    source:=fmt.Sprintf(`
public final class %s {
    private %s() {}
    private static final java.util.Map<String, ContractRuntime.Definition> DEFINITIONS = definitions();
    private static final java.util.Map<String, ContractRuntime.FunctionDef> FUNCTIONS = %s;
    public static Validation.Outcome validate(String root, Data input) { return validate(root, input, Budget.Limits.defaults()); }
    public static Validation.Outcome validate(String root, Data input, Budget.Limits caller) { return ContractRuntime.validate(DEFINITIONS, FUNCTIONS, root, input, caller); }
    public static Validation.Outcome validateStructure(String root, Data input, Budget.Limits caller) { return ContractRuntime.validateStructure(DEFINITIONS, FUNCTIONS, root, input, caller); }
    public static Data requireValid(String root, Data input) { validate(root, input).orThrow(); return input; }
`,className,className,functions)+e.source(definitions,signatures)
    files,failure=GenerateRuntime(namespace);if failure!=nil{return nil,failure}
    prefix:=strings.ReplaceAll(namespace,".","/")
    files=append(files,File{Path:path.Join(prefix,"Data.java"),Source:header+dataJava},File{Path:path.Join(prefix,"ContractRuntime.java"),Source:header+contractRuntimeJava},File{Path:path.Join(prefix,className+".java"),Source:header+source})
    return files,nil
}

func (e *initializer) scopes(scope map[string]string)string{
    names:=[]string{};for name:=range scope{names=append(names,name)};slices.Sort(names)
    entries:=[]string{};for _,name:=range names{entries=append(entries,e.node("ContractRuntime.Scope","new ContractRuntime.Scope("+e.literal(name)+","+e.literal(scope[name])+")"))}
    return e.list("ContractRuntime.Scope",entries)
}

func inlineRefinement(t *language.Type)bool{
    match t.Form{
    case language.RefinedType(_,_):return true
    case language.ListType(a):return inlineRefinement(a)
    case language.AppliedType(a,b):return inlineRefinement(a)||inlineRefinement(b)
    case language.ArrowType(a,b):return inlineRefinement(a)||inlineRefinement(b)
    case language.RecordType(fields):for _,field:=range fields{if inlineRefinement(field.Type){return true}}
    case language.NamedType(_):
    }
    return false
}

// Inference metadata retains binary type application and arrow nodes: their
// traversal contributes to the shared evaluator's exact logical-step cost.
func (e *initializer) meta(t *language.Type)string{
    if t==nil{return "null"}
    kind,name:="","";args,fields,rules:=[]string{},[]string{},[]string{}
    match t.Form{
    case language.NamedType(n):if n=="Timestamp"{unsupported(t.At,"Java timestamps remain required")};kind,name="named",n
    case language.ListType(a):kind="list";args=append(args,e.meta(a))
    case language.AppliedType(a,b):kind="applied";args=append(args,e.meta(a),e.meta(b))
    case language.ArrowType(a,b):kind="arrow";args=append(args,e.meta(a),e.meta(b))
    case language.RecordType(members):kind="record";for _,field:=range members{fields=append(fields,e.node("ContractRuntime.Member","new ContractRuntime.Member("+e.literal(field.Name)+","+e.meta(field.Type)+")"))}
    case language.RefinedType(base,conditions):
        kind="refined";args=append(args,e.meta(base))
        for _,rule:=range conditions{
            scope:=map[string]bool{"it":true};message:="null";if rule.Message!=nil{message=e.expr(rule.Message,scope)}
            source:=fmt.Sprintf("new ContractRuntime.Rule(%s,%d,%s,%s,%s,new java.math.BigInteger(%s))",e.literal(rule.Code),rule.At.Start.Offset,e.literal(language.FormatExpression(rule.Predicate)),e.expr(rule.Predicate,scope),message,javaQuote(fmt.Sprint(rule.Steps)))
            rules=append(rules,e.node("ContractRuntime.Rule",source))
        }
    }
    return e.node("ContractRuntime.Type","new ContractRuntime.Type("+javaQuote(kind)+","+e.literal(name)+","+e.list("ContractRuntime.Type",args)+","+e.list("ContractRuntime.Member",fields)+","+e.list("ContractRuntime.Rule",rules)+")")
}

func (e *initializer) pattern(p *language.Pattern,scope map[string]bool)string{
    kind,name,literal:="","","null";args:=[]string{}
    match p.Form{
    case language.BindPattern(n):kind,name="bind",n;scope[n]=true
    case language.WildPattern():kind="wild"
    case language.LiteralPattern(expr):kind="literal";literal=e.expr(expr,map[string]bool{})
    case language.ConstructorPattern(n,children):kind,name="constructor",n;for _,child:=range children{args=append(args,e.pattern(child,scope))}
    case language.ListPattern(children):kind="list";for _,child:=range children{args=append(args,e.pattern(child,scope))}
    case language.ConsPattern(a,b):kind="cons";args=append(args,e.pattern(a,scope),e.pattern(b,scope))
    }
    return e.node("ContractRuntime.Pattern","new ContractRuntime.Pattern("+javaQuote(kind)+","+e.literal(name)+","+e.list("ContractRuntime.Pattern",args)+","+literal+")")
}
