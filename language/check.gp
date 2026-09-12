package language

import (
    "fmt"
    "strconv"
    "strings"
)

// Program owns a parsed and statically checked module. It exposes no mutable
// compiler state. Imported modules must be resolved before using Compile; the
// standalone entry point refuses unresolved imports instead of ignoring them.
type Program struct { module *Module }
func (p *Program) Source() string { return p.module.Source }
func (p *Program) Formatted() string { return Format(p.module) }
func (p *Program) Syntax() *Module {
    // A fresh parse prevents callers from mutating the checked representation.
    copy, err := Parse(p.module.Source)
    if err != nil { panic("checked source stopped parsing") }
    return copy
}

// CheckedModule is a caller-owned code-generation snapshot. Inferred expression
// keys belong to Syntax's tree; type-variable scopes connect generic declaration
// parameters to the checker's reified symbols. Mutating any part of the snapshot
// cannot change the compiled Program or a later snapshot.
type CheckedModule struct {
    Syntax *Module
    Inferred map[*Expr]*Type
    FunctionScopes map[string]map[string]string
    DeclarationScopes map[string]map[string]string
    // FunctionCapabilities contains the effective explicit plus inferred
    // requirements in stable order. Its entries are detached from compiler state.
    FunctionCapabilities map[string][]CapabilityConstraint
}

func (p *Program) CheckedSyntax() CheckedModule {
    // Rechecking a fresh tree preserves all inference/AST identity relationships
    // without exposing the interpreter's compiler-owned representation.
    copy,err:=Compile(p.module.Source)
    if err!=nil{panic("checked source stopped compiling")}
    module:=copy.module
    return checkedModuleSnapshot(module)
}

type term struct { name string; args []*term; fields []typedField; variable int; rigid bool; rules []Where }
type typedField struct { name string; typ *term }
type constructor struct { parent string; parameters []string; arguments []*Type }
type obligation struct { class string; typ *term; at Span }
type capabilityRequirement struct { class string; typ *term; at Span }
type capabilityCall struct { callee string; bindings map[string]*term; at Span }
type checker struct {
    module *Module
    declarations map[string]TypeDecl
    functions map[string]Function
    constructors map[string]constructor
    substitution map[int]*term
    nextVariable int
    obligations []obligation
    coverageWork uint64
    expressionTerms map[*Expr]*term
    reified map[*term]*Type
    expressionOrder []*Expr
    typeVariables map[string]*term
    functionVariables map[string]map[string]*term
    capabilityRequirements []capabilityRequirement
    capabilityCalls []capabilityCall
}

func typeError(at Span, message string) { panic(&Error{Code:"language.type",At:at,Message:message}) }
func (c *checker) fresh(rigid bool) *term { c.nextVariable++; return &term{variable:c.nextVariable,rigid:rigid} }
func base(name string, args ...*term) *term { return &term{name:name,args:args} }
func arrow(arg, result *term) *term { return base("->",arg,result) }
func (c *checker) prune(t *term) *term {
    if t.variable != 0 { if replacement, ok := c.substitution[t.variable]; ok { return c.prune(replacement) } }
    return t
}
func (c *checker) describe(t *term) string {
    t = c.prune(t)
    if t.variable != 0 { return "type variable" }
    if t.name == "[]" { return "[" + c.describe(t.args[0]) + "]" }
    if t.name == "->" { return "(" + c.describe(t.args[0]) + " -> " + c.describe(t.args[1]) + ")" }
    if t.name == "{}" { return "record" }
    text := t.name; for _, arg := range t.args { text += " " + c.describe(arg) }; return text
}
func (c *checker) occurs(variable int, t *term) bool {
    t = c.prune(t)
    if t.variable != 0 { return t.variable == variable }
    for _, arg := range t.args { if c.occurs(variable,arg) { return true } }
    for _, field := range t.fields { if c.occurs(variable,field.typ) { return true } }
    return false
}
func (c *checker) unify(left, right *term, at Span) {
    left, right = c.prune(left), c.prune(right)
    if left == right || left.variable != 0 && left.variable == right.variable { return }
    if left.variable != 0 && !left.rigid {
        if c.occurs(left.variable,right) { typeError(at,"infinite inferred type") }
        c.substitution[left.variable] = right; return
    }
    if right.variable != 0 && !right.rigid { c.unify(right,left,at); return }
    if left.variable != 0 || right.variable != 0 || left.name != right.name || len(left.args) != len(right.args) || len(left.fields) != len(right.fields) {
        typeError(at,"expected " + c.describe(left) + ", got " + c.describe(right))
    }
    for i := range left.args { c.unify(left.args[i],right.args[i],at) }
    for _, field := range left.fields {
        found := false
        for _, other := range right.fields { if field.name == other.name { c.unify(field.typ,other.typ,at); found = true; break } }
        if !found { typeError(at,"record fields differ") }
    }
}

func primitive(name string) bool {
    switch name { case "Int", "Real", "Float32", "Float64", "String", "Bool", "Timestamp": return true }
    prefix := "Int"; if strings.HasPrefix(name,"UInt") { prefix = "UInt" }
    digits := strings.TrimPrefix(name,prefix)
    if digits == name || digits == "" { return false }
    width, err := strconv.ParseUint(digits,10,32)
    return err == nil && width > 0 && strconv.FormatUint(width,10) == digits
}
func (c *checker) arity(name string, at Span) int {
    if primitive(name) { return 0 }
    switch name { case "Maybe", "Nullable": return 1; case "Result": return 2 }
    if decl, ok := c.declarations[name]; ok { return len(decl.Parameters) }
    typeError(at,"unknown type " + name); return 0
}
func (c *checker) typ(t *Type, variables map[string]*term, allowNew bool, rigid bool) *term {
    match t.Form {
    case NamedType(name):
        if !uppercase(name) {
            if existing, ok := variables[name]; ok { return existing }
            if !allowNew { typeError(t.At,"undeclared type parameter " + name) }
            created := c.fresh(rigid); variables[name] = created; return created
        }
        if c.arity(name,t.At) != 0 { typeError(t.At,"type constructor " + name + " needs arguments") }
        return base(name)
    case ListType(element): return base("[]",c.typ(element,variables,allowNew,rigid))
    case AppliedType(_, _):
        root := t; arguments := []*Type{}
        for {
            stop := false
            match root.Form {
            case AppliedType(constructor, arg): arguments = append([]*Type{arg},arguments...); root = constructor
            case _: stop = true
            }
            if stop { break }
        }
        match root.Form {
        case NamedType(name):
            if !uppercase(name) { typeError(root.At,"higher-kinded type parameters require an explicit supported constructor") }
            if c.arity(name,t.At) != len(arguments) { typeError(t.At,"wrong number of arguments for " + name) }
            args := make([]*term,len(arguments)); for i, arg := range arguments { args[i] = c.typ(arg,variables,allowNew,rigid) }
            return base(name,args...)
        case _: typeError(root.At,"expected a named type constructor")
        }
    case ArrowType(arg, result): return arrow(c.typ(arg,variables,allowNew,rigid),c.typ(result,variables,allowNew,rigid))
    case RecordType(fields):
        result := base("{}"); for _, field := range fields { result.fields = append(result.fields,typedField{name:field.Name,typ:c.typ(field.Type,variables,allowNew,rigid)}) }; return result
    case RefinedType(parent, rules):
        result := *c.typ(parent,variables,allowNew,rigid)
        result.rules = append(append([]Where(nil),result.rules...),rules...)
        return &result
    }
    panic("unreachable type form")
}

func (c *checker) expandOne(t *term) (*term, bool) {
    t = c.prune(t)
    declaration, ok := c.declarations[t.name]
    if !ok || declaration.Body == nil { return t, false }
    variables := make(map[string]*term)
    for i, name := range declaration.Parameters { variables[name] = t.args[i] }
    return c.typ(declaration.Body,variables,false,false), true
}
func (c *checker) underlying(t *term, at Span) *term {
    seen := make(map[string]bool)
    for {
        t = c.prune(t)
        if seen[t.name] { typeError(at,"unproductive cycle in named type definitions") }
        seen[t.name] = true
        next, expanded := c.expandOne(t)
        if !expanded { return t }
        t = next
    }
}

// Assignment admits a declared child where its parent is required, but does
// not equate unrelated nominal types with equal underlying structure.
func (c *checker) assign(expected, actual *term, at Span) {
    e, a := c.prune(expected), c.prune(actual)
    if e.variable != 0 || a.variable != 0 { c.unify(e,a,at); return }
    visited := make(map[string]bool)
    for e.name != a.name {
        if visited[a.name] { break }; visited[a.name] = true
        parent, ok := c.expandOne(a)
        if !ok { break }; a = c.prune(parent)
    }
    c.unify(e,a,at)
}

var builtinSignatures = map[string]string{
    "not":"Bool -> Bool", "show":"a -> String",
    "map":"(a -> b) -> [a] -> [b]", "filter":"(a -> Bool) -> [a] -> [a]",
    "all":"(a -> Bool) -> [a] -> Bool", "any":"(a -> Bool) -> [a] -> Bool",
    "foldl":"(a -> b -> a) -> a -> [b] -> a", "reverse":"[a] -> [a]",
    "satisfiesAll":"[a -> Bool] -> a -> Bool", "satisfiesOnlyOneOf":"[a -> Bool] -> a -> Bool",
    "satisfiesOneOf":"[a -> Bool] -> a -> Bool", "satisfiesAtLeastOneOf":"[a -> Bool] -> a -> Bool",
    "matches":"String -> String -> Bool", "search":"String -> String -> Bool",
    "isInteger":"Real -> Bool",
    "toReal":"Int -> Real", "toInteger":"Real -> Result String Int",
    "truncate":"Real -> Int", "floor":"Real -> Int", "ceiling":"Real -> Int", "roundHalfEven":"Real -> Int",
    "civilSecondsUntil":"Timestamp -> Timestamp -> Result String Real", "siSecondsUntil":"Timestamp -> Timestamp -> Result String Real",
}

func (c *checker) function(name string, at Span) *term {
    if fn, ok := c.functions[name]; ok {
        variables:=make(map[string]*term)
        signature:=c.typ(fn.Signature,variables,true,false)
        c.capabilityCalls=append(c.capabilityCalls,capabilityCall{callee:name,bindings:variables,at:at})
        return signature
    }
    if conversion,ok:=FixedIntegerConversion(name);ok{if conversion.Mode=="from"{return arrow(base(conversion.Type),base("Int"))};if conversion.Mode=="wrap"{return arrow(base("Int"),base(conversion.Type))};return arrow(base("Int"),base("Result",base("String"),base(conversion.Type)))}
    if conversion,ok:=FixedFloatConversion(name);ok{if conversion.Mode=="from"{return arrow(base(conversion.Type),base("Real"))};return arrow(base("Real"),base("Result",base("String"),base(conversion.Type)))}
    if constructor, ok := c.constructors[name]; ok {
        variables := make(map[string]*term); args := []*term{}
        for _, parameter := range constructor.parameters { variables[parameter] = c.fresh(false); args = append(args,variables[parameter]) }
        result := base(constructor.parent,args...)
        for i := len(constructor.arguments)-1; i >= 0; i-- { result = arrow(c.typ(constructor.arguments[i],variables,false,false),result) }
        return result
    }
    if name == "length" {
        arg := c.fresh(false); c.obligations = append(c.obligations,obligation{class:"length",typ:arg,at:at}); return arrow(arg,base("Int"))
    }
    if name == "read" {
        result := c.fresh(false); c.obligations = append(c.obligations,obligation{class:"read",typ:result,at:at})
        return arrow(base("String"),base("Result",base("String"),result))
    }
    if name == "show" {
        argument:=c.fresh(false);c.obligations=append(c.obligations,obligation{class:"show",typ:argument,at:at})
        return arrow(argument,base("String"))
    }
    if name == "oneOf" || name == "elem" || name == "unique" {
        item := c.fresh(false)
        c.obligations = append(c.obligations,obligation{class:"equality",typ:item,at:at})
        if name == "unique" { return arrow(base("[]",item),base("Bool")) }
        return arrow(item,arrow(base("[]",item),base("Bool")))
    }
    if signature, ok := builtinSignatures[name]; ok {
        p := parser{tokens:lex(signature)}
        return c.typ(p.typeExpression(),make(map[string]*term),true,false)
    }
    typeError(at,"unknown function or variable " + name); return nil
}

func copyEnvironment(env map[string]*term) map[string]*term { result := make(map[string]*term); for k, v := range env { result[k] = v }; return result }
func (c *checker) numeric(t *term, at Span) *term {
    t = c.underlying(t,at)
    if t.variable != 0 { c.obligations=append(c.obligations,obligation{class:"numeric",typ:t,at:at});return t }
    if !numericCapabilityPrimitive(t.name) { typeError(at,"expected a numeric type, got " + c.describe(t)) }
    return t
}
func (c *checker) integral(t *term,at Span)*term {
    t=c.underlying(t,at)
    if t.variable!=0{c.obligations=append(c.obligations,obligation{class:"integral",typ:t,at:at});return t}
    if !integralCapabilityPrimitive(t.name){typeError(at,"remainder requires integers")}
    return t
}
func (c *checker) expression(e *Expr, env map[string]*term) (result *term) {
    defer func(){if result!=nil && c.expressionTerms!=nil{if _,seen:=c.expressionTerms[e];!seen{c.expressionOrder=append(c.expressionOrder,e)};c.expressionTerms[e]=result}}()
    match e.Form {
    case NumberLiteral(text): if strings.ContainsAny(text,".eE") { return base("Real") }; return base("Int")
    case TextLiteral(_): return base("String")
    case BoolLiteral(_): return base("Bool")
    case Variable(name): if t, ok := env[name]; ok { return t }; return c.function(name,e.At)
    case ListLiteral(items):
        element := c.fresh(false)
        for _, item := range items { c.assign(element,c.expression(item,env),item.At) }
        return base("[]",element)
    case RecordLiteral(fields):
        result := base("{}"); for _, field := range fields { result.fields = append(result.fields,typedField{name:field.Name,typ:c.expression(field.Value,env)}) }; return result
    case Apply(fn, arg):
        function := c.prune(c.expression(fn,env)); argument := c.expression(arg,env)
        if function.variable != 0 && !function.rigid { result := c.fresh(false); c.unify(function,arrow(argument,result),e.At); return result }
        if function.name != "->" { typeError(fn.At,"expected a function, got " + c.describe(function)) }
        c.assign(function.args[0],argument,arg.At); return function.args[1]
    case Project(record, field):
        object := c.underlying(c.expression(record,env),record.At)
        if object.name == "Maybe" || object.name == "Nullable" { typeError(e.At,"handle absence/null explicitly before accessing a field") }
        if object.name != "{}" { typeError(e.At,"record type cannot be inferred; add an annotation") }
        for _, member := range object.fields { if member.name == field { return member.typ } }
        typeError(e.At,"record has no field " + field)
    case Unary(_, operand): return c.numeric(c.expression(operand,env),operand.At)
    case Binary(operator, left, right):
        a, b := c.expression(left,env), c.expression(right,env)
        switch operator {
        case "&&", "||": c.unify(base("Bool"),a,left.At); c.unify(base("Bool"),b,right.At); return base("Bool")
        case "==", "/=": c.unify(a,b,e.At); c.obligations = append(c.obligations,obligation{class:"equality",typ:a,at:e.At}); return base("Bool")
        case "<", "<=", ">", ">=":
            a, b = c.underlying(a,left.At), c.underlying(b,right.At); c.unify(a,b,e.At)
            c.obligations=append(c.obligations,obligation{class:"ordering",typ:a,at:e.At});return base("Bool")
        case "++":
            a, b = c.underlying(a,left.At), c.underlying(b,right.At); c.unify(a,b,e.At)
            c.obligations = append(c.obligations,obligation{class:"length",typ:a,at:e.At}); return a
        case ":": c.unify(base("[]",a),b,right.At); return b
        default:
            if operator=="%"{a,b=c.integral(a,left.At),c.integral(b,right.At)}else{a,b=c.numeric(a,left.At),c.numeric(b,right.At)}
            c.unify(a,b,e.At)
            if operator == "/" { return base("Real") }; return a
        }
    case Conditional(condition, yes, no):
        c.unify(base("Bool"),c.expression(condition,env),condition.At)
        a, b := c.expression(yes,env), c.expression(no,env); c.unify(a,b,e.At); return a
    case Let(name, annotation, bound, body):
        typ := c.expression(bound,env)
        if annotation != nil { expected := c.typ(annotation,c.typeVariables,false,false);c.assign(expected,typ,bound.At);c.refinements(annotation,c.typeVariables);typ=expected }
        local := copyEnvironment(env); local[name] = typ; return c.expression(body,local)
    case Case(subject, arms):
        typ := c.expression(subject,env); result := c.fresh(false); matrix := [][]*coveragePattern{}
        for _, arm := range arms {
            local := copyEnvironment(env); used := make(map[string]bool)
            pattern := c.pattern(arm.Pattern,typ,local,used)
            c.assign(result,c.expression(arm.Body,local),arm.Body.At)
            matrix = append(matrix,[]*coveragePattern{pattern})
        }
        if !c.covered(matrix,[]*term{typ},0) { typeError(e.At,"case patterns are not exhaustive; add the missing cases or an explicit fallback") }
        return result
    }
    panic("unreachable expression form")
}

func (c *checker) solveObligations() {
    for _, pending := range c.obligations {
        switch pending.class {
        case "read","show","equality","numeric","integral","ordering":c.capabilityRequirements=append(c.capabilityRequirements,capabilityRequirement{class:capabilityName(pending.class),typ:pending.typ,at:pending.at})
        case "length":
            t:=c.underlying(pending.typ,pending.at)
            if t.name != "String" && t.name != "[]" { typeError(pending.at,"length/concatenation requires String or a list; add an annotation if inference is insufficient") }
        }
    }
    c.obligations = nil
}

func (c *checker) equalityType(t *term, at Span, visiting map[string]bool) {
    t = c.prune(t)
    if t.variable != 0 { typeError(at,"equality operand type cannot be inferred; add a concrete annotation") }
    if t.name == "->" { typeError(at,"functions do not support value equality") }
    for _, arg := range t.args { c.equalityType(arg,at,visiting) }
    for _, field := range t.fields { c.equalityType(field.typ,at,visiting) }
    if visiting[t.name] { return }
    visiting[t.name] = true
    if underlying, ok := c.expandOne(t); ok { c.equalityType(underlying,at,visiting) }
    for _, constructor := range c.family(t) { for _, arg := range constructor.arguments { c.equalityType(arg,at,visiting) } }
    delete(visiting,t.name)
}

func (c *checker) known(t *term) bool {
    t = c.prune(t)
    if t.variable != 0 { return t.rigid }
    for _, arg := range t.args { if !c.known(arg) { return false } }
    for _, field := range t.fields { if !c.known(field.typ) { return false } }
    return true
}

func (c *checker) refinements(t *Type, variables map[string]*term) {
    previous:=c.typeVariables;c.typeVariables=variables;defer func(){c.typeVariables=previous}()
    match t.Form {
    case RefinedType(parent, rules):
        c.refinements(parent,variables)
        // Rules have their own inference boundary. Checking a local annotation
        // must not prematurely solve obligations belonging to the surrounding
        // expression, whose later uses may still determine a read target.
        enclosing:=c.obligations;c.obligations=nil
        defer func(){c.obligations=enclosing}()
        env := map[string]*term{"it":c.typ(parent,variables,false,false)}
        for _, rule := range rules {
            c.unify(base("Bool"),c.expression(rule.Predicate,env),rule.Predicate.At)
            if rule.Message != nil { c.unify(base("String"),c.expression(rule.Message,env),rule.Message.At) }
            c.solveObligations()
        }
    case RecordType(fields): for _, field := range fields { c.refinements(field.Type,variables) }
    case ListType(element): c.refinements(element,variables)
    case AppliedType(constructor, arg): c.refinements(constructor,variables); c.refinements(arg,variables)
    case ArrowType(arg, result): c.refinements(arg,variables); c.refinements(result,variables)
    case NamedType(_):
    }
}

// Compile performs static checks before a Program can be evaluated or emitted.
func Compile(source string) (program *Program, failure error) {
    defer recoverSyntax(&failure)
    module, err := Parse(source); if err != nil { return nil, err }
    return checkModule(module,nil),nil
}

// An optional payload target is checked only after the original module, so
// target inference cannot change the module's existing generic scope symbols.
func checkModule(module *Module,payload *Type)*Program {
    if len(module.Imports) != 0 { panic(&Error{Code:"language.import",At:module.Imports[0].At,Message:"resolve and bundle imports before standalone compilation"}) }
    c := checker{module:module,declarations:make(map[string]TypeDecl),functions:make(map[string]Function),constructors:make(map[string]constructor),substitution:make(map[int]*term),expressionTerms:make(map[*Expr]*term),functionVariables:make(map[string]map[string]*term)}
    module.functionScopes=make(map[string]map[string]string)
    module.declarationScopes=make(map[string]map[string]string)
    for _, declaration := range module.Types {
        if primitive(declaration.Name) || declaration.Name == "Maybe" || declaration.Name == "Nullable" || declaration.Name == "Result" { typeError(declaration.At,"cannot redefine a built-in type") }
        seen := make(map[string]bool)
        for _, parameter := range declaration.Parameters { if seen[parameter] { typeError(declaration.At,"duplicate type parameter") }; seen[parameter] = true }
        c.declarations[declaration.Name] = declaration
    }
    // Built-in constructor signatures use the same pattern machinery as data.
    named := func(name string) *Type { return &Type{Form:NamedType(name)} }
    c.constructors["Nothing"] = constructor{parent:"Maybe",parameters:[]string{"a"}}
    c.constructors["Just"] = constructor{parent:"Maybe",parameters:[]string{"a"},arguments:[]*Type{named("a")}}
    c.constructors["Null"] = constructor{parent:"Nullable",parameters:[]string{"a"}}
    c.constructors["NonNull"] = constructor{parent:"Nullable",parameters:[]string{"a"},arguments:[]*Type{named("a")}}
    c.constructors["Err"] = constructor{parent:"Result",parameters:[]string{"e","a"},arguments:[]*Type{named("e")}}
    c.constructors["Ok"] = constructor{parent:"Result",parameters:[]string{"e","a"},arguments:[]*Type{named("a")}}
    for _, declaration := range module.Types {
        for _, variant := range declaration.Variants {
            if _, exists := c.constructors[variant.Name]; exists || variant.Name == "True" || variant.Name == "False" { typeError(variant.At,"duplicate or reserved constructor") }
            c.constructors[variant.Name] = constructor{parent:declaration.Name,parameters:declaration.Parameters,arguments:variant.Arguments}
        }
    }
    for _, fn := range module.Functions {
        if fn.Signature == nil { typeError(fn.At,"named functions require an explicit signature") }
        if len(fn.Equations) == 0 { typeError(fn.At,"function signature has no definition") }
        c.functions[fn.Name] = fn
    }
    for _, declaration := range module.Types {
        variables := make(map[string]*term)
        for _, parameter := range declaration.Parameters { variables[parameter] = c.fresh(true) }
        module.declarationScopes[declaration.Name]=typeScope(variables)
        if declaration.Body != nil {
            typ := c.typ(declaration.Body,variables,false,true); c.underlying(typ,declaration.At); c.refinements(declaration.Body,variables)
        }
        for _, variant := range declaration.Variants { for _, arg := range variant.Arguments { c.typ(arg,variables,false,true); c.refinements(arg,variables) } }
    }
    for _, fn := range module.Functions {
        variables := make(map[string]*term)
        signature := c.typ(fn.Signature,variables,true,true)
        c.typeVariables=variables
        c.functionVariables[fn.Name]=variables
        module.functionScopes[fn.Name]=typeScope(variables)
        c.refinements(fn.Signature,variables)
        arity := len(fn.Equations[0].Patterns)
        arguments := []*term{}; result := signature
        for i := 0; i < arity; i++ {
            result = c.prune(result)
            if result.name != "->" { typeError(fn.At,"too many function arguments for signature") }
            arguments = append(arguments,result.args[0]); result = result.args[1]
        }
        matrix := [][]*coveragePattern{}
        for _, equation := range fn.Equations {
            if len(equation.Patterns) != arity { typeError(equation.At,"function equations have different argument counts") }
            env := make(map[string]*term); seen := make(map[string]bool); row := []*coveragePattern{}
            for i, pattern := range equation.Patterns { row = append(row,c.pattern(pattern,arguments[i],env,seen)) }
            actual := c.expression(equation.Body,env); c.assign(result,actual,equation.Body.At); c.solveObligations()
            matrix = append(matrix,row)
        }
        if !c.covered(matrix,arguments,0) { typeError(fn.At,"function patterns are not exhaustive; add the missing cases or an explicit fallback") }
    }
    if payload!=nil{
        variables:=make(map[string]*term)
        target:=c.typ(payload,variables,false,true)
        c.readableType(target,payload.At,make(map[string]bool))
        c.refinements(payload,variables);c.solveObligations()
    }
    c.solveCapabilities()
    module.inferred=make(map[*Expr]*Type,len(c.expressionTerms))
    c.reified=make(map[*term]*Type)
    for _,expr:=range c.expressionOrder {module.inferred[expr]=c.reify(c.expressionTerms[expr],expr.At)}
    return &Program{module:module}
}

func checkedModuleSnapshot(module *Module)CheckedModule {
    capabilities:=make(map[string][]CapabilityConstraint,len(module.functionCapabilities))
    for name,items:=range module.functionCapabilities{capabilities[name]=append([]CapabilityConstraint(nil),items...)}
    return CheckedModule{Syntax:module,Inferred:module.inferred,FunctionScopes:module.functionScopes,DeclarationScopes:module.declarationScopes,FunctionCapabilities:capabilities}
}

func typeScope(variables map[string]*term)map[string]string {
    scope:=make(map[string]string)
    for name,typ:=range variables{scope[name]="$"+strconv.Itoa(typ.variable)}
    return scope
}

// Reification retains nominal names and anonymous refinements. It does not
// expand recursive declarations or leak the mutable unification environment.
func (c *checker) reify(t *term,at Span)*Type {
    t=c.prune(t)
    if existing,ok:=c.reified[t];ok{return existing}
    result:=&Type{At:at}
    c.reified[t]=result
    if t.variable!=0 {
        result.Form=NamedType("$"+strconv.Itoa(t.variable))
        if len(t.rules)>0{result=&Type{Form:RefinedType(result,append([]Where(nil),t.rules...)),At:at};c.reified[t]=result}
        return result
    }
    switch t.name {
    case "[]":result.Form=ListType(c.reify(t.args[0],at))
    case "->":result.Form=ArrowType(c.reify(t.args[0],at),c.reify(t.args[1],at))
    case "{}":
        fields:=make([]Field,len(t.fields));for i,field:=range t.fields{fields[i]=Field{Name:field.name,Type:c.reify(field.typ,at),At:at}}
        result.Form=RecordType(fields)
    default:
        result.Form=NamedType(t.name)
        for _,arg:=range t.args{result=&Type{Form:AppliedType(result,c.reify(arg,at)),At:at}}
    }
    if len(t.rules)>0{result=&Type{Form:RefinedType(result,append([]Where(nil),t.rules...)),At:at}}
    c.reified[t]=result
    return result
}

func (c *checker) readableType(t *term,at Span,visiting map[string]bool) {
    t=c.prune(t)
    if t.variable!=0{return}
    if t.name=="->"{typeError(at,"functions are not readable payload values")}
    for _,arg:=range t.args{c.readableType(arg,at,visiting)}
    for _,field:=range t.fields{c.readableType(field.typ,at,visiting)}
    if visiting[t.name]{return};visiting[t.name]=true
    if underlying,ok:=c.expandOne(t);ok{c.readableType(underlying,at,visiting)}
    for _,variant:=range c.family(t){for _,arg:=range variant.arguments{c.readableType(arg,at,visiting)}}
    delete(visiting,t.name)
}

func (p *Program) Summary() string { return fmt.Sprintf("%d types, %d functions",len(p.module.Types),len(p.module.Functions)) }
